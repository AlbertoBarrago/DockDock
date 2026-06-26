import AppKit
import SwiftUI

struct ThumbnailView: View {
    let window: WindowInfo
    let showTitle: Bool
    let onActivate: () -> Void
    let onMinimize: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            thumbnail
            if showTitle && !window.title.isEmpty {
                titleBar
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered ? Color.accentColor : Color.white.opacity(0.15),
                    lineWidth: isHovered ? 2 : 1
                )
        )
        .scaleEffect(isHovered ? 1.03 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onActivate)
        .contextMenu {
            Button("Bring to Front", action: onActivate)
            Divider()
            Button("Minimize", action: onMinimize)
            Button("Close", role: .destructive, action: onClose)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let cgImage = window.thumbnail {
            Image(cgImage, scale: 1, orientation: .up, label: Text(window.title))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Image(systemName: "macwindow")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var titleBar: some View {
        Text(window.title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
    }
}
