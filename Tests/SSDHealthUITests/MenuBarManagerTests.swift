import XCTest
import SwiftUI
import AppKit
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

@MainActor
final class MenuBarManagerTests: XCTestCase {

    var settings: AppSettings!
    var userDefaults: UserDefaults!

    override func setUp() async throws {
        // Status items and windows need a window server connection, which only exists once
        // NSApplication is initialized; a bare xctest process otherwise aborts in CGSConnectionByID.
        _ = NSApplication.shared
        try await super.setUp()
        let suiteName = "test.suite.menubar.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        settings = AppSettings(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        userDefaults = nil
        settings = nil
        try await super.tearDown()
    }

    // MARK: - Display Mode Formatting

    func testMenuBar_TitleFormatting_AllFourModes_Celsius() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD",
            serialNumber: "SN123",
            firmwareRevision: "1.0",
            interconnect: "PCIe",
            capacityBytes: 500_000_000_000,
            healthScorePercent: 98,
            wearPercentage: 2,
            temperatureCelsius: 38.4,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 12.5,
            terabytesRead: 20.1,
            powerOnHours: 1000,
            powerCycles: 200,
            unsafeShutdowns: 3,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let mockReader = MockSSDStorageReader(preset: .healthy, customMetrics: metrics)
        let state = AppState(storageReader: mockReader, settings: settings)
        state.currentMetrics = metrics

        // 1. Icon Only
        settings.displayMode = .iconOnly
        XCTAssertEqual(state.menuBarTitle, "")

        // 2. Health Percent
        settings.displayMode = .healthPercent
        XCTAssertEqual(state.menuBarTitle, "98%")

        // 3. Temperature
        settings.displayMode = .temperature
        XCTAssertEqual(state.menuBarTitle, "38°C")

        // 4. Combined
        settings.displayMode = .combined
        XCTAssertEqual(state.menuBarTitle, "98% · 38°C")
    }

    func testMenuBar_TitleFormatting_FahrenheitUnit() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD",
            serialNumber: "SN123",
            firmwareRevision: "1.0",
            interconnect: "PCIe",
            capacityBytes: 500_000_000_000,
            healthScorePercent: 95,
            wearPercentage: 5,
            temperatureCelsius: 40.0, // 40°C = 104°F
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 12.5,
            terabytesRead: 20.1,
            powerOnHours: 1000,
            powerCycles: 200,
            unsafeShutdowns: 3,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        state.currentMetrics = metrics

        settings.temperatureUnit = .fahrenheit
        settings.displayMode = .temperature
        XCTAssertEqual(state.menuBarTitle, "104°F")

        settings.displayMode = .combined
        XCTAssertEqual(state.menuBarTitle, "95% · 104°F")
    }

    func testMenuBar_NilMetrics_ReturnsFallbackTitle() {
        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        state.currentMetrics = nil

        XCTAssertEqual(state.menuBarTitle, "--%")
    }

    // MARK: - Health Status & Dynamic SF Symbol

    func testMenuBar_HealthStatusEvaluation_MapsCorrectly() {
        // Healthy
        let healthy = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 35.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 10, terabytesRead: 10,
            powerOnHours: 100, powerCycles: 50, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(HealthStatus.evaluate(metrics: healthy), .good)
        XCTAssertEqual(HealthStatus.evaluate(metrics: healthy).iconName, "internaldrive")

        // Warning (Wear 82% -> Health 18%)
        let warning = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 18, wearPercentage: 82, temperatureCelsius: 40.0,
            availableSparePercent: 90, availableSpareThresholdPercent: 10, terabytesWritten: 100, terabytesRead: 100,
            powerOnHours: 1000, powerCycles: 500, unsafeShutdowns: 5, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(HealthStatus.evaluate(metrics: warning), .warning)
        XCTAssertEqual(HealthStatus.evaluate(metrics: warning).iconName, "exclamationmark.triangle.fill")

        // Critical (Critical Warning Bitmask Set)
        let critical = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 80, wearPercentage: 20, temperatureCelsius: 40.0,
            availableSparePercent: 90, availableSpareThresholdPercent: 10, terabytesWritten: 50, terabytesRead: 50,
            powerOnHours: 500, powerCycles: 200, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: [.reliabilityDegraded]
        )
        XCTAssertEqual(HealthStatus.evaluate(metrics: critical), .critical)
        XCTAssertEqual(HealthStatus.evaluate(metrics: critical).iconName, "exclamationmark.octagon.fill")
    }

    // MARK: - MenuBarStatusView Declarative Rendering

    func testMenuBarStatusView_InitWithMetrics() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 92, wearPercentage: 8, temperatureCelsius: 41.2,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 15, terabytesRead: 25,
            powerOnHours: 200, powerCycles: 80, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let view = MenuBarStatusView(metrics: metrics, mode: .combined, unit: .celsius)
        XCTAssertEqual(view.status, .good)
        XCTAssertEqual(view.title, "92% · 41°C")
        XCTAssertEqual(view.iconName, "internaldrive")
    }

    // MARK: - CircularGaugeView Component Tests

    func testCircularGaugeView_ClampingAndProperties() {
        let gaugeNormal = CircularGaugeView(score: 95, size: 100, lineWidth: 10, showLabel: true, title: "HEALTH", subtitle: "5% Wear")
        XCTAssertEqual(gaugeNormal.score, 95)
        XCTAssertEqual(gaugeNormal.size, 100)
        XCTAssertEqual(gaugeNormal.lineWidth, 10)
        XCTAssertEqual(gaugeNormal.showLabel, true)
        XCTAssertEqual(gaugeNormal.title, "HEALTH")
        XCTAssertEqual(gaugeNormal.subtitle, "5% Wear")

        // Over-clamped > 100
        let gaugeOver = CircularGaugeView(score: 150)
        XCTAssertEqual(gaugeOver.score, 100)

        // Under-clamped < 0
        let gaugeUnder = CircularGaugeView(score: -20)
        XCTAssertEqual(gaugeUnder.score, 0)
    }

    // MARK: - TemperatureUnit Formatting Tests

    func testTemperatureUnit_FormattingHelpers() {
        let celsius = TemperatureUnit.celsius
        XCTAssertEqual(celsius.format(celsius: 42.45), "42.5 °C")
        XCTAssertEqual(celsius.formatRounded(celsius: 42.45), "42°C")

        let fahrenheit = TemperatureUnit.fahrenheit
        // 40°C = 104°F
        XCTAssertEqual(fahrenheit.format(celsius: 40.0), "104.0 °F")
        XCTAssertEqual(fahrenheit.formatRounded(celsius: 40.0), "104°F")
    }

    // MARK: - MenuBarManager Setup & Window Management

    func testMenuBarManager_SetupAndWindowController() {
        let manager = MenuBarManager.shared
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(storageReader: mockReader, settings: settings)

        manager.setup(appState: state)

        XCTAssertNotNil(manager.statusItem)
        XCTAssertNotNil(manager.popover)
        XCTAssertNotNil(manager.appState)

        // Opening dashboard window
        manager.openDashboardWindow(selectedTab: .smartTable)
        XCTAssertNotNil(manager.dashboardWindow)
        XCTAssertEqual(state.selectedTab, .smartTable)

        // Re-opening existing dashboard window
        manager.openDashboardWindow(selectedTab: .forecast)
        XCTAssertEqual(state.selectedTab, .forecast)

        // Close popover
        manager.closePopover()
    }
}
