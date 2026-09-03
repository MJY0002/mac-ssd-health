import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService

/// Aggressive empirical stress test suite for Milestone 2:
/// - 4-Tier Decimation Engine (10,000 samples, monotonicity, bucket boundaries, leap years, shuffled inputs)
/// - ForecastEngine & OLS Linear Regression (negative slopes, zero deltas, single points, burst writes, timestamp gaps, confidence intervals)
/// - HistoryPersistenceActor (corrupted JSON recovery, schema divergence, atomic writes, concurrent access)
/// - DiagnosticExporter & NotificationService boundary conditions
final class Milestone2_AdversarialStressTests: XCTestCase {

    var baseDate: Date!

    override func setUp() {
        super.setUp()
        baseDate = Date(timeIntervalSince1970: 1787832000) // Deterministic reference date
    }

    override func tearDown() {
        baseDate = nil
        super.tearDown()
    }

    // =========================================================================
    // MARK: - Section 1: Decimation Algorithm Stress Testing (10,000 Samples)
    // =========================================================================

    func test_Decimation_10000Samples_StrictMonotonicityAndReduction() {
        var samples: [SSDHistorySnapshot] = []
        var rng = SplitMix64(seed: 0xDEAD_BEEF_CAFE_0001)

        // Generate 10,000 samples distributed over 3 years (1095 days) in random order
        for i in 0..<10_000 {
            let randomSec = Double(rng.next() % UInt64(1095 * 86_400))
            let t = baseDate.addingTimeInterval(-randomSec)
            let tbw = 1.0 + Double(i) * 0.001
            samples.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: 95,
                wearPercentage: 5,
                temperatureCelsius: 35.0,
                terabytesWritten: tbw,
                availableSparePercent: 100
            ))
        }

        let decimated = samples.decimated(relativeTo: baseDate)

        // 1. Monotonic ordering verification
        XCTAssertGreaterThan(decimated.count, 0)
        for i in 0..<(decimated.count - 1) {
            XCTAssertLessThan(
                decimated[i].timestamp,
                decimated[i + 1].timestamp,
                "Decimated sequence MUST be strictly monotonically ascending. Failed at index \(i)"
            )
        }

        // 2. Data reduction verification (10,000 -> < 850 samples)
        XCTAssertLessThan(decimated.count, 850, "Decimation must compress 10,000 samples to < 850")
        XCTAssertGreaterThan(decimated.count, 50, "Decimation should retain sufficient history across tiers")
    }

    func test_Decimation_BucketBoundaries_ExactTimeDelimitation() {
        // Tiers:
        // Tier 1 (< 24h): 100% retained
        // Tier 2 (24h to 7d): 1 sample / hr
        // Tier 3 (7d to 365d): 1 sample / day
        // Tier 4 (> 365d): 1 sample / week

        let exact24hAgo = baseDate.addingTimeInterval(-86_400.0)
        let exact7dAgo = baseDate.addingTimeInterval(-7.0 * 86_400.0)
        let exact365dAgo = baseDate.addingTimeInterval(-365.0 * 86_400.0)

        // 10 samples within Tier 1 (< 24h), 1 minute apart
        var tier1: [SSDHistorySnapshot] = []
        for m in 1...10 {
            tier1.append(SSDHistorySnapshot(
                timestamp: baseDate.addingTimeInterval(-Double(m) * 60.0),
                healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 30.0,
                terabytesWritten: 1.0, availableSparePercent: 100
            ))
        }

        // Generate 10 samples within Tier 2 (all within same hour, e.g. 48h ago)
        var tier2SameHour: [SSDHistorySnapshot] = []
        let t2Base = baseDate.addingTimeInterval(-48.0 * 3600.0)
        for m in 1...10 {
            tier2SameHour.append(SSDHistorySnapshot(
                timestamp: t2Base.addingTimeInterval(Double(m) * 60.0),
                healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 30.0,
                terabytesWritten: 1.0, availableSparePercent: 100
            ))
        }

        // Generate 10 samples within Tier 3 (all within same 4-hour span on day 30, strictly within same calendar day)
        var tier3SameDay: [SSDHistorySnapshot] = []
        let t3Base = baseDate.addingTimeInterval(-30.0 * 86_400.0)
        for m in 1...10 {
            tier3SameDay.append(SSDHistorySnapshot(
                timestamp: t3Base.addingTimeInterval(Double(m) * 60.0),
                healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 30.0,
                terabytesWritten: 1.0, availableSparePercent: 100
            ))
        }

        // Generate 10 samples within Tier 4 (all within same 2-hour span on day 400, strictly within same calendar week)
        var tier4SameWeek: [SSDHistorySnapshot] = []
        let t4Base = baseDate.addingTimeInterval(-400.0 * 86_400.0)
        for m in 1...10 {
            tier4SameWeek.append(SSDHistorySnapshot(
                timestamp: t4Base.addingTimeInterval(Double(m) * 60.0),
                healthScorePercent: 100, wearPercentage: 0, temperatureCelsius: 30.0,
                terabytesWritten: 1.0, availableSparePercent: 100
            ))
        }

        let allSamples = tier1 + tier2SameHour + tier3SameDay + tier4SameWeek
        let decimated = allSamples.decimated(relativeTo: baseDate)

        // Tier 1 verification: all 10 raw samples kept
        let retainedTier1 = decimated.filter { $0.timestamp >= exact24hAgo }
        XCTAssertEqual(retainedTier1.count, 10, "All raw samples in Tier 1 (<24h) must be retained")

        // Tier 2 verification: exactly 1 sample kept for that single hour
        let retainedTier2 = decimated.filter { $0.timestamp >= exact7dAgo && $0.timestamp < exact24hAgo }
        XCTAssertEqual(retainedTier2.count, 1, "Only 1 sample per hour in Tier 2 must be retained")

        // Tier 3 verification: exactly 1 sample kept for that single day
        let retainedTier3 = decimated.filter { $0.timestamp >= exact365dAgo && $0.timestamp < exact7dAgo }
        XCTAssertEqual(retainedTier3.count, 1, "Only 1 sample per day in Tier 3 must be retained")

        // Tier 4 verification: exactly 1 sample kept for that single week
        let retainedTier4 = decimated.filter { $0.timestamp < exact365dAgo }
        XCTAssertEqual(retainedTier4.count, 1, "Only 1 sample per week in Tier 4 must be retained")
    }

    func test_Decimation_EdgeCases_EmptyAndSingleElement() {
        let empty: [SSDHistorySnapshot] = []
        XCTAssertTrue(empty.decimated(relativeTo: baseDate).isEmpty)

        let single = [SSDHistorySnapshot(
            timestamp: baseDate, healthScorePercent: 100, wearPercentage: 0,
            temperatureCelsius: 30.0, terabytesWritten: 1.0, availableSparePercent: 100
        )]
        let decimatedSingle = single.decimated(relativeTo: baseDate)
        XCTAssertEqual(decimatedSingle.count, 1)
        XCTAssertEqual(decimatedSingle.first?.timestamp, baseDate)
    }

    func test_Decimation_LeapYearAndCrossingBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let leapDate = calendar.date(from: DateComponents(year: 2028, month: 3, day: 1, hour: 12))!

        var samples: [SSDHistorySnapshot] = []
        // Feb 28, Feb 29 (leap day), March 1
        for hour in 0..<72 {
            let t = leapDate.addingTimeInterval(-Double(hour) * 3600.0)
            samples.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 95, wearPercentage: 5,
                temperatureCelsius: 35.0, terabytesWritten: 10.0 + Double(hour) * 0.01,
                availableSparePercent: 100
            ))
        }

        let decimated = samples.decimated(relativeTo: leapDate)
        XCTAssertFalse(decimated.isEmpty)
        for i in 0..<(decimated.count - 1) {
            XCTAssertLessThan(decimated[i].timestamp, decimated[i + 1].timestamp)
        }
    }

    // =========================================================================
    // MARK: - Section 2: Forecast Engine & OLS Linear Regression Stress Tests
    // =========================================================================

    private func makeMetrics(
        wearPercentage: Int = 10,
        terabytesWritten: Double = 10.0,
        powerOnHours: UInt64 = 2000,
        capacityBytes: UInt64 = 512_000_000_000,
        timestamp: Date? = nil
    ) -> SSDHealthMetrics {
        SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0512Q",
            serialNumber: "SN-M2-STRESS",
            firmwareRevision: "1.0",
            interconnect: "Apple Fabric",
            capacityBytes: capacityBytes,
            healthScorePercent: max(0, 100 - wearPercentage),
            wearPercentage: wearPercentage,
            temperatureCelsius: 38.0,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: terabytesWritten,
            terabytesRead: terabytesWritten * 1.5,
            powerOnHours: powerOnHours,
            powerCycles: 300,
            unsafeShutdowns: 3,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: timestamp ?? baseDate
        )
    }

    func test_OLS_NegativeSlope_GracefullyClampedToZero() {
        let engine = ForecastEngine()
        // Anomaly: 10 data points with decreasing TBW
        var history: [SSDHistorySnapshot] = []
        for i in 0..<10 {
            let t = baseDate.addingTimeInterval(-Double(10 - i) * 86_400.0)
            let tbw = 20.0 - Double(i) * 0.5 // Decreasing TBW
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 90, wearPercentage: 10,
                temperatureCelsius: 38.0, terabytesWritten: tbw, availableSparePercent: 100
            ))
        }

        let metrics = makeMetrics(terabytesWritten: 15.0, powerOnHours: 2000)
        let result = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(result.dailyWriteRate7dGB, 0.0, accuracy: 0.001, "Negative OLS slope must be clamped to 0.0")
        XCTAssertEqual(result.dailyWriteRate30dGB, 0.0, accuracy: 0.001, "Negative OLS slope must be clamped to 0.0")
        XCTAssertGreaterThanOrEqual(result.confidenceInterval95.lowerGB, 0.0)
        XCTAssertGreaterThanOrEqual(result.confidenceInterval95.upperGB, 0.0)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isNaN)
        XCTAssertFalse(result.primaryDailyWriteRateGB.isInfinite)
    }

    func test_OLS_ZeroDeltas_IdenticalTimestampsAndFlatline() {
        let engine = ForecastEngine()

        // Case A: Identical timestamps (zero time delta -> den = 0)
        let identicalTimestamps = [
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 10.5, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 11.0, availableSparePercent: 100)
        ]

        let metricsA = makeMetrics(terabytesWritten: 11.0, powerOnHours: 1000)
        let resultA = engine.calculateForecast(current: metricsA, history: identicalTimestamps, ratedTBW: 300.0, referenceDate: baseDate)

        // Must fallback to lifetime write rate without crashing
        XCTAssertFalse(resultA.primaryDailyWriteRateGB.isNaN)
        XCTAssertEqual(resultA.primaryDailyWriteRateGB, resultA.dailyWriteRateLifetimeGB, accuracy: 0.01)

        // Case B: Identical TBW (flatline zero writes -> beta = 0)
        var flatline: [SSDHistorySnapshot] = []
        for i in 0..<10 {
            let t = baseDate.addingTimeInterval(-Double(10 - i) * 86_400.0)
            flatline.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 99, wearPercentage: 1,
                temperatureCelsius: 32.0, terabytesWritten: 5.0, availableSparePercent: 100
            ))
        }

        let metricsB = makeMetrics(terabytesWritten: 5.0, powerOnHours: 1000)
        let resultB = engine.calculateForecast(current: metricsB, history: flatline, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(resultB.dailyWriteRate7dGB, 0.0, accuracy: 0.001)
        XCTAssertEqual(resultB.dailyWriteRate30dGB, 0.0, accuracy: 0.001)
        XCTAssertTrue(resultB.estimatedDaysRemaining.isInfinite)
        XCTAssertTrue(resultB.estimatedYearsRemaining.isInfinite)
        XCTAssertNil(resultB.estimatedExhaustionDate)
        XCTAssertEqual(resultB.degradationStatus, .stable)
    }

    func test_OLS_SinglePointAndEmptyHistory_SafeLifetimeFallback() {
        let engine = ForecastEngine()
        let metrics = makeMetrics(terabytesWritten: 24.0, powerOnHours: 2000)

        // 0 historical points
        let resEmpty = engine.calculateForecast(current: metrics, history: [], ratedTBW: 300.0, referenceDate: baseDate)
        XCTAssertEqual(resEmpty.degradationStatus, .insufficientData)
        let expectedLifetimeGB = (24_000.0 / 2000.0) * 24.0 // 288.0 GB/day
        XCTAssertEqual(resEmpty.dailyWriteRateLifetimeGB, expectedLifetimeGB, accuracy: 0.01)
        XCTAssertEqual(resEmpty.primaryDailyWriteRateGB, expectedLifetimeGB, accuracy: 0.01)

        // 1 historical point
        let single = [SSDHistorySnapshot(
            timestamp: baseDate, healthScorePercent: 95, wearPercentage: 5,
            temperatureCelsius: 35.0, terabytesWritten: 24.0, availableSparePercent: 100
        )]
        let resSingle = engine.calculateForecast(current: metrics, history: single, ratedTBW: 300.0, referenceDate: baseDate)
        XCTAssertEqual(resSingle.degradationStatus, .insufficientData)
        XCTAssertEqual(resSingle.primaryDailyWriteRateGB, expectedLifetimeGB, accuracy: 0.01)
    }

    func test_OLS_BurstWrites_ExtremeSlopeAndDegradationState() {
        let engine = ForecastEngine()

        // 1. Micro-burst: 10 TB written in 2 hours (span < 24h)
        let microBurstHistory = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-7200), healthScorePercent: 80, wearPercentage: 20, temperatureCelsius: 55.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-3600), healthScorePercent: 78, wearPercentage: 22, temperatureCelsius: 58.0, terabytesWritten: 15.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 75, wearPercentage: 25, temperatureCelsius: 60.0, terabytesWritten: 20.0, availableSparePercent: 100)
        ]

        let metricsMicro = makeMetrics(wearPercentage: 25, terabytesWritten: 20.0, powerOnHours: 500)
        let resultMicro = engine.calculateForecast(current: metricsMicro, history: microBurstHistory, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertGreaterThan(resultMicro.primaryDailyWriteRateGB, 10_000.0)
        XCTAssertFalse(resultMicro.estimatedDaysRemaining.isNaN)
        XCTAssertLessThan(resultMicro.estimatedDaysRemaining, 30.0)
        // Span < 24h is safely guarded against false-positive degradation alerts:
        XCTAssertEqual(resultMicro.degradationStatus, .insufficientData)

        // 2. Sustained heavy burst: 3 days of 400 GB/day writes with constant wear (Model B, span >= 24h)
        let sustainedHistory = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-3 * 86_400), healthScorePercent: 75, wearPercentage: 25, temperatureCelsius: 50.0, terabytesWritten: 18.8, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-2 * 86_400), healthScorePercent: 75, wearPercentage: 25, temperatureCelsius: 51.0, terabytesWritten: 19.2, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-1 * 86_400), healthScorePercent: 75, wearPercentage: 25, temperatureCelsius: 52.0, terabytesWritten: 19.6, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 75, wearPercentage: 25, temperatureCelsius: 53.0, terabytesWritten: 20.0, availableSparePercent: 100)
        ]

        let metricsSustained = makeMetrics(wearPercentage: 25, terabytesWritten: 20.0, powerOnHours: 1000)
        let resultSustained = engine.calculateForecast(current: metricsSustained, history: sustainedHistory, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(resultSustained.primaryDailyWriteRateGB, 400.0, accuracy: 5.0)
        XCTAssertEqual(resultSustained.degradationStatus, .acceleratedWear, "Sustained >200 GB/day over multiple days with lifespan < 2y must trigger acceleratedWear")

        // 3. Rapid wear progression (Model A: 5% wear consumed in 3 days -> 45 days remaining -> criticalWear)
        let rapidWearHistory = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-3 * 86_400), healthScorePercent: 80, wearPercentage: 20, temperatureCelsius: 50.0, terabytesWritten: 18.8, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 75, wearPercentage: 25, temperatureCelsius: 53.0, terabytesWritten: 20.0, availableSparePercent: 100)
        ]
        let resultRapid = engine.calculateForecast(current: metricsSustained, history: rapidWearHistory + [sustainedHistory[1]], ratedTBW: 300.0, referenceDate: baseDate)
        XCTAssertEqual(resultRapid.degradationStatus, .criticalWear, "Rapid wear increase yielding <90 days remaining must trigger criticalWear")
    }

    func test_OLS_TimestampGaps_IrregularSamplingAndUnorderedInput() {
        let engine = ForecastEngine()

        // Irregular intervals: 20 days ago, 5 days ago, 5 min ago, 1 sec ago
        let irregularHistory = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-20 * 86_400), healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 35.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-5 * 86_400), healthScorePercent: 94, wearPercentage: 6, temperatureCelsius: 36.0, terabytesWritten: 10.3, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-300), healthScorePercent: 94, wearPercentage: 6, temperatureCelsius: 36.0, terabytesWritten: 10.4, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-1), healthScorePercent: 94, wearPercentage: 6, temperatureCelsius: 36.0, terabytesWritten: 10.41, availableSparePercent: 100)
        ]

        let reversedHistory = Array(irregularHistory.reversed())
        let metrics = makeMetrics(wearPercentage: 6, terabytesWritten: 10.41, powerOnHours: 1000)

        let resultNormal = engine.calculateForecast(current: metrics, history: irregularHistory, ratedTBW: 300.0, referenceDate: baseDate)
        let resultReversed = engine.calculateForecast(current: metrics, history: reversedHistory, ratedTBW: 300.0, referenceDate: baseDate)

        // Engine must sort internally and produce identical rates
        XCTAssertEqual(resultNormal.primaryDailyWriteRateGB, resultReversed.primaryDailyWriteRateGB, accuracy: 0.001)
        XCTAssertEqual(resultNormal.estimatedDaysRemaining, resultReversed.estimatedDaysRemaining, accuracy: 0.001)
    }

    // =========================================================================
    // MARK: - Section 3: HistoryPersistenceActor Corrupted JSON Recovery
    // =========================================================================

    func test_Persistence_CorruptedJSONRecovery_AllCorruptionVariants() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M2StressPersistence_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFileURL = tempDir.appendingPathComponent("corrupted_history.json")

        let corruptPayloads: [(name: String, data: Data)] = [
            ("Empty 0-byte file", Data()),
            ("Truncated JSON object", Data("{\"schemaVersion\": 1, \"driveIdentifier\": \"disk0\", \"snapshots\": [{\"wear\"".utf8)),
            ("Invalid syntax", Data("{{{ NOT JSON DATA }}}".utf8)),
            ("Root is JSON Array", Data("[1, 2, 3, 4]".utf8)),
            ("Root is JSON String", Data("\"just a string\"".utf8)),
            ("Schema type mismatch", Data("{\"schemaVersion\": \"v1\", \"snapshots\": 12345}".utf8)),
            ("Binary garbage bytes", Data([0x00, 0xFF, 0xFE, 0x12, 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE]))
        ]

        for (name, payload) in corruptPayloads {
            try payload.write(to: testFileURL, options: .atomic)

            let actor = HistoryPersistenceActor(storageURL: testFileURL, driveIdentifier: "disk0_recover", ratedTBW: 300.0)
            let loaded = try await actor.loadHistory()
            XCTAssertTrue(loaded.isEmpty, "Corruption variant '\(name)' must recover gracefully to empty history")

            // Test resumption of normal persistence after corruption
            let snapshot = SSDHistorySnapshot(
                timestamp: baseDate,
                healthScorePercent: 92,
                wearPercentage: 8,
                temperatureCelsius: 36.0,
                terabytesWritten: 12.5,
                availableSparePercent: 100
            )
            try await actor.record(snapshot: snapshot, relativeTo: baseDate)

            // Re-instantiate new actor to guarantee disk read
            let freshActor = HistoryPersistenceActor(storageURL: testFileURL, driveIdentifier: "disk0_recover", ratedTBW: 300.0)
            let reloaded = try await freshActor.loadHistory()
            XCTAssertEqual(reloaded.count, 1, "Actor should successfully write and reload valid history after '\(name)'")
            XCTAssertEqual(reloaded.first?.terabytesWritten, 12.5)

            // Verify disk JSON is syntactically valid
            let onDisk = try Data(contentsOf: testFileURL)
            let parsed = try JSONSerialization.jsonObject(with: onDisk, options: []) as? [String: Any]
            XCTAssertNotNil(parsed)
            XCTAssertEqual(parsed?["schemaVersion"] as? Int, 1)
        }
    }

    func test_Persistence_ConcurrentCorruptedRecovery_ThreadSafety() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("M2StressPersistence_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFileURL = tempDir.appendingPathComponent("concurrent_corrupt.json")
        try "CORRUPT_BYTES_DATA".write(to: testFileURL, atomically: true, encoding: .utf8)

        let actor = HistoryPersistenceActor(storageURL: testFileURL, driveIdentifier: "disk0_concur", ratedTBW: 300.0)
        let now = Date()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    let s = SSDHistorySnapshot(
                        timestamp: now.addingTimeInterval(-Double(30 - i) * 60.0),
                        healthScorePercent: 95,
                        wearPercentage: 5,
                        temperatureCelsius: 36.0,
                        terabytesWritten: 10.0 + Double(i) * 0.01,
                        availableSparePercent: 100
                    )
                    try? await actor.record(snapshot: s, relativeTo: now)
                }
            }
        }

        let loaded = try await actor.loadHistory()
        XCTAssertEqual(loaded.count, 30)
    }

    // =========================================================================
    // MARK: - Section 4: Diagnostic Exporter & Notifications Boundary Tests
    // =========================================================================

    func test_DiagnosticExporter_SanitizesInfinitiesInJSON() throws {
        let exporter = DiagnosticExporter()
        let metrics = makeMetrics(wearPercentage: 0, terabytesWritten: 0.0, powerOnHours: 1)
        let infiniteForecast = SSDForecastResult(
            dailyWriteRate7dGB: 0.0,
            dailyWriteRate30dGB: 0.0,
            dailyWriteRateLifetimeGB: 0.0,
            primaryDailyWriteRateGB: 0.0,
            estimatedDaysRemaining: Double.infinity,
            estimatedYearsRemaining: Double.infinity,
            estimatedExhaustionDate: nil,
            degradationStatus: .stable,
            confidenceInterval95: ConfidenceInterval95(lowerGB: 0.0, upperGB: 0.0)
        )

        let json = try exporter.exportJSON(metrics: metrics, history: [], forecast: infiniteForecast)
        XCTAssertFalse(json.isEmpty)

        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        let fDict = obj?["forecast"] as? [String: Any]
        XCTAssertEqual(fDict?["estimatedDaysRemaining"] as? Double, -1.0)
        XCTAssertEqual(fDict?["estimatedYearsRemaining"] as? Double, -1.0)
    }

    func test_NotificationService_ThresholdBoundaries() {
        let cooldownManager = AlertCooldownManager(userDefaults: nil)
        let service = NotificationService(cooldownManager: cooldownManager, notificationCenter: nil)

        // Normal metrics
        let normal = makeMetrics(wearPercentage: 10, terabytesWritten: 10.0)
        let normalAlerts = service.evaluateAlerts(metrics: normal, now: baseDate)
        XCTAssertTrue(normalAlerts.isEmpty)

        // Wear 80% milestone
        let wear80 = makeMetrics(wearPercentage: 80, terabytesWritten: 100.0)
        let alerts80 = service.evaluateAlerts(metrics: wear80, now: baseDate)
        XCTAssertEqual(alerts80.count, 1)
        XCTAssertTrue(alerts80.first?.contains("WEAR_MILESTONE_80") == true)
    }
}

// MARK: - Deterministic PRNG Helper

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
