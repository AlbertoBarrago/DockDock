import AppKit
import ApplicationServices
import Foundation

/// Watches global mouse movement and fires when the cursor enters/leaves a Dock icon.
@MainActor
final class DockObserver: ObservableObject {
    @Published private(set) var hoveredApp: NSRunningApplication?
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var hoveredIconFrame: CGRect = .zero

    var keepAliveRect: CGRect = .zero

    private var globalMonitor: Any?
    private var rightClickMonitor: Any?
    private var debounceTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private let settings = AppSettings.shared

    // Throttle diagnostic noise — log AX failures at most once per second.
    private var lastDiagLog = Date.distantPast

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
        if globalMonitor == nil {
            log("DockObserver: ⚠️ global monitor is nil — check Accessibility permission")
        } else {
            log("DockObserver: global mouse monitor active ✓")
        }
    }

    func stop() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = rightClickMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        rightClickMonitor = nil
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

        // Fast path: dismiss immediately only when the mouse is clearly away from
        // both the Dock zone and the panel (with a 30px grace buffer around the panel).
        if hoveredApp != nil && !isNearDock(location) && !isNearPanel(location) {
            dismissImmediately()
            return
        }

        // Skip expensive AX lookup entirely when far from Dock and nothing is showing.
        if hoveredApp == nil && !isNearDock(location) { return }

        guard let (app, frame) = findDockIcon(at: location) else {
            scheduleDismiss()
            return
        }

        dismissTask?.cancel()
        dismissTask = nil

        if app.bundleIdentifier == hoveredApp?.bundleIdentifier { return }

        log("DockObserver: hovered '\(app.localizedName ?? "?")' frame=\(frame)")
        debounceTask?.cancel()
        debounceTask = Task {
            // When the Dock is auto-hidden it animates in (~300ms). Wait at least 400ms
            // so the panel doesn't appear before the Dock has fully slid into view.
            let delay = isDockAutoHidden()
                ? max(settings.showDelay, .milliseconds(400))
                : settings.showDelay
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hoveredIconFrame = frame
            hoveredApp = app
            windows = await WindowCapture.windows(for: app.processIdentifier)
            log("DockObserver: captured \(windows.count) window(s) for '\(app.localizedName ?? "?")'")
        }
    }

    private func scheduleDismiss() {
        debounceTask?.cancel()
        guard hoveredApp != nil else { return }
        // Don't reset an already-pending dismiss — let it fire naturally.
        guard dismissTask == nil else { return }
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            clearHover()
        }
    }

    private func dismissImmediately() {
        debounceTask?.cancel()
        dismissTask?.cancel()
        dismissTask = nil
        clearHover()
    }

    private func clearHover() {
        hoveredApp = nil
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
    private func findDockIcon(at point: NSPoint) -> (NSRunningApplication, CGRect)? {
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

        // diagLog("DockObserver: Dock has \(topChildren.count) AX children")

        for container in topChildren {
            var itemsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(container, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                  let items = itemsRef as? [AXUIElement]
            else { continue }

            for item in items {
                let frame = appKitFrame(of: item, screenHeight: screenHeight)
                guard frame != .zero, frame.contains(point) else { continue }

                if let result = appForDockItem(item, frame: frame) {
                    return result
                }
            }
        }

        return nil
    }

    private func appForDockItem(_ item: AXUIElement, frame: CGRect) -> (NSRunningApplication, CGRect)? {
        var bundleID: String?

        // Primary: AXURL gives the bundle path → bundle identifier.
        var urlValue: AnyObject?
        if AXUIElementCopyAttributeValue(item, "AXURL" as CFString, &urlValue) == .success,
           let url = urlValue as? URL {
            bundleID = Bundle(url: url)?.bundleIdentifier
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
            return (app, frame)
        }
        if let name = title,
           let app = running.first(where: { $0.localizedName == name }) {
            return (app, frame)
        }

        return nil
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
