import AppKit
import ApplicationServices

enum WindowManager {
    /// Brings the app to front and raises the specific window.
    static func activate(window: WindowInfo, app: NSRunningApplication) {
        app.activate(options: .activateIgnoringOtherApps)

        // Use AX to raise the specific window (activate() alone may raise the wrong one).
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else { return }

        // Match by title since we can't directly map CGWindowID → AXUIElement.
        for axWindow in axWindows {
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            if (titleRef as? String) == window.title {
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
                break
            }
        }
    }

    static func minimize(window: WindowInfo, app: NSRunningApplication) {
        withAXWindow(windowTitle: window.title, app: app) { axWindow in
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
        }
    }

    static func close(window: WindowInfo, app: NSRunningApplication) {
        withAXWindow(windowTitle: window.title, app: app) { axWindow in
            var closeButton: AnyObject?
            if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
               let button = closeButton {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        }
    }

    // MARK: - Private

    private static func withAXWindow(windowTitle: String, app: NSRunningApplication, action: (AXUIElement) -> Void) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else { return }

        for axWindow in axWindows {
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            if (titleRef as? String) == windowTitle {
                action(axWindow)
                break
            }
        }
    }
}
