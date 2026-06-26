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
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            log("WindowCapture: SCKit threw — Screen Recording TCC denied (\(error.localizedDescription))")
            return []
        }

        // Multi-process apps (Firefox, Chrome, Electron) own windows under a
        // different PID than the main app process — match by bundle ID instead.
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        let scWindows = content.windows.filter { w in
            guard w.frame.width > 50, w.frame.height > 50 else { return false }
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
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let cfg = SCStreamConfiguration()
        let scale: CGFloat = 0.5
        cfg.width  = max(1, Int(w.frame.width  * scale))
        cfg.height = max(1, Int(w.frame.height * scale))
        cfg.showsCursor = false
        let thumb = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return WindowInfo(
            id: CGWindowID(w.windowID),
            ownerPID: w.owningApplication?.processID ?? pid,
            title: w.title ?? "",
            bounds: w.frame,
            thumbnail: thumb,
            isMinimized: false
        )
    }

    // MARK: - Legacy CGWindowList fallback

    private static func captureLegacy(pid: pid_t) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            log("WindowCapture: CGWindowListCopyWindowInfo returned nil")
            return []
        }

        let pidEntries = list.filter { ($0[kCGWindowOwnerPID] as? pid_t) == pid }
        log("WindowCapture: legacy pid=\(pid) raw entries=\(pidEntries.count)")

        return pidEntries.compactMap { info -> WindowInfo? in
            guard
                let windowID = info[kCGWindowNumber]  as? CGWindowID,
                let layer    = info[kCGWindowLayer]   as? Int,    layer >= 0, layer <= 8,
                let dict     = info[kCGWindowBounds]  as? [String: CGFloat]
            else { return nil }

            let bounds = CGRect(x: dict["X"] ?? 0, y: dict["Y"] ?? 0,
                                width: dict["Width"] ?? 0, height: dict["Height"] ?? 0)
            guard bounds.width > 50, bounds.height > 50 else { return nil }

            let thumb = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                               [.nominalResolution, .boundsIgnoreFraming])
            return WindowInfo(
                id: windowID, ownerPID: pid,
                title: (info[kCGWindowName] as? String) ?? "",
                bounds: bounds, thumbnail: thumb, isMinimized: false
            )
        }
    }
}
