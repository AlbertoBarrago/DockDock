import AppKit
import Foundation

struct AppWindowGroup: Identifiable {
    var id: String { app.bundleIdentifier ?? app.localizedName ?? "?" }
    let app: NSRunningApplication
    let windows: [WindowInfo]
}

@MainActor
final class AllWindowsModel: ObservableObject {
    static let shared = AllWindowsModel()

    @Published private(set) var groups: [AppWindowGroup] = []
    @Published private(set) var isLoading = false

    private var loadTask: Task<Void, Never>?

    /// Panel size for PreviewPanel — computed before SwiftUI lays out the view.
    /// Width is dynamic (content-driven, capped at 560px); height is fixed at 163px
    /// (42 header + 1 divider + 120 mosaic strip) so the panel never grows upward.
    var panelSize: CGSize {
        guard !isLoading, !groups.isEmpty else { return CGSize(width: 280, height: 90) }
        // Per window: 110px thumb + 6px gap = 116px. Per section: 2x8px h-padding + 1px divider.
        let totalWindows = groups.reduce(0) { $0 + $1.windows.count }
        let contentW = CGFloat(totalWindows) * 116 + CGFloat(groups.count) * 17 + 10
        return CGSize(width: max(min(contentW, 560), 280), height: 163)
    }

    func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.load() }
    }

    private func load() async {
        isLoading = true
        groups = []

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var results: [AppWindowGroup] = []
        await withTaskGroup(of: AppWindowGroup?.self) { group in
            for app in apps {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let wins = await WindowCapture.windows(for: app.processIdentifier)
                    return wins.isEmpty ? nil : AppWindowGroup(app: app, windows: wins)
                }
            }
            for await g in group {
                guard !Task.isCancelled else { break }
                if let g { results.append(g) }
            }
        }

        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        groups = results.sorted { ($0.app.localizedName ?? "") < ($1.app.localizedName ?? "") }
        isLoading = false
    }
}
