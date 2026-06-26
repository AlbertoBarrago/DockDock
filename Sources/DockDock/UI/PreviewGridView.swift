import AppKit
import SwiftUI

struct PreviewGridView: View {
    let app: NSRunningApplication
    let windows: [WindowInfo]

    @ObservedObject private var settings = AppSettings.shared

    private var thumbnailSize: CGSize { settings.previewSize.thumbnailSize }
    private var maxColumns: Int { settings.previewSize.maxColumns }

    var body: some View {
        VStack(spacing: 8) {
            appHeader
            if windows.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Subviews

    private var appHeader: some View {
        HStack(spacing: 6) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(app.localizedName ?? "")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(windows.count) window\(windows.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        let cols = min(maxColumns, windows.count)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(thumbnailSize.width), spacing: 8), count: cols),
            spacing: 8
        ) {
            ForEach(windows) { window in
                ThumbnailView(
                    window: window,
                    showTitle: settings.showTitles,
                    onActivate: { WindowManager.activate(window: window, app: app) },
                    onMinimize: { WindowManager.minimize(window: window, app: app) },
                    onClose:    { WindowManager.close(window: window, app: app) }
                )
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            }
        }
    }

    private var emptyState: some View {
        Text("No open windows")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: thumbnailSize.width, height: 60)
    }
}
