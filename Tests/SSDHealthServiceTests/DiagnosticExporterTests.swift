import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService

final class DiagnosticExporterTests: XCTestCase {

    var exporter: DiagnosticExporter!
    var sampleMetrics: SSDHealthMetrics!
    var sampleForecast: SSDForecastResult!
    var sampleHistory: [SSDHistorySnapshot]!
    var baseDate: Date = Date(timeIntervalSince1970: 1787832000)

    override func setUp() {
        super.setUp()
        exporter = DiagnosticExporter()
        baseDate = Date(timeIntervalSince1970: 1787832000)

        sampleMetrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0256Q",
            serialNumber: "0ba018e2018c480f",
            firmwareRevision: "561.100.",
            interconnect: "Apple Fabric",
            capacityBytes: 251_000_193_024,
            healthScorePercent: 82,
            wearPercentage: 18,
            temperatureCelsius: 38.0,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 24.196,
            terabytesRead: 29.896,
            powerOnHours: 4120,
            powerCycles: 842,
            unsafeShutdowns: 14,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: baseDate
        )

        sampleForecast = SSDForecastResult(
            dailyWriteRate7dGB: 14.82,
            dailyWriteRate30dGB: 16.45,
            dailyWriteRateLifetimeGB: 14.09,
            primaryDailyWriteRateGB: 16.45,
            estimatedDaysRemaining: 7646.0,
            estimatedYearsRemaining: 20.93,
            estimatedExhaustionDate: baseDate.addingTimeInterval(7646.0 * 86_400.0),
            degradationStatus: .stable,
            confidenceInterval95: (lowerGB: 13.20, upperGB: 16.44)
        )

        sampleHistory = [
            SSDHistorySnapshot(
                timestamp: baseDate.addingTimeInterval(-86_400.0 * 2),
                healthScorePercent: 82,
                wearPercentage: 18,
                temperatureCelsius: 37.0,
                terabytesWritten: 24.092,
                availableSparePercent: 100
            ),
            SSDHistorySnapshot(
                timestamp: baseDate.addingTimeInterval(-86_400.0),
                healthScorePercent: 82,
                wearPercentage: 18,
                temperatureCelsius: 38.0,
                terabytesWritten: 24.126,
                availableSparePercent: 100
            ),
            SSDHistorySnapshot(
                timestamp: baseDate,
                healthScorePercent: 82,
                wearPercentage: 18,
                temperatureCelsius: 38.0,
                terabytesWritten: 24.196,
                availableSparePercent: 100
            )
        ]
    }

    override func tearDown() {
        exporter = nil
        sampleMetrics = nil
        sampleForecast = nil
        sampleHistory = nil
        super.tearDown()
    }

    // MARK: - JSON Export Validation

    func test_ExportJSON_ProducesValidSchemaAndAllTopLevelKeys() throws {
        let jsonString = try exporter.exportJSON(
            metrics: sampleMetrics,
            history: sampleHistory,
            forecast: sampleForecast,
            ratedTBW: 150.0,
            now: baseDate
        )

        guard let data = jsonString.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to deserialize exported JSON")
            return
        }

        // Validate top-level keys
        XCTAssertNotNil(root["metadata"])
        XCTAssertNotNil(root["drive"])
        XCTAssertNotNil(root["currentMetrics"])
        XCTAssertNotNil(root["forecast"])
        XCTAssertNotNil(root["history"])
        XCTAssertEqual(root["historySampleCount"] as? Int, 3)

        // Validate drive subsection
        let drive = root["drive"] as? [String: Any]
        XCTAssertEqual(drive?["productName"] as? String, "APPLE SSD AP0256Q")
        XCTAssertEqual(drive?["ratedTBW"] as? Double, 150.0)

        // Validate metrics subsection
        let metrics = root["currentMetrics"] as? [String: Any]
        XCTAssertEqual(metrics?["healthScore"] as? Int, 82)
        XCTAssertEqual(metrics?["percentageUsed"] as? Int, 18)

        // Validate forecast subsection
        let forecast = root["forecast"] as? [String: Any]
        XCTAssertEqual(forecast?["degradationStatus"] as? String, "stable")
        XCTAssertEqual(forecast?["dailyWriteRate30dGB"] as? Double, 16.45)
    }

    func test_ExportJSON_WithNilForecastAndEmptyHistory() throws {
        let jsonString = try exporter.exportJSON(
            metrics: sampleMetrics,
            history: [],
            forecast: nil,
            ratedTBW: 150.0,
            now: baseDate
        )

        guard let data = jsonString.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to deserialize exported JSON")
            return
        }

        XCTAssertNil(root["forecast"])
        XCTAssertEqual(root["historySampleCount"] as? Int, 0)
        let history = root["history"] as? [[String: Any]]
        XCTAssertTrue(history?.isEmpty == true)
    }

    // MARK: - CSV Export RFC 4180 Validation

    func test_ExportCSV_RFC4180Conformance_CRLFAndColumns() throws {
        let csv = try exporter.exportCSV(history: sampleHistory)

        // RFC 4180 requires CRLF (\r\n) line endings
        XCTAssertTrue(csv.contains("\r\n"))
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Header + 3 data rows = 4 lines
        XCTAssertEqual(lines.count, 4)

        let headerCols = lines[0].components(separatedBy: ",")
        XCTAssertEqual(headerCols.count, 9)
        XCTAssertEqual(headerCols[0], "Timestamp_ISO8601")
        XCTAssertEqual(headerCols[1], "Timestamp_Unix")
        XCTAssertEqual(headerCols[2], "Percentage_Used")
        XCTAssertEqual(headerCols[3], "Health_Score_Pct")

        for i in 1...3 {
            let rowCols = lines[i].components(separatedBy: ",")
            XCTAssertEqual(rowCols.count, 9, "Row \(i) must have 9 columns")
            XCTAssertFalse(rowCols[0].isEmpty)
            XCTAssertNotNil(Int(rowCols[1])) // Timestamp_Unix is integer
            XCTAssertNotNil(Int(rowCols[2])) // Percentage_Used is integer
            XCTAssertNotNil(Double(rowCols[5])) // TBW_Decimal is double
        }
    }

    func test_ExportCSV_EmptyHistory_ReturnsHeaderOnly() throws {
        let csv = try exporter.exportCSV(history: [])
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].starts(with: "Timestamp_ISO8601"))
    }

    // MARK: - ASCII Text Report Formatting

    func test_ExportTextReport_StructureAndContent() {
        let report = exporter.exportTextReport(
            metrics: sampleMetrics,
            history: sampleHistory,
            forecast: sampleForecast,
            ratedTBW: 150.0,
            now: baseDate
        )

        // Check essential report sections
        XCTAssertTrue(report.contains("macOS SSD HEALTH & SMART DIAGNOSTIC REPORT"))
        XCTAssertTrue(report.contains("1. STORAGE DEVICE IDENTIFICATION"))
        XCTAssertTrue(report.contains("APPLE SSD AP0256Q"))
        XCTAssertTrue(report.contains("150.0 TBW"))

        XCTAssertTrue(report.contains("2. HEALTH & LIFESPAN SUMMARY"))
        XCTAssertTrue(report.contains("Overall Health Score:     82%"))
        XCTAssertTrue(report.contains("Percentage Used:          18%"))
        XCTAssertTrue(report.contains("Total Bytes Written:      24.20 TBW"))

        XCTAssertTrue(report.contains("3. FORECAST & WEAR PROJECTION"))
        XCTAssertTrue(report.contains("Daily Write Rate (7d):    14.82 GB/day"))
        XCTAssertTrue(report.contains("Daily Write Rate (30d):   16.45 GB/day"))
        XCTAssertTrue(report.contains("Degradation Trajectory:   STABLE"))

        XCTAssertTrue(report.contains("4. HARDWARE RELIABILITY FLAGS & WARNINGS"))
        XCTAssertTrue(report.contains("[x] Available Spare (100% >= 10% threshold)"))
        XCTAssertTrue(report.contains("[x] Thermal Status (38.0 °C < 65.0 °C threshold)"))
        XCTAssertTrue(report.contains("[x] Zero Media Errors"))
    }

    func test_ExportTextReport_WithNilForecast_ShowsFallback() {
        let report = exporter.exportTextReport(
            metrics: sampleMetrics,
            history: [],
            forecast: nil,
            ratedTBW: 150.0,
            now: baseDate
        )

        XCTAssertTrue(report.contains("Prognosis:                Insufficient historical data"))
    }
}
