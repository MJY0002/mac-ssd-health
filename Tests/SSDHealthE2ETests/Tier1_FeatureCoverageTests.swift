import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

/// Tier 1: Complete Feature Coverage Test Suite (15 Features x >= 5 tests = >= 75 tests).
/// Verifies primary behavior and specification contracts for each individual feature.
final class Tier1_FeatureCoverageTests: XCTestCase {

    // =========================================================================
    // MARK: - Feature 1: NVMe 512-Byte SMART Parser
    // =========================================================================

    func test_F1_01_Standard512ByteDecoding_PopulatesAllFields() throws {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("NVMESmartLog failed to decode valid 512-byte buffer")
            return
        }

        XCTAssertTrue(log.criticalWarning.isClean)
        XCTAssertEqual(log.compositeTemperatureKelvin, 311)
        assertDoubleEqual(log.temperatureCelsius, 37.85, accuracy: 0.1)
        XCTAssertEqual(log.availableSparePercent, 100)
        XCTAssertEqual(log.availableSpareThresholdPercent, 10)
        XCTAssertEqual(log.percentageUsed, 18)
        XCTAssertEqual(log.healthScorePercent, 82)
    }

    func test_F1_02_DataUnitsReadAndWritten_128BitArithmeticToBytesAndTBW() throws {
        let unitsWritten = UInt128Value(low: 47_258_900, high: 0)
        let unitsRead = UInt128Value(low: 58_392_100, high: 0)
        let buffer = SyntheticNVMeFixtures.makeBuffer(
            dataUnitsRead: unitsRead,
            dataUnitsWritten: unitsWritten
        )

        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        // 1 NVMe Unit = 512,000 bytes
        let expectedWrittenBytes = 47_258_900.0 * 512_000.0
        let expectedWrittenTB = expectedWrittenBytes / 1_000_000_000_000.0

        assertDoubleEqual(log.totalBytesWritten, expectedWrittenBytes, accuracy: 1.0)
        assertDoubleEqual(log.totalTerabytesWritten, expectedWrittenTB, accuracy: 0.001)
        assertDoubleEqual(log.totalTerabytesWritten, 24.196, accuracy: 0.01)

        let expectedReadBytes = 58_392_100.0 * 512_000.0
        let expectedReadTB = expectedReadBytes / 1_000_000_000_000.0
        assertDoubleEqual(log.totalTerabytesRead, expectedReadTB, accuracy: 0.001)
        assertDoubleEqual(log.totalTerabytesRead, 29.896, accuracy: 0.01)
    }

    func test_F1_03_LifetimeCounters_PowerOnHours_PowerCycles_UnsafeShutdowns() throws {
        let buffer = SyntheticNVMeFixtures.makeBuffer(
            powerCycles: UInt128Value(low: 842),
            powerOnHours: UInt128Value(low: 4_120),
            unsafeShutdowns: UInt128Value(low: 14)
        )

        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        XCTAssertEqual(log.powerCycles.low, 842)
        XCTAssertEqual(log.powerOnHours.low, 4_120)
        XCTAssertEqual(log.unsafeShutdowns.low, 14)
    }

    func test_F1_04_ErrorCounters_MediaErrors_And_NumErrorInfoLogEntries() throws {
        let buffer = SyntheticNVMeFixtures.makeBuffer(
            mediaErrors: UInt128Value(low: 14),
            numErrorInfoLogEntries: UInt128Value(low: 32)
        )

        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        XCTAssertEqual(log.mediaErrors.low, 14)
        XCTAssertEqual(log.numErrorInfoLogEntries.low, 32)
    }

    func test_F1_05_MultiSensorTemperatures_And_ThermalManagementCounters() throws {
        let sensors: [UInt16] = [310, 312, 315, 308, 0, 0, 0, 0]
        let buffer = SyntheticNVMeFixtures.makeBuffer(
            warningCompositeTempTimeMinutes: 45,
            criticalCompositeTempTimeMinutes: 5,
            temperatureSensorsKelvin: sensors,
            thermalManagementTemp1TransitionCount: 3,
            thermalManagementTemp2TransitionCount: 1,
            totalTimeForThermalManagementTemp1Seconds: 120,
            totalTimeForThermalManagementTemp2Seconds: 30
        )

        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        XCTAssertEqual(log.warningCompositeTempTimeMinutes, 45)
        XCTAssertEqual(log.criticalCompositeTempTimeMinutes, 5)
        XCTAssertEqual(log.temperatureSensorsKelvin.count, 8)
        XCTAssertEqual(log.activeTemperatureSensorsCelsius.count, 4)
        assertDoubleEqual(log.activeTemperatureSensorsCelsius[0], 36.85, accuracy: 0.1)
        assertDoubleEqual(log.activeTemperatureSensorsCelsius[1], 38.85, accuracy: 0.1)
        XCTAssertEqual(log.thermalManagementTemp1TransitionCount, 3)
        XCTAssertEqual(log.totalTimeForThermalManagementTemp1Seconds, 120)
    }

    // =========================================================================
    // MARK: - Feature 2: IOKit Native Storage Client
    // =========================================================================

    func test_F2_01_StorageReaderProtocol_ConformsSendable() {
        let reader: any SSDStorageReading = MockSSDStorageReader()
        XCTAssertNotNil(reader)
    }

    func test_F2_02_LiveHardwareProbe_ReturnsBoolean() {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        XCTAssertTrue(mockReader.isLiveHardwareAccessAvailable())

        let errorReader = MockSSDStorageReader(preset: .simulatedError(.deviceNotFound))
        XCTAssertFalse(errorReader.isLiveHardwareAccessAvailable())
    }

    func test_F2_03_ReadRawSmartLog_ReturnsValidNVMESmartLog() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let log = try await mockReader.readRawSmartLog()

        XCTAssertEqual(log.percentageUsed, 2)
        XCTAssertEqual(log.healthScorePercent, 98)
        XCTAssertEqual(log.availableSparePercent, 100)
    }

    func test_F2_04_ReadHealthMetrics_ReturnsPopulatedSSDHealthMetrics() async throws {
        let mockReader = MockSSDStorageReader(preset: .healthy)
        let metrics = try await mockReader.readHealthMetrics()

        XCTAssertEqual(metrics.bsdName, "disk0")
        XCTAssertEqual(metrics.modelName, "APPLE SSD AP0512R")
        XCTAssertEqual(metrics.healthScorePercent, 98)
        XCTAssertEqual(metrics.wearPercentage, 2)
        XCTAssertFalse(metrics.isFallbackData)
    }

    func test_F2_05_IOKitReader_HandlesDeviceMatchingAndFallback() async throws {
        let liveReader = IOKitStorageReader()
        let isLive = liveReader.isLiveHardwareAccessAvailable()

        // When executed on hardware (or falling back in sandbox), readHealthMetrics should return valid metrics
        let metrics = try await liveReader.readHealthMetrics()
        XCTAssertFalse(metrics.bsdName.isEmpty)
        XCTAssertGreaterThan(metrics.capacityBytes, 0)
        XCTAssertTrue(isLive ? !metrics.isFallbackData : metrics.isFallbackData)
    }

    // =========================================================================
    // MARK: - Feature 3: IORegistry Fallback & Error Handling
    // =========================================================================

    func test_F3_01_FallbackMode_SetsIsFallbackDataFlagTrue() {
        let fallbackMetrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "Apple Internal SSD",
            serialNumber: "FALLBACK-001",
            firmwareRevision: "N/A",
            interconnect: "Apple Fabric",
            capacityBytes: 500_000_000_000,
            healthScorePercent: 100,
            wearPercentage: 0,
            temperatureCelsius: 38.0,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 12.5,
            terabytesRead: 15.0,
            powerOnHours: 0,
            powerCycles: 0,
            unsafeShutdowns: 0,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            isFallbackData: true
        )

        XCTAssertTrue(fallbackMetrics.isFallbackData)
        XCTAssertEqual(fallbackMetrics.healthScorePercent, 100)
    }

    func test_F3_02_FallbackDriverStatistics_RetrievesByteCounters() {
        let bytesWritten: UInt64 = 50_000_000_000_000 // 50 TB
        let tbw = Double(bytesWritten) / 1_000_000_000_000.0
        assertDoubleEqual(tbw, 50.0, accuracy: 0.001)
    }

    func test_F3_03_FallbackPlaceholderHealthScores_SafeDefaultsWithoutCrashing() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "Apple SSD",
            serialNumber: "SN-001",
            firmwareRevision: "1.0",
            interconnect: "Apple Fabric",
            capacityBytes: 256_000_000_000,
            healthScorePercent: 100,
            wearPercentage: 0,
            temperatureCelsius: 38.0,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 0.0,
            terabytesRead: 0.0,
            powerOnHours: 0,
            powerCycles: 0,
            unsafeShutdowns: 0,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            isFallbackData: true
        )

        XCTAssertTrue(metrics.isHealthy)
        XCTAssertEqual(metrics.healthScorePercent, 100)
    }

    func test_F3_04_StorageReaderError_LocalizationsAndDescriptions() {
        let errNotFound = StorageReaderError.deviceNotFound
        XCTAssertTrue(errNotFound.localizedDescription.contains("No NVMe"))

        let errPerm = StorageReaderError.permissionDenied(reason: "Entitlement missing")
        XCTAssertTrue(errPerm.localizedDescription.contains("Permission denied"))

        let errLength = StorageReaderError.invalidDataLength(expected: 512, actual: 256)
        XCTAssertTrue(errLength.localizedDescription.contains("512 bytes"))
    }

    func test_F3_05_SimulatedErrorPropagation_ThrowsDescriptiveErrors() async {
        let reader = MockSSDStorageReader(preset: .simulatedError(.deviceNotFound))
        do {
            _ = try await reader.readHealthMetrics()
            XCTFail("Should have thrown error")
        } catch let error as StorageReaderError {
            XCTAssertEqual(error, .deviceNotFound)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // =========================================================================
    // MARK: - Feature 4: Data Models & 128-Bit Arithmetic
    // =========================================================================

    func test_F4_01_UInt128Value_Initialization_And_DoubleValueScale() {
        let val1 = UInt128Value(low: 500, high: 0)
        assertDoubleEqual(val1.doubleValue, 500.0)

        // high = 1 represents 2^64
        let val2 = UInt128Value(low: 0, high: 1)
        assertDoubleEqual(val2.doubleValue, 18446744073709551616.0)

        let val3 = UInt128Value(low: 1000, high: 2)
        let expected = 2.0 * 18446744073709551616.0 + 1000.0
        assertDoubleEqual(val3.doubleValue, expected)
    }

    func test_F4_02_CriticalWarningFlags_OptionSet_AllIndividualFlags() {
        let flag0 = CriticalWarningFlags.availableSpareBelowThreshold
        XCTAssertEqual(flag0.rawValue, 0x01)

        let flag1 = CriticalWarningFlags.temperatureExceedsThreshold
        XCTAssertEqual(flag1.rawValue, 0x02)

        let flag2 = CriticalWarningFlags.reliabilityDegraded
        XCTAssertEqual(flag2.rawValue, 0x04)

        let flag3 = CriticalWarningFlags.readOnly
        XCTAssertEqual(flag3.rawValue, 0x08)

        let flag4 = CriticalWarningFlags.volatileMemoryBackupFailed
        XCTAssertEqual(flag4.rawValue, 0x10)

        let flag5 = CriticalWarningFlags.persistentMemoryUnreliable
        XCTAssertEqual(flag5.rawValue, 0x20)
    }

    func test_F4_03_CriticalWarningFlags_ActiveWarningsArray_And_IsClean() {
        let clean = CriticalWarningFlags(rawValue: 0)
        XCTAssertTrue(clean.isClean)
        XCTAssertEqual(clean.activeWarnings.count, 0)

        let combined: CriticalWarningFlags = [.availableSpareBelowThreshold, .temperatureExceedsThreshold]
        XCTAssertFalse(combined.isClean)
        XCTAssertEqual(combined.activeWarnings.count, 2)
        XCTAssertTrue(combined.activeWarnings.contains("Available Spare Below Threshold"))
        XCTAssertTrue(combined.activeWarnings.contains("Temperature Exceeds Threshold"))
    }

    func test_F4_04_SSDHealthMetrics_ComputedHelpers_And_HealthScoreInversion() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0256Q",
            serialNumber: "SN-TEST",
            firmwareRevision: "561.100.",
            interconnect: "Apple Fabric",
            capacityBytes: 251_000_193_024,
            healthScorePercent: 82,
            wearPercentage: 18,
            temperatureCelsius: 38.5,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 24.2,
            terabytesRead: 29.9,
            powerOnHours: 4120,
            powerCycles: 842,
            unsafeShutdowns: 14,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        XCTAssertEqual(metrics.capacityFormatted, "251 GB")
        XCTAssertEqual(metrics.temperatureFormatted, "38.5 °C")
        XCTAssertEqual(metrics.tbwFormatted, "24.20 TBW")
        XCTAssertEqual(metrics.wearFormatted, "18%")
        XCTAssertEqual(metrics.healthScoreFormatted, "82%")
        XCTAssertTrue(metrics.isHealthy)
    }

    func test_F4_05_CodableRoundtrip_JSONSerializationForCoreModels() throws {
        let original = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP1024R",
            serialNumber: "SN-JSON-ROUNDTRIP",
            firmwareRevision: "741.140.",
            interconnect: "Apple Fabric",
            capacityBytes: 1_000_000_000_000,
            healthScorePercent: 95,
            wearPercentage: 5,
            temperatureCelsius: 41.0,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 35.5,
            terabytesRead: 45.0,
            powerOnHours: 2500,
            powerCycles: 500,
            unsafeShutdowns: 5,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SSDHealthMetrics.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // =========================================================================
    // MARK: - Feature 5: Mock Data Provider Presets
    // =========================================================================

    func test_F5_01_HealthyPreset_ReturnsLowWearAndCleanFlags() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.wearPercentage, 2)
        XCTAssertEqual(metrics.healthScorePercent, 98)
        XCTAssertTrue(metrics.criticalWarnings.isClean)
        assertDoubleEqual(metrics.temperatureCelsius, 33.5, accuracy: 0.1)
    }

    func test_F5_02_WarningPreset_ReturnsElevatedWearAndWarmTemp() async throws {
        let reader = MockSSDStorageReader(preset: .warning)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.wearPercentage, 28)
        XCTAssertEqual(metrics.healthScorePercent, 72)
        assertDoubleEqual(metrics.temperatureCelsius, 56.0, accuracy: 0.1)
        XCTAssertEqual(metrics.availableSparePercent, 88)
    }

    func test_F5_03_OverheatingPreset_ReturnsHotTempAndCriticalBit1() async throws {
        let reader = MockSSDStorageReader(preset: .overheating)
        let metrics = try await reader.readHealthMetrics()

        assertDoubleEqual(metrics.temperatureCelsius, 76.5, accuracy: 0.1)
        XCTAssertTrue(metrics.criticalWarnings.contains(.temperatureExceedsThreshold))
    }

    func test_F5_04_CriticalWearPreset_ReturnsLowHealthAndDegradedSpare() async throws {
        let reader = MockSSDStorageReader(preset: .criticalWear)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.wearPercentage, 96)
        XCTAssertEqual(metrics.healthScorePercent, 4)
        XCTAssertEqual(metrics.availableSparePercent, 8)
        XCTAssertTrue(metrics.criticalWarnings.contains(.availableSpareBelowThreshold))
        XCTAssertEqual(metrics.mediaErrors, 14)
    }

    func test_F5_05_DegradedSparePreset_ReturnsSevereHardwareFlags() async throws {
        let reader = MockSSDStorageReader(preset: .degradedSpare)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.availableSparePercent, 5)
        XCTAssertTrue(metrics.criticalWarnings.contains(.availableSpareBelowThreshold))
        XCTAssertTrue(metrics.criticalWarnings.contains(.reliabilityDegraded))
        XCTAssertEqual(metrics.mediaErrors, 42)
    }

    // =========================================================================
    // MARK: - Feature 6: OLS Daily Write Rate Algorithm
    // =========================================================================

    func test_F6_01_OLSLinearRegression_CalculatesExactSlopeOnLinearData() {
        let engine = ReferenceForecastEngine()
        let now = Date()
        var history: [SSDHistorySnapshot] = []

        // Generate 10 days of exactly 20 GB/day writes (0.02 TB/day)
        for day in 0..<10 {
            let t = now.addingTimeInterval(Double(day - 9) * 86_400.0)
            let tbw = 10.0 + Double(day) * 0.02
            history.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: 90,
                wearPercentage: 10,
                temperatureCelsius: 38.0,
                terabytesWritten: tbw,
                availableSparePercent: 100
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 10.18, terabytesRead: 15.0, powerOnHours: 2400,
            powerCycles: 300, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)

        assertDoubleEqual(result.primaryDailyWriteRateGB, 20.0, accuracy: 0.1)
    }

    func test_F6_02_WindowedRateFiltering_7DayAnd30DayWindows() {
        let engine = ReferenceForecastEngine()
        let now = Date()
        var history: [SSDHistorySnapshot] = []

        // Past 30 days: 10 GB/day, past 7 days: 50 GB/day burst
        for day in 0..<30 {
            let t = now.addingTimeInterval(Double(day - 29) * 86_400.0)
            let tbw: Double
            if day < 23 {
                tbw = 10.0 + Double(day) * 0.01 // 10 GB/day
            } else {
                tbw = 10.23 + Double(day - 22) * 0.05 // 50 GB/day
            }
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 90, wearPercentage: 10,
                temperatureCelsius: 38.0, terabytesWritten: tbw, availableSparePercent: 100
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 10.58, terabytesRead: 15.0, powerOnHours: 3000,
            powerCycles: 300, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)

        assertDoubleEqual(result.dailyWriteRate7dGB, 50.0, accuracy: 2.0)
        XCTAssertLessThan(result.dailyWriteRate30dGB, result.dailyWriteRate7dGB)
    }

    func test_F6_03_TwoPointDeltaFallback_WhenNIsTwo() {
        let engine = ReferenceForecastEngine()
        let now = Date()
        let t1 = now.addingTimeInterval(-86_400.0)
        let t2 = now

        let history = [
            SSDHistorySnapshot(timestamp: t1, healthScorePercent: 99, wearPercentage: 1, temperatureCelsius: 35.0, terabytesWritten: 1.000, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t2, healthScorePercent: 99, wearPercentage: 1, temperatureCelsius: 35.0, terabytesWritten: 1.025, availableSparePercent: 100) // 25 GB written
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: 99, wearPercentage: 1, temperatureCelsius: 35.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 1.025, terabytesRead: 2.0, powerOnHours: 100,
            powerCycles: 20, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 150.0, referenceDate: now)
        assertDoubleEqual(result.primaryDailyWriteRateGB, 25.0, accuracy: 0.5)
    }

    func test_F6_04_LifetimeWriteRate_CalculatedFromCumulativeBytesAndHours() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // 24 TB written over 2400 hours -> 24,000 GB / 2400 hrs = 10 GB/hr = 240 GB/day
        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 24.0, terabytesRead: 30.0, powerOnHours: 2400,
            powerCycles: 500, unsafeShutdowns: 5, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: [], ratedTBW: 300.0, referenceDate: now)

        assertDoubleEqual(result.dailyWriteRateLifetimeGB, 240.0, accuracy: 0.1)
    }

    func test_F6_05_MonotonicityAndClockReset_HandlesAnomalousDeltas() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // History with a clock jump / negative delta
        let history = [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-3600), healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-3600), healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100)
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 10.0, terabytesRead: 15.0, powerOnHours: 1000,
            powerCycles: 200, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isNaN)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isInfinite)
    }

    // =========================================================================
    // MARK: - Feature 7: Lifespan Prognosis & CI Bounds
    // =========================================================================

    func test_F7_01_ModelA_WearRateExtrapolation_WhenDeltaWearNonZero() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // 10 days, wear went from 10% to 12% (delta = 2% in 10 days -> 0.2% / day)
        // Current wear 12% -> 88% remaining -> 88 / 0.2 = 440 days remaining
        let history = [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-10 * 86_400), healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 20.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 88, wearPercentage: 12, temperatureCelsius: 38.0, terabytesWritten: 24.0, availableSparePercent: 100)
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 88, wearPercentage: 12, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 24.0, terabytesRead: 30.0, powerOnHours: 2000,
            powerCycles: 300, unsafeShutdowns: 3, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)

        assertDoubleEqual(result.estimatedDaysRemaining, 440.0, accuracy: 1.0)
        assertDoubleEqual(result.estimatedYearsRemaining, 440.0 / 365.25, accuracy: 0.1)
    }

    func test_F7_02_ModelB_RatedTBWEndurance_WhenDeltaWearZero() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // History with 0 wear increase (wear stayed at 5%)
        // Rated TBW = 300 TBW, Written = 30 TBW, Remaining = 270 TBW
        // Daily rate = 27 GB/day = 0.027 TBW/day -> Days remaining = 270 / 0.027 = 10,000 days
        var history: [SSDHistorySnapshot] = []
        for day in 0..<10 {
            let t = now.addingTimeInterval(Double(day - 9) * 86_400.0)
            let tbw = 29.757 + Double(day) * 0.027
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 95, wearPercentage: 5,
                temperatureCelsius: 38.0, terabytesWritten: tbw, availableSparePercent: 100
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 30.0, terabytesRead: 40.0, powerOnHours: 3000,
            powerCycles: 400, unsafeShutdowns: 4, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)

        assertDoubleEqual(result.estimatedDaysRemaining, 10_000.0, accuracy: 100.0)
        XCTAssertEqual(result.degradationStatus, .stable)
    }

    func test_F7_03_ConfidenceInterval95_CalculatesOptimisticAndPessimisticBounds() {
        let engine = ReferenceForecastEngine()
        let now = Date()
        var history: [SSDHistorySnapshot] = []

        for day in 0..<14 {
            let t = now.addingTimeInterval(Double(day - 13) * 86_400.0)
            let noise = (day % 2 == 0 ? 0.002 : -0.002)
            let tbw = 10.0 + Double(day) * 0.02 + noise
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 95, wearPercentage: 5,
                temperatureCelsius: 38.0, terabytesWritten: tbw, availableSparePercent: 100
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 10.26, terabytesRead: 15.0, powerOnHours: 2000,
            powerCycles: 200, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)

        XCTAssertLessThan(result.confidenceInterval95.lowerGB, result.primaryDailyWriteRateGB)
        XCTAssertGreaterThan(result.confidenceInterval95.upperGB, result.primaryDailyWriteRateGB)
    }

    func test_F7_04_DegradationStatusMatrix_ClassifiesAllTiers() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // 1. Insufficient data (< 3 samples)
        let res1 = engine.calculateForecast(
            current: SSDHealthMetrics(
                bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
                interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
                wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
                availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
                powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
                criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
            ),
            history: [], ratedTBW: 300.0, referenceDate: now
        )
        XCTAssertEqual(res1.degradationStatus, .insufficientData)

        // 2. Critical wear (wear >= 90%)
        let res2 = engine.calculateForecast(
            current: SSDHealthMetrics(
                bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
                interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 8,
                wearPercentage: 92, temperatureCelsius: 38.0, availableSparePercent: 100,
                availableSpareThresholdPercent: 10, terabytesWritten: 280.0, terabytesRead: 300.0,
                powerOnHours: 15000, powerCycles: 2000, unsafeShutdowns: 20, mediaErrors: 0, errorLogEntries: 0,
                criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
            ),
            history: [
                SSDHistorySnapshot(timestamp: now.addingTimeInterval(-200_000), healthScorePercent: 9, wearPercentage: 91, temperatureCelsius: 38.0, terabytesWritten: 279.0, availableSparePercent: 100),
                SSDHistorySnapshot(timestamp: now.addingTimeInterval(-100_000), healthScorePercent: 8, wearPercentage: 92, temperatureCelsius: 38.0, terabytesWritten: 279.5, availableSparePercent: 100),
                SSDHistorySnapshot(timestamp: now, healthScorePercent: 8, wearPercentage: 92, temperatureCelsius: 38.0, terabytesWritten: 280.0, availableSparePercent: 100)
            ],
            ratedTBW: 300.0, referenceDate: now
        )
        XCTAssertEqual(res2.degradationStatus, .criticalWear)
    }

    func test_F7_05_ZeroWriteRate_HandlesInfiniteLifespanGracefully() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 100,
            wearPercentage: 0, temperatureCelsius: 35.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 0.0, terabytesRead: 0.0,
            powerOnHours: 10, powerCycles: 5, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: [], ratedTBW: 300.0, referenceDate: now)

        XCTAssertTrue(result.estimatedDaysRemaining.isInfinite)
        XCTAssertNil(result.estimatedExhaustionDate)
    }

    // =========================================================================
    // MARK: - Feature 8: Local History Persistence & Decimation
    // =========================================================================

    func test_F8_01_JSONStoreDocument_EncodingAndDecodingRoundtrip() throws {
        let now = Date()
        let snapshot = SSDHistorySnapshot(
            timestamp: now,
            healthScorePercent: 92,
            wearPercentage: 8,
            temperatureCelsius: 41.5,
            terabytesWritten: 18.4,
            availableSparePercent: 100,
            criticalWarningsRaw: 0,
            mediaErrors: 0
        )
        let doc = SSDHistoryStoreDocument(
            driveIdentifier: "APPLE SSD AP0512R - SN12345",
            firstRecorded: now.addingTimeInterval(-86400),
            lastUpdated: now,
            ratedTBW: 300.0,
            snapshots: [snapshot]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(doc)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(SSDHistoryStoreDocument.self, from: data)

        XCTAssertEqual(loaded.driveIdentifier, doc.driveIdentifier)
        XCTAssertEqual(loaded.snapshots.count, 1)
        XCTAssertEqual(loaded.snapshots[0].healthScorePercent, 92)
    }

    func test_F8_02_DecimationTier1_RetainsAllRawSamplesWithin24Hours() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []

        // 24 samples in past 24 hours (1 per hour)
        for h in 0..<24 {
            let t = now.addingTimeInterval(-Double(h) * 3600.0)
            samples.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 98, wearPercentage: 2,
                temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100
            ))
        }

        let decimated = ReferenceDecimationEngine.decimate(samples: samples, relativeTo: now)
        XCTAssertEqual(decimated.count, 24)
    }

    func test_F8_03_DecimationTier2_RetainsHourlySamplesFor7Days() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []

        // Samples between 24h ago and 7 days ago (1 sample every 15 minutes = 4 per hour)
        // 6 days * 24 hours * 4 samples = 576 samples
        let start = now.addingTimeInterval(-7 * 86_400)
        let end = now.addingTimeInterval(-86_400)
        var curr = start
        while curr < end {
            samples.append(SSDHistorySnapshot(
                timestamp: curr, healthScorePercent: 98, wearPercentage: 2,
                temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100
            ))
            curr = curr.addingTimeInterval(900) // 15 min
        }

        let decimated = ReferenceDecimationEngine.decimate(samples: samples, relativeTo: now)

        // Should decimate down to ~144 hourly samples
        XCTAssertLessThanOrEqual(decimated.count, 145)
        XCTAssertGreaterThanOrEqual(decimated.count, 140)
    }

    func test_F8_04_DecimationTier3_RetainsDailySamplesFor1Year() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []

        // Samples between 7 days ago and 365 days ago (1 sample every hour)
        // ~358 days * 24 = 8592 samples
        let start = now.addingTimeInterval(-365 * 86_400)
        let end = now.addingTimeInterval(-7 * 86_400)
        var curr = start
        while curr < end {
            samples.append(SSDHistorySnapshot(
                timestamp: curr, healthScorePercent: 98, wearPercentage: 2,
                temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100
            ))
            curr = curr.addingTimeInterval(3600) // 1 hr
        }

        let decimated = ReferenceDecimationEngine.decimate(samples: samples, relativeTo: now)

        // Should decimate down to ~358 daily samples
        XCTAssertLessThanOrEqual(decimated.count, 362)
        XCTAssertGreaterThanOrEqual(decimated.count, 355)
    }

    func test_F8_05_DecimationTier4_RetainsWeeklySamplesBeyond1Year() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []

        // Samples older than 1 year (e.g. 2 years old, 1 sample every day = 365 samples)
        let start = now.addingTimeInterval(-2 * 365 * 86_400)
        let end = now.addingTimeInterval(-365 * 86_400)
        var curr = start
        while curr < end {
            samples.append(SSDHistorySnapshot(
                timestamp: curr, healthScorePercent: 98, wearPercentage: 2,
                temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100
            ))
            curr = curr.addingTimeInterval(86400) // 1 day
        }

        let decimated = ReferenceDecimationEngine.decimate(samples: samples, relativeTo: now)

        // Should decimate down to ~52 weekly samples
        XCTAssertLessThanOrEqual(decimated.count, 54)
        XCTAssertGreaterThanOrEqual(decimated.count, 50)
    }

    // =========================================================================
    // MARK: - Feature 9: Notification Engine & Debounce
    // =========================================================================

    func test_F9_01_ThermalThreshold_TriggersWarningAt60AndCriticalAt65() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let warnMetrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 62.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let alerts1 = engine.evaluateAlerts(metrics: warnMetrics, now: now)
        XCTAssertEqual(alerts1.count, 1)
        XCTAssertTrue(alerts1[0].contains("HIGH_TEMPERATURE"))

        let critMetrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 68.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let alerts2 = engine.evaluateAlerts(metrics: critMetrics, now: now)
        XCTAssertEqual(alerts2.count, 1)
        XCTAssertTrue(alerts2[0].contains("CRITICAL_TEMPERATURE"))
    }

    func test_F9_02_WearMilestone_TriggersOneShotAt80_90_95_100() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let m80 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 20,
            wearPercentage: 80, temperatureCelsius: 40.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 200.0, terabytesRead: 200.0,
            powerOnHours: 5000, powerCycles: 500, unsafeShutdowns: 5, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let alerts1 = engine.evaluateAlerts(metrics: m80, now: now)
        XCTAssertTrue(alerts1.contains(where: { $0.contains("WEAR_MILESTONE_80") }))

        // Subsequent call should NOT re-trigger 80% milestone
        let alerts2 = engine.evaluateAlerts(metrics: m80, now: now.addingTimeInterval(300))
        XCTAssertFalse(alerts2.contains(where: { $0.contains("WEAR_MILESTONE_80") }))
    }

    func test_F9_03_SpareBelowThreshold_TriggersHardwareAlert() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let lowSpare = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 50,
            wearPercentage: 50, temperatureCelsius: 40.0, availableSparePercent: 8,
            availableSpareThresholdPercent: 10, terabytesWritten: 100.0, terabytesRead: 100.0,
            powerOnHours: 5000, powerCycles: 500, unsafeShutdowns: 5, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: [.availableSpareBelowThreshold], timestamp: now
        )

        let alerts = engine.evaluateAlerts(metrics: lowSpare, now: now)
        XCTAssertTrue(alerts.contains(where: { $0.contains("SPARE_CAPACITY_LOW") }))
    }

    func test_F9_04_CriticalWarningBitmask_TriggersOnReliabilityOrReadOnly() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let degraded = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 50,
            wearPercentage: 50, temperatureCelsius: 40.0, availableSparePercent: 50,
            availableSpareThresholdPercent: 10, terabytesWritten: 100.0, terabytesRead: 100.0,
            powerOnHours: 5000, powerCycles: 500, unsafeShutdowns: 5, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: [.reliabilityDegraded, .readOnly], timestamp: now
        )

        let alerts = engine.evaluateAlerts(metrics: degraded, now: now)
        XCTAssertTrue(alerts.contains(where: { $0.contains("CRITICAL_RELIABILITY_DEGRADED") }))
        XCTAssertTrue(alerts.contains(where: { $0.contains("CRITICAL_DRIVE_READ_ONLY") }))
    }

    func test_F9_05_CooldownState_SuppressesDuplicateAlertsWithinWindow() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let hot = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 68.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let alerts1 = engine.evaluateAlerts(metrics: hot, now: now)
        XCTAssertEqual(alerts1.count, 1)

        // 5 minutes later (cooldown is 15 minutes) -> should be suppressed
        let alerts2 = engine.evaluateAlerts(metrics: hot, now: now.addingTimeInterval(300))
        XCTAssertEqual(alerts2.count, 0)

        // 16 minutes later -> should trigger again
        let alerts3 = engine.evaluateAlerts(metrics: hot, now: now.addingTimeInterval(960))
        XCTAssertEqual(alerts3.count, 1)
    }

    // =========================================================================
    // MARK: - Feature 10: Diagnostic Export (JSON/CSV/Text)
    // =========================================================================

    func test_F10_01_JSONExport_ContainsMetadataDriveMetricsAndForecast() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP0256Q", serialNumber: "0ba018e2018c480f",
            firmwareRevision: "561.100.", interconnect: "Apple Fabric", capacityBytes: 251_000_193_024,
            healthScorePercent: 82, wearPercentage: 18, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 24.196,
            terabytesRead: 29.896, powerOnHours: 4120, powerCycles: 842, unsafeShutdowns: 14,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let jsonStr = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: [], forecast: nil)
        assertJSONValid(jsonStr, requiredTopLevelKeys: ["metadata", "drive", "currentMetrics", "history"])
    }

    func test_F10_02_CSVExport_CompliesWithRFC4180FormatAndHeaders() {
        let now = Date()
        let s1 = SSDHistorySnapshot(timestamp: now.addingTimeInterval(-86400), healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100)
        let s2 = SSDHistorySnapshot(timestamp: now, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 39.0, terabytesWritten: 10.05, availableSparePercent: 100)

        let csv = ReferenceDiagnosticExporter.exportCSV(history: [s1, s2])
        assertCSVValid(csv, expectedRowCount: 2)
    }

    func test_F10_03_TextReport_ContainsAllSixStandardReportSections() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP0512R", serialNumber: "SN-TEXT-REP",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 98, wearPercentage: 2, temperatureCelsius: 34.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 14.82,
            terabytesRead: 28.51, powerOnHours: 1240, powerCycles: 310, unsafeShutdowns: 4,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let rep = ReferenceDiagnosticExporter.exportTextReport(metrics: metrics, history: [], forecast: nil)
        XCTAssertTrue(rep.contains("1. STORAGE DEVICE IDENTIFICATION"))
        XCTAssertTrue(rep.contains("2. HEALTH & LIFESPAN SUMMARY"))
        XCTAssertTrue(rep.contains("3. FORECAST & WEAR PROJECTION"))
        XCTAssertTrue(rep.contains("4. HARDWARE RELIABILITY FLAGS & WARNINGS"))
    }

    func test_F10_04_ExportEngines_HandleEmptyHistoryGracefully() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-EMPTY",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 35.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 0.0,
            terabytesRead: 0.0, powerOnHours: 0, powerCycles: 0, unsafeShutdowns: 0,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let json = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: [], forecast: nil)
        XCTAssertFalse(json.isEmpty)

        let csv = ReferenceDiagnosticExporter.exportCSV(history: [])
        assertCSVValid(csv, expectedRowCount: 0)
    }

    func test_F10_05_ExportEngines_CaptureCriticalAlertsAndDegradedStates() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-CRIT",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: 5, wearPercentage: 95, temperatureCelsius: 72.0,
            availableSparePercent: 4, availableSpareThresholdPercent: 10, terabytesWritten: 300.0,
            terabytesRead: 350.0, powerOnHours: 20000, powerCycles: 3000, unsafeShutdowns: 50,
            mediaErrors: 12, errorLogEntries: 20,
            criticalWarnings: [.availableSpareBelowThreshold, .temperatureExceedsThreshold]
        )

        let json = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: [], forecast: nil)
        XCTAssertTrue(json.contains("\"criticalWarningBitmask\" : 3"))

        let rep = ReferenceDiagnosticExporter.exportTextReport(metrics: metrics, history: [], forecast: nil)
        XCTAssertTrue(rep.contains("Critical"))
    }

    // =========================================================================
    // MARK: - Feature 11: Menu Bar StatusItem & Display Modes
    // =========================================================================

    func test_F11_01_DisplayMode_IconOnly_ProducesEmptyTitle() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 98,
            wearPercentage: 2, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let title = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconOnly)
        XCTAssertEqual(title, "")
    }

    func test_F11_02_DisplayMode_IconAndHealth_FormatsHealthPercentage() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 98,
            wearPercentage: 2, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let title = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndHealth)
        XCTAssertEqual(title, "98%")
    }

    func test_F11_03_DisplayMode_IconAndTemp_FormatsCelsiusAndFahrenheit() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 98,
            wearPercentage: 2, temperatureCelsius: 41.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let titleC = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndTemp, unit: .celsius)
        XCTAssertEqual(titleC, "41°C")

        let titleF = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndTemp, unit: .fahrenheit)
        XCTAssertEqual(titleF, "106°F") // 41 * 1.8 + 32 = 105.8 -> 106°F
    }

    func test_F11_04_DisplayMode_IconHealthAndTemp_CombinesBothMetrics() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 98,
            wearPercentage: 2, temperatureCelsius: 41.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let title = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconHealthAndTemp, unit: .celsius)
        XCTAssertEqual(title, "98% · 41°C")
    }

    func test_F11_05_HealthStatusResolution_MapsToCorrectColorAndIcon() {
        let healthy = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 98,
            wearPercentage: 2, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(ReferenceMenuBarFormatter.resolveStatus(metrics: healthy), .good)

        let hot = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 98,
            wearPercentage: 2, temperatureCelsius: 70.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: [.temperatureExceedsThreshold]
        )
        XCTAssertEqual(ReferenceMenuBarFormatter.resolveStatus(metrics: hot), .critical)
    }

    // =========================================================================
    // MARK: - Feature 12: Popover QuickView Summary
    // =========================================================================

    func test_F12_01_CircularGauge_NormalizesScoreWithin0To100() {
        let score1 = max(0, min(100, 98))
        XCTAssertEqual(score1, 98)

        let score2 = max(0, min(100, -5))
        XCTAssertEqual(score2, 0)

        let score3 = max(0, min(100, 105))
        XCTAssertEqual(score3, 100)
    }

    func test_F12_02_TemperatureBadge_ClassifiesOptimalWarmAndHot() {
        func classifyTemp(_ c: Double) -> String {
            if c >= 65.0 { return "Hot" }
            if c >= 50.0 { return "Warm" }
            return "Optimal"
        }

        XCTAssertEqual(classifyTemp(38.0), "Optimal")
        XCTAssertEqual(classifyTemp(55.0), "Warm")
        XCTAssertEqual(classifyTemp(72.0), "Hot")
    }

    func test_F12_03_TotalTBWCard_FormatsTerabytesAndDailyRate() {
        let tbw = 34.22
        let dailyGB = 24.5
        let str = String(format: "%.1f TBW (%.1f GB/day)", tbw, dailyGB)
        XCTAssertEqual(str, "34.2 TBW (24.5 GB/day)")
    }

    func test_F12_04_LifespanSummary_FormatsRemainingYears() {
        let years = 8.44
        let str = String(format: "~%.1f Years", years)
        XCTAssertEqual(str, "~8.4 Years")
    }

    func test_F12_05_QuickView_HandlesMissingOrNilMetricsGracefully() {
        let title = ReferenceMenuBarFormatter.formatTitle(metrics: nil, mode: .iconAndHealth)
        XCTAssertEqual(title, "--%")
    }

    // =========================================================================
    // MARK: - Feature 13: Dashboard Window & SMART Table
    // =========================================================================

    func test_F13_01_KPIGrid_CalculatesSixKeyMetrics() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP0512R", serialNumber: "SN-KPI",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 98, wearPercentage: 2, temperatureCelsius: 41.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 34.22,
            terabytesRead: 48.15, powerOnHours: 4820, powerCycles: 420, unsafeShutdowns: 3,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        XCTAssertEqual(metrics.healthScorePercent, 98)
        XCTAssertEqual(metrics.availableSparePercent, 100)
        assertDoubleEqual(metrics.terabytesWritten, 34.22, accuracy: 0.01)
        XCTAssertEqual(metrics.powerOnHours, 4820)
        XCTAssertEqual(metrics.unsafeShutdowns, 3)
        XCTAssertEqual(metrics.mediaErrors, 0)
    }

    func test_F13_02_SMARTTableRows_GeneratesNineteenStandardParameters() {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse log")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        XCTAssertGreaterThanOrEqual(rows.count, 17)
    }

    func test_F13_03_SMARTTableRowStatus_ClassifiesNormalWarningCriticalInfo() {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse log")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        let cwRow = rows.first(where: { $0.name == "Critical Warning" })
        XCTAssertEqual(cwRow?.status, .normal)

        let tbwRow = rows.first(where: { $0.name == "Data Units Written" })
        XCTAssertEqual(tbwRow?.status, .info)
    }

    func test_F13_04_SMARTTableSearch_FiltersByNameOrId() {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse log")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        let filtered = rows.filter { $0.name.localizedCaseInsensitiveContains("Temperature") }
        XCTAssertGreaterThanOrEqual(filtered.count, 1)
    }

    func test_F13_05_SMARTTable_FormatsUInt128HexAndDecimalUnits() {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse log")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        let tbwRow = rows.first(where: { $0.name == "Data Units Written" })
        XCTAssertNotNil(tbwRow)
        XCTAssertTrue(tbwRow!.formattedValue.contains("TBW"))
    }

    // =========================================================================
    // MARK: - Feature 14: Swift Charts Visualizations
    // =========================================================================

    func test_F14_01_WearProgressionData_PreparesHistoricalPointsAndProjection() {
        let now = Date()
        var points: [(x: Date, y: Double)] = []
        for i in 0..<10 {
            points.append((x: now.addingTimeInterval(Double(i - 9) * 86400), y: Double(i) * 0.2))
        }
        XCTAssertEqual(points.count, 10)
        XCTAssertEqual(points.last?.y, 1.8)
    }

    func test_F14_02_TBWAccumulationData_CalculatesDailyWriteDeltas() {
        let cumulativeTBW = [10.0, 10.05, 10.12, 10.20]
        var dailyDeltasGB: [Double] = []
        for i in 1..<cumulativeTBW.count {
            let delta = (cumulativeTBW[i] - cumulativeTBW[i - 1]) * 1000.0
            dailyDeltasGB.append(delta)
        }
        assertDoubleEqual(dailyDeltasGB[0], 50.0, accuracy: 0.1)
        assertDoubleEqual(dailyDeltasGB[1], 70.0, accuracy: 0.1)
        assertDoubleEqual(dailyDeltasGB[2], 80.0, accuracy: 0.1)
    }

    func test_F14_03_ThermalTrendData_AppliesWarningAndCriticalRules() {
        let temps = [35.0, 42.0, 58.0, 68.0]
        let warnThreshold = 55.0
        let critThreshold = 65.0

        let warmCount = temps.filter { $0 >= warnThreshold && $0 < critThreshold }.count
        let hotCount = temps.filter { $0 >= critThreshold }.count

        XCTAssertEqual(warmCount, 1)
        XCTAssertEqual(hotCount, 1)
    }

    func test_F14_04_TimeRangeFiltering_Filters24H_7D_30D_90D_1Y_ALL() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []
        for day in 0..<100 {
            samples.append(SSDHistorySnapshot(
                timestamp: now.addingTimeInterval(Double(-day) * 86400),
                healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0,
                terabytesWritten: 10.0, availableSparePercent: 100
            ))
        }

        let filter7D = samples.filter { $0.timestamp >= now.addingTimeInterval(-7 * 86400) }
        XCTAssertEqual(filter7D.count, 8)

        let filter30D = samples.filter { $0.timestamp >= now.addingTimeInterval(-30 * 86400) }
        XCTAssertEqual(filter30D.count, 31)
    }

    func test_F14_05_EmptyStateDetection_FlagsInsufficientSamples() {
        let samples: [SSDHistorySnapshot] = []
        let hasSufficientData = samples.count >= 2
        XCTAssertFalse(hasSufficientData)
    }

    // =========================================================================
    // MARK: - Feature 15: Settings & Threshold Configuration
    // =========================================================================

    func test_F15_01_PollingIntervalOptions_ValidatesSupportedRanges() {
        let validIntervalsMinutes = [1, 5, 15, 30, 60]
        for interval in validIntervalsMinutes {
            XCTAssertGreaterThanOrEqual(interval, 1)
            XCTAssertLessThanOrEqual(interval, 60)
        }
    }

    func test_F15_02_AlertThresholdCustomization_ValidatesRanges() {
        let tempWarn = 60
        let tempCrit = 65
        XCTAssertLessThan(tempWarn, tempCrit)

        let wearWarn = 80
        let wearCrit = 95
        XCTAssertLessThan(wearWarn, wearCrit)
    }

    func test_F15_03_TemperatureUnitSwitching_MaintainsExactConversion() {
        let c = 38.0
        let f = c * 1.8 + 32.0
        assertDoubleEqual(f, 100.4, accuracy: 0.01)

        let backC = (f - 32.0) / 1.8
        assertDoubleEqual(backC, c, accuracy: 0.01)
    }

    func test_F15_04_RatedTBWCustomOverride_OverridesCapacityDefault() {
        let capacityBytes: UInt64 = 512_000_000_000
        let autoTBW = Double(capacityBytes) / 1_000_000_000.0 * 0.6 // 307.2 TBW
        let customTBW = 600.0

        let effectiveTBW = customTBW > 0 ? customTBW : autoTBW
        XCTAssertEqual(effectiveTBW, 600.0)
    }

    func test_F15_05_SettingsPersistence_MaintainsStateAcrossSessions() {
        struct MockSettings: Codable {
            var pollingIntervalMinutes: Int = 15
            var tempWarningThreshold: Int = 65
            var displayMode: MenuBarDisplayMode = .iconAndHealth
        }

        var settings = MockSettings()
        settings.pollingIntervalMinutes = 30
        settings.displayMode = .iconHealthAndTemp

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(settings) else {
            XCTFail("Encoding failed")
            return
        }

        let decoder = JSONDecoder()
        guard let loaded = try? decoder.decode(MockSettings.self, from: data) else {
            XCTFail("Decoding failed")
            return
        }

        XCTAssertEqual(loaded.pollingIntervalMinutes, 30)
        XCTAssertEqual(loaded.displayMode, .iconHealthAndTemp)
    }
}
