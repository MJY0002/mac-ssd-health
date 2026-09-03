import SwiftUI
import AppKit
import SSDHealthCore
import SSDHealthService
import SSDHealthUI

/// Main SwiftUI entry point for the Native macOS SSD Health application.
/// Bridges the SwiftUI App lifecycle with AppKit's NSApplicationDelegate for menu bar management.
@main
struct SSDHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
