import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService

final class HistoryPersistenceTests: XCTestCase {

    var tempDirectoryURL: URL!
    var tempFileURL: URL!
    var baseDate: Date = Date(timeIntervalSince1970: 1787832000)

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("SSDHealthTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        tempFileURL = tempDirectoryURL.appendingPathComponent("history.json")
        baseDate = Date(timeIntervalSince1970: 1787832000)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        tempFileURL = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeSnapshot(
        offsetSeconds: TimeInterval,
        healthScore: Int = 90,
        wear: Int = 10,
        temp: Double = 38.0,
        tbw: Double = 20.0
    ) -> SSDHistorySnapshot {
        SSDHistorySnapshot(
            timestamp: baseDate.addingTimeInterval(offsetSeconds),
            healthScorePercent: healthScore,
            wearPercentage: wear,
            temperatureCelsius: temp,
            terabytesWritten: tbw,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            criticalWarningsRaw: 0,
            mediaErrors: 0
        )
    }

    // MARK: - Storage Roundtrip & Atomic File Safety

    func test_RecordAndLoad_SingleSnapshot_PersistsToDisk() async throws {
        let actor = HistoryPersistenceActor(storageURL: tempFileURL, driveIdentifier: "disk0_test", ratedTBW: 300.0)
        let snapshot = makeSnapshot(offsetSeconds: 0)

        try await actor.record(snapshot: snapshot)

        let loaded = try await actor.loadHistory()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.healthScorePercent, 90)
        XCTAssertEqual(loaded.first?.terabytesWritten, 20.0)

        // Verify JSON file exists on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func test_RecordMultipleSnapshots_MaintainsChronologicalOrder() async throws {
        let actor = HistoryPersistenceActor(storageURL: tempFileURL, driveIdentifier: "disk0_test", ratedTBW: 300.0)

        for i in 0..<5 {
            let s = makeSnapshot(offsetSeconds: Double(i) * 3600.0, tbw: 20.0 + Double(i) * 0.1)
            try await actor.record(snapshot: s)
        }

        let loaded = try await actor.loadHistory()
        XCTAssertEqual(loaded.count, 5)
        XCTAssertEqual(loaded.last?.terabytesWritten, 20.4)
    }

    func test_ConcurrentRecordOperations_ActorThreadSafety() async throws {
        let actor = HistoryPersistenceActor(storageURL: tempFileURL, driveIdentifier: "disk0_test", ratedTBW: 300.0)
        let now = Date()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let s = SSDHistorySnapshot(
                        timestamp: now.addingTimeInterval(-Double(20 - i) * 60.0),
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
        XCTAssertEqual(loaded.count, 20)
    }

    // MARK: - 4-Tier Temporal Decimation Policy

    func test_Tier1_Last24Hours_RetainsAllRawSamples() {
        var rawSamples: [SSDHistorySnapshot] = []
        // Generate 96 samples (every 15 minutes for 24h)
        for i in 0..<96 {
            let offset = -Double(96 - i) * 900.0 // up to now
            rawSamples.append(makeSnapshot(offsetSeconds: offset))
        }

        let decimated = rawSamples.decimated(relativeTo: baseDate)
        XCTAssertEqual(decimated.count, 96, "Tier 1 must preserve 100% of samples within the last 24h")
    }

    func test_Tier2_24hTo7Days_RetainsOneSamplePerHour() {
        var rawSamples: [SSDHistorySnapshot] = []
        // In the 24h..7d window (days 2 to 7): 4 samples per hour (15m interval)
        // 6 days * 24 hours * 4 = 576 samples
        for hour in 1...144 {
            let hourOffset = -Double(hour) * 3600.0 - 86_400.0 // strictly > 24h ago
            for sub in 0..<4 {
                let offset = hourOffset + Double(sub) * 900.0
                rawSamples.append(makeSnapshot(offsetSeconds: offset))
            }
        }

        let decimated = rawSamples.decimated(relativeTo: baseDate)
        // Should prune 4 samples/hr down to 1 sample/hr (approx 144 samples)
        XCTAssertLessThanOrEqual(decimated.count, 150)
        XCTAssertGreaterThanOrEqual(decimated.count, 140)
    }

    func test_Tier3_7dTo365Days_RetainsOneSamplePerDay() {
        var rawSamples: [SSDHistorySnapshot] = []
        // In the 7d..365d window: 24 samples per day for 100 days
        for day in 8...107 {
            let dayOffset = -Double(day) * 86_400.0
            for hr in 0..<24 {
                let offset = dayOffset + Double(hr) * 900.0
                rawSamples.append(makeSnapshot(offsetSeconds: offset))
            }
        }

        let decimated = rawSamples.decimated(relativeTo: baseDate)
        // 100 days -> pruned to 100 samples
        XCTAssertEqual(decimated.count, 100)
    }

    func test_Tier4_Over365Days_RetainsOneSamplePerWeek() {
        var rawSamples: [SSDHistorySnapshot] = []
        // Over 1 year ago (days 400 to 764): 1 sample per day for 52 weeks (364 days)
        for day in 400..<764 {
            let offset = -Double(day) * 86_400.0
            rawSamples.append(makeSnapshot(offsetSeconds: offset))
        }

        let decimated = rawSamples.decimated(relativeTo: baseDate)
        // 364 days / 7 = 52 weeks -> pruned to ~52-53 samples
        XCTAssertLessThanOrEqual(decimated.count, 55)
        XCTAssertGreaterThanOrEqual(decimated.count, 50)
    }

    func test_Decimation_10000Samples_PerformanceStress() {
        var samples: [SSDHistorySnapshot] = []
        // 10,000 samples over 3 years (1095 days)
        for i in 0..<10_000 {
            let offset = -Double(10_000 - i) * (1095.0 * 86_400.0 / 10_000.0)
            samples.append(makeSnapshot(offsetSeconds: offset, tbw: 10.0 + Double(i) * 0.001))
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = samples.decimated(relativeTo: baseDate)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 0.05, "Decimation of 10,000 samples must take < 50ms")
        XCTAssertLessThan(result.count, 850, "Total sample count should be decimated under 850 points")
    }

    // MARK: - Document Schema, Migration & Recovery

    func test_DocumentSchemaAndMetadataUpdates() async throws {
        let actor = HistoryPersistenceActor(storageURL: tempFileURL, driveIdentifier: "APPLE SSD AP0256Q", ratedTBW: 150.0)
        let doc = try await actor.loadDocument()

        XCTAssertEqual(doc.schemaVersion, 1)
        XCTAssertEqual(doc.driveIdentifier, "APPLE SSD AP0256Q")
        XCTAssertEqual(doc.ratedTBW, 150.0)

        try await actor.updateRatedTBW(200.0)
        let updated = try await actor.loadDocument()
        XCTAssertEqual(updated.ratedTBW, 200.0)
    }

    func test_CorruptedJSONRecovery_GracefullyFallbacksToEmptyDocument() async throws {
        // Write invalid corrupted bytes to history.json
        try "CORRUPTED_NOT_JSON_DATA{{{".write(to: tempFileURL, atomically: true, encoding: .utf8)

        let actor = HistoryPersistenceActor(storageURL: tempFileURL, driveIdentifier: "disk0_recovery", ratedTBW: 300.0)
        let loaded = try await actor.loadHistory()

        XCTAssertTrue(loaded.isEmpty, "Corrupted JSON should gracefully fallback to empty history without crashing")
    }

    func test_PurgeAll_ClearsDiskAndMemory() async throws {
        let actor = HistoryPersistenceActor(storageURL: tempFileURL, driveIdentifier: "disk0", ratedTBW: 300.0)
        try await actor.record(snapshot: makeSnapshot(offsetSeconds: 0))

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        try await actor.purgeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
        let afterPurge = try await actor.loadHistory()
        XCTAssertTrue(afterPurge.isEmpty)
    }
}
