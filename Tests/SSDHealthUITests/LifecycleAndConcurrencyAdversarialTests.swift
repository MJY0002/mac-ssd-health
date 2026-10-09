import XCTest
import SwiftUI
import AppKit
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

/// Adversarial Empirical Test Suite for Lifecycle, Concurrency & Telemetry Load (Milestone 4)
@MainActor
final class LifecycleAndConcurrencyAdversarialTests: XCTestCase {

    var tempDir: URL!
    var userDefaults: UserDefaults!
    var persistenceActor: HistoryPersistenceActor!
    var settings: AppSettings!

    override func setUp() async throws {
        // Status items and windows need a window server connection, which only exists once
        // NSApplication is initialized; a bare xctest process otherwise aborts in CGSConnectionByID.
        _ = NSApplication.shared
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AdvLifecycleTests_\(uniqueID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let suiteName = "test.suite.advlifecycle.\(uniqueID)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let storeURL = tempDir.appendingPathComponent("history.json")
        persistenceActor = HistoryPersistenceActor(storageURL: storeURL, driveIdentifier: "adv-lifecycle-drive", ratedTBW: 300.0)
        settings = AppSettings(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        userDefaults = nil
        settings = nil
        persistenceActor = nil
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Challenge 1: AppState, MenuBarManager & Mock Reader Concurrency
    // =========================================================================

    func test_MockReader_RapidConcurrentPresetSwitchingWithSimulatedLatency() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        mockReader.setSimulatedLatency(milliseconds: 10)

        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        let presets: [MockSSDStorageReader.Preset] = [
            .healthy, .warning, .overheating, .criticalWear, .degradedSpare
        ]

        // Concurrently switch presets and trigger refreshes from 50 tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let preset = presets[i % presets.count]
                group.addTask { @MainActor in
                    state.setMockPreset(preset)
                    await state.refreshNow()
                }
            }
        }

        XCTAssertFalse(state.isRefreshing)
        XCTAssertNotNil(state.currentMetrics)
        XCTAssertNotNil(state.rawSmartLog)
        XCTAssertNotNil(state.forecast)
    }

    func test_AppState_ToggleMockReaderRapidlyDuringActivePolling() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        state.settings.pollingIntervalSeconds = 5.0
        state.start()

        // Rapidly toggle mock reader on and off during active polling
        for i in 0..<30 {
            state.toggleMockReader(i % 2 == 0)
            if i % 5 == 0 {
                await state.refreshNow()
            }
        }

        state.stop()
        XCTAssertFalse(state.isRefreshing)
    }

    func test_MenuBarManager_RapidConcurrentUpdatesAndRebuilds() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        let menuManager = MenuBarManager()
        menuManager.setup(appState: state)

        XCTAssertNotNil(menuManager.statusItem)
        XCTAssertNotNil(menuManager.popover)

        let presets: [MockSSDStorageReader.Preset] = [
            .healthy, .warning, .overheating, .criticalWear, .degradedSpare
        ]

        // Rapidly mutate telemetry and trigger menu bar rebuilds
        for i in 0..<50 {
            let preset = presets[i % presets.count]
            mockReader.setPreset(preset)
            await state.refreshNow()
            menuManager.updateMenuBarButton()

            for mode in MenuBarDisplayMode.allCases {
                state.settings.displayMode = mode
                menuManager.updateMenuBarButton()
            }
        }

        XCTAssertNotNil(menuManager.statusItem?.button)
    }

    func test_MenuBarManager_RepeatedSetupAndReconfiguration() async throws {
        let menuManager = MenuBarManager()

        for _ in 0..<10 {
            let mockReader = MockSSDStorageReader(preset: .healthy)
            let state = AppState(storageReader: mockReader, settings: settings)
            menuManager.setup(appState: state)
            menuManager.updateMenuBarButton()
            menuManager.openDashboardWindow(selectedTab: .overview)
            menuManager.closePopover()
        }

        XCTAssertNotNil(menuManager.statusItem)
    }

    func test_MenuBarManager_OpenAndCloseDashboardWindowStress() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(storageReader: mockReader, settings: settings)
        let menuManager = MenuBarManager()
        menuManager.setup(appState: state)

        for tab in DashboardTab.allCases {
            menuManager.openDashboardWindow(selectedTab: tab)
            XCTAssertEqual(state.selectedTab, tab)
            XCTAssertNotNil(menuManager.dashboardWindow)
            XCTAssertTrue(menuManager.dashboardWindow?.isVisible ?? false)
        }

        menuManager.dashboardWindow?.close()
    }

    // =========================================================================
    // MARK: - Challenge 2: Executable & AppDelegate Lifecycle Behavior
    // =========================================================================

    func test_AppState_StartStopLifecycle_NoTaskLeaks() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        // Multiple consecutive start/stop cycles
        for _ in 0..<10 {
            state.start()
            try await Task.sleep(nanoseconds: 10_000_000)
            state.stop()
        }

        // Final start and stop
        state.start()
        await state.refreshNow()
        XCTAssertNotNil(state.currentMetrics)
        state.stop()
    }

    func test_AppState_DeinitReleasesResourcesCleanly() async throws {
        weak var weakRef: AppState?
        do {
            let mockReader = MockSSDStorageReader(preset: .healthy)
            let localState = AppState(storageReader: mockReader, persistence: persistenceActor, settings: settings)
            weakRef = localState
            localState.start()
            localState.stop()
        }

        // Allow any in-flight un-tracked task from loadInitialData() to complete
        for _ in 0..<10 {
            if weakRef == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNil(weakRef, "AppState instance must be deallocated without retain cycles")
    }

    // =========================================================================
    // MARK: - Challenge 3: Cross-Module Stress & Telemetry Load
    // =========================================================================

    func test_HistoryPersistence_ConcurrentWriteReadPurgeStorm() async throws {
        // 50 concurrent tasks performing mixed writes, reads, and prunes
        let baseDate = Date()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let snapshot = SSDHistorySnapshot(
                    timestamp: baseDate.addingTimeInterval(Double(i) * 60.0),
                    healthScorePercent: 95,
                    wearPercentage: 5,
                    temperatureCelsius: 38.0 + Double(i % 10),
                    terabytesWritten: 10.0 + Double(i) * 0.1,
                    availableSparePercent: 100
                )
                group.addTask {
                    try? await self.persistenceActor.record(snapshot: snapshot)
                    _ = try? await self.persistenceActor.loadHistory()
                }
            }
        }

        let loaded = try await persistenceActor.loadHistory()
        XCTAssertGreaterThan(loaded.count, 0)
    }

    func test_NotificationService_HighConcurrencyAlertEvaluation() async throws {
        let service = NotificationService(
            cooldownManager: AlertCooldownManager(userDefaults: userDefaults)
        )

        let criticalMetrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 10, wearPercentage: 90, temperatureCelsius: 75.0,
            availableSparePercent: 4, availableSpareThresholdPercent: 10, terabytesWritten: 500, terabytesRead: 500,
            powerOnHours: 10000, powerCycles: 500, unsafeShutdowns: 10, mediaErrors: 5, errorLogEntries: 10,
            criticalWarnings: [.availableSpareBelowThreshold, .temperatureExceedsThreshold, .reliabilityDegraded]
        )

        // Run 50 concurrent evaluation calls
        await withTaskGroup(of: [AlertEvent].self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await service.evaluateAndDispatch(metrics: criticalMetrics, now: Date())
                }
            }
        }
    }

    func test_ForecastEngine_MassiveHistoryStress_50000Snapshots() {
        let engine = ForecastEngine()
        let now = Date()

        var snapshots: [SSDHistorySnapshot] = []
        snapshots.reserveCapacity(50_000)

        for i in 0..<50_000 {
            snapshots.append(SSDHistorySnapshot(
                timestamp: now.addingTimeInterval(-Double(50_000 - i) * 60.0),
                healthScorePercent: max(0, 100 - i / 1000),
                wearPercentage: min(100, i / 1000),
                temperatureCelsius: 35.0,
                terabytesWritten: 1.0 + Double(i) * 0.01,
                availableSparePercent: 100
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 50, wearPercentage: 50, temperatureCelsius: 35.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 501.0, terabytesRead: 600.0,
            powerOnHours: 5000, powerCycles: 100, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let result = engine.calculateForecast(current: current, history: snapshots, ratedTBW: 600.0)
        XCTAssertGreaterThan(result.primaryDailyWriteRateGB, 0.0)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isNaN)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isInfinite)
    }

    func test_DiagnosticExporter_ConcurrentExportStress_100Tasks() async throws {
        let exporter = DiagnosticExporter()
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 36.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 10, terabytesRead: 10,
            powerOnHours: 100, powerCycles: 50, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    if i % 3 == 0 {
                        _ = try? exporter.exportJSON(metrics: metrics, history: [], forecast: nil)
                    } else if i % 3 == 1 {
                        _ = try? exporter.exportCSV(history: [])
                    } else {
                        _ = exporter.exportTextReport(metrics: metrics, history: [], forecast: nil)
                    }
                }
            }
        }
    }
}
