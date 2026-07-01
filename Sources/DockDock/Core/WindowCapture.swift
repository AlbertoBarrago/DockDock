import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum WindowCapture {
    static func windows(for pid: pid_t) async -> [WindowInfo] {
        if #available(macOS 14.2, *) {
            // nil = SCKit threw (e.g. Screen Recording denied) → try legacy
            // [] = SCKit succeeded but AX confirmed no real windows → authoritative empty
            if let result = await captureWithSCKit(pid: pid) { return result }
            log("WindowCapture: SCKit failed for pid=\(pid) — trying legacy fallback")
        }
        return captureLegacy(pid: pid)
    }

    // MARK: - Accessibility ground truth

    private struct AXWindowEntry {
        let title: String
        let isMinimized: Bool
        let frame: CGRect?
    }

    /// Returns the windows AX considers user-facing for `pid`.
    /// Returns nil when AX is unavailable (no Accessibility permission or unsupported app),
    /// so callers can fall back to heuristic filtering instead of treating nil as "no windows".
    private static func axWindows(for pid: pid_t) -> [AXWindowEntry]? {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWins = ref as? [AXUIElement]
        else { return nil }

        return axWins.compactMap { win -> AXWindowEntry? in
            var titleRef: AnyObject?
            guard AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String, !title.isEmpty
            else { return nil }

            var minimizedRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minimizedRef)
            return AXWindowEntry(
                title: title,
                isMinimized: (minimizedRef as? Bool) ?? false,
                frame: axFrame(of: win)
            )
        }
    }

    private static func axFrame(of win: AXUIElement) -> CGRect? {
        var positionRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef,
              let sizeRef
        else { return nil }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }

    // MARK: - ScreenCaptureKit (macOS 14.2+)

    /// Returns nil when SCKit itself fails (permission denied) so the caller can fall back to legacy.
    /// Returns an empty array when SCKit succeeds but the app has no real user windows.
    @available(macOS 14.2, *)
    private static func captureWithSCKit(pid: pid_t) async -> [WindowInfo]? {
        let content: SCShareableContent
        do {
            // excludingDesktopWindows: true — avoids Finder's Desktop layer.
            // onScreenWindowsOnly: false — keeps minimized windows for the panel.
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            log("WindowCapture: SCKit threw — Screen Recording TCC denied (\(error.localizedDescription))")
            return nil
        }

        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        // AX is the authoritative list of real user windows.
        // - nil: AX unavailable → fall back to title heuristic
        // - []: AX available, app has no windows → return empty authoritatively
        let axEntries = axWindows(for: pid)
        let hasChromeLikeBundle = isChromeLikeBundle(bundleID)
        let usableAXEntries = axEntries.flatMap { entries -> [AXWindowEntry]? in
            if entries.isEmpty && hasChromeLikeBundle {
                return nil
            }
            return entries
        }
        let axByTitle: [String: AXWindowEntry]? = usableAXEntries.map { entries in
            Dictionary(entries.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
        }

        let scWindows = content.windows.filter { w in
            guard w.frame.width > 50, w.frame.height > 50 else { return false }
            guard w.windowLayer >= 0 else { return false }
            if hasChromeLikeBundle && w.windowLayer != 0 { return false }

            if let lookup = axByTitle {
                // AX available: only include windows AX considers real.
                guard let title = w.title, !title.isEmpty else { return false }
                if lookup[title] == nil && !hasChromeLikeBundle { return false }
            } else {
                // AX unavailable: exclude off-screen windows without a title
                // (background/utility windows that are never real user windows).
                if !w.isOnScreen, w.title?.isEmpty ?? true { return false }
            }

            return windowOwnerMatchesTarget(w, targetPID: pid, targetBundleID: bundleID)
        }

        log("WindowCapture: SCKit total=\(content.windows.count) matched=\(scWindows.count) for '\(bundleID ?? String(pid))'")

        return await withTaskGroup(of: WindowInfo?.self) { group in
            for w in scWindows {
                // Use AX's minimized state when available — it's more accurate than
                // isOnScreen (which also catches invisible utility/background windows).
                let axEntry = axByTitle?[w.title ?? ""]
                group.addTask { await screenshotWindow(w, pid: pid, axEntry: axEntry) }
            }
            var out: [WindowInfo] = []
            for await i in group { if let i { out.append(i) } }
            return out
        }
    }

    @available(macOS 14.2, *)
    private static func screenshotWindow(_ w: SCWindow, pid: pid_t, axEntry: AXWindowEntry? = nil) async -> WindowInfo? {
        let isMinimized = axEntry?.isMinimized ?? (!w.isOnScreen && !w.isActive)
        var thumb: CGImage?
        let shouldCapture = shouldCaptureThumbnail(for: pid)
        let sizeMatches = matchesAXWindowSize(w, axEntry: axEntry)
        // With Stage Manager, inactive shelf previews can still be "on screen".
        // Capturing those returns the small stored Stage Manager view instead of the real window.
        if !isMinimized && shouldCapture && w.isActive && sizeMatches {
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let cfg = SCStreamConfiguration()
            let scale: CGFloat = 0.5
            cfg.width  = max(1, Int(w.frame.width  * scale))
            cfg.height = max(1, Int(w.frame.height * scale))
            cfg.showsCursor = false
            thumb = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        }
        return WindowInfo(
            id: CGWindowID(w.windowID),
            ownerPID: w.owningApplication?.processID ?? pid,
            title: w.title ?? "",
            bounds: w.frame,
            thumbnail: thumb,
            isMinimized: isMinimized
        )
    }

    @available(macOS 14.2, *)
    private static func matchesAXWindowSize(_ w: SCWindow, axEntry: AXWindowEntry?) -> Bool {
        guard let axFrame = axEntry?.frame, axFrame.width > 0, axFrame.height > 0 else { return true }

        let widthRatio = w.frame.width / axFrame.width
        let heightRatio = w.frame.height / axFrame.height
        let sizeMatches = (0.65...1.35).contains(widthRatio) && (0.65...1.35).contains(heightRatio)
        if !sizeMatches {
            log("WindowCapture: skipped Stage Manager-sized thumbnail '\(w.title ?? "")' sc=\(Int(w.frame.width))x\(Int(w.frame.height)) ax=\(Int(axFrame.width))x\(Int(axFrame.height))")
        }
        return sizeMatches
    }

    private static func shouldCaptureThumbnail(for pid: pid_t) -> Bool {
        if isStageManagerEnabled() {
            log("WindowCapture: skipped thumbnail for pid=\(pid) because Stage Manager is enabled")
            return false
        }
        return true
    }

    private static func isStageManagerEnabled() -> Bool {
        let value = CFPreferencesCopyAppValue(
            "GloballyEnabled" as CFString,
            "com.apple.WindowManager" as CFString
        )
        return (value as? Bool) ?? false
    }

    private static func isChromeLikeBundle(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == "com.google.Chrome"
            || bundleID.hasPrefix("com.google.Chrome.")
            || bundleID.hasPrefix("com.google.Chrome")
            || bundleID.hasPrefix("org.chromium.Chromium")
    }

    @available(macOS 14.2, *)
    private static func windowOwnerMatchesTarget(_ w: SCWindow, targetPID: pid_t, targetBundleID: String?) -> Bool {
        guard let targetBundleID else {
            return w.owningApplication?.processID == targetPID
        }

        let ownerBundleID = w.owningApplication?.bundleIdentifier
        if ownerBundleID == targetBundleID { return true }

        if isChromeLikeBundle(targetBundleID) {
            return isChromeLikeBundle(ownerBundleID)
                || w.owningApplication?.applicationName == "Google Chrome"
        }

        return false
    }

    private static func format(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return "(\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width))x\(Int(rect.height)))"
    }

    // MARK: - Legacy CGWindowList fallback

    private static func captureLegacy(pid: pid_t) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            log("WindowCapture: CGWindowListCopyWindowInfo returned nil")
            return []
        }

        let pidEntries = list.filter { ($0[kCGWindowOwnerPID] as? pid_t) == pid }
        log("WindowCapture: legacy pid=\(pid) raw entries=\(pidEntries.count)")

        let axEntries = axWindows(for: pid)
        let axByTitle: [String: AXWindowEntry]? = axEntries.map { entries in
            Dictionary(entries.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
        }

        let screenRecording = CGPreflightScreenCaptureAccess()

        return pidEntries.compactMap { info -> WindowInfo? in
            guard
                let windowID = info[kCGWindowNumber] as? CGWindowID,
                let layer    = info[kCGWindowLayer]  as? Int, layer >= 0,
                let dict     = info[kCGWindowBounds] as? [String: CGFloat]
            else { return nil }

            let bounds = CGRect(x: dict["X"] ?? 0, y: dict["Y"] ?? 0,
                                width: dict["Width"] ?? 0, height: dict["Height"] ?? 0)
            guard bounds.width > 50, bounds.height > 50 else { return nil }

            let title = (info[kCGWindowName] as? String) ?? ""
            let isOnScreen = (info[kCGWindowIsOnscreen] as? Bool) ?? true

            if let lookup = axByTitle {
                guard !title.isEmpty, lookup[title] != nil else { return nil }
            } else {
                // Without AX, exclude on-screen windows without a title — they're
                // background/system windows that produce misleading screenshots.
                if isOnScreen && title.isEmpty { return nil }
            }

            let isMinimized = axByTitle?[title]?.isMinimized ?? !isOnScreen
            let thumb: CGImage? = !isMinimized && isOnScreen && screenRecording && shouldCaptureThumbnail(for: pid)
                ? CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.nominalResolution, .boundsIgnoreFraming])
                : nil
            return WindowInfo(
                id: windowID, ownerPID: pid,
                title: title, bounds: bounds, thumbnail: thumb, isMinimized: isMinimized
            )
        }
    }
}
