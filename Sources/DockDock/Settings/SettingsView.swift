import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Preview") {
                Picker("Size", selection: $settings.previewSize) {
                    ForEach(PreviewSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show window titles", isOn: $settings.showTitles)
            }

            Section("Behavior") {
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $settings.showDelayMs, in: 50...500, step: 25)
                        Text("\(Int(settings.showDelayMs)) ms")
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }
}
