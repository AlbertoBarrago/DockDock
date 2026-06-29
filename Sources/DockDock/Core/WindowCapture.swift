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
            return AXWindowEntry(title: title, isMinimized: (minimizedRef as? Bool) ?? false)
        }
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
        let axByTitle: [String: Bool]? = axEntries.map { entries in
            Dictionary(entries.map { ($0.title, $0.isMinimized) }, uniquingKeysWith: { first, _ in first })
        }

        let scWindows = content.windows.filter { w in
            guard w.frame.width > 50, w.frame.height > 50 else { return false }
            guard w.windowLayer >= 0 else { return false }

            if let lookup = axByTitle {
                // AX available: only include windows AX considers real.
                guard let title = w.title, !title.isEmpty, lookup[title] != nil else { return false }
            } else {
                // AX unavailable: exclude off-screen windows without a title
                // (background/utility windows that are never real user windows).
                if !w.isOnScreen, w.title?.isEmpty ?? true { return false }
            }

            if let bid = bundleID {
                return w.owningApplication?.bundleIdentifier == bid
            }
            return w.owningApplication?.processID == pid
        }

        log("WindowCapture: SCKit total=\(content.windows.count) matched=\(scWindows.count) for '\(bundleID ?? String(pid))'")

        return await withTaskGroup(of: WindowInfo?.self) { group in
            for w in scWindows {
                // Use AX's minimized state when available — it's more accurate than
                // isOnScreen (which also catches invisible utility/background windows).
                let axMinimized = axByTitle?[w.title ?? ""]
                group.addTask { await screenshotWindow(w, pid: pid, isMinimizedOverride: axMinimized) }
            }
            var out: [WindowInfo] = []
            for await i in group { if let i { out.append(i) } }
            return out
        }
    }

    @available(macOS 14.2, *)
    private static func screenshotWindow(_ w: SCWindow, pid: pid_t, isMinimizedOverride: Bool? = nil) async -> WindowInfo? {
        let isMinimized = isMinimizedOverride ?? !w.isOnScreen
        var thumb: CGImage?
        if !isMinimized && w.isOnScreen {
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
        let axByTitle: [String: Bool]? = axEntries.map { entries in
            Dictionary(entries.map { ($0.title, $0.isMinimized) }, uniquingKeysWith: { first, _ in first })
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

            let isMinimized = axByTitle?[title] ?? !isOnScreen
            let thumb: CGImage? = !isMinimized && isOnScreen && screenRecording
                ? CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.nominalResolution, .boundsIgnoreFraming])
                : nil
            return WindowInfo(
                id: windowID, ownerPID: pid,
                title: title, bounds: bounds, thumbnail: thumb, isMinimized: isMinimized
            )
        }
    }
}
