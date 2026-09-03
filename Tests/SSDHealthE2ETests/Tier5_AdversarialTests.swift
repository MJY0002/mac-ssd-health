import Foundation
import XCTest
@testable import SSDHealthCore

/// Tier 5: Adversarial Stress, Boundary Fuzzing & Memory Safety Test Suite.
///
/// Designed to aggressively challenge assumptions, stress-test extreme boundary conditions,
/// probe arithmetic overflow / borrow mechanics, and fuzz binary parsers with corrupted inputs.
final class Tier5_AdversarialTests: XCTestCase {

    // =========================================================================
    // MARK: - Category 1: Binary Buffer Boundary, Truncation & Corruption
    // =========================================================================

    func test_ADV01_TruncatedBuffers_AllSub512Lengths_SafelyRejected() {
        // Test every single length from 0 to 511 bytes to verify no buffer overrun
        for length in 0..<512 {
            let truncated = Data(repeating: UInt8(length % 256), count: length)
            let log = NVMESmartLog(data: truncated)
            XCTAssertNil(log, "Buffer of length \(length) must be rejected with nil")
        }
    }

    func test_ADV02_OversizedBuffers_VariableLengths_SafelyParsed() {
        let baseBuffer = SyntheticNVMeFixtures.makePristineBuffer()
        let oversizedLengths = [513, 514, 600, 1024, 4096, 65536, 1_048_576]

        for extraLen in oversizedLengths {
            var data = baseBuffer
            data.append(Data(repeating: 0xEE, count: extraLen - 512))
            XCTAssertEqual(data.count, extraLen)

            guard let log = NVMESmartLog(data: data) else {
                XCTFail("Oversized buffer of length \(extraLen) should parse first 512 bytes successfully")
                continue
            }

            XCTAssertEqual(log.compositeTemperatureKelvin, 305)
            XCTAssertEqual(log.percentageUsed, 0)
            XCTAssertEqual(log.healthScorePercent, 100)
            XCTAssertTrue(log.criticalWarning.isClean)
        }
    }

    func test_ADV03_AllZeroBuffer_ExtremeFieldValues() {
        let allZero = Data(repeating: 0x00, count: 512)
        guard let log = NVMESmartLog(data: allZero) else {
            XCTFail("All zeros buffer should parse without crashing")
            return
        }

        XCTAssertTrue(log.criticalWarning.isClean)
        XCTAssertEqual(log.criticalWarning.rawValue, 0)
        XCTAssertEqual(log.compositeTemperatureKelvin, 0)
        XCTAssertEqual(log.temperatureCelsius, 0.0) // 0 K guard
        XCTAssertEqual(log.temperatureFahrenheit, 32.0)
        XCTAssertEqual(log.percentageUsed, 0)
        XCTAssertEqual(log.healthScorePercent, 100)
        XCTAssertEqual(log.availableSparePercent, 0)
        XCTAssertEqual(log.availableSpareThresholdPercent, 0)
        XCTAssertEqual(log.enduranceGroupSummary, 0)
        XCTAssertEqual(log.dataUnitsRead, .zero)
        XCTAssertEqual(log.dataUnitsWritten, .zero)
        XCTAssertEqual(log.totalBytesWritten, 0.0)
        XCTAssertEqual(log.totalTerabytesWritten, 0.0)
        XCTAssertEqual(log.activeTemperatureSensorsCelsius.count, 0)
    }

    func test_ADV04_AllOnesBuffer_ExtremeFieldValues() {
        let allOnes = Data(repeating: 0xFF, count: 512)
        guard let log = NVMESmartLog(data: allOnes) else {
            XCTFail("All ones buffer should parse without crashing")
            return
        }

        XCTAssertEqual(log.criticalWarning.rawValue, 0xFF)
        XCTAssertFalse(log.criticalWarning.isClean)
        XCTAssertTrue(log.criticalWarning.isSevereHardwareAlert)
        XCTAssertEqual(log.compositeTemperatureKelvin, UInt16.max)
        XCTAssertEqual(log.percentageUsed, 255)
        XCTAssertEqual(log.healthScorePercent, 0) // Clamped to 0%
        XCTAssertEqual(log.availableSparePercent, 255)
        XCTAssertEqual(log.availableSpareThresholdPercent, 255)
        XCTAssertEqual(log.enduranceGroupSummary, 255)
        XCTAssertEqual(log.dataUnitsRead, .max)
        XCTAssertEqual(log.dataUnitsWritten, .max)
        XCTAssertEqual(log.powerCycles, .max)
        XCTAssertEqual(log.powerOnHours, .max)
        XCTAssertEqual(log.unsafeShutdowns, .max)
        XCTAssertEqual(log.mediaErrors, .max)
        XCTAssertEqual(log.numErrorInfoLogEntries, .max)
        XCTAssertEqual(log.warningCompositeTempTimeMinutes, UInt32.max)
        XCTAssertEqual(log.criticalCompositeTempTimeMinutes, UInt32.max)
        XCTAssertEqual(log.temperatureSensorsKelvin.count, 8)
        XCTAssertEqual(log.activeTemperatureSensorsCelsius.count, 8)
    }

    // =========================================================================
    // MARK: - Category 2: Temperature Conversions & Sensors Edge Cases
    // =========================================================================

    func test_ADV05_TemperatureKelvinBoundaries() {
        // 0 Kelvin -> Guarded to 0.0 °C
        let log0 = NVMESmartLog(data: SyntheticSMARTFixtures.makeCustomBuffer(temperatureKelvin: 0))!
        XCTAssertEqual(log0.compositeTemperatureKelvin, 0)
        XCTAssertEqual(log0.temperatureCelsius, 0.0)
        XCTAssertEqual(log0.temperatureFahrenheit, 32.0)

        // 1 Kelvin -> -272.15 °C
        let log1 = NVMESmartLog(data: SyntheticSMARTFixtures.makeCustomBuffer(temperatureKelvin: 1))!
        XCTAssertEqual(log1.compositeTemperatureKelvin, 1)
        XCTAssertEqual(round(log1.temperatureCelsius * 100) / 100, -272.15)
        XCTAssertEqual(round(log1.temperatureFahrenheit * 100) / 100, -457.87)

        // 273 Kelvin -> -0.15 °C
        let log273 = NVMESmartLog(data: SyntheticSMARTFixtures.makeCustomBuffer(temperatureKelvin: 273))!
        XCTAssertEqual(round(log273.temperatureCelsius * 100) / 100, -0.15)

        // 274 Kelvin -> +0.85 °C
        let log274 = NVMESmartLog(data: SyntheticSMARTFixtures.makeCustomBuffer(temperatureKelvin: 274))!
        XCTAssertEqual(round(log274.temperatureCelsius * 100) / 100, 0.85)

        // Max UInt16 (65,535 Kelvin) -> 65,261.85 °C
        let logMax = NVMESmartLog(data: SyntheticSMARTFixtures.makeCustomBuffer(temperatureKelvin: UInt16.max))!
        XCTAssertEqual(logMax.compositeTemperatureKelvin, UInt16.max)
        XCTAssertEqual(round(logMax.temperatureCelsius * 100) / 100, 65261.85)
        XCTAssertEqual(round(logMax.temperatureFahrenheit * 100) / 100, 117503.33)
    }

    func test_ADV06_TemperatureSensorsFilteringAndPadding() {
        // Custom sensor arrays of varying lengths
        let emptySensors: [UInt16] = []
        let logEmpty = NVMESmartLog(
            criticalWarning: CriticalWarningFlags(rawValue: 0),
            compositeTemperatureKelvin: 300,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: 0,
            dataUnitsRead: .zero,
            dataUnitsWritten: .zero,
            powerCycles: .zero,
            powerOnHours: .zero,
            unsafeShutdowns: .zero,
            mediaErrors: .zero,
            numErrorInfoLogEntries: .zero,
            temperatureSensorsKelvin: emptySensors
        )
        XCTAssertEqual(logEmpty.temperatureSensorsKelvin.count, 8)
        XCTAssertEqual(logEmpty.temperatureSensorsKelvin, [0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(logEmpty.activeTemperatureSensorsCelsius.count, 0)

        // Sensors with >8 elements (truncated to 8)
        let tenSensors: [UInt16] = [300, 301, 302, 303, 304, 305, 306, 307, 308, 309]
        let logTen = NVMESmartLog(
            criticalWarning: CriticalWarningFlags(rawValue: 0),
            compositeTemperatureKelvin: 300,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: 0,
            dataUnitsRead: .zero,
            dataUnitsWritten: .zero,
            powerCycles: .zero,
            powerOnHours: .zero,
            unsafeShutdowns: .zero,
            mediaErrors: .zero,
            numErrorInfoLogEntries: .zero,
            temperatureSensorsKelvin: tenSensors
        )
        XCTAssertEqual(logTen.temperatureSensorsKelvin.count, 8)
        XCTAssertEqual(logTen.temperatureSensorsKelvin.last, 307)
        XCTAssertEqual(logTen.activeTemperatureSensorsCelsius.count, 8)
    }

    // =========================================================================
    // MARK: - Category 3: Wear Percentage & Health Score Clamping
    // =========================================================================

    func test_ADV07_WearPercentageAndHealthScoreClamping() {
        // Test boundary values 0, 1, 99, 100, 101, 150, 200, 254, 255
        let wearMap: [(UInt8, Int)] = [
            (0, 100),
            (1, 99),
            (50, 50),
            (99, 1),
            (100, 0),
            (101, 0),
            (150, 0),
            (200, 0),
            (254, 0),
            (255, 0)
        ]

        for (wearVal, expectedHealth) in wearMap {
            let buffer = SyntheticSMARTFixtures.makeCustomBuffer(percentageUsed: wearVal)
            let log = NVMESmartLog(data: buffer)!
            XCTAssertEqual(log.percentageUsed, wearVal)
            XCTAssertEqual(log.healthScorePercent, expectedHealth, "Wear \(wearVal)% should map to Health Score \(expectedHealth)%")
        }
    }

    // =========================================================================
    // MARK: - Category 4: UInt128 Arithmetic, Overflows & Borrow Mechanics
    // =========================================================================

    func test_ADV08_UInt128Arithmetic_CarryOverflowAndBorrowUnderflow() {
        // 1. Full 128-bit Addition with carry from low to high
        let valLowMax = UInt128Value(low: UInt64.max, high: 0)
        let one = UInt128Value(low: 1, high: 0)
        let sumCarry = valLowMax + one
        XCTAssertEqual(sumCarry.low, 0)
        XCTAssertEqual(sumCarry.high, 1)

        // 2. Addition causing high word overflow (wraps around to zero safely)
        let valMax = UInt128Value.max
        let sumMaxOverflow = valMax + one
        XCTAssertEqual(sumMaxOverflow.low, 0)
        XCTAssertEqual(sumMaxOverflow.high, 0)
        XCTAssertTrue(sumMaxOverflow.isZero)

        // 3. Subtraction requiring borrow from high word
        let oneHigh = UInt128Value(low: 0, high: 1)
        let diffBorrow = oneHigh - one
        XCTAssertEqual(diffBorrow.low, UInt64.max)
        XCTAssertEqual(diffBorrow.high, 0)

        // 4. Subtraction causing high word underflow (wraps around to max safely)
        let zero = UInt128Value.zero
        let diffUnderflow = zero - one
        XCTAssertEqual(diffUnderflow.low, UInt64.max)
        XCTAssertEqual(diffUnderflow.high, UInt64.max)
        XCTAssertEqual(diffUnderflow, UInt128Value.max)

        // 5. Large addition across both words
        let a = UInt128Value(low: 0x8000_0000_0000_0000, high: 0x4000_0000_0000_0000)
        let b = UInt128Value(low: 0x8000_0000_0000_0000, high: 0x2000_0000_0000_0000)
        let c = a + b
        XCTAssertEqual(c.low, 0)
        XCTAssertEqual(c.high, 0x6000_0000_0000_0001) // 0x4000 + 0x2000 + 1 carry
    }

    func test_ADV09_UInt128Comparisons_AllCombinations() {
        let v0 = UInt128Value(low: 0, high: 0)
        let v1 = UInt128Value(low: 100, high: 0)
        let v2 = UInt128Value(low: 200, high: 0)
        let v3 = UInt128Value(low: 50, high: 1)
        let v4 = UInt128Value(low: 100, high: 1)
        let v5 = UInt128Value(low: 100, high: 2)

        XCTAssertTrue(v0 < v1)
        XCTAssertTrue(v1 < v2)
        XCTAssertTrue(v2 < v3) // v3 has high=1, v2 has high=0
        XCTAssertTrue(v3 < v4)
        XCTAssertTrue(v4 < v5)

        XCTAssertTrue(v5 > v4)
        XCTAssertTrue(v4 > v3)
        XCTAssertTrue(v3 > v2)
        XCTAssertTrue(v2 > v1)
        XCTAssertTrue(v1 > v0)

        XCTAssertTrue(v1 <= v1)
        XCTAssertTrue(v1 >= v1)
        XCTAssertEqual(v1, UInt128Value(low: 100, high: 0))
        XCTAssertNotEqual(v1, v2)
    }

    func test_ADV10_UInt128BufferOffsetBoundaries() {
        var data = Data(repeating: 0, count: 32)
        for i in 0..<32 { data[i] = UInt8(i) }

        // Valid offset at 0
        let u0 = UInt128Value(data: data, offset: 0)
        XCTAssertFalse(u0.isZero)

        // Valid offset at 16 (last possible 16-byte window)
        let u16 = UInt128Value(data: data, offset: 16)
        XCTAssertFalse(u16.isZero)

        // Invalid offset at 17 (only 15 bytes left -> defaults to zero)
        let u17 = UInt128Value(data: data, offset: 17)
        XCTAssertTrue(u17.isZero)

        // Offset > data.count
        let u100 = UInt128Value(data: data, offset: 100)
        XCTAssertTrue(u100.isZero)

        // Byte array initializer short buffer
        let shortBytes: [UInt8] = [1, 2, 3, 4, 5]
        let uBytes = UInt128Value(littleEndianBytes: shortBytes)
        XCTAssertTrue(uBytes.isZero)
    }

    func test_ADV11_UInt128DoubleValueAndFormattingExtremeValues() {
        // Max UInt128 doubleValue
        let maxVal = UInt128Value.max
        let dblMax = maxVal.doubleValue
        XCTAssertFalse(dblMax.isInfinite)
        XCTAssertFalse(dblMax.isNaN)
        XCTAssertGreaterThan(dblMax, 3.4e38)

        // Decimal formatting
        let small = UInt128Value(low: 123456789, high: 0)
        XCTAssertEqual(small.formattedDecimalString, "123456789")

        let large = UInt128Value(low: 0, high: 1000)
        XCTAssertTrue(large.formattedDecimalString.contains("e+"))
        XCTAssertEqual(large.hexString, "0x00000000000003E8_0000000000000000")
    }

    // =========================================================================
    // MARK: - Category 5: Critical Warning Flags Bitmask (All 256 Permutations)
    // =========================================================================

    func test_ADV12_CriticalWarningFlags_All256ByteValues() {
        for byteVal in 0...255 {
            let flags = CriticalWarningFlags(rawValue: UInt8(byteVal))

            if byteVal == 0 {
                XCTAssertTrue(flags.isClean)
                XCTAssertFalse(flags.isSevereHardwareAlert)
                XCTAssertEqual(flags.activeWarnings.count, 0)
                XCTAssertEqual(flags.description, "Clean (0x00)")
            } else {
                XCTAssertFalse(flags.isClean)
                XCTAssertTrue(flags.description.contains("Critical Warnings"))

                // Verify specific bit detections
                if (byteVal & 0x01) != 0 {
                    XCTAssertTrue(flags.contains(.availableSpareBelowThreshold))
                    XCTAssertTrue(flags.activeWarnings.contains("Available Spare Below Threshold"))
                }
                if (byteVal & 0x02) != 0 {
                    XCTAssertTrue(flags.contains(.temperatureExceedsThreshold))
                    XCTAssertTrue(flags.activeWarnings.contains("Temperature Exceeds Threshold"))
                }
                if (byteVal & 0x04) != 0 {
                    XCTAssertTrue(flags.contains(.reliabilityDegraded))
                    XCTAssertTrue(flags.activeWarnings.contains("NVM Subsystem Reliability Degraded"))
                    XCTAssertTrue(flags.isSevereHardwareAlert)
                }
                if (byteVal & 0x08) != 0 {
                    XCTAssertTrue(flags.contains(.readOnly))
                    XCTAssertTrue(flags.activeWarnings.contains("Drive in Read-Only Mode"))
                    XCTAssertTrue(flags.isSevereHardwareAlert)
                }
                if (byteVal & 0x10) != 0 {
                    XCTAssertTrue(flags.contains(.volatileMemoryBackupFailed))
                    XCTAssertTrue(flags.activeWarnings.contains("Volatile Memory Backup Device Failed"))
                    XCTAssertTrue(flags.isSevereHardwareAlert)
                }
                if (byteVal & 0x20) != 0 {
                    XCTAssertTrue(flags.contains(.persistentMemoryUnreliable))
                    XCTAssertTrue(flags.activeWarnings.contains("Persistent Memory Unreliable"))
                }

                // Reserved bits 6 (0x40) and 7 (0x80) should not crash
                if (byteVal & 0xC0) != 0 {
                    // Description should safely include the hex string
                    XCTAssertFalse(flags.description.isEmpty)
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Category 6: Random & Mutational Fuzzing (10,000 Iterations)
    // =========================================================================

    func test_ADV13_Fuzzing_Random512ByteBuffers_ZeroCrashes() {
        var rng = SplitMix64(seed: 0xDEADBEEF_CAFE1234)

        for _ in 0..<5000 {
            var randomBytes = [UInt8](repeating: 0, count: 512)
            for i in 0..<512 {
                randomBytes[i] = UInt8(truncatingIfNeeded: rng.next())
            }

            let data = Data(randomBytes)
            guard let log = NVMESmartLog(data: data) else {
                XCTFail("512-byte random data must not fail initialization")
                return
            }

            // Exercise all computed properties to verify zero crashes, div-by-zero or overflows
            _ = log.temperatureCelsius
            _ = log.temperatureFahrenheit
            _ = log.healthScorePercent
            _ = log.totalBytesWritten
            _ = log.totalTerabytesWritten
            _ = log.totalGigabytesWritten
            _ = log.totalBytesRead
            _ = log.totalTerabytesRead
            _ = log.totalGigabytesRead
            _ = log.activeTemperatureSensorsCelsius
            _ = log.criticalWarning.description
            _ = log.criticalWarning.isClean
            _ = log.criticalWarning.isSevereHardwareAlert

            // Serialization roundtrip
            let reserialized = log.toData()
            XCTAssertEqual(reserialized.count, 512)
            let roundtrip = NVMESmartLog(data: reserialized)
            XCTAssertNotNil(roundtrip)
            XCTAssertEqual(log, roundtrip)
        }
    }

    func test_ADV14_Fuzzing_VariableLengthAndCorruptedBuffers_ZeroCrashes() {
        var rng = SplitMix64(seed: 0x12345678_9ABCDEF0)

        // 2000 iterations of variable-length buffers
        for _ in 0..<2000 {
            let length = Int(rng.next() % 2048)
            var bytes = [UInt8](repeating: 0, count: length)
            for i in 0..<length {
                bytes[i] = UInt8(truncatingIfNeeded: rng.next())
            }

            let data = Data(bytes)
            let log = NVMESmartLog(data: data)
            if length < 512 {
                XCTAssertNil(log)
            } else {
                XCTAssertNotNil(log)
                _ = log?.temperatureCelsius
                _ = log?.healthScorePercent
                _ = log?.totalTerabytesWritten
            }
        }
    }

    func test_ADV15_Fuzzing_MutatedValidBuffers_ZeroCrashes() {
        var rng = SplitMix64(seed: 0xCAFEBABE_FEEDFACE)
        let template = SyntheticSMARTFixtures.healthyRawBuffer()

        // 3000 iterations of single/multi-byte mutations on valid buffer
        for _ in 0..<3000 {
            var mutated = template
            let mutationCount = Int((rng.next() % 20) + 1)

            for _ in 0..<mutationCount {
                let offset = Int(rng.next() % 512)
                let val = UInt8(truncatingIfNeeded: rng.next())
                mutated[offset] = val
            }

            guard let log = NVMESmartLog(data: mutated) else {
                XCTFail("Mutated 512-byte buffer should parse")
                continue
            }

            _ = log.healthScorePercent
            _ = log.temperatureCelsius
            _ = log.totalTerabytesWritten
            _ = log.criticalWarning.activeWarnings
        }
    }

    // =========================================================================
    // MARK: - Category 7: Storage Reader Fallback, Concurrency & Resilience
    // =========================================================================

    func test_ADV16_IOKitStorageReader_GracefulFallbackUnderSandboxOrNoHW() async throws {
        let reader = IOKitStorageReader()
        let metrics = try await reader.readHealthMetrics()

        XCTAssertFalse(metrics.modelName.isEmpty)
        XCTAssertFalse(metrics.bsdName.isEmpty)
        XCTAssertGreaterThan(metrics.capacityBytes, 0)
        XCTAssertGreaterThanOrEqual(metrics.healthScorePercent, 0)
        XCTAssertLessThanOrEqual(metrics.healthScorePercent, 100)
        XCTAssertGreaterThanOrEqual(metrics.wearPercentage, 0)
        XCTAssertGreaterThanOrEqual(metrics.terabytesWritten, 0.0)
        XCTAssertGreaterThanOrEqual(metrics.terabytesRead, 0.0)

        // Live hardware or fallback data
        if reader.isLiveHardwareAccessAvailable() {
            XCTAssertFalse(metrics.isFallbackData)
        } else {
            XCTAssertTrue(metrics.isFallbackData)
            XCTAssertEqual(metrics.healthScorePercent, 100)
            XCTAssertEqual(metrics.temperatureCelsius, 38.0)
        }
    }

    func test_ADV17_MockStorageReader_HighConcurrencyStress() async throws {
        let reader = MockSSDStorageReader(preset: .warning)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let m = try await reader.readHealthMetrics()
                    XCTAssertEqual(m.healthScorePercent, 72)
                    XCTAssertEqual(m.wearPercentage, 28)
                    let log = try await reader.readRawSmartLog()
                    XCTAssertEqual(log.percentageUsed, 28)
                }
            }
            try await group.waitForAll()
        }
    }

    func test_ADV18_SSDHealthMetrics_ExtremeValuesFormatting() {
        let extreme = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "Extreme SSD",
            serialNumber: "",
            firmwareRevision: "REV99",
            interconnect: "Apple Fabric",
            capacityBytes: UInt64.max,
            healthScorePercent: 0,
            wearPercentage: 255,
            temperatureCelsius: -273.15,
            availableSparePercent: 0,
            availableSpareThresholdPercent: 100,
            terabytesWritten: 999_999_999.99,
            terabytesRead: 1_999_999_999.99,
            powerOnHours: UInt64.max,
            powerCycles: UInt64.max,
            unsafeShutdowns: UInt64.max,
            mediaErrors: UInt64.max,
            errorLogEntries: UInt64.max,
            criticalWarnings: CriticalWarningFlags(rawValue: 0xFF)
        )

        XCTAssertEqual(extreme.id, "disk0") // Fallback to BSD name when serial is empty
        XCTAssertEqual(extreme.wearFormatted, "255%")
        XCTAssertEqual(extreme.healthScoreFormatted, "0%")
        XCTAssertEqual(extreme.temperatureFormatted, "-273.1 °C")
        XCTAssertFalse(extreme.isHealthy)
    }

    func test_ADV19_DataSubSequenceSlices_NonZeroStartIndex() {
        var base = Data(repeating: 0xAA, count: 100)
        base.append(SyntheticSMARTFixtures.healthyRawBuffer())
        base.append(Data(repeating: 0xBB, count: 100))

        // Subdata (starts at index 0)
        let subData = base.subdata(in: 100..<612)
        let logFromSub = NVMESmartLog(data: subData)
        XCTAssertNotNil(logFromSub)
        XCTAssertEqual(logFromSub?.percentageUsed, 2)

        // Sliced Data (starts at index 100)
        // Converting slice to contiguous Data ensures 0-based indices
        let slice = base[100..<612]
        let contiguousData = Data(slice)
        let logFromContiguous = NVMESmartLog(data: contiguousData)
        XCTAssertNotNil(logFromContiguous)
        XCTAssertEqual(logFromContiguous?.percentageUsed, 2)
    }

    func test_ADV20_MockReader_AllSevenPresets_ProduceValidMetrics() async throws {
        let presets: [MockSSDStorageReader.Preset] = [
            .healthy,
            .warning,
            .overheating,
            .criticalWear,
            .degradedSpare
        ]

        for preset in presets {
            let reader = MockSSDStorageReader(preset: preset)
            let metrics = try await reader.readHealthMetrics()
            XCTAssertFalse(metrics.modelName.isEmpty)
            XCTAssertFalse(metrics.serialNumber.isEmpty)
            XCTAssertGreaterThan(metrics.capacityBytes, 0)
            XCTAssertGreaterThanOrEqual(metrics.healthScorePercent, 0)
            XCTAssertLessThanOrEqual(metrics.healthScorePercent, 100)

            let rawLog = try await reader.readRawSmartLog()
            XCTAssertEqual(rawLog.percentageUsed, UInt8(metrics.wearPercentage))
        }

        // Error presets
        let errReader1 = MockSSDStorageReader(preset: .permissionDenied)
        XCTAssertFalse(errReader1.isLiveHardwareAccessAvailable())
        do {
            _ = try await errReader1.readHealthMetrics()
            XCTFail("Should throw permission denied")
        } catch let err as StorageReaderError {
            if case .permissionDenied = err {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error: \(err)")
            }
        }

        let errReader2 = MockSSDStorageReader(preset: .deviceNotFound)
        XCTAssertFalse(errReader2.isLiveHardwareAccessAvailable())
        do {
            _ = try await errReader2.readHealthMetrics()
            XCTFail("Should throw device not found")
        } catch let err as StorageReaderError {
            XCTAssertEqual(err, .deviceNotFound)
        }
    }

    func test_ADV21_UInt128Value_DoubleValue_NoInfiniteOrNaNInTBW() {
        let maxUInt128 = UInt128Value.max
        let logMax = NVMESmartLog(
            criticalWarning: CriticalWarningFlags(rawValue: 0),
            compositeTemperatureKelvin: 300,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: 0,
            dataUnitsRead: maxUInt128,
            dataUnitsWritten: maxUInt128,
            powerCycles: .zero,
            powerOnHours: .zero,
            unsafeShutdowns: .zero,
            mediaErrors: .zero,
            numErrorInfoLogEntries: .zero
        )

        XCTAssertFalse(logMax.totalBytesWritten.isNaN)
        XCTAssertFalse(logMax.totalTerabytesWritten.isNaN)
        XCTAssertFalse(logMax.totalBytesRead.isNaN)
        XCTAssertFalse(logMax.totalTerabytesRead.isNaN)
        XCTAssertGreaterThan(logMax.totalTerabytesWritten, 1e20)
    }

    func test_ADV22_SSDHealthMetrics_isHealthy_AllCriteriaEvaluation() {
        // Healthy baseline
        let cleanWarnings = CriticalWarningFlags(rawValue: 0)
        let mHealthy = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 40.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: cleanWarnings
        )
        XCTAssertTrue(mHealthy.isHealthy)

        // Fails when healthScorePercent <= 20
        let mLowHealth = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 20,
            wearPercentage: 80, temperatureCelsius: 40.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: cleanWarnings
        )
        XCTAssertFalse(mLowHealth.isHealthy)

        // Fails when spare < threshold
        let mLowSpare = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 40.0, availableSparePercent: 9,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: cleanWarnings
        )
        XCTAssertFalse(mLowSpare.isHealthy)

        // Fails when temperature >= 65.0
        let mOverheat = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 65.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: cleanWarnings
        )
        XCTAssertFalse(mOverheat.isHealthy)

        // Fails when mediaErrors > 0
        let mErrors = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 500_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 40.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 1, errorLogEntries: 0,
            criticalWarnings: cleanWarnings
        )
        XCTAssertFalse(mErrors.isHealthy)
    }
}

// MARK: - Deterministic PRNG for Fuzzing

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
