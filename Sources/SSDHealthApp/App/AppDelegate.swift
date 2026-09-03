import AppKit
import SwiftUI
import UserNotifications
import SSDHealthCore
import SSDHealthService
import SSDHealthUI

/// Application delegate managing NSApplication lifecycle, menu bar setup,
/// notification permissions, and background telemetry polling.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var appState: AppState?
    public private(set) var menuBarManager: MenuBarManager?

    public override init() {
        self.appState = nil
        self.menuBarManager = nil
        super.init()
    }

    public init(appState: AppState? = nil, menuBarManager: MenuBarManager? = nil) {
        self.appState = appState
        self.menuBarManager = menuBarManager
        super.init()
    }

    private var hasSetup = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard !hasSetup else { return }
        hasSetup = true

        // Configure as a background / accessory menu bar agent application (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Initialize state and menu bar manager if not already injected
        let state = self.appState ?? AppState()
        self.appState = state

        let manager = self.menuBarManager ?? MenuBarManager.shared
        manager.setup(appState: state)
        self.menuBarManager = manager

        // Wire reactive state observation to menu bar updates
        state.onStateChange = { [weak self] in
            self?.menuBarManager?.updateMenuBarButton()
        }

        // Request notification authorization on launch
        Task { @MainActor in
            _ = await state.notificationService.requestAuthorization()
        }

        // Start background polling and telemetry synchronization
        state.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
        menuBarManager?.teardown()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarManager?.openDashboardWindow()
        return true
    }
}
