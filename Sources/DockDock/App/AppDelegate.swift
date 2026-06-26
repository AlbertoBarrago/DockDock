import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionManager = PermissionManager()
    private let dockObserver = DockObserver()
    private let previewPanel = PreviewPanel()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSApp is guaranteed non-nil here — safe to set activation policy.
        NSApp.setActivationPolicy(.accessory)
        log("AppDelegate: launched")
        setupMenuBar()
        setupPanelCallback()
        permissionManager.checkAll()

        if permissionManager.canStart {
            log("AppDelegate: permissions already granted, starting observer")
            startObserving()
        } else {
            log("AppDelegate: requesting permissions…")
            permissionManager.requestAll()
            waitForAccessibility()
        }
    }

    // MARK: - Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "dock.rectangle",
            accessibilityDescription: "DockDock"
        )

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "DockDock", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupPanelCallback() {
        previewPanel.onFrameChanged = { [weak self] frame in
            self?.dockObserver.keepAliveRect = frame
        }
    }

    // MARK: - Observing

    /// Waits only for Accessibility — enough to detect icons and list windows.
    private func waitForAccessibility() {
        permissionManager.$canStart
            .filter { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Bool) in
                log("AppDelegate: accessibility granted, starting observer")
                self?.startObserving()
            }
            .store(in: &cancellables)
    }

    private func startObserving() {
        dockObserver.start()

        // Hide when no app is hovered.
        dockObserver.$hoveredApp
            .receive(on: DispatchQueue.main)
            .filter { $0 == nil }
            .sink { [weak self] _ in
                guard let self else { return }
                dockObserver.keepAliveRect = .zero
                previewPanel.hide()
            }
            .store(in: &cancellables)

        // Show/refresh whenever app OR windows change — windows arrive async after SCKit.
        Publishers.CombineLatest(dockObserver.$hoveredApp, dockObserver.$windows)
            .receive(on: DispatchQueue.main)
            .compactMap { app, windows -> (NSRunningApplication, [WindowInfo])? in
                guard let app else { return nil }
                return (app, windows)
            }
            .sink { [weak self] app, windows in
                guard let self else { return }
                log("AppDelegate: panel '\(app.localizedName ?? "?")' windows=\(windows.count)")
                previewPanel.show(app: app, windows: windows, dockIconFrame: dockObserver.hoveredIconFrame)
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "DockDock Settings"
        w.contentView = NSHostingView(rootView: SettingsView())
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
    }
}
