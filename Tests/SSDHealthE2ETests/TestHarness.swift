import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

// MARK: - Synthetic NVMe 512-Byte Binary Test Fixtures

/// Authoritative generator of standard 512-byte NVMe SMART / Health Information Log Pages (Log ID 0x02).
/// Conforms to NVM Express Base Specification Revision 1.0c through 2.0.
public enum SyntheticNVMeFixtures {

    /// Constructs a fully customized 512-byte raw binary NVMe SMART log buffer.
    public static func makeBuffer(
        criticalWarning: UInt8 = 0,
        temperatureKelvin: UInt16 = 311, // 37.85°C (38°C)
        availableSparePercent: UInt8 = 100,
        availableSpareThresholdPercent: UInt8 = 10,
        percentageUsed: UInt8 = 0,
        enduranceGroupSummary: UInt8 = 0,
        dataUnitsRead: UInt128Value = UInt128Value(low: 0, high: 0),
        dataUnitsWritten: UInt128Value = UInt128Value(low: 0, high: 0),
        hostReadCommands: UInt128Value = UInt128Value(low: 0, high: 0),
        hostWriteCommands: UInt128Value = UInt128Value(low: 0, high: 0),
        controllerBusyTimeMinutes: UInt128Value = UInt128Value(low: 0, high: 0),
        powerCycles: UInt128Value = UInt128Value(low: 0, high: 0),
        powerOnHours: UInt128Value = UInt128Value(low: 0, high: 0),
        unsafeShutdowns: UInt128Value = UInt128Value(low: 0, high: 0),
        mediaErrors: UInt128Value = UInt128Value(low: 0, high: 0),
        numErrorInfoLogEntries: UInt128Value = UInt128Value(low: 0, high: 0),
        warningCompositeTempTimeMinutes: UInt32 = 0,
        criticalCompositeTempTimeMinutes: UInt32 = 0,
        temperatureSensorsKelvin: [UInt16] = [0, 0, 0, 0, 0, 0, 0, 0],
        thermalManagementTemp1TransitionCount: UInt32 = 0,
        thermalManagementTemp2TransitionCount: UInt32 = 0,
        totalTimeForThermalManagementTemp1Seconds: UInt32 = 0,
        totalTimeForThermalManagementTemp2Seconds: UInt32 = 0
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)

        bytes[0] = criticalWarning

        func writeUInt16(offset: Int, val: UInt16) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<2 { bytes[offset + i] = raw[i] }
            }
        }

        func writeUInt32(offset: Int, val: UInt32) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<4 { bytes[offset + i] = raw[i] }
            }
        }

        func writeUInt64(offset: Int, val: UInt64) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<8 { bytes[offset + i] = raw[i] }
            }
        }

        func writeUInt128(offset: Int, val: UInt128Value) {
            writeUInt64(offset: offset, val: val.low)
            writeUInt64(offset: offset + 8, val: val.high)
        }

        writeUInt16(offset: 1, val: temperatureKelvin)
        bytes[3] = availableSparePercent
        bytes[4] = availableSpareThresholdPercent
        bytes[5] = percentageUsed
        bytes[6] = enduranceGroupSummary

        writeUInt128(offset: 32, val: dataUnitsRead)
        writeUInt128(offset: 48, val: dataUnitsWritten)
        writeUInt128(offset: 64, val: hostReadCommands)
        writeUInt128(offset: 80, val: hostWriteCommands)
        writeUInt128(offset: 96, val: controllerBusyTimeMinutes)
        writeUInt128(offset: 112, val: powerCycles)
        writeUInt128(offset: 128, val: powerOnHours)
        writeUInt128(offset: 144, val: unsafeShutdowns)
        writeUInt128(offset: 160, val: mediaErrors)
        writeUInt128(offset: 176, val: numErrorInfoLogEntries)

        writeUInt32(offset: 192, val: warningCompositeTempTimeMinutes)
        writeUInt32(offset: 196, val: criticalCompositeTempTimeMinutes)

        for i in 0..<min(8, temperatureSensorsKelvin.count) {
            writeUInt16(offset: 200 + i * 2, val: temperatureSensorsKelvin[i])
        }

        writeUInt32(offset: 216, val: thermalManagementTemp1TransitionCount)
        writeUInt32(offset: 220, val: thermalManagementTemp2TransitionCount)
        writeUInt32(offset: 224, val: totalTimeForThermalManagementTemp1Seconds)
        writeUInt32(offset: 228, val: totalTimeForThermalManagementTemp2Seconds)

        return Data(bytes)
    }

    /// Pristine out-of-box SSD: 0% wear, 32°C (305 K), 100% spare, ~0.5 TBW.
    public static func makePristineBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x00,
            temperatureKelvin: 305, // 31.85°C (~32°C)
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: 0,
            dataUnitsRead: UInt128Value(low: 1_200_000), // ~0.614 TB
            dataUnitsWritten: UInt128Value(low: 976_562), // ~0.500 TB
            hostReadCommands: UInt128Value(low: 50_000),
            hostWriteCommands: UInt128Value(low: 40_000),
            controllerBusyTimeMinutes: UInt128Value(low: 15),
            powerCycles: UInt128Value(low: 45),
            powerOnHours: UInt128Value(low: 120),
            unsafeShutdowns: UInt128Value(low: 1),
            mediaErrors: UInt128Value(low: 0),
            numErrorInfoLogEntries: UInt128Value(low: 0),
            temperatureSensorsKelvin: [304, 306, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Developer Workload SSD: 18% wear, 38°C (311 K), 100% spare, ~24.2 TBW.
    public static func makeDeveloperWorkloadBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x00,
            temperatureKelvin: 311, // 37.85°C (~38°C)
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: 18,
            dataUnitsRead: UInt128Value(low: 58_392_100), // ~29.90 TB
            dataUnitsWritten: UInt128Value(low: 47_258_900), // ~24.20 TB
            hostReadCommands: UInt128Value(low: 328_190_442),
            hostWriteCommands: UInt128Value(low: 289_451_090),
            controllerBusyTimeMinutes: UInt128Value(low: 1_420),
            powerCycles: UInt128Value(low: 842),
            powerOnHours: UInt128Value(low: 4_120),
            unsafeShutdowns: UInt128Value(low: 14),
            mediaErrors: UInt128Value(low: 0),
            numErrorInfoLogEntries: UInt128Value(low: 0),
            temperatureSensorsKelvin: [310, 312, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Thermal Spike SSD: 68°C (341 K), Critical Warning Bit 1 (0x02) active.
    public static func makeThermalSpikeBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x02, // Temperature Exceeds Threshold
            temperatureKelvin: 341, // 67.85°C (~68°C)
            availableSparePercent: 98,
            availableSpareThresholdPercent: 10,
            percentageUsed: 18,
            dataUnitsRead: UInt128Value(low: 60_000_000),
            dataUnitsWritten: UInt128Value(low: 48_000_000),
            hostReadCommands: UInt128Value(low: 330_000_000),
            hostWriteCommands: UInt128Value(low: 290_000_000),
            controllerBusyTimeMinutes: UInt128Value(low: 1_450),
            powerCycles: UInt128Value(low: 850),
            powerOnHours: UInt128Value(low: 4_150),
            unsafeShutdowns: UInt128Value(low: 14),
            mediaErrors: UInt128Value(low: 0),
            numErrorInfoLogEntries: UInt128Value(low: 0),
            warningCompositeTempTimeMinutes: 45,
            criticalCompositeTempTimeMinutes: 5,
            temperatureSensorsKelvin: [339, 343, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Near End-of-Life SSD: 96% wear, 6% spare (< 10% thresh), 14 media errors, Critical Bits 0 and 2 set.
    public static func makeNearEOLBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x05, // Available Spare Low (0x01) + Reliability Degraded (0x04)
            temperatureKelvin: 321, // 47.85°C (~48°C)
            availableSparePercent: 6,
            availableSpareThresholdPercent: 10,
            percentageUsed: 96,
            dataUnitsRead: UInt128Value(low: 610_800_000),
            dataUnitsWritten: UInt128Value(low: 495_600_000),
            hostReadCommands: UInt128Value(low: 3_800_000_000),
            hostWriteCommands: UInt128Value(low: 3_200_000_000),
            controllerBusyTimeMinutes: UInt128Value(low: 18_900),
            powerCycles: UInt128Value(low: 3_200),
            powerOnHours: UInt128Value(low: 19_800),
            unsafeShutdowns: UInt128Value(low: 84),
            mediaErrors: UInt128Value(low: 14),
            numErrorInfoLogEntries: UInt128Value(low: 32),
            warningCompositeTempTimeMinutes: 120,
            criticalCompositeTempTimeMinutes: 12,
            temperatureSensorsKelvin: [319, 323, 0, 0, 0, 0, 0, 0]
        )
    }

    /// All zeros buffer: 512 bytes of 0x00.
    public static func makeAllZerosBuffer() -> Data {
        Data(repeating: 0, count: 512)
    }

    /// All ones buffer: 512 bytes of 0xFF.
    public static func makeAllOnesBuffer() -> Data {
        Data(repeating: 0xFF, count: 512)
    }
}

// MARK: - Production Adapters
//
// These used to be independent "reference" re-implementations of the forecast engine, decimation,
// alerting, exporters and formatters, plus duplicate copies of the production model types. The E2E
// suite therefore exercised the copies, not the app: a bug in the shipped code could not fail it.
// The adapters below keep the call shape the tier tests use but delegate to the production code.

/// Delegates to `ForecastEngine`.
public final class ReferenceForecastEngine: Sendable {
    private let engine = ForecastEngine()

    public init() {}

    public func calculateForecast(
        current: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        ratedTBW: Double?,
        referenceDate: Date = Date()
    ) -> SSDForecastResult {
        engine.calculateForecast(current: current, history: history, ratedTBW: ratedTBW, referenceDate: referenceDate)
    }
}

/// Delegates to `Array<SSDHistorySnapshot>.decimated(relativeTo:)`.
public enum ReferenceDecimationEngine {
    public static func decimate(samples: [SSDHistorySnapshot], relativeTo now: Date = Date()) -> [SSDHistorySnapshot] {
        samples.decimated(relativeTo: now)
    }
}

/// Delegates to `NotificationService` with an in-memory cooldown state and no notification center.
public final class ReferenceNotificationEngine: @unchecked Sendable {
    private let service = NotificationService(
        cooldownManager: AlertCooldownManager(userDefaults: nil),
        notificationCenter: nil
    )

    public init() {}

    public func evaluateAlerts(
        metrics: SSDHealthMetrics,
        tempWarnThreshold: Double = 60.0,
        tempCritThreshold: Double = 65.0,
        wearWarnThreshold: Int = 80,
        spareWarnThreshold: Int = 10,
        now: Date = Date()
    ) -> [String] {
        service.evaluateAlerts(
            metrics: metrics,
            tempWarnThreshold: tempWarnThreshold,
            tempCritThreshold: tempCritThreshold,
            wearWarnThreshold: wearWarnThreshold,
            spareWarnThreshold: spareWarnThreshold,
            now: now
        )
    }
}

/// Delegates to `DiagnosticExporter`.
public enum ReferenceDiagnosticExporter {
    public static func exportJSON(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?,
        ratedTBW: Double = 300.0,
        now: Date = Date()
    ) throws -> String {
        try DiagnosticExporter().exportJSON(metrics: metrics, history: history, forecast: forecast, ratedTBW: ratedTBW, now: now)
    }

    public static func exportCSV(history: [SSDHistorySnapshot]) -> String {
        (try? DiagnosticExporter().exportCSV(history: history)) ?? ""
    }

    public static func exportTextReport(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?,
        ratedTBW: Double = 300.0,
        now: Date = Date()
    ) -> String {
        DiagnosticExporter().exportTextReport(metrics: metrics, history: history, forecast: forecast, ratedTBW: ratedTBW, now: now)
    }
}

/// Delegates to `MenuBarStatusView` and `HealthStatus.evaluate`.
public enum ReferenceMenuBarFormatter {
    public static func formatTitle(
        metrics: SSDHealthMetrics?,
        mode: MenuBarDisplayMode,
        unit: TemperatureUnit = .celsius
    ) -> String {
        // XCTest runs synchronous tests on the main thread
        MainActor.assumeIsolated {
            MenuBarStatusView(metrics: metrics, mode: mode, unit: unit).title
        }
    }

    public static func resolveStatus(metrics: SSDHealthMetrics?) -> HealthStatus {
        HealthStatus.evaluate(metrics: metrics)
    }
}

/// Delegates to `SMARTTableView.buildRows(from:)` with default settings.
public enum ReferenceSMARTTableFormatter {
    public static func buildTableRows(from log: NVMESmartLog) -> [SMARTParameterRow] {
        MainActor.assumeIsolated {
            let defaults = UserDefaults(suiteName: "SSDHealthE2E-\(UUID().uuidString)")!
            let state = AppState(storageReader: MockSSDStorageReader(), settings: AppSettings(userDefaults: defaults))
            return SMARTTableView(appState: state).buildRows(from: log)
        }
    }
}

// MARK: - Assertion & Verification Helpers

public func assertDoubleEqual(_ actual: Double, _ expected: Double, accuracy: Double = 1e-4, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(actual, expected, accuracy: accuracy, "Expected \(expected), got \(actual) (diff: \(abs(actual - expected)))", file: file, line: line)
}

public func assertDateClose(_ actual: Date?, _ expected: Date?, toleranceSeconds: TimeInterval = 2.0, file: StaticString = #file, line: UInt = #line) {
    guard let a = actual, let e = expected else {
        XCTAssertEqual(actual, expected, "One or both dates are nil", file: file, line: line)
        return
    }
    let diff = abs(a.timeIntervalSince(e))
    XCTAssertLessThanOrEqual(diff, toleranceSeconds, "Date \(a) differs from \(e) by \(diff) seconds (tolerance: \(toleranceSeconds)s)", file: file, line: line)
}

public func assertCSVValid(_ csvString: String, expectedRowCount: Int? = nil, file: StaticString = #file, line: UInt = #line) {
    let lines = csvString.components(separatedBy: "\r\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    XCTAssertGreaterThanOrEqual(lines.count, 1, "CSV must contain at least a header row", file: file, line: line)

    let headerCols = lines[0].components(separatedBy: ",")
    XCTAssertGreaterThanOrEqual(headerCols.count, 5, "Header must have at least 5 columns", file: file, line: line)

    if let expRows = expectedRowCount {
        XCTAssertEqual(lines.count - 1, expRows, "Expected \(expRows) data rows in CSV, got \(lines.count - 1)", file: file, line: line)
    }

    for (idx, lineStr) in lines.enumerated() {
        let cols = lineStr.components(separatedBy: ",")
        XCTAssertEqual(cols.count, headerCols.count, "Row \(idx) column count \(cols.count) mismatch with header \(headerCols.count)", file: file, line: line)
    }
}

public func assertJSONValid(_ jsonString: String, requiredTopLevelKeys: [String] = [], file: StaticString = #file, line: UInt = #line) {
    guard let data = jsonString.data(using: .utf8) else {
        XCTFail("Failed to convert JSON string to Data", file: file, line: line)
        return
    }

    do {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Root JSON is not a dictionary", file: file, line: line)
            return
        }

        for key in requiredTopLevelKeys {
            XCTAssertNotNil(dict[key], "Required JSON key '\(key)' missing in root object", file: file, line: line)
        }
    } catch {
        XCTFail("JSON parsing failed with error: \(error)", file: file, line: line)
    }
}
