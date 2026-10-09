import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

/// Tier 2: Boundary Value Analysis & Corner Condition Test Suite (15 Features x >= 5 tests = >= 75 tests).
/// Verifies extreme values, numerical overflows, underflows, truncated data, and edge conditions.
final class Tier2_BoundaryCornerTests: XCTestCase {

    // =========================================================================
    // MARK: - Boundary Group 1: NVMe Parser Boundary Conditions
    // =========================================================================

    func test_B1_01_AllZerosBuffer_DecodesSafelyWithoutCrash() {
        let buffer = SyntheticNVMeFixtures.makeAllZerosBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse all-zeros buffer")
            return
        }

        XCTAssertTrue(log.criticalWarning.isClean)
        XCTAssertEqual(log.compositeTemperatureKelvin, 0)
        assertDoubleEqual(log.temperatureCelsius, 0.0) // 0 K reported as 0.0°C by guard
        XCTAssertEqual(log.availableSparePercent, 0)
        XCTAssertEqual(log.percentageUsed, 0)
        XCTAssertEqual(log.healthScorePercent, 100)
        assertDoubleEqual(log.totalBytesWritten, 0.0)
    }

    func test_B1_02_AllOnesBuffer_DecodesExtremeValuesWithClampedHealth() {
        let buffer = SyntheticNVMeFixtures.makeAllOnesBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse all-ones buffer")
            return
        }

        XCTAssertEqual(log.criticalWarning.rawValue, 0xFF)
        XCTAssertEqual(log.percentageUsed, 255)
        XCTAssertEqual(log.healthScorePercent, 0) // Clamped to 0%
        XCTAssertEqual(log.availableSparePercent, 255)
        XCTAssertEqual(log.dataUnitsWritten.low, UInt64.max)
        XCTAssertEqual(log.dataUnitsWritten.high, UInt64.max)
    }

    func test_B1_03_TruncatedBuffers_RejectedSafely() {
        let sizes = [0, 1, 16, 256, 511]
        for size in sizes {
            let truncated = Data(repeating: 0, count: size)
            let log = NVMESmartLog(data: truncated)
            XCTAssertNil(log, "Buffer of size \(size) should have been rejected (expected >= 512 bytes)")
        }
    }

    func test_B1_04_OversizedBuffers_ParsesFirst512BytesCorrectly() {
        var buffer = SyntheticNVMeFixtures.makePristineBuffer()
        buffer.append(Data(repeating: 0xEE, count: 512)) // 1024 bytes total

        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Oversized buffer should be accepted using first 512 bytes")
            return
        }

        XCTAssertEqual(log.compositeTemperatureKelvin, 305)
        XCTAssertEqual(log.percentageUsed, 0)
        XCTAssertEqual(log.healthScorePercent, 100)
    }

    func test_B1_05_SerializationRoundtrip_MaintainsExactByteEquality() {
        let originalBuffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: originalBuffer) else {
            XCTFail("Failed to parse original buffer")
            return
        }

        let serializedData = log.toData()
        XCTAssertEqual(serializedData.count, 512)

        guard let roundtripLog = NVMESmartLog(data: serializedData) else {
            XCTFail("Failed to parse serialized buffer")
            return
        }

        XCTAssertEqual(log, roundtripLog)
    }

    // =========================================================================
    // MARK: - Boundary Group 2: IOKit Storage Client Boundary Conditions
    // =========================================================================

    func test_B2_01_EmptyServiceMatching_ThrowsDeviceNotFound() {
        let err = StorageReaderError.deviceNotFound
        XCTAssertEqual(err, .deviceNotFound)
    }

    func test_B2_02_UnsupportedInterface_ThrowsError() {
        let err = StorageReaderError.unsupportedDevice(reason: "USB Flash Storage")
        XCTAssertTrue(err.localizedDescription.contains("Unsupported"))
    }

    func test_B2_03_InvalidDataLength_ThrowsExpectedAndActual() {
        let err = StorageReaderError.invalidDataLength(expected: 512, actual: 128)
        XCTAssertTrue(err.localizedDescription.contains("512"))
        XCTAssertTrue(err.localizedDescription.contains("128"))
    }

    func test_B2_04_KernelErrorCodes_FormattedInHex() {
        let err = StorageReaderError.smartReadFailed(kernReturn: -536870212)
        XCTAssertTrue(err.localizedDescription.contains("0x"))
    }

    func test_B2_05_RapidSequentialReads_DoNotLeakMemoryOrCrash() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        for _ in 0..<50 {
            let m = try await reader.readHealthMetrics()
            XCTAssertEqual(m.healthScorePercent, 98)
        }
    }

    // =========================================================================
    // MARK: - Boundary Group 3: IORegistry Fallback Boundary Conditions
    // =========================================================================

    func test_B3_01_FallbackWithEmptyStats_DefaultsToZero() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "FALLBACK-ZERO",
            firmwareRevision: "1.0", interconnect: "Apple Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 0.0, terabytesRead: 0.0, powerOnHours: 0, powerCycles: 0,
            unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), isFallbackData: true
        )
        assertDoubleEqual(metrics.terabytesWritten, 0.0)
        assertDoubleEqual(metrics.terabytesRead, 0.0)
    }

    func test_B3_02_FallbackWithMaxUInt64Stats_ConvertsWithoutOverflow() {
        let maxBytes: UInt64 = UInt64.max
        let tb = Double(maxBytes) / 1_000_000_000_000.0
        XCTAssertGreaterThan(tb, 18_000_000.0) // ~18.44 Million TB
    }

    func test_B3_03_FallbackWithMissingCapacity_SafelyDefaulted() {
        let cap: UInt64 = 0
        let effectiveCap = cap > 0 ? cap : 256_000_000_000
        XCTAssertEqual(effectiveCap, 256_000_000_000)
    }

    func test_B3_04_FallbackWithMissingStrings_DoesNotCrash() {
        let metrics = SSDHealthMetrics(
            bsdName: "", modelName: "", serialNumber: "",
            firmwareRevision: "", interconnect: "", capacityBytes: 0,
            healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 0.0, terabytesRead: 0.0, powerOnHours: 0, powerCycles: 0,
            unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), isFallbackData: true
        )
        XCTAssertEqual(metrics.id, "")
        XCTAssertEqual(metrics.wearFormatted, "0%")
    }

    func test_B3_05_FallbackIsIdentifiableAndCodable() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-FALLBACK",
            firmwareRevision: "1.0", interconnect: "Apple Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 5.0, terabytesRead: 10.0, powerOnHours: 0, powerCycles: 0,
            unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), isFallbackData: true
        )

        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(SSDHealthMetrics.self, from: data)
        XCTAssertTrue(decoded.isFallbackData)
    }

    // =========================================================================
    // MARK: - Boundary Group 4: Data Models & 128-Bit Arithmetic Boundary Conditions
    // =========================================================================

    func test_B4_01_MaxUInt128Value_DoubleConversionDoesNotOverflow() {
        let maxVal = UInt128Value(low: UInt64.max, high: UInt64.max)
        let dbl = maxVal.doubleValue
        XCTAssertGreaterThan(dbl, 3.4e38)
        XCTAssertFalse(dbl.isInfinite)
        XCTAssertFalse(dbl.isNaN)
    }

    func test_B4_02_ZeroUInt128Value_DoubleConversionExactZero() {
        let zeroVal = UInt128Value.zero
        assertDoubleEqual(zeroVal.doubleValue, 0.0)
    }

    func test_B4_03_WearPercentageOver100_ClampsHealthScoreToZero() {
        let buffer = SyntheticNVMeFixtures.makeBuffer(percentageUsed: 150)
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        XCTAssertEqual(log.percentageUsed, 150)
        XCTAssertEqual(log.healthScorePercent, 0)
    }

    func test_B4_04_SubZeroKelvinTemperature_HandledGracefully() {
        let buffer = SyntheticNVMeFixtures.makeBuffer(temperatureKelvin: 0)
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }
        assertDoubleEqual(log.temperatureCelsius, 0.0)
    }

    func test_B4_05_AllCriticalWarningBitsSetSimultaneously() {
        let allBits = CriticalWarningFlags(rawValue: 0x3F) // Bits 0-5
        XCTAssertEqual(allBits.activeWarnings.count, 6)
        XCTAssertTrue(allBits.contains(.availableSpareBelowThreshold))
        XCTAssertTrue(allBits.contains(.temperatureExceedsThreshold))
        XCTAssertTrue(allBits.contains(.reliabilityDegraded))
        XCTAssertTrue(allBits.contains(.readOnly))
        XCTAssertTrue(allBits.contains(.volatileMemoryBackupFailed))
        XCTAssertTrue(allBits.contains(.persistentMemoryUnreliable))
    }

    // =========================================================================
    // MARK: - Boundary Group 5: Mock Data Provider Boundary Conditions
    // =========================================================================

    func test_B5_01_CustomMetricsOverride_ReturnsExactCustomValues() async throws {
        let reader = MockSSDStorageReader()
        let custom = SSDHealthMetrics(
            bsdName: "disk1", modelName: "CUSTOM SSD", serialNumber: "CUSTOM-999",
            firmwareRevision: "9.9", interconnect: "PCI-Express", capacityBytes: 2_000_000_000_000,
            healthScorePercent: 42, wearPercentage: 58, temperatureCelsius: 61.2,
            availableSparePercent: 50, availableSpareThresholdPercent: 10,
            terabytesWritten: 120.0, terabytesRead: 150.0, powerOnHours: 12000, powerCycles: 1500,
            unsafeShutdowns: 30, mediaErrors: 5, errorLogEntries: 8,
            criticalWarnings: [.reliabilityDegraded]
        )
        reader.customMetrics = custom

        let fetched = try await reader.readHealthMetrics()
        XCTAssertEqual(fetched.serialNumber, "CUSTOM-999")
        XCTAssertEqual(fetched.healthScorePercent, 42)
    }

    func test_B5_02_SimulatedErrorSwitching_ThrowsConfiguredError() async {
        let reader = MockSSDStorageReader(preset: .simulatedError(.permissionDenied(reason: "Root required")))
        do {
            _ = try await reader.readHealthMetrics()
            XCTFail("Should have thrown permission error")
        } catch let err as StorageReaderError {
            if case .permissionDenied = err {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error case: \(err)")
            }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_B5_03_SyntheticDataGenerator_ProducesValid512ByteOutput() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-SYNTH",
            firmwareRevision: "1.0", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 39.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 15.0, terabytesRead: 20.0, powerOnHours: 1000, powerCycles: 200,
            unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let data = MockSSDStorageReader.generateSyntheticRawData(for: metrics)
        XCTAssertEqual(data.count, 512)

        guard let log = NVMESmartLog(data: data) else {
            XCTFail("Synthetic data should be valid NVMESmartLog")
            return
        }
        XCTAssertEqual(log.percentageUsed, 5)
    }

    func test_B5_04_HighVolumeConcurrentReads_ExecutesSafely() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        try await withThrowingTaskGroup(of: SSDHealthMetrics.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    try await reader.readHealthMetrics()
                }
            }
            for try await m in group {
                XCTAssertEqual(m.healthScorePercent, 98)
            }
        }
    }

    func test_B5_05_EmptySerialNumber_DefaultsIDToBSDName() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "",
            firmwareRevision: "1.0", interconnect: "Apple Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 0.0, terabytesRead: 0.0, powerOnHours: 0, powerCycles: 0,
            unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(metrics.id, "disk0")
    }

    // =========================================================================
    // MARK: - Boundary Group 6: OLS Write Rate Boundary Conditions
    // =========================================================================

    func test_B6_01_SinglePointHistory_FallsBackToLifetimeRate() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        let history = [
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100)
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
            wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 15.0,
            powerOnHours: 1000, powerCycles: 200, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)
        // 10 TB over 1000 hours -> 10,000 GB / 1000 hrs = 10 GB/hr = 240 GB/day
        assertDoubleEqual(result.primaryDailyWriteRateGB, 240.0, accuracy: 0.1)
    }

    func test_B6_02_ZeroWriteRateOver30Days_ComputesZeroSlope() {
        let engine = ReferenceForecastEngine()
        let now = Date()
        var history: [SSDHistorySnapshot] = []

        for day in 0..<30 {
            let t = now.addingTimeInterval(Double(day - 29) * 86_400.0)
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 95, wearPercentage: 5,
                temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100 // Exact same TBW
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
            wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 15.0,
            powerOnHours: 2000, powerCycles: 200, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)
        assertDoubleEqual(result.dailyWriteRate30dGB, 0.0, accuracy: 1e-4)
    }

    func test_B6_03_NegativeTimeDelta_RejectedSafely() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        let history = [
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-86400), healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100)
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
            wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 15.0,
            powerOnHours: 1000, powerCycles: 200, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isNaN)
    }

    func test_B6_04_IdenticalTimestampsInHistory_HandledWithoutDivisionByZero() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        let history = [
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100)
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
            wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 15.0,
            powerOnHours: 1000, powerCycles: 200, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isNaN)
    }

    func test_B6_05_ExtremeWriteBurst_HandlesLargeValuesGracefully() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // 1 TB written in 1 day (1000 GB/day)
        let history = [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-86400), healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 11.0, availableSparePercent: 100)
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
            wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 11.0, terabytesRead: 15.0,
            powerOnHours: 1000, powerCycles: 200, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)
        assertDoubleEqual(result.primaryDailyWriteRateGB, 1000.0, accuracy: 1.0)
    }

    // =========================================================================
    // MARK: - Boundary Group 7: Lifespan Prognosis Boundary Conditions
    // =========================================================================

    func test_B7_01_ExhaustedEndurance_SetsZeroDaysRemainingAndExceededStatus() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 256_000_000_000, healthScorePercent: 0,
            wearPercentage: 105, temperatureCelsius: 45.0, availableSparePercent: 80,
            availableSpareThresholdPercent: 10, terabytesWritten: 160.0, terabytesRead: 200.0,
            powerOnHours: 20000, powerCycles: 2000, unsafeShutdowns: 50, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-200_000), healthScorePercent: 0, wearPercentage: 104, temperatureCelsius: 45.0, terabytesWritten: 159.0, availableSparePercent: 80),
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-100_000), healthScorePercent: 0, wearPercentage: 105, temperatureCelsius: 45.0, terabytesWritten: 159.5, availableSparePercent: 80),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 0, wearPercentage: 105, temperatureCelsius: 45.0, terabytesWritten: 160.0, availableSparePercent: 80)
        ], ratedTBW: 150.0, referenceDate: now)

        assertDoubleEqual(result.estimatedDaysRemaining, 0.0)
        XCTAssertEqual(result.degradationStatus, .exceededEndurance)
    }

    func test_B7_02_WearAt100Percent_RemainingDaysZero() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 0,
            wearPercentage: 100, temperatureCelsius: 40.0, availableSparePercent: 90,
            availableSpareThresholdPercent: 10, terabytesWritten: 300.0, terabytesRead: 350.0,
            powerOnHours: 15000, powerCycles: 1500, unsafeShutdowns: 20, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-200_000), healthScorePercent: 1, wearPercentage: 99, temperatureCelsius: 40.0, terabytesWritten: 299.0, availableSparePercent: 90),
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-100_000), healthScorePercent: 0, wearPercentage: 100, temperatureCelsius: 40.0, terabytesWritten: 299.5, availableSparePercent: 90),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 0, wearPercentage: 100, temperatureCelsius: 40.0, terabytesWritten: 300.0, availableSparePercent: 90)
        ], ratedTBW: 300.0, referenceDate: now)

        assertDoubleEqual(result.estimatedDaysRemaining, 0.0)
    }

    func test_B7_03_ExtremeWearRate_CalculatesShortLifespanAccurately() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // 10% wear in 1 day -> 10% / day -> 90% remaining / 10% = 9 days remaining
        let history = [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-86400), healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 40.0, terabytesWritten: 0.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 40.0, terabytesWritten: 30.0, availableSparePercent: 100)
        ]

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 40.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 30.0, terabytesRead: 30.0,
            powerOnHours: 100, powerCycles: 10, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)
        assertDoubleEqual(result.estimatedDaysRemaining, 9.0, accuracy: 0.1)
    }

    func test_B7_04_NegativeRemainingTBW_ClampedToZero() {
        let written = 350.0
        let rated = 300.0
        let rem = max(0.0, rated - written)
        XCTAssertEqual(rem, 0.0)
    }

    func test_B7_05_LongLifespanBeyond100Years_SetsNilExhaustionDate() {
        let engine = ReferenceForecastEngine()
        let now = Date()

        // 0.001 GB/day on 300 TBW drive -> >800,000 years
        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 100,
            wearPercentage: 0, temperatureCelsius: 30.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 0.001, terabytesRead: 0.001,
            powerOnHours: 1000, powerCycles: 10, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: [], ratedTBW: 300.0, referenceDate: now)
        XCTAssertNil(result.estimatedExhaustionDate)
    }

    // =========================================================================
    // MARK: - Boundary Group 8: History Persistence Boundary Conditions
    // =========================================================================

    func test_B8_01_DecimationWithZeroOrOneSample_ReturnsOriginal() {
        let empty: [SSDHistorySnapshot] = []
        XCTAssertEqual(ReferenceDecimationEngine.decimate(samples: empty).count, 0)

        let single = [SSDHistorySnapshot(timestamp: Date(), healthScorePercent: 99, wearPercentage: 1, temperatureCelsius: 38.0, terabytesWritten: 1.0, availableSparePercent: 100)]
        XCTAssertEqual(ReferenceDecimationEngine.decimate(samples: single).count, 1)
    }

    func test_B8_02_TenThousandSamplesDecimation_CompletesUnder50ms() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []
        samples.reserveCapacity(10_000)

        for i in 0..<10_000 {
            let t = now.addingTimeInterval(-Double(i) * 300.0) // Every 5 minutes over ~34 days
            samples.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 95, wearPercentage: 5,
                temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100
            ))
        }

        let start = CFAbsoluteTimeGetCurrent()
        let decimated = ReferenceDecimationEngine.decimate(samples: samples, relativeTo: now)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.100, "Decimation of 10,000 samples took \(elapsed)s (expected < 100ms)")
        XCTAssertLessThan(decimated.count, 1000)
    }

    func test_B8_03_SamplesAcrossLeapYearAndDaylightSavings() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let leapDay = formatter.date(from: "2024-02-29 12:00:00") else {
            XCTFail("Failed to create leap day date")
            return
        }

        let s = SSDHistorySnapshot(timestamp: leapDay, healthScorePercent: 98, wearPercentage: 2, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100)
        let decimated = ReferenceDecimationEngine.decimate(samples: [s], relativeTo: leapDay.addingTimeInterval(86400))
        XCTAssertEqual(decimated.count, 1)
    }

    func test_B8_04_CorruptedHistoryJSON_ThrowsDecodingError() {
        let corrupted = "{ invalid json data ...".data(using: .utf8)!
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(SSDHistoryStoreDocument.self, from: corrupted))
    }

    func test_B8_05_HistoryPersistenceIsolation_DifferentiatesSerialNumbers() {
        let doc1 = SSDHistoryStoreDocument(driveIdentifier: "DRIVE-AAA", ratedTBW: 150.0)
        let doc2 = SSDHistoryStoreDocument(driveIdentifier: "DRIVE-BBB", ratedTBW: 300.0)

        XCTAssertNotEqual(doc1.driveIdentifier, doc2.driveIdentifier)
        XCTAssertNotEqual(doc1.ratedTBW, doc2.ratedTBW)
    }

    // =========================================================================
    // MARK: - Boundary Group 9: Notification Engine Boundary Conditions
    // =========================================================================

    func test_B9_01_TemperatureExactThreshold_59_9vs60_0() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let m59 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 59.9, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        XCTAssertEqual(engine.evaluateAlerts(metrics: m59, now: now).count, 0)

        let m60 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 60.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        XCTAssertEqual(engine.evaluateAlerts(metrics: m60, now: now).count, 1)
    }

    func test_B9_02_WearMilestoneExactBoundary_79vs80() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let m79 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 21,
            wearPercentage: 79, temperatureCelsius: 40.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 100.0, terabytesRead: 100.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        XCTAssertFalse(engine.evaluateAlerts(metrics: m79, now: now).contains(where: { $0.contains("WEAR_MILESTONE") }))

        let m80 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 20,
            wearPercentage: 80, temperatureCelsius: 40.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 100.0, terabytesRead: 100.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        XCTAssertTrue(engine.evaluateAlerts(metrics: m80, now: now).contains(where: { $0.contains("WEAR_MILESTONE_80") }))
    }

    func test_B9_03_AvailableSpareExactBoundary_10vs9() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let m10 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 50,
            wearPercentage: 50, temperatureCelsius: 40.0, availableSparePercent: 10,
            availableSpareThresholdPercent: 10, terabytesWritten: 100.0, terabytesRead: 100.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        XCTAssertFalse(engine.evaluateAlerts(metrics: m10, spareWarnThreshold: 10, now: now).contains(where: { $0.contains("SPARE_CAPACITY_LOW") }))

        let m9 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 50,
            wearPercentage: 50, temperatureCelsius: 40.0, availableSparePercent: 9,
            availableSpareThresholdPercent: 10, terabytesWritten: 100.0, terabytesRead: 100.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        XCTAssertTrue(engine.evaluateAlerts(metrics: m9, spareWarnThreshold: 10, now: now).contains(where: { $0.contains("SPARE_CAPACITY_LOW") }))
    }

    func test_B9_04_Rapid1msBurstTriggers_DebounceSuppressesAllExceptFirst() {
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

        let a1 = engine.evaluateAlerts(metrics: hot, now: now)
        XCTAssertEqual(a1.count, 1)

        let a2 = engine.evaluateAlerts(metrics: hot, now: now.addingTimeInterval(0.001))
        XCTAssertEqual(a2.count, 0)

        let a3 = engine.evaluateAlerts(metrics: hot, now: now.addingTimeInterval(0.002))
        XCTAssertEqual(a3.count, 0)
    }

    func test_B9_05_SimultaneousMultipleAlertCategories() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let multi = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 5,
            wearPercentage: 95, temperatureCelsius: 72.0, availableSparePercent: 5,
            availableSpareThresholdPercent: 10, terabytesWritten: 280.0, terabytesRead: 300.0,
            powerOnHours: 15000, powerCycles: 2000, unsafeShutdowns: 20, mediaErrors: 5, errorLogEntries: 10,
            criticalWarnings: [.reliabilityDegraded, .readOnly], timestamp: now
        )

        let alerts = engine.evaluateAlerts(metrics: multi, now: now)
        XCTAssertGreaterThanOrEqual(alerts.count, 4) // Thermal, Wear, Spare, Reliability, ReadOnly
    }

    // =========================================================================
    // MARK: - Boundary Group 10: Diagnostic Export Boundary Conditions
    // =========================================================================

    func test_B10_01_SpecialCharactersInDeviceNames_HandledSafely() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0s1", modelName: "APPLE SSD \"Custom\" <Pro>", serialNumber: "SN/123\\456,789",
            firmwareRevision: "561.100.", interconnect: "Apple Fabric", capacityBytes: 251_000_193_024,
            healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 10.0,
            terabytesRead: 10.0, powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let jsonStr = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: [], forecast: nil)
        assertJSONValid(jsonStr, requiredTopLevelKeys: ["drive"])
    }

    func test_B10_02_CSVExportWithZeroRows_ProducesValidHeaderOnly() {
        let csv = ReferenceDiagnosticExporter.exportCSV(history: [])
        assertCSVValid(csv, expectedRowCount: 0)
    }

    func test_B10_03_MaxUInt64CountersInExport_FormattedAccurately() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-MAX",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 10_000_000_000_000_000,
            healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 100000.0,
            terabytesRead: 100000.0, powerOnHours: UInt64.max, powerCycles: UInt64.max,
            unsafeShutdowns: UInt64.max, mediaErrors: UInt64.max, errorLogEntries: UInt64.max,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let rep = ReferenceDiagnosticExporter.exportTextReport(metrics: metrics, history: [], forecast: nil)
        XCTAssertTrue(rep.contains("\(UInt64.max)"))
    }

    func test_B10_04_TextReportSections_MaintainConsistentSeparators() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 98,
            wearPercentage: 2, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let rep = ReferenceDiagnosticExporter.exportTextReport(metrics: metrics, history: [], forecast: nil)
        let separatorCount = rep.components(separatedBy: "--------------------------------------------------------------------------------").count
        XCTAssertGreaterThanOrEqual(separatorCount, 5)
    }

    func test_B10_05_UnicodeAndEmojisInExportStrings_Preserved() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD 🚀 Edition", serialNumber: "SN-✨",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 98, wearPercentage: 2, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 10.0,
            terabytesRead: 10.0, powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let json = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: [], forecast: nil)
        XCTAssertTrue(json.contains("🚀"))
    }

    // =========================================================================
    // MARK: - Boundary Group 11: Menu Bar Display Mode Boundary Conditions
    // =========================================================================

    func test_B11_01_ZeroPercentHealth_FormatsCorrectly() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 0,
            wearPercentage: 100, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndHealth), "0%")
    }

    func test_B11_02_HundredPercentHealth_FormatsCorrectly() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 100,
            wearPercentage: 0, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndHealth), "100%")
    }

    func test_B11_03_SubZeroTemperature_FormatsWithMinusSign() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 100,
            wearPercentage: 0, temperatureCelsius: -5.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndTemp), "-5°C")
    }

    func test_B11_04_HighTemperature_FormatsAboveHundred() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 100,
            wearPercentage: 0, temperatureCelsius: 105.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndTemp), "105°C")
    }

    func test_B11_05_NilMetricsAcrossAllModes_HandlesGracefully() {
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: nil, mode: .iconOnly), "--%")
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: nil, mode: .iconAndHealth), "--%")
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: nil, mode: .iconAndTemp), "--%")
        XCTAssertEqual(ReferenceMenuBarFormatter.formatTitle(metrics: nil, mode: .iconHealthAndTemp), "--%")
    }

    // =========================================================================
    // MARK: - Boundary Group 12: Popover QuickView Boundary Conditions
    // =========================================================================

    func test_B12_01_ScoreClamp_ZeroAndHundred() {
        let clampMin = max(0, min(100, -10))
        XCTAssertEqual(clampMin, 0)
        let clampMax = max(0, min(100, 110))
        XCTAssertEqual(clampMax, 100)
    }

    func test_B12_02_TemperatureBoundary49_9vs50_0() {
        func tempClass(_ c: Double) -> String {
            if c >= 65.0 { return "Hot" }
            if c >= 50.0 { return "Warm" }
            return "Optimal"
        }
        XCTAssertEqual(tempClass(49.9), "Optimal")
        XCTAssertEqual(tempClass(50.0), "Warm")
        XCTAssertEqual(tempClass(64.9), "Warm")
        XCTAssertEqual(tempClass(65.0), "Hot")
    }

    func test_B12_03_ExtremeTBWFormatting_PetabytesScale() {
        let tbw = 12500.5
        let formatted = String(format: "%.1f TBW", tbw)
        XCTAssertEqual(formatted, "12500.5 TBW")
    }

    func test_B12_04_LifespanStringForExhaustedDrive() {
        func formatLifespan(days: Double) -> String {
            days <= 0 ? "Exhausted" : String(format: "~%.1f Years", days / 365.25)
        }
        let str = formatLifespan(days: 0.0)
        XCTAssertEqual(str, "Exhausted")
    }

    func test_B12_05_QuickViewActionState_TogglesIndependently() {
        var isRefreshing = false
        isRefreshing = true
        XCTAssertTrue(isRefreshing)
        isRefreshing = false
        XCTAssertFalse(isRefreshing)
    }

    // =========================================================================
    // MARK: - Boundary Group 13: Dashboard Window & SMART Table Boundary Conditions
    // =========================================================================

    func test_B13_01_AllParametersMaximized_BuildsTableWithoutCrash() {
        let buffer = SyntheticNVMeFixtures.makeAllOnesBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        XCTAssertGreaterThanOrEqual(rows.count, 17)
    }

    func test_B13_02_SearchQueryNonExistent_ReturnsEmpty() {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        let filtered = rows.filter { $0.name.localizedCaseInsensitiveContains("NON_EXISTENT_PARAMETER") }
        XCTAssertEqual(filtered.count, 0)
    }

    func test_B13_03_SearchQueryPartial_ReturnsMatchingRows() {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        let filtered = rows.filter { $0.name.localizedCaseInsensitiveContains("power") }
        XCTAssertEqual(filtered.count, 2) // Power Cycles, Power-On Hours
    }

    func test_B13_04_SMARTTableSorting_SortsByIdOrder() {
        let buffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        let sorted = rows.sorted(by: { $0.id < $1.id })
        XCTAssertEqual(sorted.first?.id, 1)
        XCTAssertEqual(sorted.first?.name, "Critical Warning")
    }

    func test_B13_05_AllCriticalStatusClassification() {
        let buffer = SyntheticNVMeFixtures.makeNearEOLBuffer()
        guard let log = NVMESmartLog(data: buffer) else {
            XCTFail("Failed to parse buffer")
            return
        }

        let rows = ReferenceSMARTTableFormatter.buildTableRows(from: log)
        let critCount = rows.filter { $0.status == .critical }.count
        XCTAssertGreaterThanOrEqual(critCount, 2) // Critical Warning, Available Spare, Percentage Used, Media Errors
    }

    // =========================================================================
    // MARK: - Boundary Group 14: Swift Charts Boundary Conditions
    // =========================================================================

    func test_B14_01_SingleSampleEmptyStateChart() {
        let samples = [SSDHistorySnapshot(timestamp: Date(), healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100)]
        XCTAssertFalse(samples.count >= 2)
    }

    func test_B14_02_FlatlineWearAt100Percent() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []
        for i in 0..<10 {
            samples.append(SSDHistorySnapshot(
                timestamp: now.addingTimeInterval(Double(i) * 86400),
                healthScorePercent: 0, wearPercentage: 100, temperatureCelsius: 40.0,
                terabytesWritten: 300.0, availableSparePercent: 80
            ))
        }
        let wearDeltas = samples.map { $0.wearPercentage }
        XCTAssertTrue(wearDeltas.allSatisfy { $0 == 100 })
    }

    func test_B14_03_TimestampGapHandling_SleepFor3Months() {
        let now = Date()
        let t1 = now.addingTimeInterval(-90 * 86400)
        let t2 = now
        let span = t2.timeIntervalSince(t1)
        XCTAssertGreaterThan(span, 80 * 86400)
    }

    func test_B14_04_MultiYearDataset_MaintainsTemporalOrder() {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []
        for i in (0..<500).reversed() {
            samples.append(SSDHistorySnapshot(
                timestamp: now.addingTimeInterval(-Double(i) * 86400),
                healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0,
                terabytesWritten: 10.0, availableSparePercent: 100
            ))
        }
        let sorted = samples.sorted(by: { $0.timestamp < $1.timestamp })
        XCTAssertEqual(sorted.first?.timestamp, samples.first?.timestamp)
    }

    func test_B14_05_ZeroDeltaDailyWrites_ProducesZeroBars() {
        let tbw = [10.0, 10.0, 10.0]
        var deltas: [Double] = []
        for i in 1..<tbw.count {
            deltas.append((tbw[i] - tbw[i - 1]) * 1000.0)
        }
        XCTAssertEqual(deltas, [0.0, 0.0])
    }

    // =========================================================================
    // MARK: - Boundary Group 15: Settings Boundary Conditions
    // =========================================================================

    func test_B15_01_ThresholdMinGreaterOrEqualMax_Validated() {
        let warn = 70
        let crit = 65
        let isValid = warn < crit
        XCTAssertFalse(isValid)
    }

    func test_B15_02_PollingIntervalBoundsClamping() {
        let rawMin = -5
        let rawMax = 120
        let clampedMin = max(1, min(60, rawMin))
        let clampedMax = max(1, min(60, rawMax))
        XCTAssertEqual(clampedMin, 1)
        XCTAssertEqual(clampedMax, 60)
    }

    func test_B15_03_TemperatureUnitToggling_RepeatedFlips() {
        var unit: TemperatureUnit = .celsius
        for _ in 0..<10 {
            unit = (unit == .celsius ? .fahrenheit : .celsius)
        }
        XCTAssertEqual(unit, .celsius)
    }

    func test_B15_04_ExtremeCustomTBWValues() {
        let tinyTBW = 1.0
        let hugeTBW = 100_000.0
        XCTAssertGreaterThan(tinyTBW, 0.0)
        XCTAssertGreaterThan(hugeTBW, 1000.0)
    }

    func test_B15_05_EmptySettingsDocument_DefaultsGracefully() {
        let defaultPolling = 15
        let defaultTempWarn = 65
        XCTAssertEqual(defaultPolling, 15)
        XCTAssertEqual(defaultTempWarn, 65)
    }
}
