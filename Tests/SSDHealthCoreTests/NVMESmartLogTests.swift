import XCTest
import Foundation
@testable import SSDHealthCore

final class NVMESmartLogTests: XCTestCase {

    func testDecodingStandardHealthyLog() {
        let rawBuffer = SyntheticSMARTFixtures.healthyRawBuffer()
        XCTAssertEqual(rawBuffer.count, 512)

        guard let log = NVMESmartLog(data: rawBuffer) else {
            XCTFail("Failed to decode standard healthy raw buffer")
            return
        }

        XCTAssertTrue(log.criticalWarning.isClean)
        XCTAssertEqual(log.criticalWarning.rawValue, 0)
        XCTAssertEqual(log.percentageUsed, 2)
        XCTAssertEqual(log.healthScorePercent, 98)
        XCTAssertEqual(log.availableSparePercent, 100)
        XCTAssertEqual(log.availableSpareThresholdPercent, 10)

        XCTAssertEqual(log.compositeTemperatureKelvin, 307)
        XCTAssertEqual(round(log.temperatureCelsius * 100) / 100, 33.85)

        XCTAssertEqual(log.powerCycles.low, 310)
        XCTAssertEqual(log.powerOnHours.low, 1240)
        XCTAssertEqual(log.unsafeShutdowns.low, 4)
        XCTAssertEqual(log.mediaErrors.low, 0)
        XCTAssertEqual(log.numErrorInfoLogEntries.low, 0)

        // Verify TBW calculation (28,945,313 units * 512,000 bytes ≈ 14.82 TB)
        XCTAssertGreaterThan(log.totalTerabytesWritten, 14.80)
        XCTAssertLessThan(log.totalTerabytesWritten, 14.85)
        XCTAssertGreaterThan(log.totalGigabytesWritten, 14800.0)

        // Sensors
        XCTAssertEqual(log.activeTemperatureSensorsCelsius.count, 2)
    }

    func testCriticalWarningBitmaskParsing() {
        // Test each bit individually
        let bits: [(UInt8, CriticalWarningFlags, String)] = [
            (0x01, .availableSpareBelowThreshold, "Available Spare Below Threshold"),
            (0x02, .temperatureExceedsThreshold, "Temperature Exceeds Threshold"),
            (0x04, .reliabilityDegraded, "NVM Subsystem Reliability Degraded"),
            (0x08, .readOnly, "Drive in Read-Only Mode"),
            (0x10, .volatileMemoryBackupFailed, "Volatile Memory Backup Device Failed"),
            (0x20, .persistentMemoryUnreliable, "Persistent Memory Unreliable")
        ]

        for (byteVal, expectedFlag, desc) in bits {
            let buffer = SyntheticSMARTFixtures.makeCustomBuffer(criticalWarning: byteVal)
            guard let log = NVMESmartLog(data: buffer) else {
                XCTFail("Failed to parse buffer with warning byte 0x\(String(format: "%02x", byteVal))")
                continue
            }
            XCTAssertTrue(log.criticalWarning.contains(expectedFlag))
            XCTAssertTrue(log.criticalWarning.activeWarnings.contains(desc))
            XCTAssertFalse(log.criticalWarning.isClean)
        }

        // Test combined multiple warning bits (Spare + Overheating + Degraded = 0x07)
        let multiBuffer = SyntheticSMARTFixtures.makeCustomBuffer(criticalWarning: 0x07)
        let multiLog = NVMESmartLog(data: multiBuffer)!
        XCTAssertTrue(multiLog.criticalWarning.contains(.availableSpareBelowThreshold))
        XCTAssertTrue(multiLog.criticalWarning.contains(.temperatureExceedsThreshold))
        XCTAssertTrue(multiLog.criticalWarning.contains(.reliabilityDegraded))
        XCTAssertEqual(multiLog.criticalWarning.activeWarnings.count, 3)
        XCTAssertTrue(multiLog.criticalWarning.isSevereHardwareAlert)
    }

    func testTemperatureConversionsAndSensors() {
        // Absolute Zero / 0 Kelvin (Inactive sensor)
        let zeroBuffer = SyntheticSMARTFixtures.makeCustomBuffer(temperatureKelvin: 0)
        let zeroLog = NVMESmartLog(data: zeroBuffer)!
        XCTAssertEqual(zeroLog.compositeTemperatureKelvin, 0)
        XCTAssertEqual(zeroLog.temperatureCelsius, 0.0)

        // 300 Kelvin -> 26.85 °C -> 80.33 °F
        let k300Buffer = SyntheticSMARTFixtures.makeCustomBuffer(temperatureKelvin: 300)
        let k300Log = NVMESmartLog(data: k300Buffer)!
        XCTAssertEqual(k300Log.compositeTemperatureKelvin, 300)
        XCTAssertEqual(round(k300Log.temperatureCelsius * 100) / 100, 26.85)
        XCTAssertEqual(round(k300Log.temperatureFahrenheit * 100) / 100, 80.33)

        // Multiple sensor filtering
        let customSensors: [UInt16] = [310, 312, 0, 0, 315, 0, 0, 0]
        let sensorBuffer = SyntheticSMARTFixtures.makeCustomBuffer(temperatureSensorsKelvin: customSensors)
        let sensorLog = NVMESmartLog(data: sensorBuffer)!
        let activeSensors = sensorLog.activeTemperatureSensorsCelsius
        XCTAssertEqual(activeSensors.count, 3)
        XCTAssertEqual(round(activeSensors[0] * 100) / 100, 36.85)
        XCTAssertEqual(round(activeSensors[1] * 100) / 100, 38.85)
        XCTAssertEqual(round(activeSensors[2] * 100) / 100, 41.85)
    }

    func testWearPercentageAndHealthScoreClamping() {
        // 0% Wear -> 100% Health
        let b0 = SyntheticSMARTFixtures.makeCustomBuffer(percentageUsed: 0)
        XCTAssertEqual(NVMESmartLog(data: b0)?.healthScorePercent, 100)

        // 45% Wear -> 55% Health
        let b45 = SyntheticSMARTFixtures.makeCustomBuffer(percentageUsed: 45)
        XCTAssertEqual(NVMESmartLog(data: b45)?.healthScorePercent, 55)

        // 100% Wear -> 0% Health
        let b100 = SyntheticSMARTFixtures.makeCustomBuffer(percentageUsed: 100)
        XCTAssertEqual(NVMESmartLog(data: b100)?.healthScorePercent, 0)

        // 120% Wear (Exceeded Rating) -> Clamped to 0% Health without underflow
        let b120 = SyntheticSMARTFixtures.makeCustomBuffer(percentageUsed: 120)
        let log120 = NVMESmartLog(data: b120)!
        XCTAssertEqual(log120.percentageUsed, 120)
        XCTAssertEqual(log120.healthScorePercent, 0)

        // 255% Wear -> Clamped to 0% Health
        let b255 = SyntheticSMARTFixtures.makeCustomBuffer(percentageUsed: 255)
        let log255 = NVMESmartLog(data: b255)!
        XCTAssertEqual(log255.percentageUsed, 255)
        XCTAssertEqual(log255.healthScorePercent, 0)
    }

    func testDataUnitsAndTBWArithmetic() {
        // 1 unit = 512,000 bytes = 0.000512 TB
        let buffer1 = SyntheticSMARTFixtures.makeCustomBuffer(dataUnitsRead: 1, dataUnitsWritten: 2)
        let log1 = NVMESmartLog(data: buffer1)!
        XCTAssertEqual(log1.totalBytesRead, 512_000.0)
        XCTAssertEqual(log1.totalBytesWritten, 1_024_000.0)
        XCTAssertEqual(log1.totalTerabytesRead, 0.000000512)
        XCTAssertEqual(log1.totalTerabytesWritten, 0.000001024)

        // 1,953,125,000 units = 1,000,000,000,000,000 bytes = 1,000 TB = 1 PB
        let pbUnits: UInt64 = 1_953_125_000
        let bufferPB = SyntheticSMARTFixtures.makeCustomBuffer(dataUnitsWritten: pbUnits)
        let logPB = NVMESmartLog(data: bufferPB)!
        XCTAssertEqual(round(logPB.totalTerabytesWritten), 1000.0)
    }

    func testTruncatedBufferRejection() {
        let short256 = SyntheticSMARTFixtures.truncatedBuffer(length: 256)
        XCTAssertNil(NVMESmartLog(data: short256))

        let short511 = SyntheticSMARTFixtures.truncatedBuffer(length: 511)
        XCTAssertNil(NVMESmartLog(data: short511))

        let empty = Data()
        XCTAssertNil(NVMESmartLog(data: empty))
    }

    func testBinarySerializationRoundtrip() {
        let originalBuffer = SyntheticSMARTFixtures.maxValuesRawBuffer()
        guard let originalLog = NVMESmartLog(data: originalBuffer) else {
            XCTFail("Failed to parse max values buffer")
            return
        }

        let serializedData = originalLog.toData()
        XCTAssertEqual(serializedData.count, 512)

        guard let roundtripLog = NVMESmartLog(data: serializedData) else {
            XCTFail("Failed to parse reserialized binary data")
            return
        }

        XCTAssertEqual(roundtripLog, originalLog)
        XCTAssertEqual(roundtripLog.criticalWarning, originalLog.criticalWarning)
        XCTAssertEqual(roundtripLog.compositeTemperatureKelvin, originalLog.compositeTemperatureKelvin)
        XCTAssertEqual(roundtripLog.dataUnitsWritten, originalLog.dataUnitsWritten)
        XCTAssertEqual(roundtripLog.temperatureSensorsKelvin, originalLog.temperatureSensorsKelvin)
    }

    func testCodableSerializationRoundtrip() throws {
        let raw = SyntheticSMARTFixtures.overheatingRawBuffer()
        let originalLog = NVMESmartLog(data: raw)!

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(originalLog)

        let decoder = JSONDecoder()
        let decodedLog = try decoder.decode(NVMESmartLog.self, from: jsonData)
        XCTAssertEqual(decodedLog, originalLog)
    }
}
