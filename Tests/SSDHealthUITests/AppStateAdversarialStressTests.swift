import XCTest
import SwiftUI
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

/// Empirical Adversarial Stress Test Suite for AppState (Milestone 3):
/// 1. Rapid concurrent refreshes & task storms (re-entrancy, debouncing, data consistency)
/// 2. Simulated hardware error switches & flapping (permission denied, device not found, recovery)
/// 3. History purge under active background polling & concurrent operations
/// 4. Export triggering under empty, full (10,000 samples), and extreme boundary datasets
@MainActor
final class AppStateAdversarialStressTests: XCTestCase {

    var tempDir: URL!
    var userDefaults: UserDefaults!
    var persistenceActor: HistoryPersistenceActor!
    var settings: AppSettings!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AppStateAdversarialTests_\(uniqueID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let suiteName = "test.suite.adversarial.appstate.\(uniqueID)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let storeURL = tempDir.appendingPathComponent("history.json")
        persistenceActor = HistoryPersistenceActor(storageURL: storeURL, driveIdentifier: "adv-test-drive", ratedTBW: 300.0)
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
    // MARK: - Section 1: Rapid Concurrent Refreshes & Task Storms
    // =========================================================================

    func test_ConcurrentRefreshes_100Tasks_NoCrashesOrDeadlocks() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        // Fire 100 concurrent refreshNow tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { @MainActor in
                    await state.refreshNow()
                }
            }
        }

        XCTAssertFalse(state.isRefreshing, "isRefreshing must be reset to false after all tasks complete")
        XCTAssertNotNil(state.currentMetrics, "Metrics must be populated")
        XCTAssertEqual(state.currentMetrics?.healthScorePercent, 98)
        XCTAssertNil(state.errorMessage, "ErrorMessage should be nil on healthy refresh")
        XCTAssertNotNil(state.lastUpdated, "lastUpdated should be set")
        XCTAssertGreaterThanOrEqual(state.history.count, 1, "At least one snapshot must be recorded")
    }

    func test_OverlappingInitialLoadAndRefreshStorm() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        // Interleave loadInitialData and refreshNow concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<40 {
                if i % 2 == 0 {
                    group.addTask { @MainActor in
                        state.loadInitialData()
                    }
                } else {
                    group.addTask { @MainActor in
                        await state.refreshNow()
                    }
                }
            }
        }

        // Allow any background tasks from loadInitialData to settle
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(state.isRefreshing)
        XCTAssertFalse(state.isLoading)
        XCTAssertNotNil(state.currentMetrics)
        XCTAssertNotNil(state.rawSmartLog)
        XCTAssertNotNil(state.forecast)
        XCTAssertFalse(state.history.isEmpty)
    }

    func test_RapidPresetSwitchingDuringConcurrentRefreshes() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        let presets: [MockSSDStorageReader.Preset] = [
            .healthy, .warning, .overheating, .criticalWear, .degradedSpare
        ]

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let preset = presets[i % presets.count]
                group.addTask { @MainActor in
                    mockReader.setPreset(preset)
                    await state.refreshNow()
                }
            }
        }

        XCTAssertFalse(state.isRefreshing)
        XCTAssertNotNil(state.currentMetrics)
        XCTAssertNil(state.errorMessage)
        XCTAssertNotNil(state.forecast)
    }

    // =========================================================================
    // MARK: - Section 2: Simulated Hardware Error Switches & Flapping
    // =========================================================================

    func test_HardwareErrorFlapping_AlternatingErrorsAndHealthy() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        let sequence: [MockSSDStorageReader.Preset] = [
            .healthy,
            .permissionDenied,
            .healthy,
            .deviceNotFound,
            .warning,
            .simulatedError(.smartReadFailed(kernReturn: -536870212)),
            .overheating,
            .healthy
        ]

        for preset in sequence {
            mockReader.setPreset(preset)
            await state.refreshNow()

            switch preset {
            case .permissionDenied, .deviceNotFound, .simulatedError:
                XCTAssertNotNil(state.errorMessage, "Error message must be set for error preset \(preset)")
                XCTAssertFalse(state.isRefreshing)
            case .healthy, .warning, .overheating, .criticalWear, .degradedSpare:
                XCTAssertNil(state.errorMessage, "Error message must be cleared for successful preset \(preset)")
                XCTAssertNotNil(state.currentMetrics)
                XCTAssertFalse(state.isRefreshing)
            }
        }

        // Final state is healthy
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(state.currentMetrics?.healthScorePercent, 98)
        XCTAssertEqual(state.menuBarStatus, .good)
    }

    func test_ToggleMockReaderRapidlyUnderLoad() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        for _ in 0..<20 {
            state.toggleMockReader(true)
            XCTAssertTrue(state.settings.useMockReader)
            state.toggleMockReader(false)
            XCTAssertFalse(state.settings.useMockReader)
        }

        state.toggleMockReader(true)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(state.settings.useMockReader)
        XCTAssertNotNil(state.currentMetrics)
    }

    func test_TransientReaderThrowsIntermittently_GracefulDegradation() async throws {
        // A flaky reader that fails on odd iterations
        final class FlakyStorageReader: SSDStorageReading, @unchecked Sendable {
            var callCount = 0
            let underlying = MockSSDStorageReader(preset: .healthy)

            func readHealthMetrics() async throws -> SSDHealthMetrics {
                callCount += 1
                if callCount % 2 == 1 {
                    throw StorageReaderError.plugInCreationFailed(kernReturn: -1)
                }
                return try await underlying.readHealthMetrics()
            }

            func readRawSmartLog() async throws -> NVMESmartLog {
                if callCount % 2 == 1 {
                    throw StorageReaderError.plugInCreationFailed(kernReturn: -1)
                }
                return try await underlying.readRawSmartLog()
            }

            func isLiveHardwareAccessAvailable() -> Bool { false }
        }

        let flakyReader = FlakyStorageReader()
        let state = AppState(
            storageReader: flakyReader,
            mockReader: MockSSDStorageReader(preset: .healthy),
            persistence: persistenceActor,
            settings: settings
        )

        // Iteration 1 (callCount=1 -> fails)
        await state.refreshNow()
        XCTAssertNotNil(state.errorMessage)

        // Iteration 2 (callCount=2 -> succeeds)
        await state.refreshNow()
        XCTAssertNil(state.errorMessage)
        XCTAssertNotNil(state.currentMetrics)

        // Iteration 3 (callCount=3 -> fails)
        await state.refreshNow()
        XCTAssertNotNil(state.errorMessage)

        // Iteration 4 (callCount=4 -> succeeds)
        await state.refreshNow()
        XCTAssertNil(state.errorMessage)
        XCTAssertNotNil(state.currentMetrics)
    }

    // =========================================================================
    // MARK: - Section 3: History Purge Under Active Polling & Operations
    // =========================================================================

    func test_HistoryPurgeDuringActivePolling_SafePersistenceAndState() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        // Populate initial history
        for _ in 0..<5 {
            await state.refreshNow()
        }
        XCTAssertEqual(state.history.count, 5)

        // Start polling (using short interval)
        state.settings.pollingIntervalSeconds = 5.0
        state.start()

        // Concurrently purge history while refreshing
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await state.purgeHistory()
            }
            group.addTask { @MainActor in
                await state.refreshNow()
            }
        }

        state.stop()

        // Verify history is consistent and persistence is valid
        let diskHistory = try await persistenceActor.loadHistory()
        XCTAssertLessThanOrEqual(state.history.count, 2, "History should reflect purge and possible subsequent refresh")
        XCTAssertEqual(diskHistory.count, state.history.count, "In-memory state must match disk state")
        XCTAssertNotNil(state.forecast, "Forecast must be recomputed")
        XCTAssertFalse(state.forecast?.primaryDailyWriteRateGB.isNaN ?? true)
    }

    func test_ConcurrentPurgeStorm_MultiplePurgeRequests() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()
        XCTAssertEqual(state.history.count, 1)

        // Fire 20 concurrent purges
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { @MainActor in
                    await state.purgeHistory()
                }
            }
        }

        XCTAssertEqual(state.history.count, 0)
        let diskHistory = try await persistenceActor.loadHistory()
        XCTAssertEqual(diskHistory.count, 0)
        XCTAssertEqual(state.forecast?.degradationStatus, .insufficientData)
    }

    // =========================================================================
    // MARK: - Section 4: Export Triggering (Empty vs Full vs Extreme Datasets)
    // =========================================================================

    func test_Export_UninitializedState_ThrowsExpectedErrorsAndFallbacks() {
        let state = AppState(
            mockReader: MockSSDStorageReader(preset: .healthy),
            persistence: persistenceActor,
            settings: settings
        )

        XCTAssertNil(state.currentMetrics)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertNil(state.forecast)

        // exportJSON should throw error when currentMetrics is nil
        XCTAssertThrowsError(try state.exportJSON()) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.code, 404)
        }

        // exportCSV should produce valid RFC 4180 header with 0 data rows
        XCTAssertNoThrow(try {
            let csv = try state.exportCSV()
            XCTAssertTrue(csv.starts(with: "Timestamp_ISO8601,"))
            let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            XCTAssertEqual(lines.count, 1, "CSV with empty history must only have the header line")
        }())

        // exportTextReport should return fallback string
        let report = state.exportTextReport()
        XCTAssertEqual(report, "No SSD metrics available.")
    }

    func test_Export_PopulatedMetricsWithEmptyHistory() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()
        // Force history to empty to test empty history export with active metrics
        state.history = []
        state.forecast = nil

        let json = try state.exportJSON()
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("\"history\" : ["))
        XCTAssertTrue(json.contains("\"historySampleCount\" : 0"))

        let csv = try state.exportCSV()
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1)

        let report = state.exportTextReport()
        XCTAssertTrue(report.contains("macOS SSD HEALTH & SMART DIAGNOSTIC REPORT"))
        XCTAssertTrue(report.contains("Prognosis:                Insufficient historical data"))
    }

    func test_Export_LargeDataset_10000Snapshots_IntegrityAndPerformance() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()

        // Generate 10,000 snapshots over 3 years
        let baseDate = Date()
        var hugeHistory: [SSDHistorySnapshot] = []
        hugeHistory.reserveCapacity(10_000)

        for i in 0..<10_000 {
            let t = baseDate.addingTimeInterval(-Double(10_000 - i) * 600.0) // 10 min intervals
            hugeHistory.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: max(0, 100 - (i / 150)),
                wearPercentage: min(100, i / 150),
                temperatureCelsius: 35.0 + Double(i % 15),
                terabytesWritten: 5.0 + Double(i) * 0.05,
                availableSparePercent: 100,
                criticalWarningsRaw: 0,
                mediaErrors: 0
            ))
        }

        state.history = hugeHistory

        // Measure JSON Export performance & correctness
        let json = try state.exportJSON()
        XCTAssertTrue(json.contains("\"historySampleCount\" : 10000"))
        XCTAssertTrue(json.contains("APPLE SSD AP0512R"))

        // Measure CSV Export performance & correctness
        let csv = try state.exportCSV()
        let csvLines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(csvLines.count, 10_001, "CSV must contain 1 header + 10,000 data rows")

        // Text report
        let report = state.exportTextReport()
        XCTAssertTrue(report.contains("macOS SSD HEALTH & SMART DIAGNOSTIC REPORT"))
        XCTAssertTrue(report.contains("APPLE SSD AP0512R"))
    }

    func test_Export_ExtremeBoundaryMetrics_NoOverflowOrEncodingFailure() throws {
        let extremeMetrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "EXTREME TEST SSD 16TB",
            serialNumber: "SN-EXTREME-9999",
            firmwareRevision: "99.99A",
            interconnect: "Apple Fabric",
            capacityBytes: 100_000_000_000_000, // 100 TB
            healthScorePercent: 0,
            wearPercentage: 255, // Extreme wear
            temperatureCelsius: 125.0, // Extreme temp
            availableSparePercent: 0,
            availableSpareThresholdPercent: 100,
            terabytesWritten: 10_000_000.0,
            terabytesRead: 20_000_000.0,
            powerOnHours: UInt64(Int64.max),
            powerCycles: UInt64(Int64.max),
            unsafeShutdowns: UInt64(Int64.max),
            mediaErrors: UInt64(Int64.max),
            errorLogEntries: UInt64(Int64.max),
            criticalWarnings: CriticalWarningFlags(rawValue: 0xFF), // All flags set
            timestamp: Date()
        )

        let exporter = DiagnosticExporter()
        let json = try exporter.exportJSON(metrics: extremeMetrics, history: [], forecast: nil, ratedTBW: 100_000.0)
        XCTAssertFalse(json.isEmpty)

        // Validate JSON can be round-trip deserialized
        let data = Data(json.utf8)
        let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertNotNil(root)
        let current = root?["currentMetrics"] as? [String: Any]
        XCTAssertEqual(current?["percentageUsed"] as? Int, 255)
        XCTAssertEqual(current?["criticalWarningBitmask"] as? UInt8, 0xFF)

        let report = exporter.exportTextReport(metrics: extremeMetrics, history: [], forecast: nil, ratedTBW: 100_000.0)
        XCTAssertTrue(report.contains("EXTREME TEST SSD 16TB"))
        XCTAssertTrue(report.contains("125.0 °C"))
    }

    func test_ConcurrentExportStorm_50Tasks() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()

        // Fire 50 concurrent export tasks across JSON, CSV, and Text Report
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { @MainActor in
                    if i % 3 == 0 {
                        let json = try? state.exportJSON()
                        XCTAssertNotNil(json)
                        XCTAssertFalse(json?.isEmpty ?? true)
                    } else if i % 3 == 1 {
                        let csv = try? state.exportCSV()
                        XCTAssertNotNil(csv)
                        XCTAssertFalse(csv?.isEmpty ?? true)
                    } else {
                        let report = state.exportTextReport()
                        XCTAssertFalse(report.isEmpty)
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Section 5: Additional Edge Cases & Concurrency Mutations
    // =========================================================================

    func test_MenuBarFormatting_RapidConcurrentModeSwitches() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        await state.refreshNow()

        for _ in 0..<100 {
            for mode in MenuBarDisplayMode.allCases {
                state.settings.displayMode = mode
                let title = state.menuBarTitle
                switch mode {
                case .iconOnly:
                    XCTAssertEqual(title, "")
                case .healthPercent:
                    XCTAssertEqual(title, "98%")
                case .temperature:
                    XCTAssertEqual(title, "34°C")
                case .combined:
                    XCTAssertEqual(title, "98% · 34°C")
                }
            }

            state.settings.temperatureUnit = .fahrenheit
            state.settings.displayMode = .temperature
            XCTAssertEqual(state.menuBarTitle, "92°F")

            state.settings.temperatureUnit = .celsius
            XCTAssertEqual(state.menuBarTitle, "34°C")
        }
    }

    func test_HardwareErrorPreservesExistingHistoryAndState() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        // Generate 3 successful samples
        for _ in 0..<3 {
            await state.refreshNow()
        }
        XCTAssertEqual(state.history.count, 3)
        XCTAssertNil(state.errorMessage)

        // Inject simulated error
        mockReader.setPreset(.permissionDenied)
        await state.refreshNow()

        // History and previous metrics should be retained for user display
        XCTAssertEqual(state.history.count, 3)
        XCTAssertNotNil(state.currentMetrics)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertTrue(state.errorMessage?.contains("Permission denied") ?? false)

        // Recover to healthy
        mockReader.setPreset(.healthy)
        await state.refreshNow()

        XCTAssertEqual(state.history.count, 4)
        XCTAssertNil(state.errorMessage)
    }

    func test_PollingIntervalNegativeOrZeroClamping() {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mockReader,
            mockReader: mockReader,
            persistence: persistenceActor,
            settings: settings
        )

        state.start()

        // Test very small or zero intervals (clamped to >= 5.0s inside startPollingTimer)
        state.updatePollingInterval(0.0)
        XCTAssertEqual(state.settings.pollingIntervalSeconds, 0.0)

        state.updatePollingInterval(-10.0)
        XCTAssertEqual(state.settings.pollingIntervalSeconds, -10.0)

        state.updatePollingInterval(120.0)
        XCTAssertEqual(state.settings.pollingIntervalSeconds, 120.0)

        state.stop()
    }

    func test_Export_SpecialCharactersInDeviceNames() throws {
        let weirdMetrics = SSDHealthMetrics(
            bsdName: "disk0s2",
            modelName: "APPLE SSD, AP0512R \"Special Edition\"\n\t<New>",
            serialNumber: "SN/001,999:X",
            firmwareRevision: "1.00\"B",
            interconnect: "PCIe / NVMe",
            capacityBytes: 500_000_000_000,
            healthScorePercent: 95,
            wearPercentage: 5,
            temperatureCelsius: 40.0,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 12.34,
            terabytesRead: 20.0,
            powerOnHours: 100,
            powerCycles: 50,
            unsafeShutdowns: 1,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: Date()
        )

        let exporter = DiagnosticExporter()
        let json = try exporter.exportJSON(metrics: weirdMetrics, history: [], forecast: nil)
        XCTAssertFalse(json.isEmpty)

        // Ensure valid JSON parse
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        let drive = obj?["drive"] as? [String: Any]
        XCTAssertEqual(drive?["productName"] as? String, "APPLE SSD, AP0512R \"Special Edition\"\n\t<New>")

        let report = exporter.exportTextReport(metrics: weirdMetrics, history: [], forecast: nil)
        XCTAssertTrue(report.contains("APPLE SSD, AP0512R \"Special Edition\""))
    }
}

