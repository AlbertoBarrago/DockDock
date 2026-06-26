import SwiftUI

struct AboutView: View {
    private let icon: NSImage? = {
        // Load from the bundle's .icns at native resolution — never use applicationIconImage
        // which returns a scaled-down composite.
        guard let url = Bundle.main.url(forResource: "DockDock", withExtension: "icns") else {
            return NSApp.applicationIconImage
        }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Icon
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: 96, height: 96)
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 14)

            // Name + version
            Text("DockDock")
                .font(.system(size: 20, weight: .semibold))
            Text("Version 0.1.0")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Divider()
                .padding(.horizontal, 32)
                .padding(.vertical, 20)

            // Creator
            VStack(spacing: 4) {
                Text("Made by")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Alberto Barrago")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.bottom, 20)

            // Links
            HStack(spacing: 16) {
                linkButton(title: "GitHub", url: "https://github.com/AlbertoBarrago/DockDock")
                linkButton(title: "README", url: "https://github.com/AlbertoBarrago/DockDock#readme")
            }
            .padding(.bottom, 28)
        }
        .frame(width: 280)
        .background(Color(.windowBackgroundColor))
    }

    private func linkButton(title: String, url: String) -> some View {
        Button(title) {
            NSWorkspace.shared.open(URL(string: url)!)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.accentColor)
        .font(.system(size: 12))
    }
}
