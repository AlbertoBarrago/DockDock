import AppKit
import SwiftUI

struct AllWindowsView: View {
    @ObservedObject private var model = AllWindowsModel.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { model.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("All Windows")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if !model.isLoading {
                let total = model.groups.reduce(0) { $0 + $1.windows.count }
                Text("\(total) window\(total == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            loadingView
        } else if model.groups.isEmpty {
            emptyView
        } else {
            mosaicScroll
        }
    }

    /// Horizontal mosaic — panel stays short so the mouse never needs to go up toward
    /// the menu bar (which would trigger auto-hide). Apps are columns, windows are rows.
    private var mosaicScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(model.groups.enumerated()), id: \.element.id) { idx, group in
                    if idx > 0 {
                        Divider()
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 8)
                            .opacity(0.3)
                    }
                    MosaicAppSection(group: group)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(height: 120)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.75)
            Text("Collecting windows…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "macwindow.badge.plus")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No open windows")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

// MARK: - Per-app mosaic section

private struct MosaicAppSection: View {
    let group: AppWindowGroup

    private let thumbW: CGFloat = 110
    private let thumbH: CGFloat = 75

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            appLabel
            thumbRow
        }
        .padding(.horizontal, 8)
    }

    private var appLabel: some View {
        HStack(spacing: 4) {
            if let icon = group.app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(group.app.localizedName ?? "")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: thumbW * CGFloat(group.windows.count) + 6 * CGFloat(group.windows.count - 1))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            group.app.activate(options: .activateIgnoringOtherApps)
        }
    }

    private var thumbRow: some View {
        HStack(spacing: 6) {
            ForEach(group.windows) { window in
                ThumbnailView(
                    window: window,
                    showTitle: false,
                    onActivate: { WindowManager.activate(window: window, app: group.app) },
                    onMinimize: { WindowManager.minimize(window: window, app: group.app) },
                    onClose:    { WindowManager.close(window: window, app: group.app) }
                )
                .frame(width: thumbW, height: thumbH)
            }
        }
    }
}
