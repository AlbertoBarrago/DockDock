import CoreGraphics
import Foundation

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let ownerPID: pid_t
    let title: String
    let bounds: CGRect
    let thumbnail: CGImage?
    let isMinimized: Bool

    /// Whether the window has usable content to show in a preview.
    var isPreviewable: Bool {
        thumbnail != nil && bounds.width > 50 && bounds.height > 50
    }
}
