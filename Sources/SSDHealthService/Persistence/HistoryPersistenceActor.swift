import Foundation
import SSDHealthCore

/// Protocol defining the contract for persisting and retrieving SSD historical telemetry.
public protocol HistoryPersistenceProtocol: Sendable {
    /// Records a new snapshot, automatically pruning history via temporal decimation.
    func record(snapshot: SSDHistorySnapshot) async throws

    /// Loads all historical snapshots in chronological order.
    func loadHistory() async throws -> [SSDHistorySnapshot]

    /// Purges all persisted history records from disk.
    func purgeAll() async throws
}

/// Swift Actor providing thread-safe, atomic JSON file persistence for SSD telemetry.
///
/// Stores history in `~/Library/Application Support/SSDHealth/history.json` and performs
/// automatic 4-tier temporal decimation on every record cycle.
public actor HistoryPersistenceActor: HistoryPersistenceProtocol {

    private let fileURL: URL
    private var driveIdentifier: String
    private var ratedTBW: Double
    private var cachedDocument: SSDHistoryStoreDocument?

    /// Initializes the persistence actor with an optional custom file URL for testing.
    public init(
        storageURL: URL? = nil,
        driveIdentifier: String = "primary",
        ratedTBW: Double = 300.0
    ) {
        self.driveIdentifier = driveIdentifier
        self.ratedTBW = ratedTBW

        if let customURL = storageURL {
            self.fileURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("SSDHealth", isDirectory: true)
            self.fileURL = appDir.appendingPathComponent("history.json")
        }
    }

    /// Records a snapshot, applies 4-tier decimation, and atomically commits changes to disk.
    public func record(snapshot: SSDHistorySnapshot) async throws {
        try await record(snapshot: snapshot, relativeTo: Date())
    }

    /// Records a snapshot with an explicit timestamp reference for deterministic testing.
    public func record(snapshot: SSDHistorySnapshot, relativeTo now: Date) async throws {
        var doc = try await loadDocument()

        doc.snapshots.append(snapshot)
        doc.snapshots = doc.snapshots.decimated(relativeTo: now)
        doc.lastUpdated = now

        try await saveDocument(doc)
    }

    /// Loads all historical snapshots in chronological order.
    public func loadHistory() async throws -> [SSDHistorySnapshot] {
        let doc = try await loadDocument()
        return doc.snapshots
    }

    /// Loads the entire root history document, creating a new document if file doesn't exist.
    public func loadDocument() async throws -> SSDHistoryStoreDocument {
        if let cached = cachedDocument {
            return cached
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let initial = SSDHistoryStoreDocument(
                driveIdentifier: driveIdentifier,
                firstRecorded: Date(),
                lastUpdated: Date(),
                ratedTBW: ratedTBW,
                snapshots: []
            )
            self.cachedDocument = initial
            return initial
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let document = try decoder.decode(SSDHistoryStoreDocument.self, from: data)
            self.cachedDocument = document
            self.driveIdentifier = document.driveIdentifier
            self.ratedTBW = document.ratedTBW
            return document
        } catch {
            // If decoding corrupted JSON fails, fallback gracefully to a fresh document while logging
            let fallback = SSDHistoryStoreDocument(
                driveIdentifier: driveIdentifier,
                firstRecorded: Date(),
                lastUpdated: Date(),
                ratedTBW: ratedTBW,
                snapshots: []
            )
            self.cachedDocument = fallback
            return fallback
        }
    }

    /// Updates rated TBW in the persisted store.
    public func updateRatedTBW(_ tbw: Double) async throws {
        var doc = try await loadDocument()
        doc.ratedTBW = tbw
        self.ratedTBW = tbw
        try await saveDocument(doc)
    }

    /// Updates drive identifier in the persisted store.
    public func updateDriveIdentifier(_ identifier: String) async throws {
        var doc = try await loadDocument()
        doc.driveIdentifier = identifier
        self.driveIdentifier = identifier
        try await saveDocument(doc)
    }

    /// Purges all persisted history records from disk and clears the in-memory cache.
    public func purgeAll() async throws {
        cachedDocument = nil
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Manually applies decimation to the stored history.
    public func pruneHistory(relativeTo now: Date = Date()) async throws {
        var doc = try await loadDocument()
        doc.snapshots = doc.snapshots.decimated(relativeTo: now)
        try await saveDocument(doc)
    }

    // MARK: - Private Disk IO Helpers

    private func saveDocument(_ doc: SSDHistoryStoreDocument) async throws {
        self.cachedDocument = doc

        let parentDir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(doc)
        try data.write(to: fileURL, options: [.atomic])
    }
}
