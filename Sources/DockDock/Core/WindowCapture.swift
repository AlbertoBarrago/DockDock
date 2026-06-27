import CoreGraphics
import Foundation
import ScreenCaptureKit

enum WindowCapture {
    static func windows(for pid: pid_t) async -> [WindowInfo] {
        if #available(macOS 14.2, *) {
            let result = await captureWithSCKit(pid: pid)
            if !result.isEmpty { return result }
            log("WindowCapture: SCKit returned 0 for pid=\(pid) — trying legacy fallback")
        }
        return captureLegacy(pid: pid)
    }

    // MARK: - ScreenCaptureKit (macOS 14.2+)

    @available(macOS 14.2, *)
    private static func captureWithSCKit(pid: pid_t) async -> [WindowInfo] {
        let content: SCShareableContent
        do {
            // excludingDesktopWindows: true — avoids Finder's Desktop layer appearing
            // as a capturable window. onScreenWindowsOnly: false — keeps minimized
            // windows in the list so they appear in the panel (but without a thumbnail).
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            log("WindowCapture: SCKit threw — Screen Recording TCC denied (\(error.localizedDescription))")
            return []
        }

        // Multi-process apps (Firefox, Chrome, Electron) own windows under a
        // different PID than the main app process — match by bundle ID instead.
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        let scWindows = content.windows.filter { w in
            guard w.frame.width > 50, w.frame.height > 50 else { return false }
            // Exclude negative-layer system windows (menu bar extra windows, etc.).
            guard w.windowLayer >= 0 else { return false }
            // Internal helper/renderer windows (Electron, Firefox content procs) are
            // off-screen and have no title. Real minimized windows keep their title.
            if !w.isOnScreen, w.title?.isEmpty ?? true { return false }
            if let bid = bundleID {
                return w.owningApplication?.bundleIdentifier == bid
            }
            return w.owningApplication?.processID == pid
        }

        log("WindowCapture: SCKit total=\(content.windows.count) matched=\(scWindows.count) for '\(bundleID ?? String(pid))'")

        return await withTaskGroup(of: WindowInfo?.self) { group in
            for w in scWindows { group.addTask { await screenshotWindow(w, pid: pid) } }
            var out: [WindowInfo] = []
            for await i in group { if let i { out.append(i) } }
            return out
        }
    }

    @available(macOS 14.2, *)
    private static func screenshotWindow(_ w: SCWindow, pid: pid_t) async -> WindowInfo? {
        var thumb: CGImage?
        // Minimized windows (isOnScreen == false) can't be screenshotted.
        if w.isOnScreen {
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
            isMinimized: !w.isOnScreen
        )
    }

    // MARK: - Legacy CGWindowList fallback

    private static func captureLegacy(pid: pid_t) -> [WindowInfo] {
        // Use optionAll (not optionOnScreenOnly) so minimized windows and windows
        // on other Mission Control spaces are included. We filter by PID so the
        // broader query doesn't cause performance issues.
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            log("WindowCapture: CGWindowListCopyWindowInfo returned nil")
            return []
        }

        let pidEntries = list.filter { ($0[kCGWindowOwnerPID] as? pid_t) == pid }
        log("WindowCapture: legacy pid=\(pid) raw entries=\(pidEntries.count)")

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

            let isOnScreen = (info[kCGWindowIsOnscreen] as? Bool) ?? true

            // CGWindowListCreateImage returns a blank opaque image (not nil) without Screen Recording.
            // Only attempt capture for on-screen windows; minimized windows can't be captured anyway.
            let thumb: CGImage? = isOnScreen && screenRecording
                ? CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.nominalResolution, .boundsIgnoreFraming])
                : nil
            return WindowInfo(
                id: windowID, ownerPID: pid,
                title: (info[kCGWindowName] as? String) ?? "",
                bounds: bounds, thumbnail: thumb, isMinimized: !isOnScreen
            )
        }
    }
}
