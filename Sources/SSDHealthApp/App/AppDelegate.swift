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

        // Menu bar refresh on state change is wired by MenuBarManager.setup(appState:)

        // Route notification clicks and actions to the matching dashboard tab
        state.notificationService.onNotificationResponse = { [weak self] action, category in
            let tab: DashboardTab
            switch (action, category) {
            case ("ACTION_VIEW_THERMAL", _), (_, NotificationService.categoryThermal):
                tab = .charts
            case ("ACTION_VIEW_FORECAST", _), (_, NotificationService.categoryWearMilestone):
                tab = .forecast
            default:
                tab = .smartTable
            }
            Task { @MainActor in
                self?.menuBarManager?.openDashboardWindow(selectedTab: tab)
            }
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
