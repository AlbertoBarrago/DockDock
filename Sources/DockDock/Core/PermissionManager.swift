import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Monitors and requests the permissions DockDock needs.
/// Only Accessibility is strictly required to start. Screen Recording enables thumbnails.
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasScreenRecording = false

    /// True as soon as Accessibility is granted — enough to start the observer.
    @Published private(set) var canStart = false

    private var pollTimer: Timer?

    func checkAll() {
        hasAccessibility = AXIsProcessTrusted()
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        canStart = hasAccessibility
        log("PermissionManager: accessibility=\(hasAccessibility) screenRecording=\(hasScreenRecording)")
    }

    func requestAll() {
        if !hasAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        if !hasScreenRecording {
            // CGRequestScreenCaptureAccess covers CGWindowList; SCShareableContent.current
            // covers ScreenCaptureKit — they go through different TCC pathways on macOS 14+.
            CGRequestScreenCaptureAccess()
            requestScreenRecordingViaSCKit()
        }
        startPolling()
    }

    private func requestScreenRecordingViaSCKit() {
        if #available(macOS 14.0, *) {
            Task {
                _ = try? await SCShareableContent.current
                checkAll()
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAll()
                // Stop polling once everything is granted.
                if self?.hasAccessibility == true && self?.hasScreenRecording == true {
                    self?.pollTimer?.invalidate()
                }
            }
        }
    }
}
