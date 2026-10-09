import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService

final class AdversarialNotificationAndExportTests: XCTestCase {

    var baseDate: Date!

    override func setUp() {
        super.setUp()
        baseDate = Date(timeIntervalSince1970: 1787832000) // Deterministic epoch
    }

    override func tearDown() {
        baseDate = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeMetrics(
        bsdName: String = "disk0",
        modelName: String = "APPLE SSD AP0256Q",
        serialNumber: String = "SN-TEST-ADV",
        firmwareRevision: String = "561.100.",
        interconnect: String = "Apple Fabric",
        capacityBytes: UInt64 = 256_000_000_000,
        wearPercentage: Int = 10,
        temperatureCelsius: Double = 38.0,
        availableSparePercent: Int = 100,
        availableSpareThresholdPercent: Int = 10,
        terabytesWritten: Double = 10.0,
        terabytesRead: Double = 15.0,
        powerOnHours: UInt64 = 2000,
        powerCycles: UInt64 = 400,
        unsafeShutdowns: UInt64 = 3,
        criticalWarnings: CriticalWarningFlags = CriticalWarningFlags(rawValue: 0),
        mediaErrors: UInt64 = 0,
        timestamp: Date? = nil
    ) -> SSDHealthMetrics {
        SSDHealthMetrics(
            bsdName: bsdName,
            modelName: modelName,
            serialNumber: serialNumber,
            firmwareRevision: firmwareRevision,
            interconnect: interconnect,
            capacityBytes: capacityBytes,
            healthScorePercent: 100 - min(100, wearPercentage),
            wearPercentage: wearPercentage,
            temperatureCelsius: temperatureCelsius,
            availableSparePercent: availableSparePercent,
            availableSpareThresholdPercent: availableSpareThresholdPercent,
            terabytesWritten: terabytesWritten,
            terabytesRead: terabytesRead,
            powerOnHours: powerOnHours,
            powerCycles: powerCycles,
            unsafeShutdowns: unsafeShutdowns,
            mediaErrors: mediaErrors,
            errorLogEntries: 0,
            criticalWarnings: criticalWarnings,
            timestamp: timestamp ?? baseDate
        )
    }

    // MARK: - 1. Rapid Burst Alerts & Debounce Verification

    func testBurstAlerts_RapidFire_NoSpamWithinCooldown() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)

        let hotMetrics = makeMetrics(temperatureCelsius: 68.0) // Triggers temp_crit (900s cooldown)

        // Rapid burst of 100 consecutive calls at t0
        var totalTriggered = 0
        for _ in 0..<100 {
            let alerts = service.evaluateAlerts(metrics: hotMetrics, now: baseDate)
            totalTriggered += alerts.count
        }

        XCTAssertEqual(totalTriggered, 1, "Exactly 1 alert must fire during rapid burst at t0; remaining 99 must be debounced")

        // Rapid burst of 50 calls at t0 + 10s (within 900s)
        var burst2Count = 0
        for _ in 0..<50 {
            let alerts = service.evaluateAlerts(metrics: hotMetrics, now: baseDate.addingTimeInterval(10.0))
            burst2Count += alerts.count
        }
        XCTAssertEqual(burst2Count, 0, "All alerts must be suppressed within cooldown window")
    }

    func testCooldown_ExactBoundarySeconds_SuppressesAtMinusOne_FiresAtExactOrPlusOne() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)

        // Test temp_warn (1800s cooldown)
        let warnMetrics = makeMetrics(temperatureCelsius: 62.0)
        let t0 = baseDate!

        let first = service.evaluateAlerts(metrics: warnMetrics, now: t0)
        XCTAssertEqual(first.count, 1)

        // t0 + 1799s -> Cooldown still active
        let subBoundary = service.evaluateAlerts(metrics: warnMetrics, now: t0.addingTimeInterval(1799.0))
        XCTAssertEqual(subBoundary.count, 0, "Must be suppressed at cooldownSeconds - 1")

        // t0 + 1800s -> Cooldown expired (>= condition)
        let exactBoundary = service.evaluateAlerts(metrics: warnMetrics, now: t0.addingTimeInterval(1800.0))
        XCTAssertEqual(exactBoundary.count, 1, "Must trigger at exact boundary >= cooldownSeconds")

        // t0 + 1801s -> Suppressed again since 1800s recorded new trigger
        let immediateNext = service.evaluateAlerts(metrics: warnMetrics, now: t0.addingTimeInterval(1801.0))
        XCTAssertEqual(immediateNext.count, 0)
    }

    func testDebounce_AllThermalLevels_Warning_Critical_Emergency_Transitions() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)
        let t0 = baseDate!

        // Level 1: Warning (62°C) at t0 -> temp_warn fires
        let m1 = makeMetrics(temperatureCelsius: 62.0)
        let a1 = service.evaluateAlertEvents(metrics: m1, now: t0)
        XCTAssertEqual(a1.count, 1)
        XCTAssertEqual(a1[0].ruleKey, "temp_warn")
        XCTAssertEqual(a1[0].severity, .warning)

        // Level 2: Critical (67°C) at t0 + 5s -> temp_crit is a DIFFERENT rule key, so it should fire immediately!
        let m2 = makeMetrics(temperatureCelsius: 67.0)
        let a2 = service.evaluateAlertEvents(metrics: m2, now: t0.addingTimeInterval(5.0))
        XCTAssertEqual(a2.count, 1)
        XCTAssertEqual(a2[0].ruleKey, "temp_crit")
        XCTAssertEqual(a2[0].severity, .critical)

        // Level 3: Emergency (73°C) at t0 + 10s -> temp_ext is a DIFFERENT rule key, so it should fire immediately!
        let m3 = makeMetrics(temperatureCelsius: 73.0)
        let a3 = service.evaluateAlertEvents(metrics: m3, now: t0.addingTimeInterval(10.0))
        XCTAssertEqual(a3.count, 1)
        XCTAssertEqual(a3[0].ruleKey, "temp_ext")
        XCTAssertEqual(a3[0].severity, .emergency)

        // Drop back to 62°C at t0 + 20s -> temp_warn is on cooldown (1800s from t0), suppressed!
        let a4 = service.evaluateAlertEvents(metrics: m1, now: t0.addingTimeInterval(20.0))
        XCTAssertEqual(a4.count, 0)
    }

    func testDebounce_WearMilestones_OneShot_80_90_95_100_AndJumpingDirectlyTo100() {
        // Scenario A: Step-by-step wear progression
        let cd1 = AlertCooldownManager(userDefaults: nil)
        let s1 = NotificationService(cooldownManager: cd1, notificationCenter: nil)
        let t0 = baseDate!

        // Step 1: 79% wear -> no alert
        XCTAssertTrue(s1.evaluateAlerts(metrics: makeMetrics(wearPercentage: 79), now: t0).isEmpty)

        // Step 2: 80% wear -> fires 80
        let a80 = s1.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 80), now: t0.addingTimeInterval(100))
        XCTAssertEqual(a80.map { $0.ruleKey }, ["wear_m_80"])
        XCTAssertEqual(a80.first?.severity, .warning)

        // Step 3: 85% wear -> 80 already acknowledged, no other milestone reached
        let a85 = s1.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 85), now: t0.addingTimeInterval(200))
        XCTAssertTrue(a85.isEmpty)

        // Step 4: 90% wear -> fires 90
        let a90 = s1.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 90), now: t0.addingTimeInterval(300))
        XCTAssertEqual(a90.map { $0.ruleKey }, ["wear_m_90"])
        XCTAssertEqual(a90.first?.severity, .critical)

        // Step 5: 95% wear -> fires 95
        let a95 = s1.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 95), now: t0.addingTimeInterval(400))
        XCTAssertEqual(a95.map { $0.ruleKey }, ["wear_m_95"])
        XCTAssertEqual(a95.first?.severity, .emergency)

        // Step 6: 100% wear -> fires 100
        let a100 = s1.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 100), now: t0.addingTimeInterval(500))
        XCTAssertEqual(a100.map { $0.ruleKey }, ["wear_m_100"])
        XCTAssertEqual(a100.first?.severity, .emergency)

        // Step 7: 105% wear -> all [80, 90, 95, 100] acknowledged -> no new alerts
        let a105 = s1.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 105), now: t0.addingTimeInterval(600))
        XCTAssertTrue(a105.isEmpty)

        // Scenario B: Sudden jump directly to 96% on fresh drive
        let cd2 = AlertCooldownManager(userDefaults: nil)
        let s2 = NotificationService(cooldownManager: cd2, notificationCenter: nil)
        let jumpEvents = s2.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 96), now: t0)
        let jumpKeys = jumpEvents.map { $0.ruleKey }
        XCTAssertTrue(jumpKeys.contains("wear_m_80"))
        XCTAssertTrue(jumpKeys.contains("wear_m_90"))
        XCTAssertTrue(jumpKeys.contains("wear_m_95"))
        XCTAssertFalse(jumpKeys.contains("wear_m_100"))

        // Re-evaluating jump at t0 + 10s should yield zero wear alerts
        let jumpEvents2 = s2.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 96), now: t0.addingTimeInterval(10))
        XCTAssertTrue(jumpEvents2.isEmpty)
    }

    func testDebounce_SpareCapacity_CritVsWarn_Thresholds() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)
        let t0 = baseDate!

        // Available spare 8% (< 10% threshold) -> triggers spare_low
        let mWarn = makeMetrics(availableSparePercent: 8, availableSpareThresholdPercent: 10)
        let aWarn = service.evaluateAlertEvents(metrics: mWarn, now: t0)
        XCTAssertEqual(aWarn.count, 1)
        XCTAssertEqual(aWarn[0].ruleKey, "spare_low")
        XCTAssertEqual(aWarn[0].severity, .critical)

        // Next evaluation at t0 + 10s with spare 4% (<= 5% emergency) -> triggers spare_crit
        let mCrit = makeMetrics(availableSparePercent: 4, availableSpareThresholdPercent: 10)
        let aCrit = service.evaluateAlertEvents(metrics: mCrit, now: t0.addingTimeInterval(10))
        XCTAssertEqual(aCrit.count, 1)
        XCTAssertEqual(aCrit[0].ruleKey, "spare_crit")
        XCTAssertEqual(aCrit[0].severity, .emergency)

        // Evaluation at t0 + 20s with spare 4% -> spare_crit cooldown is 43200s, suppressed!
        let aSuppressed = service.evaluateAlertEvents(metrics: mCrit, now: t0.addingTimeInterval(20))
        XCTAssertTrue(aSuppressed.isEmpty)
    }

    func testDebounce_CriticalWarningBitmaskFlags_IndividualSuppression() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)
        let t0 = baseDate!

        // Set reliabilityDegraded flag
        let m1 = makeMetrics(criticalWarnings: .reliabilityDegraded)
        let a1 = service.evaluateAlertEvents(metrics: m1, now: t0)
        XCTAssertEqual(a1.count, 1)
        XCTAssertEqual(a1[0].ruleKey, "crit_reliability")
        XCTAssertEqual(a1[0].severity, .emergency)

        // At t0 + 100s, add readOnly flag
        let m2 = makeMetrics(criticalWarnings: [.reliabilityDegraded, .readOnly])
        let a2 = service.evaluateAlertEvents(metrics: m2, now: t0.addingTimeInterval(100))
        // crit_reliability is suppressed, but crit_readonly should trigger!
        XCTAssertEqual(a2.count, 1)
        XCTAssertEqual(a2[0].ruleKey, "crit_readonly")
        XCTAssertEqual(a2[0].severity, .emergency)

        // At t0 + 200s, add volatileMemoryBackupFailed
        let m3 = makeMetrics(criticalWarnings: [.reliabilityDegraded, .readOnly, .volatileMemoryBackupFailed])
        let a3 = service.evaluateAlertEvents(metrics: m3, now: t0.addingTimeInterval(200))
        XCTAssertEqual(a3.count, 1)
        XCTAssertEqual(a3[0].ruleKey, "crit_backup")
        XCTAssertEqual(a3[0].severity, .critical)
    }

    func testDebounce_MediaErrors_DeltaTriggers_NoTriggersOnConstantOrDecrease() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)
        let t0 = baseDate!

        // Initial 0 -> 3 errors: triggers alert
        let a1 = service.evaluateAlertEvents(metrics: makeMetrics(mediaErrors: 3), now: t0)
        XCTAssertEqual(a1.count, 1)
        XCTAssertEqual(a1[0].ruleKey, "media_errors")
        XCTAssertEqual(a1[0].severity, .critical)
        XCTAssertTrue(a1[0].message.contains("3 uncorrectable"))

        // Next poll with 3 errors: constant, no new alert
        let a2 = service.evaluateAlertEvents(metrics: makeMetrics(mediaErrors: 3), now: t0.addingTimeInterval(60))
        XCTAssertTrue(a2.isEmpty)

        // Next poll with 7 errors: delta +4, triggers alert
        let a3 = service.evaluateAlertEvents(metrics: makeMetrics(mediaErrors: 7), now: t0.addingTimeInterval(120))
        XCTAssertEqual(a3.count, 1)
        XCTAssertTrue(a3[0].message.contains("7 uncorrectable"))

        // Next poll with 2 errors (device reset / new drive): decrease, should not trigger
        let a4 = service.evaluateAlertEvents(metrics: makeMetrics(mediaErrors: 2), now: t0.addingTimeInterval(180))
        XCTAssertTrue(a4.isEmpty)

        // After the decrease the baseline is rebased, so 2 -> 4 must alert even though 4 < 7
        XCTAssertEqual(cooldownManager.lastMediaErrorCount(), 2)
        let a5 = service.evaluateAlertEvents(metrics: makeMetrics(mediaErrors: 4), now: t0.addingTimeInterval(240))
        XCTAssertEqual(a5.map { $0.ruleKey }, ["media_errors"])
    }

    func testWearMilestones_FollowUserWarningThreshold() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)
        let t0 = baseDate!

        // Threshold 70: first milestone fires at 70, not at 80
        let a70 = service.evaluateAlertEvents(metrics: makeMetrics(wearPercentage: 72), wearWarnThreshold: 70, now: t0)
        XCTAssertEqual(a70.filter { $0.ruleKey.hasPrefix("wear_m_") }.map { $0.ruleKey }, ["wear_m_70"])
    }

    func testExtremeTemperature_RespectsHigherUserCriticalThreshold() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)

        // User critical at 75: 72 C is only a warning, not an emergency
        let events = service.evaluateAlertEvents(
            metrics: makeMetrics(temperatureCelsius: 72.0),
            tempWarnThreshold: 70.0,
            tempCritThreshold: 75.0,
            now: baseDate!
        )
        XCTAssertEqual(events.filter { $0.ruleKey.hasPrefix("temp") }.map { $0.ruleKey }, ["temp_warn"])
    }

    func testConcurrentBurstEvaluations_ThreadSafety_NoRaceCondition() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)
        let t0 = baseDate!

        let iterations = 200
        let queue = DispatchQueue(label: "test.concurrent.alerts", attributes: .concurrent)
        let group = DispatchGroup()

        var collectedEvents: [[AlertEvent]] = []
        let collectLock = NSLock()

        for i in 0..<iterations {
            group.enter()
            queue.async {
                // All threads evaluate at roughly the same timestamp t0 + small fraction
                let now = t0.addingTimeInterval(Double(i) * 0.001)
                let m = self.makeMetrics(wearPercentage: 85, temperatureCelsius: 68.0)
                let events = service.evaluateAlertEvents(metrics: m, now: now)

                collectLock.lock()
                collectedEvents.append(events)
                collectLock.unlock()

                group.leave()
            }
        }

        group.wait()

        // Count how many temp_crit and wear_m_80 events were triggered across all 200 threads
        let allEvents = collectedEvents.flatMap { $0 }
        let tempCritCount = allEvents.filter { $0.ruleKey == "temp_crit" }.count
        let wear80Count = allEvents.filter { $0.ruleKey == "wear_m_80" }.count

        // Because AlertCooldownManager state is synchronized with NSLock, triggers must be strictly debounced
        // Note: under race conditions between shouldTrigger and recordTrigger, count could exceed 1 if not safe.
        XCTAssertEqual(tempCritCount, 1, "temp_crit must trigger exactly once despite \(iterations) concurrent threads")
        XCTAssertEqual(wear80Count, 1, "wear_m_80 must trigger exactly once despite \(iterations) concurrent threads")
    }

    func testCooldownPersistence_UserDefaultsRoundtrip_PreservesTimestampsAndMilestones() {
        let suiteName = "test_alert_cooldown_persistence_\(UUID().uuidString)"
        guard let customUD = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer {
            customUD.removePersistentDomain(forName: suiteName)
        }

        let storageKey = "test_cooldown_key"
        let t0 = baseDate!

        // Session 1: record events
        do {
            let mgr1 = AlertCooldownManager(userDefaults: customUD, storageKey: storageKey)
            mgr1.recordTrigger(key: "temp_crit", now: t0)
            mgr1.acknowledgeWearMilestone(80)
            mgr1.acknowledgeWearMilestone(90)
            mgr1.updateMediaErrorCount(12)
        }

        // Session 2: restore from UserDefaults in fresh manager instance
        do {
            let mgr2 = AlertCooldownManager(userDefaults: customUD, storageKey: storageKey)

            // Verify temp_crit cooldown is preserved
            XCTAssertFalse(mgr2.shouldTrigger(key: "temp_crit", cooldownSeconds: 900.0, now: t0.addingTimeInterval(500.0)))
            XCTAssertTrue(mgr2.shouldTrigger(key: "temp_crit", cooldownSeconds: 900.0, now: t0.addingTimeInterval(901.0)))

            // Verify milestones are preserved
            XCTAssertFalse(mgr2.shouldTriggerWearMilestone(80))
            XCTAssertFalse(mgr2.shouldTriggerWearMilestone(90))
            XCTAssertTrue(mgr2.shouldTriggerWearMilestone(95))

            // Verify media errors count is preserved
            XCTAssertEqual(mgr2.lastMediaErrorCount(), 12)
        }
    }

    // MARK: - 2. RFC 4180 CSV Compliance Testing

    func testCSV_StrictRFC4180_CRLFLineEndings() throws {
        let exporter = DiagnosticExporter()
        let snapshots = [
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 36.5, terabytesWritten: 12.345, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(3600), healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 37.0, terabytesWritten: 12.350, availableSparePercent: 100)
        ]

        let csv = try exporter.exportCSV(history: snapshots)

        // RFC 4180 Section 2.1: Each record must be delimited by CRLF
        XCTAssertTrue(csv.hasSuffix("\r\n"), "CSV must end with CRLF")
        XCTAssertFalse(csv.contains("\r\r\n"), "CSV must not contain double CR")

        // Split exclusively by CRLF
        let lines = csv.components(separatedBy: "\r\n")
        // Last element after trailing CRLF is empty string
        XCTAssertEqual(lines.last, "")
        let dataLines = lines.dropLast()
        XCTAssertEqual(dataLines.count, 3, "Header + 2 rows = 3 lines")

        // Ensure none of the individual data lines contain raw \n or \r
        for line in dataLines {
            XCTAssertFalse(line.contains("\n"))
            XCTAssertFalse(line.contains("\r"))
        }
    }

    func testCSV_HeaderAndColumnCountConsistency() throws {
        let exporter = DiagnosticExporter()
        let snapshots = [
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 25.0, terabytesWritten: 0.001, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(100), healthScorePercent: 99, wearPercentage: 1, temperatureCelsius: 45.2, terabytesWritten: 0.500, availableSparePercent: 98, mediaErrors: 2)
        ]

        let csv = try exporter.exportCSV(history: snapshots)
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        let expectedHeaders = [
            "Timestamp_ISO8601",
            "Timestamp_Unix",
            "Percentage_Used",
            "Health_Score_Pct",
            "Temperature_C",
            "TBW_Decimal",
            "Available_Spare_Pct",
            "Critical_Warning_Flags",
            "Media_Errors"
        ]

        let headerFields = rows[0].components(separatedBy: ",")
        XCTAssertEqual(headerFields, expectedHeaders)

        for (idx, row) in rows.enumerated() {
            let fields = row.components(separatedBy: ",")
            XCTAssertEqual(fields.count, expectedHeaders.count, "Row \(idx) field count must exactly match header column count (\(expectedHeaders.count))")
        }
    }

    func testCSV_ChronologicalSortOrdering_IrrespectiveOfInputOrder() throws {
        let exporter = DiagnosticExporter()
        let t1 = baseDate!
        let t2 = baseDate.addingTimeInterval(3600)
        let t3 = baseDate.addingTimeInterval(7200)

        // Provide snapshots in reverse chronological order
        let unordered = [
            SSDHistorySnapshot(timestamp: t3, healthScorePercent: 70, wearPercentage: 30, temperatureCelsius: 40.0, terabytesWritten: 30.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t1, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 35.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t2, healthScorePercent: 80, wearPercentage: 20, temperatureCelsius: 38.0, terabytesWritten: 20.0, availableSparePercent: 100)
        ]

        let csv = try exporter.exportCSV(history: unordered)
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        // Data rows should be sorted t1, t2, t3
        let row1 = rows[1].components(separatedBy: ",")
        let row2 = rows[2].components(separatedBy: ",")
        let row3 = rows[3].components(separatedBy: ",")

        XCTAssertEqual(Int(row1[1]), Int(t1.timeIntervalSince1970))
        XCTAssertEqual(Int(row2[1]), Int(t2.timeIntervalSince1970))
        XCTAssertEqual(Int(row3[1]), Int(t3.timeIntervalSince1970))
    }

    func testCSV_EmptyHistory_ReturnsOnlyCRLFHeader() throws {
        let exporter = DiagnosticExporter()
        let csv = try exporter.exportCSV(history: [])

        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].starts(with: "Timestamp_ISO8601,"))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testCSV_ExtremeValues_MaxIntegers_NegativeTemps_HexFormatting() throws {
        let exporter = DiagnosticExporter()
        let extreme = SSDHistorySnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            healthScorePercent: 0,
            wearPercentage: 255,
            temperatureCelsius: -15.4,
            terabytesWritten: 999999.999,
            terabytesRead: 888888.888,
            powerOnHours: UInt64.max,
            powerCycles: UInt64.max,
            unsafeShutdowns: UInt64.max,
            availableSparePercent: 0,
            availableSpareThresholdPercent: 10,
            criticalWarningsRaw: 0x3F, // All 6 bits set
            mediaErrors: UInt64.max
        )

        let csv = try exporter.exportCSV(history: [extreme])
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(rows.count, 2)

        let fields = rows[1].components(separatedBy: ",")
        XCTAssertEqual(fields[1], "0") // 1970-01-01
        XCTAssertEqual(fields[2], "255")
        XCTAssertEqual(fields[3], "0")
        XCTAssertEqual(fields[4], "-15.4")
        XCTAssertEqual(fields[5], "999999.999")
        XCTAssertEqual(fields[6], "0")
        XCTAssertEqual(fields[7], "0x3F")
        XCTAssertEqual(fields[8], "\(UInt64.max)")
    }

    func testCSV_LargeDataset_10kRows_PerformanceAndCorrectness() throws {
        let exporter = DiagnosticExporter()
        var snapshots: [SSDHistorySnapshot] = []
        snapshots.reserveCapacity(10_000)

        let t0 = baseDate!
        for i in 0..<10_000 {
            snapshots.append(SSDHistorySnapshot(
                timestamp: t0.addingTimeInterval(Double(i) * 60.0),
                healthScorePercent: max(0, 100 - i / 100),
                wearPercentage: min(100, i / 100),
                temperatureCelsius: 35.0 + Double(i % 30),
                terabytesWritten: Double(i) * 0.01,
                availableSparePercent: 100
            ))
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let csv = try exporter.exportCSV(history: snapshots)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 2.0, "Exporting 10k CSV rows must complete in under 2 seconds (took \(elapsed)s)")

        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(rows.count, 10_001) // 1 header + 10,000 rows
    }

    // MARK: - 3. JSON Export Schema Validation & Full Roundtrip Parsing

    func testJSONExport_CompleteSchemaValidation_AllKeysAndTypes() throws {
        let exporter = DiagnosticExporter()
        let metrics = makeMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP1024Q",
            serialNumber: "C02XYZ12345",
            capacityBytes: 1_000_000_000_000,
            wearPercentage: 15,
            temperatureCelsius: 41.5,
            terabytesWritten: 32.5,
            criticalWarnings: [.availableSpareBelowThreshold, .readOnly]
        )

        let forecast = SSDForecastResult(
            dailyWriteRate7dGB: 18.5,
            dailyWriteRate30dGB: 19.2,
            dailyWriteRateLifetimeGB: 15.0,
            primaryDailyWriteRateGB: 19.2,
            estimatedDaysRemaining: 5200.0,
            estimatedYearsRemaining: 14.2,
            estimatedExhaustionDate: baseDate.addingTimeInterval(5200 * 86400),
            degradationStatus: .stable,
            confidenceInterval95: (lowerGB: 16.0, upperGB: 22.4)
        )

        let history = [
            SSDHistorySnapshot(from: metrics)
        ]

        let jsonString = try exporter.exportJSON(
            metrics: metrics,
            history: history,
            forecast: forecast,
            ratedTBW: 600.0,
            now: baseDate
        )

        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Exported string is not valid JSON")
            return
        }

        // 1. Metadata Schema
        guard let meta = json["metadata"] as? [String: Any] else {
            XCTFail("Missing metadata object")
            return
        }
        XCTAssertNotNil(meta["exportTimestamp"] as? String)
        XCTAssertNotNil(meta["appVersion"] as? String)
        XCTAssertNotNil(meta["macOSVersion"] as? String)
        XCTAssertNotNil(meta["architecture"] as? String)

        // 2. Drive Schema
        guard let drive = json["drive"] as? [String: Any] else {
            XCTFail("Missing drive object")
            return
        }
        XCTAssertEqual(drive["bsdName"] as? String, "disk0")
        XCTAssertEqual(drive["productName"] as? String, "APPLE SSD AP1024Q")
        XCTAssertEqual(drive["serialNumber"] as? String, "C02XYZ12345")
        XCTAssertEqual(drive["capacityBytes"] as? UInt64, 1_000_000_000_000)
        XCTAssertEqual(drive["ratedTBW"] as? Double, 600.0)

        // 3. CurrentMetrics Schema
        guard let m = json["currentMetrics"] as? [String: Any] else {
            XCTFail("Missing currentMetrics object")
            return
        }
        XCTAssertEqual(m["healthScore"] as? Int, 85)
        XCTAssertEqual(m["percentageUsed"] as? Int, 15)
        XCTAssertEqual(m["temperatureCelsius"] as? Double, 41.5)
        XCTAssertEqual(m["terabytesWritten"] as? Double, 32.5)
        XCTAssertEqual(m["criticalWarningBitmask"] as? UInt8, 0x09) // 0x01 | 0x08 = 0x09
        XCTAssertEqual(m["isFallbackData"] as? Bool, false)

        // 4. Forecast Schema
        guard let f = json["forecast"] as? [String: Any] else {
            XCTFail("Missing forecast object")
            return
        }
        XCTAssertEqual(f["dailyWriteRate7dGB"] as? Double, 18.5)
        XCTAssertEqual(f["dailyWriteRate30dGB"] as? Double, 19.2)
        XCTAssertEqual(f["degradationStatus"] as? String, "stable")
        XCTAssertEqual(f["estimatedYearsRemaining"] as? Double, 14.2)
        XCTAssertNotNil(f["estimatedExhaustionDate"] as? String)

        guard let ci = f["confidenceInterval95"] as? [String: Any] else {
            XCTFail("Missing confidenceInterval95 object")
            return
        }
        XCTAssertEqual(ci["lowerBoundDailyGB"] as? Double, 16.0)
        XCTAssertEqual(ci["upperBoundDailyGB"] as? Double, 22.4)

        // 5. History Schema
        XCTAssertEqual(json["historySampleCount"] as? Int, 1)
        guard let hist = json["history"] as? [[String: Any]], hist.count == 1 else {
            XCTFail("Missing or invalid history array")
            return
        }
        XCTAssertEqual(hist[0]["percentageUsed"] as? Int, 15)
        XCTAssertEqual(hist[0]["healthScore"] as? Int, 85)
    }

    func testJSONExport_InfiniteForecastValues_SafelyHandledWithoutJSONSerializationError() throws {
        let exporter = DiagnosticExporter()
        let metrics = makeMetrics(wearPercentage: 0, terabytesWritten: 0.0)

        // Forecast with infinite lifespan and nil exhaustion date
        let infiniteForecast = SSDForecastResult(
            dailyWriteRate7dGB: 0.0,
            dailyWriteRate30dGB: 0.0,
            dailyWriteRateLifetimeGB: 0.0,
            primaryDailyWriteRateGB: 0.0,
            estimatedDaysRemaining: Double.infinity,
            estimatedYearsRemaining: Double.infinity,
            estimatedExhaustionDate: nil,
            degradationStatus: .insufficientData,
            confidenceInterval95: (lowerGB: 0.0, upperGB: 0.0)
        )

        // Must NOT throw NSInvalidArgumentException when serializing infinite numbers
        let jsonString = try exporter.exportJSON(
            metrics: metrics,
            history: [],
            forecast: infiniteForecast,
            ratedTBW: 300.0,
            now: baseDate
        )

        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let f = json["forecast"] as? [String: Any] else {
            XCTFail("Invalid JSON produced for infinite forecast")
            return
        }

        // Infinite days/years should be clamped to -1.0
        XCTAssertEqual(f["estimatedDaysRemaining"] as? Double, -1.0)
        XCTAssertEqual(f["estimatedYearsRemaining"] as? Double, -1.0)
        XCTAssertNil(f["estimatedExhaustionDate"])
    }

    func testJSONExport_SpecialCharactersAndUnicodeInDriveMetadata() throws {
        let exporter = DiagnosticExporter()
        let trickyModel = "Apple SSD \"Pro\" / \\ \t \n \u{1F525} \u{0000}"
        let trickySerial = "SN\r\n,\",Special"

        let metrics = makeMetrics(
            modelName: trickyModel,
            serialNumber: trickySerial
        )

        let jsonString = try exporter.exportJSON(
            metrics: metrics,
            history: [],
            forecast: nil,
            now: baseDate
        )

        // Verify valid JSON parse despite control characters and quotes
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let drive = json["drive"] as? [String: Any] else {
            XCTFail("Failed to deserialize JSON containing special characters")
            return
        }

        XCTAssertEqual(drive["productName"] as? String, trickyModel)
        XCTAssertEqual(drive["serialNumber"] as? String, trickySerial)
    }

    func testJSONExport_FullRoundtripParsingIntoDecodableTypes() throws {
        let exporter = DiagnosticExporter()
        let metrics = makeMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0512R",
            serialNumber: "SN999888777",
            capacityBytes: 500_000_000_000,
            wearPercentage: 22,
            temperatureCelsius: 42.0,
            terabytesWritten: 45.123,
            mediaErrors: 1
        )

        let snapshot = SSDHistorySnapshot(from: metrics)
        let jsonString = try exporter.exportJSON(
            metrics: metrics,
            history: [snapshot],
            forecast: nil,
            ratedTBW: 300.0,
            now: baseDate
        )

        // Parse root object
        let decoder = JSONDecoder()
        guard let data = jsonString.data(using: .utf8) else {
            XCTFail("Failed to get UTF8 data")
            return
        }

        struct ExportRoot: Decodable {
            struct Metadata: Decodable {
                let appVersion: String
                let architecture: String
            }
            struct Drive: Decodable {
                let bsdName: String
                let productName: String
                let serialNumber: String
                let ratedTBW: Double
            }
            struct Metrics: Decodable {
                let healthScore: Int
                let percentageUsed: Int
                let temperatureCelsius: Double
                let terabytesWritten: Double
                let mediaErrors: UInt64
            }
            struct HistoryItem: Decodable {
                let percentageUsed: Int
                let healthScore: Int
                let temperatureCelsius: Double
                let terabytesWritten: Double
                let mediaErrors: UInt64
            }
            let metadata: Metadata
            let drive: Drive
            let currentMetrics: Metrics
            let historySampleCount: Int
            let history: [HistoryItem]
        }

        let parsed = try decoder.decode(ExportRoot.self, from: data)
        XCTAssertEqual(parsed.drive.productName, "APPLE SSD AP0512R")
        XCTAssertEqual(parsed.drive.ratedTBW, 300.0)
        XCTAssertEqual(parsed.currentMetrics.healthScore, 78)
        XCTAssertEqual(parsed.currentMetrics.percentageUsed, 22)
        XCTAssertEqual(parsed.currentMetrics.mediaErrors, 1)
        XCTAssertEqual(parsed.historySampleCount, 1)
        XCTAssertEqual(parsed.history[0].percentageUsed, 22)
    }

    // MARK: - 4. ASCII Diagnostic Report Formatter Validation

    func testASCIIReport_AllSectionsAndIntegrity() {
        let exporter = DiagnosticExporter()
        let metrics = makeMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0256Q",
            serialNumber: "SN-ASCII-1",
            wearPercentage: 85,
            temperatureCelsius: 66.0, // Overheated
            availableSparePercent: 8, // Below 10%
            availableSpareThresholdPercent: 10,
            terabytesWritten: 120.0,
            criticalWarnings: [.availableSpareBelowThreshold, .reliabilityDegraded],
            mediaErrors: 3
        )

        let forecast = SSDForecastResult(
            dailyWriteRate7dGB: 35.0,
            dailyWriteRate30dGB: 32.0,
            dailyWriteRateLifetimeGB: 25.0,
            primaryDailyWriteRateGB: 32.0,
            estimatedDaysRemaining: 45.0,
            estimatedYearsRemaining: 0.12,
            estimatedExhaustionDate: baseDate.addingTimeInterval(45 * 86400),
            degradationStatus: .criticalWear,
            confidenceInterval95: (lowerGB: 28.0, upperGB: 36.0)
        )

        let report = exporter.exportTextReport(
            metrics: metrics,
            history: [],
            forecast: forecast,
            ratedTBW: 150.0,
            now: baseDate
        )

        // 1. Header & System Identification
        XCTAssertTrue(report.contains("macOS SSD HEALTH & SMART DIAGNOSTIC REPORT"))
        XCTAssertTrue(report.contains("1. STORAGE DEVICE IDENTIFICATION"))
        XCTAssertTrue(report.contains("APPLE SSD AP0256Q (disk0)"))
        XCTAssertTrue(report.contains("SN-ASCII-1"))
        XCTAssertTrue(report.contains("150.0 TBW"))

        // 2. Health & Lifespan Summary
        XCTAssertTrue(report.contains("2. HEALTH & LIFESPAN SUMMARY"))
        XCTAssertTrue(report.contains("Overall Health Score:     15% (Critical)"))
        XCTAssertTrue(report.contains("Percentage Used:          85%"))
        XCTAssertTrue(report.contains("Total Bytes Written:      120.00 TBW"))
        XCTAssertTrue(report.contains("Media Integrity Errors:   3"))

        // 3. Forecast & Projection
        XCTAssertTrue(report.contains("3. FORECAST & WEAR PROJECTION"))
        XCTAssertTrue(report.contains("Daily Write Rate (7d):    35.00 GB/day"))
        XCTAssertTrue(report.contains("Degradation Trajectory:   CRITICAL_WEAR"))

        // 4. Hardware Reliability Flags
        XCTAssertTrue(report.contains("4. HARDWARE RELIABILITY FLAGS & WARNINGS"))
        XCTAssertTrue(report.contains("[ ] Available Spare (8% >= 10% threshold)")) // unchecked because 8 < 10
        XCTAssertTrue(report.contains("[ ] Thermal Status (66.0 °C < 65.0 °C threshold)")) // unchecked because 66 >= 65
        XCTAssertTrue(report.contains("[ ] NVM Subsystem Reliability Intact")) // unchecked because degraded
        XCTAssertTrue(report.contains("[x] Drive Media Writable")) // checked because writable
        XCTAssertTrue(report.contains("[ ] Zero Media Errors")) // unchecked because 3 errors
    }
}
