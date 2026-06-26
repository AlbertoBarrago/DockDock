import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Monitors and requests the permissions DockDock needs.
/// Only Accessibility is strictly required to start. Screen Recording enables thumbnails.
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasScreenRecording = false
    @Published private(set) var hasAutomation = false

    /// True as soon as Accessibility is granted — enough to start the observer.
    @Published private(set) var canStart = false

    private var pollTimer: Timer?

    func checkAll() {
        hasAccessibility   = AXIsProcessTrusted()
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        canStart           = hasAccessibility
        checkAutomation()
    }

    private func checkAutomation() {
        // Non-prompting check: noErr = granted, anything else = denied/unknown.
        let bundleID = "com.spotify.client"
        var desc = AEDesc()
        bundleID.withCString { ptr in
            AECreateDesc(typeApplicationBundleID, ptr, strlen(ptr), &desc)
        }
        let status = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, false)
        AEDisposeDesc(&desc)
        hasAutomation = (status == noErr)
    }

    func requestAll() {
        if !hasAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        if !hasScreenRecording {
            CGRequestScreenCaptureAccess()
            requestScreenRecordingViaSCKit()
        }
        startPolling()
    }

    /// Triggers the macOS Automation permission dialog for Spotify.
    func requestAutomation() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "AppleEvents", "com.alBz.DockDock"]
        try? reset.run()
        reset.waitUntilExit()

        NSApp.activate(ignoringOtherApps: true)

        let script = NSAppleScript(source: "tell application \"Spotify\" to get name")
        var err: NSDictionary?
        let result = script?.executeAndReturnError(&err)
        log("requestAutomation → result=\(result?.stringValue ?? "nil") err=\(err?.description ?? "none")")
        checkAll()

        guard result == nil else { return }

        let errorCode = (err?["NSAppleScriptErrorNumber"] as? Int) ?? 0
        let alert = NSAlert()
        if errorCode == -600 || errorCode == -1728 || errorCode == -1708 {
            alert.messageText = "Apri Spotify prima"
            alert.informativeText = "Avvia Spotify, poi clicca di nuovo \"Request Access\"."
            alert.addButton(withTitle: "OK")
        } else {
            alert.messageText = "Vai in Impostazioni di Sistema"
            alert.informativeText = "Privacy e Sicurezza → Automazione → abilita DockDock per Spotify.\n\nOppure in Terminal:\ntccutil reset Automation com.alBz.DockDock"
            alert.addButton(withTitle: "Apri Impostazioni")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
            return
        }
        alert.runModal()
    }

    /// Always-on low-frequency poll — keeps the UI in sync without heavy overhead.
    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkAll() }
        }
    }

    private func requestScreenRecordingViaSCKit() {
        if #available(macOS 14.0, *) {
            Task {
                _ = try? await SCShareableContent.current
                checkAll()
            }
        }
    }
}
