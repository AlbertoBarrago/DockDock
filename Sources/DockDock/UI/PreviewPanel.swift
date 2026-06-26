import AppKit
import SwiftUI

/// Floating borderless panel that shows window thumbnails above a Dock icon.
final class PreviewPanel: NSPanel {
    /// Called after the panel is repositioned so the observer can keep it alive.
    var onFrameChanged: ((CGRect) -> Void)?

    private var currentBundleID: String?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isMovable = false
        isMovableByWindowBackground = false
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    func show(app: NSRunningApplication, windows: [WindowInfo], dockIconFrame: CGRect) {
        let isSpotify = app.bundleIdentifier == "com.spotify.client"

        // Don't recreate the view hierarchy when the same app is already showing.
        // Special views (Spotify) own their data source and must not be torn down
        // on every windows update that CombineLatest triggers.
        let sameApp = app.bundleIdentifier == currentBundleID && isVisible
        if !sameApp {
            currentBundleID = app.bundleIdentifier
            let view = AnyView(content(for: app, windows: windows))
            contentView = NSHostingView(rootView: view)
        } else if !isSpotify {
            // For regular apps, always refresh content so window thumbnails update.
            let view = AnyView(content(for: app, windows: windows))
            contentView = NSHostingView(rootView: view)
        }

        let size: CGSize = isSpotify
            ? CGSize(width: 260, height: 370)
            : (contentView?.fittingSize ?? CGSize(width: 260, height: 180))
        let frame = position(size: size, above: dockIconFrame)

        setFrame(frame, display: false)
        onFrameChanged?(frame)

        if !isVisible {
            alphaValue = 0
            orderFront(nil)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func hide() {
        currentBundleID = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private func content(for app: NSRunningApplication, windows: [WindowInfo]) -> some View {
        if app.bundleIdentifier == "com.spotify.client" {
            SpotifyView()
        } else {
            PreviewGridView(app: app, windows: windows)
        }
    }

    // MARK: - Positioning

    /// Positions the panel centered above `iconFrame`, clamped to the visible screen area.
    private func position(size: CGSize, above iconFrame: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(iconFrame.origin) })
                           ?? NSScreen.main
        else { return CGRect(origin: .zero, size: size) }

        let gap: CGFloat = 8
        var x = iconFrame.midX - size.width / 2
        var y = iconFrame.maxY + gap

        let visibleArea = screen.visibleFrame
        // Clamp horizontally so the panel never goes off-screen.
        x = max(visibleArea.minX + 4, min(x, visibleArea.maxX - size.width - 4))
        // If there's not enough space above (e.g. top Dock), flip below.
        if y + size.height > visibleArea.maxY {
            y = iconFrame.minY - size.height - gap
        }

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
