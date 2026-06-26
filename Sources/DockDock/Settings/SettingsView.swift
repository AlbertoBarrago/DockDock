import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsSection("Preview") {
                row {
                    Text("Size").foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $settings.previewSize) {
                        ForEach(PreviewSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .labelsHidden()
                }
                divider()
                row {
                    Toggle("Show window titles", isOn: $settings.showTitles)
                }
            }

            settingsSection("Behavior") {
                row {
                    Text("Hover delay").foregroundStyle(.secondary)
                    Spacer()
                    Slider(value: $settings.showDelayMs, in: 50...500, step: 25)
                        .frame(width: 120)
                    Text("\(Int(settings.showDelayMs)) ms")
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
                divider()
                row {
                    Toggle("Spotify panel", isOn: $settings.enableSpotifyPanel)
                }
            }

            settingsSection("Permissions") {
                permissionRow(
                    name: "Accessibility",
                    granted: permissions.hasAccessibility,
                    pane: "Accessibility"
                )
                divider()
                permissionRow(
                    name: "Screen Recording",
                    granted: permissions.hasScreenRecording,
                    pane: "ScreenCapture"
                )
            }

}
        .frame(width: 340)
        .background(Color(.windowBackgroundColor))
        .onAppear { permissions.checkAll() }
    }

    // MARK: - Components

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack { content() }
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
    }

    private func divider() -> some View {
        Divider().padding(.leading, 14)
    }

    @ViewBuilder
    private func permissionRow(name: String, granted: Bool, pane: String) -> some View {
        row {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(name)
            Spacer()
            Button(granted ? "Granted ✓" : "Grant Access") {
                openPrivacyPane(pane)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(granted ? .secondary : Color.accentColor)
            .font(.system(size: 12))
        }
    }

    private func openPrivacyPane(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)")!
        NSWorkspace.shared.open(url)
    }
}
