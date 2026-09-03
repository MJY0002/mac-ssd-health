import XCTest
import SwiftUI
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

@MainActor
final class AppStateTests: XCTestCase {

    var tempDir: URL!
    var userDefaults: UserDefaults!
    var persistenceActor: HistoryPersistenceActor!
    var settings: AppSettings!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AppStateTests_\(uniqueID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let suiteName = "test.suite.appstate.\(uniqueID)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let storeURL = tempDir.appendingPathComponent("history.json")
        persistenceActor = HistoryPersistenceActor(storageURL: storeURL, driveIdentifier: "test-drive")
        settings = AppSettings(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        userDefaults = nil
        settings = nil
        try await super.tearDown()
    }

    // MARK: - Initial State & Data Loading

    func testAppState_InitialLoad_FetchesMetricsAndForecast() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.currentMetrics)

        state.loadInitialData()

        // Wait for async load
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(state.currentMetrics)
        XCTAssertEqual(state.currentMetrics?.healthScorePercent, 98)
        XCTAssertEqual(state.currentMetrics?.wearPercentage, 2)
        XCTAssertNotNil(state.rawSmartLog)
        XCTAssertNotNil(state.forecast)
        XCTAssertEqual(state.history.count, 1)
        XCTAssertNil(state.errorMessage)
    }

    func testAppState_RefreshNow_UpdatesMetricsAndHistory() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()

        XCTAssertNotNil(state.currentMetrics)
        XCTAssertEqual(state.currentMetrics?.healthScorePercent, 98)
        XCTAssertEqual(state.history.count, 1)

        // Switch to warning preset and refresh
        mockReader.setPreset(.warning)
        await state.refreshNow()

        XCTAssertEqual(state.currentMetrics?.healthScorePercent, 72)
        XCTAssertEqual(state.currentMetrics?.wearPercentage, 28)
        XCTAssertEqual(state.history.count, 2)
        XCTAssertEqual(state.menuBarStatus, .warning) // 56.0°C >= 55.0°C triggers warning
    }

    // MARK: - Mock / Live Reader Switching

    func testAppState_ToggleMockReader_SwitchesActiveReader() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        XCTAssertFalse(state.settings.useMockReader)

        // Enable mock mode
        state.toggleMockReader(true)
        XCTAssertTrue(state.settings.useMockReader)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(state.currentMetrics)

        // Switch preset
        state.setMockPreset(.overheating)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.currentMetrics?.criticalWarnings.contains(.temperatureExceedsThreshold), true)
        XCTAssertEqual(state.menuBarStatus, .critical)
    }

    // MARK: - Error Handling

    func testAppState_SimulatedError_SetsErrorMessageGracefully() async throws {
        let mockReader = MockSSDStorageReader(preset: .simulatedError(.permissionDenied(reason: "Sandbox restriction")))
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()

        XCTAssertNotNil(state.errorMessage)
        XCTAssertTrue(state.errorMessage?.contains("Permission denied") ?? false)
    }

    // MARK: - Polling Timer

    func testAppState_PollingTimer_UpdatesIntervalAndLifecycle() {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        state.start()
        state.updatePollingInterval(300.0)
        XCTAssertEqual(state.settings.pollingIntervalSeconds, 300.0)
        XCTAssertEqual(state.settings.pollingIntervalMinutes, 5)

        state.stop()
    }

    // MARK: - History Purge

    func testAppState_PurgeHistory_ClearsPersistedRecords() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()
        await state.refreshNow()
        XCTAssertEqual(state.history.count, 2)

        await state.purgeHistory()
        XCTAssertEqual(state.history.count, 0)

        let loaded = try await persistenceActor.loadHistory()
        XCTAssertEqual(loaded.count, 0)
    }

    // MARK: - Export Generation

    func testAppState_ExportFormats_ProduceValidContent() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()

        let json = try state.exportJSON()
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("currentMetrics"))
        XCTAssertTrue(json.contains("APPLE SSD AP0512R"))

        let csv = try state.exportCSV()
        XCTAssertFalse(csv.isEmpty)
        XCTAssertTrue(csv.contains("Timestamp_ISO8601"))

        let report = state.exportTextReport()
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.contains("macOS SSD HEALTH & SMART DIAGNOSTIC REPORT"))
    }
}
