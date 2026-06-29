import AppKit
import SwiftUI

struct NotRunningAppView: View {
    let info: NotRunningAppInfo

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name ?? "Unknown App")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("Not running")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button {
                launch()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(width: 220)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = info.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
        }
    }

    private func launch() {
        if let url = info.url {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else if let bid = info.bundleID,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }
}
