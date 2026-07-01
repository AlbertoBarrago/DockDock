import AppKit
import ApplicationServices
import Foundation

/// Info about a Dock icon whose app is not currently running.
struct NotRunningAppInfo: Equatable {
    let bundleID: String?
    let name: String?
    let icon: NSImage?
    let url: URL?

    /// Lenient equality: match by bundleID if both have one, then by URL, then by name.
    /// This handles intermittent AXURL failures where bundleID/url may be nil on some calls
    /// for the same icon while name (kAXTitle) is always available.
    static func == (lhs: NotRunningAppInfo, rhs: NotRunningAppInfo) -> Bool {
        if let l = lhs.bundleID, let r = rhs.bundleID { return l == r }
        if let l = lhs.url, let r = rhs.url { return l == r }
        if let l = lhs.name, let r = rhs.name { return l == r }
        return false
    }
}

/// Result of a Dock icon hit-test — either a live app or a dormant one.
private enum DockHoverItem {
    case running(app: NSRunningApplication, frame: CGRect)
    case notRunning(info: NotRunningAppInfo, frame: CGRect)
}

/// Watches global mouse movement and fires when the cursor enters/leaves a Dock icon.
@MainActor
final class DockObserver: ObservableObject {
    @Published private(set) var hoveredApp: NSRunningApplication?
    @Published private(set) var notRunningInfo: NotRunningAppInfo?
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var hoveredIconFrame: CGRect = .zero

    var keepAliveRect: CGRect = .zero

    private var globalMonitor: Any?
    private var rightClickMonitor: Any?
    private var appLaunchObserver: Any?
    private var debounceTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private let settings = AppSettings.shared

    // Throttle diagnostic noise — log AX failures at most once per second.
    private var lastDiagLog = Date.distantPast

    // Cache bundle identifiers by app URL to avoid repeated Info.plist reads on every mouse-move.
    private var bundleIDCache: [URL: String] = [:]

    // Tracks the icon currently being debounced so repeated mouse-move events over the
    // same icon don't cancel and restart the debounce timer before the panel appears.
    // debouncingID = bundleID when AXURL works; falls back to name when it fails.
    // debouncingName is always the AX title — used as a secondary key when AXURL fails
    // intermittently so the same icon doesn't restart the debounce mid-wait.
    private var debouncingID: String?
    private var debouncingName: String?

    private let dockPID: pid_t? = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.dock")
        .first?.processIdentifier

    func start() {
        log("DockObserver: starting — dockPID=\(String(describing: dockPID))")
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMouseMove() }
        }
        // Dismiss our panel when the user right-clicks a Dock icon to open its context menu.
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismissImmediately() }
        }
        // When an app launches while its Dock icon is still hovered, transition from
        // the "not running" placeholder to the real window-preview panel automatically.
        appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAppLaunched(notification)
            }
        }
        if globalMonitor == nil {
            log("DockObserver: ⚠️ global monitor is nil — check Accessibility permission")
        } else {
            log("DockObserver: global mouse monitor active ✓")
        }
    }

    func stop() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = rightClickMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = appLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        globalMonitor = nil
        rightClickMonitor = nil
        appLaunchObserver = nil
        debounceTask?.cancel()
        dismissTask?.cancel()
    }

    // MARK: - Mouse handling

    private func handleMouseMove() {
        let location = NSEvent.mouseLocation

        // Fast path: mouse over preview panel — keep alive, no AX work.
        if keepAliveRect.contains(location) {
            dismissTask?.cancel()
            dismissTask = nil
            return
        }

        let panelActive = hoveredApp != nil || notRunningInfo != nil

        // Fast path: dismiss immediately only when the mouse is clearly away from
        // both the Dock zone and the panel (with a 30px grace buffer around the panel).
        if panelActive && !isNearDock(location) && !isNearPanel(location) {
            dismissImmediately()
            return
        }

        // Far from Dock — cancel any in-progress debounce, bail when nothing is showing.
        if !isNearDock(location) {
            if debouncingID != nil { debounceTask?.cancel(); debouncingID = nil }
            if !panelActive { return }
        }

        guard let hoverItem = findDockIcon(at: location) else {
            scheduleDismiss()
            return
        }

        dismissTask?.cancel()
        dismissTask = nil

        switch hoverItem {
        case .running(let app, let frame):
            let runID = app.bundleIdentifier ?? ""
            // Already showing or already debouncing for this exact app → nothing to do.
            if runID == hoveredApp?.bundleIdentifier { return }
            if !runID.isEmpty && runID == debouncingID { return }
            log("DockObserver: hovered running '\(app.localizedName ?? "?")' frame=\(frame)")
            debouncingID = runID
            debouncingName = nil
            debounceTask?.cancel()
            debounceTask = Task {
                let delay = isDockAutoHidden()
                    ? max(settings.showDelay, .milliseconds(400))
                    : settings.showDelay
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                debouncingID = nil
                // Set hoveredApp BEFORE clearing notRunningInfo so the hide subscription
                // never sees (nil, nil) — which would flash the panel away.
                hoveredIconFrame = frame
                hoveredApp = app
                notRunningInfo = nil
                windows = await WindowCapture.windows(for: app.processIdentifier)
                log("DockObserver: captured \(windows.count) window(s) for '\(app.localizedName ?? "?")'")
            }

        case .notRunning(let info, let frame):
            let notRunID = info.bundleID ?? info.name ?? ""
            // Already showing or already debouncing for this exact app → nothing to do.
            // Check by lenient Equatable (bundleID / url / name) then by debouncing keys.
            if info == notRunningInfo { return }
            if !notRunID.isEmpty && notRunID == debouncingID { return }
            // Secondary check: if AXURL failed this call (bundleID=nil), match by name alone.
            if let n = info.name, !n.isEmpty, n == debouncingName { return }
            log("DockObserver: hovered not-running '\(info.name ?? "?")' frame=\(frame)")
            debouncingID = notRunID
            debouncingName = info.name
            debounceTask?.cancel()
            debounceTask = Task {
                let delay = isDockAutoHidden()
                    ? max(settings.showDelay, .milliseconds(400))
                    : settings.showDelay
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                // Load the icon once, after the debounce delay, rather than on every mouse-move.
                let icon: NSImage? = info.url.flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
                    ?? info.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                        .flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
                let resolved = NotRunningAppInfo(bundleID: info.bundleID, name: info.name,
                                                icon: icon, url: info.url)
                debouncingID = nil
                debouncingName = nil
                // Set notRunningInfo BEFORE clearing hoveredApp so the CombineLatest hide
                // subscription never sees (nil, nil) — which would flash the panel away.
                hoveredIconFrame = frame
                notRunningInfo = resolved
                hoveredApp = nil
                windows = []
            }
        }
    }

    // MARK: - App launch observer

    private func handleAppLaunched(_ notification: Notification) {
        guard let info = notRunningInfo,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == info.bundleID || app.localizedName == info.name
        else { return }

        log("DockObserver: '\(app.localizedName ?? "?")' launched while hovered — refreshing panel")
        let frame = hoveredIconFrame
        debounceTask?.cancel()
        debouncingID = nil
        debouncingName = nil
        debounceTask = Task {
            hoveredIconFrame = frame
            hoveredApp = app
            notRunningInfo = nil
            windows = await WindowCapture.windows(for: app.processIdentifier)
            log("DockObserver: captured \(windows.count) window(s) post-launch for '\(app.localizedName ?? "?")'")
        }
    }

    private func scheduleDismiss() {
        // Start a grace-period timer; clearHover() will cancel the debounce if it fires.
        // Do NOT cancel the debounce here — a transient AX gap between two icons must not
        // abort a debounce that was already in progress for the destination icon.
        guard hoveredApp != nil || notRunningInfo != nil || debouncingID != nil else { return }
        // Don't reset an already-pending dismiss — let it fire naturally.
        guard dismissTask == nil else { return }
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            clearHover()
        }
    }

    private func dismissImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        clearHover()
    }

    private func clearHover() {
        // Cancelling the debounce here (rather than in scheduleDismiss) means a transient
        // AX failure mid-transition doesn't abort the show sequence for the next icon.
        debounceTask?.cancel()
        debouncingID = nil
        debouncingName = nil
        hoveredApp = nil
        notRunningInfo = nil
        windows = []
        hoveredIconFrame = .zero
        dismissTask = nil
    }

    /// True when the Dock is set to auto-hide on the screen containing the mouse.
    private func isDockAutoHidden() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = screenContaining(point) else { return false }
        let full = screen.frame, visible = screen.visibleFrame
        return visible.minY == full.minY && visible.minX == full.minX && visible.maxX == full.maxX
    }

    /// True when the cursor is within 30px of the visible panel — prevents immediate
    /// dismiss when the mouse briefly exits the panel boundary on the way to/from the Dock.
    private func isNearPanel(_ point: NSPoint) -> Bool {
        guard keepAliveRect != .zero else { return false }
        return keepAliveRect.insetBy(dx: -30, dy: -30).contains(point)
    }

    /// True when the cursor could plausibly be over or near the Dock.
    /// Checks against whichever screen the cursor is currently on.
    private func isNearDock(_ point: NSPoint) -> Bool {
        guard let screen = screenContaining(point) else { return false }
        let full = screen.frame
        let visible = screen.visibleFrame
        let threshold: CGFloat = 200

        let dockAtLeft  = visible.minX > full.minX
        let dockAtRight = visible.maxX < full.maxX

        if dockAtLeft  { return point.x < full.minX + max(visible.minX - full.minX, threshold) }
        if dockAtRight { return point.x > full.maxX - max(full.maxX - visible.maxX, threshold) }
        return point.y < full.minY + max(visible.minY - full.minY, threshold)
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }

    // MARK: - Dock icon detection

    /// Primary strategy: enumerate AX children of the Dock process directly.
    /// This is reliable on macOS 14/15 where the hit-test approach can fail.
    private func findDockIcon(at point: NSPoint) -> DockHoverItem? {
        guard let dockPID else { return nil }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let dockElement = AXUIElementCreateApplication(dockPID)

        var topChildrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &topChildrenRef) == .success,
              let topChildren = topChildrenRef as? [AXUIElement]
        else {
            diagLog("DockObserver: could not get Dock AX children")
            return nil
        }

        for container in topChildren {
            var itemsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(container, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                  let items = itemsRef as? [AXUIElement]
            else { continue }

            for item in items {
                let frame = appKitFrame(of: item, screenHeight: screenHeight)
                guard frame != .zero, frame.contains(point) else { continue }

                if let result = hoverItemForDockIcon(item, frame: frame) {
                    return result
                }
            }
        }

        return nil
    }

    private func hoverItemForDockIcon(_ item: AXUIElement, frame: CGRect) -> DockHoverItem? {
        var bundleID: String?
        var appURL: URL?

        // Primary: AXURL gives the bundle path → bundle identifier.
        // Bundle ID is cached to avoid repeated Info.plist reads on every mouse-move.
        var urlValue: AnyObject?
        if AXUIElementCopyAttributeValue(item, "AXURL" as CFString, &urlValue) == .success,
           let url = urlValue as? URL {
            appURL = url
            bundleID = bundleIDCache[url] ?? {
                let bid = Bundle(url: url)?.bundleIdentifier
                if let bid { bundleIDCache[url] = bid }
                return bid
            }()
        }

        // Read the label regardless (useful for logging and fallback).
        var titleValue: AnyObject?
        let title: String? = {
            guard AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let t = titleValue as? String, !t.isEmpty else { return nil }
            return t
        }()

        let running = NSWorkspace.shared.runningApplications

        // Match by bundle ID first (most reliable), then by display name.
        if let bid = bundleID,
           let app = running.first(where: { $0.bundleIdentifier == bid }) {
            return .running(app: app, frame: frame)
        }
        if let url = appURL,
           let app = running.first(where: { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }) {
            return .running(app: app, frame: frame)
        }
        if let app = chromeRunningApp(forBundleID: bundleID, title: title, running: running) {
            return .running(app: app, frame: frame)
        }
        if let name = title,
           let app = running.first(where: { namesMatch($0.localizedName, name) }) {
            return .running(app: app, frame: frame)
        }

        // App is in the Dock but not currently running.
        // Icon is intentionally omitted here — it is loaded once in the debounce task
        // to avoid a disk/cache hit on every mouse-move event.
        guard bundleID != nil || title != nil else { return nil }
        let info = NotRunningAppInfo(bundleID: bundleID, name: title, icon: nil, url: appURL)
        return .notRunning(info: info, frame: frame)
    }

    private func chromeRunningApp(forBundleID bundleID: String?, title: String?, running: [NSRunningApplication]) -> NSRunningApplication? {
        let looksLikeChrome = bundleID?.hasPrefix("com.google.Chrome") == true
            || title.map { normalizedName($0).contains("chrome") } == true
        guard looksLikeChrome else { return nil }

        return running.first {
            $0.bundleIdentifier == "com.google.Chrome"
                || $0.bundleIdentifier?.hasPrefix("com.google.Chrome.app.") == true
                || normalizedName($0.localizedName).contains("chrome")
        }
    }

    private func namesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let l = normalizedName(lhs)
        let r = normalizedName(rhs)
        guard !l.isEmpty, !r.isEmpty else { return false }
        if l == r { return true }
        if l == "google chrome", r == "chrome" { return true }
        if l == "chrome", r == "google chrome" { return true }
        return false
    }

    private func normalizedName(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: "google ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AX helpers

    /// Converts an element's AXFrame from AX coordinates (top-left origin) to AppKit (bottom-left origin).
    private func appKitFrame(of element: AXUIElement, screenHeight: CGFloat) -> CGRect {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID()
        else { return .zero }

        var frame = CGRect.zero
        AXValueGetValue(value as! AXValue, .cgRect, &frame)
        frame.origin.y = screenHeight - frame.origin.y - frame.height
        return frame
    }

    /// Logs at most once per second to avoid flooding the console.
    private func diagLog(_ message: String) {
        let now = Date()
        guard now.timeIntervalSince(lastDiagLog) > 1 else { return }
        lastDiagLog = now
        log(message)
    }
}
