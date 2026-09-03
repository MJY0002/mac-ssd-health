import AppKit
import SwiftUI
import SSDHealthCore
import SSDHealthService

/// Controller managing the macOS NSStatusItem, NSPopover lifecycle, and dashboard window presentation.
@MainActor
public final class MenuBarManager: NSObject, NSPopoverDelegate {
    public static let shared = MenuBarManager()

    public private(set) var statusItem: NSStatusItem?
    public private(set) var popover: NSPopover?
    public private(set) var appState: AppState?
    public private(set) var dashboardWindow: NSWindow?

    public override init() {
        super.init()
    }

    deinit {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    /// Sets up the status item, popover, and state observer.
    public func setup(appState: AppState) {
        self.appState = appState

        // 1. Clean up existing NSStatusItem if setup was previously called
        if let existingItem = self.statusItem {
            NSStatusBar.system.removeStatusItem(existingItem)
            self.statusItem = nil
        }

        // 2. Create NSStatusItem
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "de.exciteddarwin.macssdhealth.statusitem"

        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        self.statusItem = item

        // 2. Setup Transient NSPopover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 340, height: 420)
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self

        let popoverView = QuickViewPopover(
            appState: appState,
            onOpenDashboard: { [weak self] in
                self?.openDashboardWindow()
            },
            onOpenSettings: { [weak self] in
                self?.openDashboardWindow(selectedTab: .settings)
            }
        )

        pop.contentViewController = NSHostingController(rootView: popoverView)
        self.popover = pop

        // 3. Wire reactive state observation
        appState.onStateChange = { [weak self] in
            self?.updateMenuBarButton()
        }

        // 4. Initial button render
        updateMenuBarButton()
    }

    /// Updates the menu bar icon, status tint, and anti-jitter monospaced text.
    public func updateMenuBarButton() {
        guard let button = statusItem?.button, let state = appState else { return }

        let iconName = state.menuBarIconName
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)

        if let symbolImage = NSImage(systemSymbolName: iconName, accessibilityDescription: "SSD Health")?.withSymbolConfiguration(config) {
            button.image = symbolImage
            button.imagePosition = .imageLeading
        }

        let title = state.menuBarTitle
        if !title.isEmpty {
            button.title = " " + title
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    /// Toggles the transient popover visibility.
    public func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Bring application to active state for popover key focus
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Closes the popover if currently visible.
    public func closePopover() {
        popover?.performClose(nil)
    }

    /// Teardown the status item and popover on app exit.
    public func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        popover?.performClose(nil)
        popover = nil
    }

    /// Displays the right-click context menu.
    public func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        let openDashboardItem = NSMenuItem(title: "Open Dashboard...", action: #selector(openDashboardAction), keyEquivalent: "d")
        openDashboardItem.target = self
        menu.addItem(openDashboardItem)

        let refreshItem = NSMenuItem(title: "Refresh Telemetry", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SSD Health", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Restore left/right click routing
    }

    @objc private func openDashboardAction() {
        openDashboardWindow(selectedTab: .overview)
    }

    @objc private func refreshAction() {
        Task { @MainActor in
            await appState?.refreshNow()
            updateMenuBarButton()
        }
    }

    @objc private func openSettingsAction() {
        openDashboardWindow(selectedTab: .settings)
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    /// Opens or brings to front the full analytics dashboard window.
    public func openDashboardWindow(selectedTab: DashboardTab = .overview) {
        closePopover()

        guard let state = appState else { return }
        state.selectedTab = selectedTab

        if let existing = dashboardWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = DashboardView(appState: state)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.setFrameAutosaveName("SSDHealthDashboardWindow")
        window.title = "SSD Health & SMART Analytics"
        window.titlebarAppearsTransparent = true
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 560)

        self.dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
