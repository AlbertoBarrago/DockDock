import Foundation
import SwiftUI

enum PreviewSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var thumbnailSize: CGSize {
        switch self {
        case .small:  CGSize(width: 160, height: 100)
        case .medium: CGSize(width: 220, height: 140)
        case .large:  CGSize(width: 300, height: 190)
        }
    }

    var maxColumns: Int {
        switch self {
        case .small:  4
        case .medium: 3
        case .large:  2
        }
    }
}

enum HoverSpeed: String, CaseIterable, Identifiable {
    case fast, normal, deliberate
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast:       "Fast"
        case .normal:     "Normal"
        case .deliberate: "Deliberate"
        }
    }

    var milliseconds: Double {
        switch self {
        case .fast:       100
        case .normal:     150
        case .deliberate: 250
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private init() {}

    @AppStorage("previewSize")        var previewSize: PreviewSize = .medium
    @AppStorage("hoverSpeed")         var hoverSpeed: HoverSpeed = .normal
    @AppStorage("showTitles")         var showTitles: Bool = true
    @AppStorage("enableSpotifyPanel") var enableSpotifyPanel: Bool = true

    var showDelay: Duration { .milliseconds(hoverSpeed.milliseconds) }
}
