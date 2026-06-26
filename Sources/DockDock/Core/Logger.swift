import Foundation
import os.log

private let subsystem = "com.alBz.DockDock"
private let logger = Logger(subsystem: subsystem, category: "main")

func log(_ message: String) {
    logger.debug("\(message, privacy: .public)")
    // Also print so it shows in Xcode's console during development.
    print("[DockDock] \(message)")
}
