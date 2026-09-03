import Foundation
import XCTest
@testable import SSDHealthCore

/// Tier 4: Real-World Scenario Simulation Test Suite.
/// End-to-end multi-step workflow verification across realistic user conditions.
final class Tier4_RealWorldScenarioTests: XCTestCase {

    // =========================================================================
    // MARK: - Scenario 1: Fresh Drive Out-of-Box Lifecycle
    // =========================================================================

    func test_Scenario1_PristineDriveLifecycle() throws {
        // Step 1: Initialize pristine hardware buffer & reader
        let pristineData = SyntheticNVMeFixtures.makePristineBuffer()
        guard let smartLog = NVMESmartLog(data: pristineData) else {
            XCTFail("Failed to decode pristine NVMe SMART buffer")
            return
        }

        XCTAssertTrue(smartLog.criticalWarning.isClean)
        XCTAssertEqual(smartLog.percentageUsed, 0)
        XCTAssertEqual(smartLog.healthScorePercent, 100)
        XCTAssertEqual(smartLog.availableSparePercent, 100)
        assertDoubleEqual(smartLog.totalTerabytesWritten, 0.500, accuracy: 0.01)

        // Step 2: Construct SSDHealthMetrics
        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0512R",
            serialNumber: "PRISTINE-MOCK-001",
            firmwareRevision: "741.140.",
            interconnect: "Apple Fabric",
            capacityBytes: 500_107_862_016,
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

        XCTAssertTrue(metrics.isHealthy)
        XCTAssertEqual(metrics.healthScoreFormatted, "100%")
        XCTAssertEqual(metrics.wearFormatted, "0%")

        // Step 3: Record initial history snapshot
        let snapshot = SSDHistorySnapshot(from: metrics)
        let history = [snapshot]

        // Step 4: Run forecasting engine on new drive
        let forecastEngine = ReferenceForecastEngine()
        let now = Date()
        let forecast = forecastEngine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: now)

        // New drive with < 24h history reports insufficientData and uses lifetime rate
        XCTAssertEqual(forecast.degradationStatus, .insufficientData)
        XCTAssertFalse(forecast.primaryDailyWriteRateGB.isNaN)

        // Step 5: Check Menu Bar and Popover status
        let status = ReferenceMenuBarFormatter.resolveStatus(metrics: metrics)
        XCTAssertEqual(status, .good)
        XCTAssertEqual(status.iconName, "internaldrive")

        let menuBarTitle = ReferenceMenuBarFormatter.formatTitle(metrics: metrics, mode: .iconAndHealth)
        XCTAssertEqual(menuBarTitle, "100%")

        // Step 6: Export Baseline Diagnostics
        let jsonExport = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: history, forecast: forecast, ratedTBW: 300.0, now: now)
        assertJSONValid(jsonExport, requiredTopLevelKeys: ["metadata", "drive", "currentMetrics", "forecast", "history"])

        let textReport = ReferenceDiagnosticExporter.exportTextReport(metrics: metrics, history: history, forecast: forecast, ratedTBW: 300.0, now: now)
        XCTAssertTrue(textReport.contains("Overall Health Score:     100% (Good)"))
    }

    // =========================================================================
    // MARK: - Scenario 2: Heavy Developer Workload with Thermal Alerts
    // =========================================================================

    func test_Scenario2_HeavyDeveloperWorkloadWithThermalAlert() throws {
        let forecastEngine = ReferenceForecastEngine()
        let notificationEngine = ReferenceNotificationEngine()
        var now = Date()

        // Step 1: Accumulate 30 days of high write volume (85 GB/day = 0.085 TB/day)
        var history: [SSDHistorySnapshot] = []
        for day in 0..<30 {
            let t = now.addingTimeInterval(Double(day - 29) * 86_400.0)
            let tbw = 10.0 + Double(day) * 0.085
            let wear = 10 + Int(Double(day) * 0.25) // Wear slowly increasing
            history.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: 100 - wear,
                wearPercentage: wear,
                temperatureCelsius: 42.0,
                terabytesWritten: tbw,
                availableSparePercent: 100
            ))
        }

        let steadyMetrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP1024R", serialNumber: "DEV-SSD-002",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 1_000_000_000_000,
            healthScorePercent: history.last!.healthScorePercent, wearPercentage: history.last!.wearPercentage,
            temperatureCelsius: 42.0, availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: history.last!.terabytesWritten, terabytesRead: 20.0,
            powerOnHours: 2400, powerCycles: 200, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        // Step 2: Calculate OLS write rate
        let forecast = forecastEngine.calculateForecast(current: steadyMetrics, history: history, ratedTBW: 600.0, referenceDate: now)
        assertDoubleEqual(forecast.primaryDailyWriteRateGB, 85.0, accuracy: 1.0)
        XCTAssertEqual(forecast.degradationStatus, .acceleratedWear)

        // Step 3: Simulate heavy multi-core build causing sudden thermal spike to 68°C
        now = now.addingTimeInterval(300) // 5 minutes later
        let thermalSpikeBuffer = SyntheticNVMeFixtures.makeBuffer(
            criticalWarning: 0x02, // Temperature Exceeds Threshold
            temperatureKelvin: 341, // 67.85°C (~68°C)
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: UInt8(steadyMetrics.wearPercentage),
            dataUnitsWritten: UInt128Value(low: UInt64(round(steadyMetrics.terabytesWritten * 1_000_000_000_000.0 / 512_000.0)))
        )
        guard let spikeLog = NVMESmartLog(data: thermalSpikeBuffer) else {
            XCTFail("Failed to parse thermal spike log")
            return
        }

        let hotMetrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP1024R", serialNumber: "DEV-SSD-002",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 1_000_000_000_000,
            healthScorePercent: spikeLog.healthScorePercent, wearPercentage: Int(spikeLog.percentageUsed),
            temperatureCelsius: spikeLog.temperatureCelsius, availableSparePercent: Int(spikeLog.availableSparePercent),
            availableSpareThresholdPercent: Int(spikeLog.availableSpareThresholdPercent),
            terabytesWritten: spikeLog.totalTerabytesWritten, terabytesRead: spikeLog.totalTerabytesRead,
            powerOnHours: 2400, powerCycles: 200, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: spikeLog.criticalWarning, timestamp: now
        )

        // Step 4: Verify notification engine triggers thermal alert
        let alerts1 = notificationEngine.evaluateAlerts(metrics: hotMetrics, now: now)
        XCTAssertTrue(alerts1.contains(where: { $0.contains("CRITICAL_TEMPERATURE") }))

        // Step 5: Verify menu bar status turns critical
        let hotStatus = ReferenceMenuBarFormatter.resolveStatus(metrics: hotMetrics)
        XCTAssertEqual(hotStatus, .critical)

        // Step 6: 5 minutes later, still hot -> Cooldown suppresses notification duplicate
        now = now.addingTimeInterval(300)
        let alerts2 = notificationEngine.evaluateAlerts(metrics: hotMetrics, now: now)
        XCTAssertEqual(alerts2.count, 0)

        // Step 7: Build completes, fans cool drive down to 46°C
        now = now.addingTimeInterval(600)
        let cooledMetrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP1024R", serialNumber: "DEV-SSD-002",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 1_000_000_000_000,
            healthScorePercent: hotMetrics.healthScorePercent, wearPercentage: hotMetrics.wearPercentage,
            temperatureCelsius: 46.0, availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: hotMetrics.terabytesWritten, terabytesRead: hotMetrics.terabytesRead,
            powerOnHours: 2400, powerCycles: 200, unsafeShutdowns: 1, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let recoveredStatus = ReferenceMenuBarFormatter.resolveStatus(metrics: cooledMetrics)
        XCTAssertEqual(recoveredStatus, .good)
    }

    // =========================================================================
    // MARK: - Scenario 3: Near End-of-Life SSD Emergency Export
    // =========================================================================

    func test_Scenario3_NearEOLSSDEmergencyExport() throws {
        // Step 1: Parse Near EOL synthetic SMART data
        let eolBuffer = SyntheticNVMeFixtures.makeNearEOLBuffer()
        guard let smartLog = NVMESmartLog(data: eolBuffer) else {
            XCTFail("Failed to parse near EOL buffer")
            return
        }

        XCTAssertEqual(smartLog.percentageUsed, 96)
        XCTAssertEqual(smartLog.healthScorePercent, 4)
        XCTAssertEqual(smartLog.availableSparePercent, 6)
        XCTAssertEqual(smartLog.availableSpareThresholdPercent, 10)
        XCTAssertEqual(smartLog.mediaErrors.low, 14)
        XCTAssertTrue(smartLog.criticalWarning.contains(.availableSpareBelowThreshold))
        XCTAssertTrue(smartLog.criticalWarning.contains(.reliabilityDegraded))

        // Step 2: Instantiate Metrics
        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0256Q",
            serialNumber: "EOL-CRIT-999",
            firmwareRevision: "561.100.",
            interconnect: "Apple Fabric",
            capacityBytes: 251_000_193_024,
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

        XCTAssertFalse(metrics.isHealthy)

        // Step 3: Evaluate Alerts
        let notificationEngine = ReferenceNotificationEngine()
        let now = Date()
        let alerts = notificationEngine.evaluateAlerts(metrics: metrics, now: now)

        XCTAssertTrue(alerts.contains(where: { $0.contains("WEAR_MILESTONE_95") }))
        XCTAssertTrue(alerts.contains(where: { $0.contains("SPARE_CAPACITY_LOW") }))
        XCTAssertTrue(alerts.contains(where: { $0.contains("CRITICAL_RELIABILITY_DEGRADED") }))
        XCTAssertTrue(alerts.contains(where: { $0.contains("MEDIA_ERRORS_DETECTED") }))

        // Step 4: Check UI status is critical
        let status = ReferenceMenuBarFormatter.resolveStatus(metrics: metrics)
        XCTAssertEqual(status, .critical)
        XCTAssertEqual(status.iconName, "exclamationmark.octagon.fill")

        // Step 5: Generate Emergency Diagnostic Reports
        let jsonExport = try ReferenceDiagnosticExporter.exportJSON(metrics: metrics, history: [], forecast: nil, ratedTBW: 150.0, now: now)
        XCTAssertTrue(jsonExport.contains("\"mediaErrors\" : 14"))
        XCTAssertTrue(jsonExport.contains("\"percentageUsed\" : 96"))

        let textReport = ReferenceDiagnosticExporter.exportTextReport(metrics: metrics, history: [], forecast: nil, ratedTBW: 150.0, now: now)
        XCTAssertTrue(textReport.contains("4% (Critical)"))
        XCTAssertTrue(textReport.contains("Media Integrity Errors:   14"))
    }

    // =========================================================================
    // MARK: - Scenario 4: Sandboxed Fallback Mode
    // =========================================================================

    func test_Scenario4_SandboxedFallbackMode() throws {
        // Step 1: Simulate non-privileged environment where UserClient fails
        let reader = MockSSDStorageReader(preset: .simulatedError(.permissionDenied(reason: "Sandboxed process lacks root entitlement")))
        XCTAssertFalse(reader.isLiveHardwareAccessAvailable())

        // Step 2: Application initiates graceful fallback to IORegistry driver stats
        let fallbackMetrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "Apple Internal SSD",
            serialNumber: "FALLBACK-SANDBOX-001",
            firmwareRevision: "N/A",
            interconnect: "Apple Fabric",
            capacityBytes: 500_000_000_000,
            healthScorePercent: 100, // Safe default placeholder
            wearPercentage: 0,
            temperatureCelsius: 38.0, // Ambient estimate
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 12.45,
            terabytesRead: 18.20,
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

        // Step 3: Menu bar displays fallback data safely without crash
        let title = ReferenceMenuBarFormatter.formatTitle(metrics: fallbackMetrics, mode: .iconAndHealth)
        XCTAssertEqual(title, "100%")

        // Step 4: Diagnostic export documents fallback status
        let now = Date()
        let json = try ReferenceDiagnosticExporter.exportJSON(metrics: fallbackMetrics, history: [], forecast: nil, ratedTBW: 300.0, now: now)
        XCTAssertTrue(json.contains("\"isFallbackData\" : true"))
    }

    // =========================================================================
    // MARK: - Scenario 5: Multi-Month History Decimation & Export Integrity
    // =========================================================================

    func test_Scenario5_MultiMonthHistoryDecimationAndExportIntegrity() throws {
        let now = Date()
        let totalHours = 18 * 30 * 24 // 18 months * 30 days * 24 hours = 12,960 hours (simulate 2,500 samples)
        let sampleCount = 2500
        var rawHistory: [SSDHistorySnapshot] = []
        rawHistory.reserveCapacity(sampleCount)

        // Known steady linear write rate = 25.0 GB/day (0.025 TB/day)
        let totalDays = Double(totalHours) / 24.0 // 540 days
        let initialTBW = 5.0

        for i in 0..<sampleCount {
            let progress = Double(i) / Double(sampleCount - 1)
            let sampleTime = now.addingTimeInterval(-Double(totalHours) * 3600.0 * (1.0 - progress))
            let daysElapsed = progress * totalDays
            let tbw = initialTBW + daysElapsed * 0.025
            let wear = Int(round((tbw / 300.0) * 100.0))

            rawHistory.append(SSDHistorySnapshot(
                timestamp: sampleTime,
                healthScorePercent: max(0, 100 - wear),
                wearPercentage: wear,
                temperatureCelsius: 38.0 + Double(i % 5),
                terabytesWritten: tbw,
                availableSparePercent: 100
            ))
        }

        XCTAssertEqual(rawHistory.count, 2500)

        // Step 1: Perform 4-Tier Decimation
        let startDecimate = CFAbsoluteTimeGetCurrent()
        let decimatedHistory = ReferenceDecimationEngine.decimate(samples: rawHistory, relativeTo: now)
        let decimateElapsed = CFAbsoluteTimeGetCurrent() - startDecimate

        XCTAssertLessThan(decimateElapsed, 0.050, "Decimation took \(decimateElapsed)s (expected < 50ms)")
        XCTAssertLessThan(decimatedHistory.count, 500, "Decimated history should be < 500 samples (got \(decimatedHistory.count))")
        XCTAssertGreaterThan(decimatedHistory.count, 200, "Decimated history should preserve adequate resolution")

        // Step 2: Compare OLS Write Rate between Raw and Decimated Datasets
        let forecastEngine = ReferenceForecastEngine()
        let current = SSDHealthMetrics(
            bsdName: "disk0", modelName: "APPLE SSD AP0512R", serialNumber: "SCENARIO-5-SSD",
            firmwareRevision: "741.140.", interconnect: "Apple Fabric", capacityBytes: 500_000_000_000,
            healthScorePercent: rawHistory.last!.healthScorePercent, wearPercentage: rawHistory.last!.wearPercentage,
            temperatureCelsius: 38.0, availableSparePercent: 100, availableSpareThresholdPercent: 10,
            terabytesWritten: rawHistory.last!.terabytesWritten, terabytesRead: 30.0,
            powerOnHours: 13000, powerCycles: 1500, unsafeShutdowns: 10, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0), timestamp: now
        )

        let rawForecast = forecastEngine.calculateForecast(current: current, history: rawHistory, ratedTBW: 300.0, referenceDate: now)
        let decimatedForecast = forecastEngine.calculateForecast(current: current, history: decimatedHistory, ratedTBW: 300.0, referenceDate: now)

        let rateDiff = abs(rawForecast.primaryDailyWriteRateGB - decimatedForecast.primaryDailyWriteRateGB)
        let errorMarginPercent = (rateDiff / rawForecast.primaryDailyWriteRateGB) * 100.0

        XCTAssertLessThan(errorMarginPercent, 2.0, "OLS rate error margin was \(errorMarginPercent)% (expected < 2%)")
        assertDoubleEqual(decimatedForecast.primaryDailyWriteRateGB, 25.0, accuracy: 0.5)

        // Step 3: Verify Export Roundtrip Integrity on Decimated History
        let csv = ReferenceDiagnosticExporter.exportCSV(history: decimatedHistory)
        assertCSVValid(csv, expectedRowCount: decimatedHistory.count)

        let json = try ReferenceDiagnosticExporter.exportJSON(metrics: current, history: decimatedHistory, forecast: decimatedForecast, ratedTBW: 300.0, now: now)
        assertJSONValid(json, requiredTopLevelKeys: ["metadata", "drive", "currentMetrics", "forecast", "history"])
    }
}
