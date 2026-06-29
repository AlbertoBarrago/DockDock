import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsGroup("Preview") {
                settingsRow(icon: "square.grid.2x2.fill", color: .blue, label: "Thumbnail size") {
                    Picker("", selection: $settings.previewSize) {
                        ForEach(PreviewSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 165)
                    .labelsHidden()
                }
                insetDivider()
                settingsRow(icon: "textformat", color: .indigo, label: "Window titles") {
                    Toggle("", isOn: $settings.showTitles).labelsHidden()
                }
            }

            settingsGroup("Behavior") {
                settingsRow(icon: "timer", color: .orange, label: "Hover speed") {
                    Picker("", selection: $settings.hoverSpeed) {
                        ForEach(HoverSpeed.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 165)
                    .labelsHidden()
                }
                insetDivider()
                settingsRow(icon: "waveform", color: .green, label: "Spotify panel") {
                    Toggle("", isOn: $settings.enableSpotifyPanel).labelsHidden()
                }
            }

            settingsGroup("Permissions") {
                permissionRow(
                    icon: "accessibility",
                    color: permissions.hasAccessibility ? .green : .orange,
                    label: "Accessibility",
                    note: "Required — detects Dock icons and manages windows",
                    granted: permissions.hasAccessibility,
                    pane: "Accessibility"
                )
                insetDivider()
                permissionRow(
                    icon: "video.fill",
                    color: permissions.hasScreenRecording ? .green : .gray,
                    label: "Screen Recording",
                    note: "Optional — enables window thumbnails",
                    granted: permissions.hasScreenRecording,
                    pane: "ScreenCapture"
                )
            }

            // Footer
            HStack {
                Text("DockDock \(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(.windowBackgroundColor))
        .onAppear { permissions.checkAll() }
    }

    // MARK: - Components

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
                .padding(.bottom, 6)

            VStack(spacing: 0) { content() }
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.bottom, 16)
    }

    private func settingsRow<Control: View>(
        icon: String,
        color: Color,
        label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            iconBadge(systemName: icon, color: color)
            Text(label)
                .font(.system(size: 13))
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
    }

    private func permissionRow(
        icon: String,
        color: Color,
        label: String,
        note: String,
        granted: Bool,
        pane: String
    ) -> some View {
        HStack(spacing: 10) {
            iconBadge(systemName: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Allow") { openPrivacyPane(pane) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }

    private func iconBadge(systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.gradient)
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func insetDivider() -> some View {
        Divider().padding(.leading, 50)
    }

    private func openPrivacyPane(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)")!
        NSWorkspace.shared.open(url)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
