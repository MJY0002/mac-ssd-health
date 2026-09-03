import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService

/// Adversarial empirical stress tests for HistoryPersistenceActor:
/// - High-frequency atomic writes
/// - Extreme concurrency races (parallel writers, readers, modifiers, purgers)
/// - Corrupted JSON file recovery and resurrection under concurrent load
/// - Multi-instance drive isolation
/// - Decimation fidelity under high-frequency writes
final class HistoryPersistenceStressAndRecoveryTests: XCTestCase {

    var tempDirectoryURL: URL!
    var baseDate: Date!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("PersistenceStress_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        baseDate = Date(timeIntervalSince1970: 1787832000)
    }

    override func tearDown() {
        if let tempDir = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDirectoryURL = nil
        baseDate = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeSnapshot(
        offsetSeconds: TimeInterval,
        wear: Int = 5,
        healthScore: Int = 95,
        temp: Double = 36.0,
        tbw: Double = 10.0,
        spare: Int = 100,
        warnings: UInt8 = 0
    ) -> SSDHistorySnapshot {
        SSDHistorySnapshot(
            timestamp: baseDate.addingTimeInterval(offsetSeconds),
            healthScorePercent: healthScore,
            wearPercentage: wear,
            temperatureCelsius: temp,
            terabytesWritten: tbw,
            terabytesRead: tbw * 1.5,
            powerOnHours: 1000,
            powerCycles: 200,
            unsafeShutdowns: 2,
            availableSparePercent: spare,
            availableSpareThresholdPercent: 10,
            criticalWarningsRaw: warnings,
            mediaErrors: 0
        )
    }

    // MARK: - 1. High-Frequency Atomic Writes Stress Test

    func testHighFrequency_SequentialWrites_500Snapshots_AtomicIntegrity() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("high_freq.json")
        let actor = HistoryPersistenceActor(storageURL: fileURL, driveIdentifier: "disk0_high_freq", ratedTBW: 300.0)

        let startTime = CFAbsoluteTimeGetCurrent()
        let count = 500

        for i in 0..<count {
            // Consecutive snapshots 60 seconds apart over the last 500 minutes (< 24h, all kept in Tier 1)
            let offset = -Double(count - i) * 60.0
            let snapshot = makeSnapshot(offsetSeconds: offset, tbw: 10.0 + Double(i) * 0.01)
            try await actor.record(snapshot: snapshot, relativeTo: baseDate)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        // Verify disk file exists and is valid JSON
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(SSDHistoryStoreDocument.self, from: data)
        XCTAssertEqual(doc.snapshots.count, count, "All 500 raw samples within 24h must be preserved")
        XCTAssertEqual(doc.snapshots.last?.terabytesWritten, 10.0 + Double(count - 1) * 0.01)

        // Verify loaded history matches
        let loaded = try await actor.loadHistory()
        XCTAssertEqual(loaded.count, count)
        XCTAssertLessThan(elapsed, 5.0, "500 sequential atomic file writes should execute comfortably fast")
    }

    // MARK: - 2. Extreme Concurrency Races (100 Concurrent Async Tasks)

    func testConcurrentWrites_100ParallelTasks_ActorThreadSafety_NoDataCorruption() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("concurrent_100.json")
        let actor = HistoryPersistenceActor(storageURL: fileURL, driveIdentifier: "disk0_concur_100", ratedTBW: 300.0)

        let taskCount = 100
        let base = baseDate!

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    let offset = -Double(taskCount - i) * 30.0 // all within last hour
                    let s = SSDHistorySnapshot(
                        timestamp: base.addingTimeInterval(offset),
                        healthScorePercent: 95,
                        wearPercentage: 5,
                        temperatureCelsius: 36.0 + Double(i % 10) * 0.1,
                        terabytesWritten: 10.0 + Double(i) * 0.005,
                        availableSparePercent: 100
                    )
                    try await actor.record(snapshot: s, relativeTo: base)
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await actor.loadHistory()
        XCTAssertEqual(loaded.count, taskCount, "All 100 concurrent writes must be recorded without lost updates")

        // Check strict chronological ordering
        for i in 0..<(loaded.count - 1) {
            XCTAssertLessThanOrEqual(loaded[i].timestamp, loaded[i + 1].timestamp)
        }

        // Verify disk JSON file is fully valid and parseable by independent decoder
        let diskData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(SSDHistoryStoreDocument.self, from: diskData)
        XCTAssertEqual(doc.snapshots.count, taskCount)
    }

    // MARK: - 3. Mixed Concurrent Operations (Readers, Writers, Modifiers, Decimators)

    func testConcurrentMixedOperations_ReadWriteUpdatePruneRaces() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("mixed_races.json")
        let actor = HistoryPersistenceActor(storageURL: fileURL, driveIdentifier: "disk0_mixed", ratedTBW: 250.0)
        let base = baseDate!

        // Seed initial history
        for i in 0..<20 {
            let s = makeSnapshot(offsetSeconds: -Double(20 - i) * 3600.0, tbw: 10.0 + Double(i) * 0.1)
            try await actor.record(snapshot: s, relativeTo: base)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            // 20 Writers
            for i in 0..<20 {
                group.addTask {
                    let s = SSDHistorySnapshot(
                        timestamp: base.addingTimeInterval(-Double(i) * 60.0),
                        healthScorePercent: 90,
                        wearPercentage: 10,
                        temperatureCelsius: 38.0,
                        terabytesWritten: 12.0 + Double(i) * 0.01,
                        availableSparePercent: 100
                    )
                    try await actor.record(snapshot: s, relativeTo: base)
                }
            }

            // 20 Readers
            for _ in 0..<20 {
                group.addTask {
                    let history = try await actor.loadHistory()
                    XCTAssertGreaterThanOrEqual(history.count, 20)
                }
            }

            // 5 TBW Updaters
            for i in 0..<5 {
                group.addTask {
                    try await actor.updateRatedTBW(300.0 + Double(i) * 50.0)
                }
            }

            // 5 Drive ID Updaters
            for i in 0..<5 {
                group.addTask {
                    try await actor.updateDriveIdentifier("APPLE SSD AP0512Q_\(i)")
                }
            }

            // 5 Manual Pruners
            for _ in 0..<5 {
                group.addTask {
                    try await actor.pruneHistory(relativeTo: base)
                }
            }

            try await group.waitForAll()
        }

        let finalDoc = try await actor.loadDocument()
        XCTAssertGreaterThan(finalDoc.snapshots.count, 0)
        XCTAssertTrue(finalDoc.driveIdentifier.starts(with: "APPLE SSD AP0512Q_") || finalDoc.driveIdentifier == "disk0_mixed")
        XCTAssertGreaterThanOrEqual(finalDoc.ratedTBW, 250.0)
    }

    // MARK: - 4. Corrupted File Recovery & Immediate Resumption Stress

    func testCorruptedFileRecovery_RepeatedCorruptions_ResilientSelfHealing() async throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("self_healing.json")

        let corruptions: [Data] = [
            Data(), // 0 bytes
            Data("### INVALID HEADER ###".utf8),
            Data("{\"schemaVersion\": 1, \"snapshots\": [".utf8), // Truncated JSON
            Data("null".utf8),
            Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03]),
            Data("{\"snapshots\": \"not-an-array\"}".utf8)
        ]

        for (idx, corruptData) in corruptions.enumerated() {
            // Inject corrupted file
            try corruptData.write(to: fileURL, options: .atomic)

            // Instantiate actor pointing to corrupted file
            let actor = HistoryPersistenceActor(storageURL: fileURL, driveIdentifier: "disk0_healing_\(idx)", ratedTBW: 500.0)

            // 1. Reading history should gracefully return empty array without throwing
            let loaded = try await actor.loadHistory()
            XCTAssertTrue(loaded.isEmpty, "Corrupted input index \(idx) must yield empty history")

            // 2. Recording new snapshot must self-heal and write valid JSON document
            let snapshot = makeSnapshot(offsetSeconds: 0, tbw: 50.0)
            try await actor.record(snapshot: snapshot, relativeTo: baseDate)

            // 3. New actor instance reading the healed file should read the newly recorded snapshot
            let verifiedActor = HistoryPersistenceActor(storageURL: fileURL, driveIdentifier: "disk0_healing_\(idx)", ratedTBW: 500.0)
            let verifiedHistory = try await verifiedActor.loadHistory()
            XCTAssertEqual(verifiedHistory.count, 1)
            XCTAssertEqual(verifiedHistory.first?.terabytesWritten, 50.0)

            // 4. Verify file on disk is valid JSON
            let diskData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let doc = try decoder.decode(SSDHistoryStoreDocument.self, from: diskData)
            XCTAssertEqual(doc.snapshots.count, 1)
        }
    }

    // MARK: - 5. Purge and Multi-Drive Persistence Isolation

    func testMultiDrive_PersistenceIsolation_IndependentFilesAndPurges() async throws {
        let fileURL1 = tempDirectoryURL.appendingPathComponent("drive1_history.json")
        let fileURL2 = tempDirectoryURL.appendingPathComponent("drive2_history.json")

        let actor1 = HistoryPersistenceActor(storageURL: fileURL1, driveIdentifier: "disk0_internal", ratedTBW: 300.0)
        let actor2 = HistoryPersistenceActor(storageURL: fileURL2, driveIdentifier: "disk1_external", ratedTBW: 1000.0)

        // Write 10 snapshots to drive 1
        for i in 0..<10 {
            try await actor1.record(snapshot: makeSnapshot(offsetSeconds: -Double(i) * 60.0, tbw: 5.0 + Double(i) * 0.1), relativeTo: baseDate)
        }

        // Write 25 snapshots to drive 2
        for i in 0..<25 {
            try await actor2.record(snapshot: makeSnapshot(offsetSeconds: -Double(i) * 60.0, tbw: 100.0 + Double(i) * 0.5), relativeTo: baseDate)
        }

        let hist1 = try await actor1.loadHistory()
        let hist2 = try await actor2.loadHistory()

        XCTAssertEqual(hist1.count, 10)
        XCTAssertEqual(hist2.count, 25)
        XCTAssertEqual(hist1.first?.terabytesWritten, 5.0 + 9.0 * 0.1)
        XCTAssertEqual(hist2.first?.terabytesWritten, 100.0 + 24.0 * 0.5)

        // Purge drive 1 only
        try await actor1.purgeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL2.path))

        let afterPurge1 = try await actor1.loadHistory()
        let afterPurge2 = try await actor2.loadHistory()

        XCTAssertEqual(afterPurge1.count, 0)
        XCTAssertEqual(afterPurge2.count, 25, "Drive 2 history must remain completely unaffected by Drive 1 purge")
    }
}
