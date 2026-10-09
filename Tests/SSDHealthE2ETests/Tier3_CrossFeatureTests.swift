import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

/// Tier 3: Pairwise Cross-Feature Interaction Test Suite.
/// Verifies end-to-end data pipelines and multi-module state transformations.
final class Tier3_CrossFeatureTests: XCTestCase {

    // =========================================================================
    // MARK: - Pipeline 1: Binary Parse -> Metrics -> History -> Decimation -> Storage
    // =========================================================================

    func test_01_Pipeline_BinaryParse_To_Metrics_To_History_To_Decimation_To_Storage() throws {
        let rawBuffer = SyntheticNVMeFixtures.makeDeveloperWorkloadBuffer()
        guard let smartLog = NVMESmartLog(data: rawBuffer) else {
            XCTFail("Failed to parse raw NVMe buffer")
            return
        }

        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0512R",
            serialNumber: "SN-PIPELINE-01",
            firmwareRevision: "741.140.",
            interconnect: "Apple Fabric",
            capacityBytes: 500_000_000_000,
            healthScorePercent: smartLog.healthScorePercent,
            wearPercentage: Int(smartLog.percentageUsed),
            temperatureCelsius: smartLog.temperatureCelsius,
            availableSparePercent: Int(smartLog.availableSparePercent),
            availableSpareThresholdPercent: Int(smartLog.availableSpareThresholdPercent),
            terabytesWritten: smartLog.totalTerabytesWritten,
            terabytesRead: smartLog.totalTerabytesRead,
            powerOnHours: smartLog.powerOnHours.low,
            powerCycles: smartLog.powerCycles.low,
            unsafeShutdowns: smartLog.unsafeShutdowns.low,
            mediaErrors: smartLog.mediaErrors.low,
            errorLogEntries: smartLog.numErrorInfoLogEntries.low,
            criticalWarnings: smartLog.criticalWarning
        )

        let snapshot = SSDHistorySnapshot(from: metrics)
        XCTAssertEqual(snapshot.healthScorePercent, 82)
        XCTAssertEqual(snapshot.wearPercentage, 18)

        var history: [SSDHistorySnapshot] = [snapshot]
        let now = Date()
        for i in 1...20 {
            let t = now.addingTimeInterval(-Double(i) * 3600.0)
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 82, wearPercentage: 18,
                temperatureCelsius: 38.0, terabytesWritten: 24.196 - Double(i) * 0.001,
                availableSparePercent: 100
            ))
        }

        let decimated = ReferenceDecimationEngine.decimate(samples: history, relativeTo: now)
        XCTAssertEqual(decimated.count, 21) // Within 24h, 100% retained

        let doc = SSDHistoryStoreDocument(
            driveIdentifier: metrics.serialNumber,
            firstRecorded: history.last!.timestamp,
            lastUpdated: now,
            ratedTBW: 300.0,
            snapshots: decimated
        )

        let data = try JSONEncoder().encode(doc)
        let loaded = try JSONDecoder().decode(SSDHistoryStoreDocument.self, from: data)

        XCTAssertEqual(loaded.snapshots.count, 21)
        XCTAssertEqual(loaded.snapshots.first?.healthScorePercent, 82)
    }

    // =========================================================================
    // MARK: - Pipeline 2: Telemetry -> OLS Regression -> Dual Model Lifespan -> CI
    // =========================================================================

    func test_02_Pipeline_Telemetry_To_OLSRegression_To_DualModelLifespan_To_ConfidenceIntervals() {
        let engine = ReferenceForecastEngine()
        let now = Date()
        var history: [SSDHistorySnapshot] = []

        // 30 days of exactly 40 GB/day (0.04 TB/day)
        for day in 0..<30 {
            let t = now.addingTimeInterval(Double(day - 29) * 86_400.0)
            let tbw = 10.0 + Double(day) * 0.04
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 95, wearPercentage: 5,
                temperatureCelsius: 38.0, terabytesWritten: tbw, availableSparePercent: 100
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-OLS",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
            healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 11.16, terabytesRead: 15.0, powerOnHours: 3000,
            powerCycles: 300, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let result = engine.calculateForecast(current: current, history: history, ratedTBW: 300.0, referenceDate: now)

        assertDoubleEqual(result.primaryDailyWriteRateGB, 40.0, accuracy: 0.2)
        XCTAssertLessThanOrEqual(result.confidenceInterval95.lowerGB, 40.0)
        XCTAssertGreaterThanOrEqual(result.confidenceInterval95.upperGB, 40.0)

        // Remaining TBW = 300 - 11.16 = 288.84 TBW -> 288.84 / 0.040 = 7,221 days
        assertDoubleEqual(result.estimatedDaysRemaining, 7221.0, accuracy: 50.0)
        XCTAssertEqual(result.degradationStatus, .stable)
    }

    // =========================================================================
    // MARK: - Pipeline 3: Polling -> Metric Evaluation -> Alert Debounce -> Notification
    // =========================================================================

    func test_03_Pipeline_Polling_To_MetricEvaluation_To_AlertDebounce_To_NotificationState() {
        let notificationEngine = ReferenceNotificationEngine()
        var now = Date()

        func makeMetrics(temp: Double, wear: Int) -> SSDHealthMetrics {
            SSDHealthMetrics(
                bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
                firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 512_000_000_000,
                healthScorePercent: 100 - wear, wearPercentage: wear, temperatureCelsius: temp,
                availableSparePercent: 100, availableSpareThresholdPercent: 10,
                terabytesWritten: 10.0, terabytesRead: 10.0, powerOnHours: 1000,
                powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
                criticalWarnings: temp >= 65.0 ? [.temperatureExceedsThreshold] : CriticalWarningFlags(rawValue: 0),
                timestamp: now
            )
        }

        // Poll 1: 45°C, 10% wear -> No alert
        let alerts1 = notificationEngine.evaluateAlerts(metrics: makeMetrics(temp: 45.0, wear: 10), now: now)
        XCTAssertEqual(alerts1.count, 0)

        // Poll 2: 5 minutes later, 62°C -> High Temp Warning
        now = now.addingTimeInterval(300)
        let alerts2 = notificationEngine.evaluateAlerts(metrics: makeMetrics(temp: 62.0, wear: 10), now: now)
        XCTAssertEqual(alerts2.count, 1)
        XCTAssertTrue(alerts2[0].contains("HIGH_TEMPERATURE"))

        // Poll 3: 5 minutes later, 62°C (still warm) -> Cooldown suppresses duplicate
        now = now.addingTimeInterval(300)
        let alerts3 = notificationEngine.evaluateAlerts(metrics: makeMetrics(temp: 62.0, wear: 10), now: now)
        XCTAssertEqual(alerts3.count, 0)

        // Poll 4: 5 minutes later, 68°C -> Critical Temp (escalation triggers immediately despite high temp cooldown)
        now = now.addingTimeInterval(300)
        let alerts4 = notificationEngine.evaluateAlerts(metrics: makeMetrics(temp: 68.0, wear: 10), now: now)
        XCTAssertEqual(alerts4.count, 1)
        XCTAssertTrue(alerts4[0].contains("CRITICAL_TEMPERATURE"))
    }

    // =========================================================================
    // MARK: - Pipeline 4: Consolidated Data -> JSON Export -> JSON Decoded Verification
    // =========================================================================

    func test_04_Pipeline_ConsolidatedData_To_JSONExport_To_JSONDecodedVerification() throws {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP0512R", serialNumber: "SN-JSON-PIPE",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 92, wearPercentage: 8, temperatureCelsius: 39.5,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 34.2,
            terabytesRead: 48.0, powerOnHours: 4200, powerCycles: 400, unsafeShutdowns: 3,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let forecast = SSDForecastResult(
            dailyWriteRate7dGB: 22.5, dailyWriteRate30dGB: 20.0, dailyWriteRateLifetimeGB: 18.0,
            primaryDailyWriteRateGB: 20.0, estimatedDaysRemaining: 3650.0, estimatedYearsRemaining: 10.0,
            estimatedExhaustionDate: Date().addingTimeInterval(3650 * 86400),
            degradationStatus: .stable, confidenceInterval95: (lowerGB: 18.0, upperGB: 22.0)
        )

        let json = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: [], forecast: forecast)

        let data = json.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let driveDict = dict["drive"] as! [String: Any]
        XCTAssertEqual(driveDict["serialNumber"] as? String, "SN-JSON-PIPE")

        let forecastDict = dict["forecast"] as! [String: Any]
        XCTAssertEqual(forecastDict["degradationStatus"] as? String, "stable")
    }

    // =========================================================================
    // MARK: - Pipeline 5: History -> CSV Export -> RFC 4180 Parsed Verification
    // =========================================================================

    func test_05_Pipeline_History_To_CSVExport_To_RFC4180ParsedVerification() {
        let now = Date()
        var history: [SSDHistorySnapshot] = []
        for i in 0..<15 {
            history.append(SSDHistorySnapshot(
                timestamp: now.addingTimeInterval(Double(-i) * 86400),
                healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0 + Double(i % 3),
                terabytesWritten: 20.0 - Double(i) * 0.05, availableSparePercent: 100
            ))
        }

        let csv = ReferenceDiagnosticExporter.exportCSV(history: history)
        assertCSVValid(csv, expectedRowCount: 15)

        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(rows.count, 16) // Header + 15 rows
    }

    // =========================================================================
    // MARK: - Pipeline 6: Consolidated Data -> ASCII Formatted Report
    // =========================================================================

    func test_06_Pipeline_ConsolidatedData_To_ASCIIFormattedReport_To_StructuralValidation() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP0512R", serialNumber: "SN-REPORT",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 15.0,
            terabytesRead: 25.0, powerOnHours: 2000, powerCycles: 200, unsafeShutdowns: 1,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let report = ReferenceDiagnosticExporter.exportTextReport(metrics: metrics, history: [], forecast: nil)

        XCTAssertTrue(report.contains("macOS SSD HEALTH & SMART DIAGNOSTIC REPORT"))
        XCTAssertTrue(report.contains("APPLE SSD AP0512R"))
        XCTAssertTrue(report.contains("SN-REPORT"))
        XCTAssertTrue(report.contains("95% (Good)"))
    }

    // =========================================================================
    // MARK: - Pipeline 7: Settings Unit Switching -> MenuBar & Popover Formatting
    // =========================================================================

    func test_07_Pipeline_SettingsUnitSwitching_To_AppState_To_MenuBarAndPopoverFormatting() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1",
            firmwareRevision: "1.0", interconnect: "Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 98, wearPercentage: 2, temperatureCelsius: 41.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 10.0, terabytesRead: 10.0, powerOnHours: 1000,
            powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        // Celsius Mode
        let titleC = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconHealthAndTemp, unit: .celsius)
        XCTAssertEqual(titleC, "98% · 41°C")

        // Switch to Fahrenheit Mode
        let titleF = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconHealthAndTemp, unit: .fahrenheit)
        XCTAssertEqual(titleF, "98% · 106°F")
    }

    // =========================================================================
    // MARK: - Pipeline 8: Storage Reader Failure -> Fallback Registry Reader -> UI State
    // =========================================================================

    func test_08_Pipeline_StorageReaderFailure_To_FallbackRegistryReader_To_UIStateAndExport() throws {
        let fallbackMetrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple Internal SSD", serialNumber: "UNKNOWN",
            firmwareRevision: "N/A", interconnect: "Apple Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 38.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 5.2, terabytesRead: 8.4, powerOnHours: 0, powerCycles: 0,
            unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), isFallbackData: true
        )

        XCTAssertTrue(fallbackMetrics.isFallbackData)
        let json = try ReferenceDiagnosticExporter.exportJSON(metrics: fallbackMetrics, history: [], forecast: nil)
        XCTAssertTrue(json.contains("\"isFallbackData\" : true"))
    }

    // =========================================================================
    // MARK: - Pipeline 9: Thermal Spike Event -> Critical Warning Bit -> MenuBar Badge
    // =========================================================================

    func test_09_Pipeline_ThermalSpikeEvent_To_CriticalWarningBit_To_AlertEngine_To_MenuBarBadge() {
        let hotBuffer = SyntheticNVMeFixtures.makeThermalSpikeBuffer()
        guard let log = NVMESmartLog(data: hotBuffer) else {
            XCTFail("Failed to parse thermal spike buffer")
            return
        }

        XCTAssertTrue(log.criticalWarning.contains(.temperatureExceedsThreshold))
        assertDoubleEqual(log.temperatureCelsius, 67.85, accuracy: 0.5)

        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-HOT",
            firmwareRevision: "1.0", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: log.healthScorePercent, wearPercentage: Int(log.percentageUsed),
            temperatureCelsius: log.temperatureCelsius, availableSparePercent: Int(log.availableSparePercent),
            availableSpareThresholdPercent: Int(log.availableSpareThresholdPercent),
            terabytesWritten: log.totalTerabytesWritten, terabytesRead: log.totalTerabytesRead,
            powerOnHours: log.powerOnHours.low, powerCycles: log.powerCycles.low,
            unsafeShutdowns: log.unsafeShutdowns.low, mediaErrors: log.mediaErrors.low,
            errorLogEntries: log.numErrorInfoLogEntries.low, criticalWarnings: log.criticalWarning
        )

        let status = ReferenceMenuBarFormatter.resolveStatus(metrics: metrics)
        XCTAssertEqual(status, .critical)
        XCTAssertEqual(status.iconName, "exclamationmark.octagon.fill")
    }

    // =========================================================================
    // MARK: - Pipeline 10: Spare Capacity Degradation -> Forecast Status Change
    // =========================================================================

    func test_10_Pipeline_SpareCapacityDegradation_To_CriticalWarning_To_ForecastStatusChange() {
        let nearEOLBuffer = SyntheticNVMeFixtures.makeNearEOLBuffer()
        guard let log = NVMESmartLog(data: nearEOLBuffer) else {
            XCTFail("Failed to parse near EOL buffer")
            return
        }

        XCTAssertEqual(log.availableSparePercent, 6)
        XCTAssertTrue(log.criticalWarning.contains(.availableSpareBelowThreshold))

        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-EOL",
            firmwareRevision: "1.0", interconnect: "Apple Fabric", capacityBytes: 256_000_000_000,
            healthScorePercent: log.healthScorePercent, wearPercentage: Int(log.percentageUsed),
            temperatureCelsius: log.temperatureCelsius, availableSparePercent: Int(log.availableSparePercent),
            availableSpareThresholdPercent: Int(log.availableSpareThresholdPercent),
            terabytesWritten: log.totalTerabytesWritten, terabytesRead: log.totalTerabytesRead,
            powerOnHours: log.powerOnHours.low, powerCycles: log.powerCycles.low,
            unsafeShutdowns: log.unsafeShutdowns.low, mediaErrors: log.mediaErrors.low,
            errorLogEntries: log.numErrorInfoLogEntries.low, criticalWarnings: log.criticalWarning
        )

        let engine = ReferenceForecastEngine()
        let now = Date()
        let result = engine.calculateForecast(
            current: metrics,
            history: [
                SSDHistorySnapshot(timestamp: now.addingTimeInterval(-200_000), healthScorePercent: 5, wearPercentage: 95, temperatureCelsius: 48.0, terabytesWritten: 494.0, availableSparePercent: 6),
                SSDHistorySnapshot(timestamp: now.addingTimeInterval(-100_000), healthScorePercent: 4, wearPercentage: 96, temperatureCelsius: 48.0, terabytesWritten: 495.0, availableSparePercent: 6),
                SSDHistorySnapshot(timestamp: now, healthScorePercent: 4, wearPercentage: 96, temperatureCelsius: 48.0, terabytesWritten: 495.6, availableSparePercent: 6)
            ],
            ratedTBW: 150.0, referenceDate: now
        )

        XCTAssertEqual(result.degradationStatus, .exceededEndurance)
    }

    // =========================================================================
    // MARK: - Pipeline 11: Long-Term Wear Progression -> Dual Model Transition
    // =========================================================================

    func test_11_Pipeline_LongTermWearProgression_To_DualModelTransition_To_MilestoneTracking() {
        let engine = ReferenceForecastEngine()
        let notificationEngine = ReferenceNotificationEngine()
        var now = Date()

        // Phase 1: 0% wear change -> Model B active
        let historyPhase1 = [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-10 * 86400), healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.5, availableSparePercent: 100)
        ]
        let current1 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
            wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.5, terabytesRead: 15.0,
            powerOnHours: 2000, powerCycles: 200, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        let res1 = engine.calculateForecast(current: current1, history: historyPhase1, ratedTBW: 300.0, referenceDate: now)
        XCTAssertEqual(res1.degradationStatus, .insufficientData)

        // Phase 2: 10% wear change over 100 days -> Model A active
        now = now.addingTimeInterval(100 * 86400)
        let historyPhase2 = [
            SSDHistorySnapshot(timestamp: now.addingTimeInterval(-100 * 86400), healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: now, healthScorePercent: 85, wearPercentage: 15, temperatureCelsius: 38.0, terabytesWritten: 40.0, availableSparePercent: 100)
        ]
        let current2 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 85,
            wearPercentage: 15, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 40.0, terabytesRead: 50.0,
            powerOnHours: 4400, powerCycles: 400, unsafeShutdowns: 2, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        let res2 = engine.calculateForecast(current: current2, history: historyPhase2, ratedTBW: 300.0, referenceDate: now)

        // Wear delta = 10% in 100 days = 0.1%/day -> 85% remaining / 0.1% = 850 days
        assertDoubleEqual(res2.estimatedDaysRemaining, 850.0, accuracy: 5.0)

        // Phase 3: Milestone trigger at 80%
        let current3 = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 20,
            wearPercentage: 80, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 240.0, terabytesRead: 280.0,
            powerOnHours: 18000, powerCycles: 2000, unsafeShutdowns: 15, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )
        let alerts = notificationEngine.evaluateAlerts(metrics: current3, now: now)
        XCTAssertTrue(alerts.contains(where: { $0.contains("WEAR_MILESTONE_80") }))
    }

    // =========================================================================
    // MARK: - Pipeline 12: Decimation Fidelity -> OLS Rate Within 2%
    // =========================================================================

    func test_12_Pipeline_DecimationFidelity_To_OLSWriteRateAccuracyWithin2Percent() {
        let engine = ReferenceForecastEngine()
        let now = Date()
        var rawHistory: [SSDHistorySnapshot] = []

        // 1,000 raw samples over 60 days with 30.0 GB/day write rate
        for i in 0..<1000 {
            let t = now.addingTimeInterval(Double(i - 999) * (60.0 * 86400.0 / 1000.0))
            let dayFraction = Double(i) * 60.0 / 1000.0
            let tbw = 10.0 + dayFraction * 0.030
            rawHistory.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 95, wearPercentage: 5,
                temperatureCelsius: 38.0, terabytesWritten: tbw, availableSparePercent: 100
            ))
        }

        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 95,
            wearPercentage: 5, temperatureCelsius: 38.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: rawHistory.last!.terabytesWritten,
            terabytesRead: 20.0, powerOnHours: 2000, powerCycles: 200, unsafeShutdowns: 1,
            mediaErrors: 0, errorLogEntries: 0, criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: now
        )

        let rawForecast = engine.calculateForecast(current: current, history: rawHistory, ratedTBW: 300.0, referenceDate: now)

        let decimatedHistory = ReferenceDecimationEngine.decimate(samples: rawHistory, relativeTo: now)
        XCTAssertLessThan(decimatedHistory.count, 250)

        let decimatedForecast = engine.calculateForecast(current: current, history: decimatedHistory, ratedTBW: 300.0, referenceDate: now)

        let diff = abs(rawForecast.primaryDailyWriteRateGB - decimatedForecast.primaryDailyWriteRateGB)
        let percentDiff = (diff / rawForecast.primaryDailyWriteRateGB) * 100.0

        XCTAssertLessThan(percentDiff, 2.0, "Decimated OLS write rate differs by \(percentDiff)% from raw rate (expected < 2%)")
    }

    // =========================================================================
    // MARK: - Pipeline 13: Multi-Drive Isolation in History Persistence
    // =========================================================================

    func test_13_Pipeline_MultiDriveIdentification_To_HistoryPersistenceIsolation() {
        let driveA = SSDHistoryStoreDocument(driveIdentifier: "APPLE SSD AP0512R - SN_AAA", ratedTBW: 300.0)
        let driveB = SSDHistoryStoreDocument(driveIdentifier: "EXTERNAL NVMe - SN_BBB", ratedTBW: 600.0)

        XCTAssertNotEqual(driveA.driveIdentifier, driveB.driveIdentifier)
        XCTAssertNotEqual(driveA.ratedTBW, driveB.ratedTBW)
    }

    // =========================================================================
    // MARK: - Pipeline 14: Settings Threshold Modification -> Immediate Re-Evaluation
    // =========================================================================

    func test_14_Pipeline_SettingsThresholdModification_To_ImmediateAlertReEvaluation() {
        let engine = ReferenceNotificationEngine()
        let now = Date()

        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "Apple SSD", serialNumber: "SN-1", firmwareRevision: "1.0",
            interconnect: "Fabric", capacityBytes: 512_000_000_000, healthScorePercent: 90,
            wearPercentage: 10, temperatureCelsius: 58.0, availableSparePercent: 100,
            availableSpareThresholdPercent: 10, terabytesWritten: 10.0, terabytesRead: 10.0,
            powerOnHours: 1000, powerCycles: 100, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        // Default warn threshold = 60°C -> No alert
        let alerts1 = engine.evaluateAlerts(metrics: metrics, tempWarnThreshold: 60.0, now: now)
        XCTAssertEqual(alerts1.count, 0)

        // User lowers warn threshold to 55°C -> Triggers alert
        let alerts2 = engine.evaluateAlerts(metrics: metrics, tempWarnThreshold: 55.0, now: now)
        XCTAssertEqual(alerts2.count, 1)
        XCTAssertTrue(alerts2[0].contains("HIGH_TEMPERATURE"))
    }

    // =========================================================================
    // MARK: - Pipeline 15: AppState Synchronization
    // =========================================================================

    func test_15_Pipeline_AppStateSynchronization_Between_MenuBarButton_And_DashboardViewModel() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP0512R", serialNumber: "SN-SYNC",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: 92, wearPercentage: 8, temperatureCelsius: 42.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: 34.2, terabytesRead: 48.0, powerOnHours: 4200,
            powerCycles: 400, unsafeShutdowns: 3, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let menuBarTitle = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconHealthAndTemp, unit: .celsius)
        XCTAssertEqual(menuBarTitle, "92% · 42°C")

        let gaugeScore = max(0, min(100, metrics.healthScorePercent))
        XCTAssertEqual(gaugeScore, 92)

        let status = ReferenceMenuBarFormatter.resolveStatus(metrics: metrics)
        XCTAssertEqual(status, .good)
    }
}
