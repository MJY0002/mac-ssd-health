import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService

final class NotificationServiceTests: XCTestCase {

    var cooldownManager: AlertCooldownManager!
    var service: NotificationService!
    var baseDate: Date = Date(timeIntervalSince1970: 1787832000)

    override func setUp() {
        super.setUp()
        cooldownManager = AlertCooldownManager(userDefaults: nil) // In-memory isolate
        service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)
        baseDate = Date(timeIntervalSince1970: 1787832000)
    }

    override func tearDown() {
        cooldownManager = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeMetrics(
        wearPercentage: Int = 10,
        temperatureCelsius: Double = 38.0,
        availableSparePercent: Int = 100,
        availableSpareThresholdPercent: Int = 10,
        criticalWarnings: CriticalWarningFlags = CriticalWarningFlags(rawValue: 0),
        mediaErrors: UInt64 = 0
    ) -> SSDHealthMetrics {
        SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0256Q",
            serialNumber: "SN-TEST-NOTIF",
            firmwareRevision: "561.100.",
            interconnect: "Apple Fabric",
            capacityBytes: 256_000_000_000,
            healthScorePercent: 100 - min(100, wearPercentage),
            wearPercentage: wearPercentage,
            temperatureCelsius: temperatureCelsius,
            availableSparePercent: availableSparePercent,
            availableSpareThresholdPercent: availableSpareThresholdPercent,
            terabytesWritten: 10.0,
            terabytesRead: 15.0,
            powerOnHours: 2000,
            powerCycles: 400,
            unsafeShutdowns: 3,
            mediaErrors: mediaErrors,
            errorLogEntries: 0,
            criticalWarnings: criticalWarnings,
            timestamp: baseDate
        )
    }

    // MARK: - Thermal Threshold Evaluations

    func test_ThermalThresholds_Warning_Critical_Emergency() {
        // Normal (55°C) -> No alerts
        let normal = makeMetrics(temperatureCelsius: 55.0)
        XCTAssertTrue(service.evaluateAlerts(metrics: normal, now: baseDate).isEmpty)

        // Warning (60°C) -> High Temp Warning
        let warnMetrics = makeMetrics(temperatureCelsius: 60.5)
        let warnAlerts = service.evaluateAlerts(metrics: warnMetrics, now: baseDate)
        XCTAssertEqual(warnAlerts.count, 1)
        XCTAssertTrue(warnAlerts.first?.contains("HIGH_TEMPERATURE") == true)

        cooldownManager.reset()

        // Critical (65°C) -> Critical Temp Alert
        let critMetrics = makeMetrics(temperatureCelsius: 66.0)
        let critAlerts = service.evaluateAlerts(metrics: critMetrics, now: baseDate)
        XCTAssertEqual(critAlerts.count, 1)
        XCTAssertTrue(critAlerts.first?.contains("CRITICAL_TEMPERATURE") == true)

        cooldownManager.reset()

        // Emergency (72°C) -> Extreme Thermal Alert
        let emergMetrics = makeMetrics(temperatureCelsius: 72.0)
        let emergAlerts = service.evaluateAlerts(metrics: emergMetrics, now: baseDate)
        XCTAssertEqual(emergAlerts.count, 1)
        XCTAssertTrue(emergAlerts.first?.contains("CRITICAL_TEMPERATURE") == true)
    }

    // MARK: - Cooldown & Debounce Suppression

    func test_CooldownSuppression_PreventsSpamWithinWindow() {
        let hotMetrics = makeMetrics(temperatureCelsius: 68.0)

        // Pass 1 at t0 -> Alert fires
        let pass1 = service.evaluateAlerts(metrics: hotMetrics, now: baseDate)
        XCTAssertEqual(pass1.count, 1)

        // Pass 2 at t0 + 60s (within 900s cooldown) -> Alert suppressed
        let pass2 = service.evaluateAlerts(metrics: hotMetrics, now: baseDate.addingTimeInterval(60.0))
        XCTAssertTrue(pass2.isEmpty, "Alert should be suppressed during cooldown")

        // Pass 3 at t0 + 950s (cooldown expired) -> Alert fires again
        let pass3 = service.evaluateAlerts(metrics: hotMetrics, now: baseDate.addingTimeInterval(950.0))
        XCTAssertEqual(pass3.count, 1)
    }

    // MARK: - Wear Milestones (One-Shot Events)

    func test_WearMilestones_TriggerOnceAcrossRepeatedPolls() {
        // Wear reaches 80%
        let m80 = makeMetrics(wearPercentage: 80)
        let alerts1 = service.evaluateAlerts(metrics: m80, now: baseDate)
        XCTAssertTrue(alerts1.contains(where: { $0.contains("WEAR_MILESTONE_80") }))

        // Subsequent poll at 80% wear -> Milestone already acknowledged, should NOT fire again
        let alerts2 = service.evaluateAlerts(metrics: m80, now: baseDate.addingTimeInterval(3600.0))
        XCTAssertFalse(alerts2.contains(where: { $0.contains("WEAR_MILESTONE_80") }))

        // Wear advances to 90% -> Milestone 90 fires
        let m90 = makeMetrics(wearPercentage: 90)
        let alerts3 = service.evaluateAlerts(metrics: m90, now: baseDate.addingTimeInterval(7200.0))
        XCTAssertTrue(alerts3.contains(where: { $0.contains("WEAR_MILESTONE_90") }))
    }

    // MARK: - Spare Capacity & Critical Bitmask Flags

    func test_SpareCapacityAlerts() {
        // Spare drops below 10%
        let lowSpare = makeMetrics(availableSparePercent: 8, availableSpareThresholdPercent: 10)
        let alerts = service.evaluateAlerts(metrics: lowSpare, now: baseDate)
        XCTAssertTrue(alerts.contains(where: { $0.contains("SPARE_CAPACITY_LOW") }))
    }

    func test_CriticalWarningFlags_TriggersIndividualAlerts() {
        // Reliability degraded bitmask
        let relDegraded = makeMetrics(criticalWarnings: .reliabilityDegraded)
        let alertsRel = service.evaluateAlerts(metrics: relDegraded, now: baseDate)
        XCTAssertTrue(alertsRel.contains("CRITICAL_RELIABILITY_DEGRADED"))

        cooldownManager.reset()

        // Read-only bitmask
        let readOnly = makeMetrics(criticalWarnings: .readOnly)
        let alertsRO = service.evaluateAlerts(metrics: readOnly, now: baseDate)
        XCTAssertTrue(alertsRO.contains("CRITICAL_DRIVE_READ_ONLY"))
    }

    func test_MediaErrorsDelta_FiresOnlyWhenCountIncreases() {
        // Initial state: 0 errors -> 5 errors
        let m1 = makeMetrics(mediaErrors: 5)
        let alerts1 = service.evaluateAlerts(metrics: m1, now: baseDate)
        XCTAssertTrue(alerts1.contains("MEDIA_ERRORS_DETECTED: 5"))

        // Next poll: still 5 errors -> No new alert
        let alerts2 = service.evaluateAlerts(metrics: m1, now: baseDate.addingTimeInterval(60.0))
        XCTAssertFalse(alerts2.contains(where: { $0.contains("MEDIA_ERRORS") }))

        // Next poll: increased to 8 errors -> Alert fires
        let m2 = makeMetrics(mediaErrors: 8)
        let alerts3 = service.evaluateAlerts(metrics: m2, now: baseDate.addingTimeInterval(120.0))
        XCTAssertTrue(alerts3.contains("MEDIA_ERRORS_DETECTED: 8"))
    }

    // MARK: - Multi-Category Combined Alerts

    func test_SimultaneousMultiCategoryAlerts_EvaluatesAll() {
        // Drive near EOL: 96% wear, 68°C temp, 6% spare, reliability degraded, 14 media errors
        let emergencyMetrics = makeMetrics(
            wearPercentage: 96,
            temperatureCelsius: 68.0,
            availableSparePercent: 6,
            availableSpareThresholdPercent: 10,
            criticalWarnings: [.availableSpareBelowThreshold, .reliabilityDegraded],
            mediaErrors: 14
        )

        let events = service.evaluateAlertEvents(metrics: emergencyMetrics, now: baseDate)

        XCTAssertGreaterThanOrEqual(events.count, 4)
        XCTAssertTrue(events.contains(where: { $0.ruleKey.contains("temp") }))
        XCTAssertTrue(events.contains(where: { $0.ruleKey.contains("wear") }))
        XCTAssertTrue(events.contains(where: { $0.ruleKey.contains("spare") }))
        XCTAssertTrue(events.contains(where: { $0.ruleKey.contains("media") }))
    }

    func test_AlertSeverity_RankingAndComparison() {
        XCTAssertTrue(AlertSeverity.info < AlertSeverity.warning)
        XCTAssertTrue(AlertSeverity.warning < AlertSeverity.critical)
        XCTAssertTrue(AlertSeverity.critical < AlertSeverity.emergency)
    }
}
