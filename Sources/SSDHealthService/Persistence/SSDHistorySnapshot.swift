import Foundation
import SSDHealthCore

/// Historical measurement snapshot capturing key SMART indicators and wear telemetry at a single point in time.
public struct SSDHistorySnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: Date { timestamp }

    public let timestamp: Date
    public let healthScorePercent: Int
    public let wearPercentage: Int
    public let temperatureCelsius: Double
    public let terabytesWritten: Double
    public let terabytesRead: Double
    public let powerOnHours: UInt64
    public let powerCycles: UInt64
    public let unsafeShutdowns: UInt64
    public let availableSparePercent: Int
    public let availableSpareThresholdPercent: Int
    public let criticalWarningsRaw: UInt8
    public let mediaErrors: UInt64

    public init(
        timestamp: Date,
        healthScorePercent: Int,
        wearPercentage: Int,
        temperatureCelsius: Double,
        terabytesWritten: Double,
        terabytesRead: Double = 0.0,
        powerOnHours: UInt64 = 0,
        powerCycles: UInt64 = 0,
        unsafeShutdowns: UInt64 = 0,
        availableSparePercent: Int,
        availableSpareThresholdPercent: Int = 10,
        criticalWarningsRaw: UInt8 = 0,
        mediaErrors: UInt64 = 0
    ) {
        self.timestamp = timestamp
        self.healthScorePercent = healthScorePercent
        self.wearPercentage = wearPercentage
        self.temperatureCelsius = temperatureCelsius
        self.terabytesWritten = terabytesWritten
        self.terabytesRead = terabytesRead
        self.powerOnHours = powerOnHours
        self.powerCycles = powerCycles
        self.unsafeShutdowns = unsafeShutdowns
        self.availableSparePercent = availableSparePercent
        self.availableSpareThresholdPercent = availableSpareThresholdPercent
        self.criticalWarningsRaw = criticalWarningsRaw
        self.mediaErrors = mediaErrors
    }

    /// Convenience initializer mapping directly from live SSDHealthMetrics.
    public init(from metrics: SSDHealthMetrics) {
        self.timestamp = metrics.timestamp
        self.healthScorePercent = metrics.healthScorePercent
        self.wearPercentage = metrics.wearPercentage
        self.temperatureCelsius = metrics.temperatureCelsius
        self.terabytesWritten = metrics.terabytesWritten
        self.terabytesRead = metrics.terabytesRead
        self.powerOnHours = metrics.powerOnHours
        self.powerCycles = metrics.powerCycles
        self.unsafeShutdowns = metrics.unsafeShutdowns
        self.availableSparePercent = metrics.availableSparePercent
        self.availableSpareThresholdPercent = metrics.availableSpareThresholdPercent
        self.criticalWarningsRaw = metrics.criticalWarnings.rawValue
        self.mediaErrors = metrics.mediaErrors
    }

    // MARK: - Computed Properties

    public var gbWrittenDecimal: Double {
        terabytesWritten * 1_000.0
    }

    public var tbWrittenDecimal: Double {
        terabytesWritten
    }

    public var temperatureFormatted: String {
        String(format: "%.1f °C", temperatureCelsius)
    }

    public var tbwFormatted: String {
        String(format: "%.2f TBW", terabytesWritten)
    }
}

/// Root persistence document with schema versioning for atomic JSON file storage.
public struct SSDHistoryStoreDocument: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var driveIdentifier: String
    public let firstRecorded: Date
    public var lastUpdated: Date
    public var ratedTBW: Double
    public var snapshots: [SSDHistorySnapshot]

    public init(
        schemaVersion: Int = SSDHistoryStoreDocument.currentSchemaVersion,
        driveIdentifier: String,
        firstRecorded: Date = Date(),
        lastUpdated: Date = Date(),
        ratedTBW: Double = 300.0,
        snapshots: [SSDHistorySnapshot] = []
    ) {
        self.schemaVersion = schemaVersion
        self.driveIdentifier = driveIdentifier
        self.firstRecorded = firstRecorded
        self.lastUpdated = lastUpdated
        self.ratedTBW = ratedTBW
        self.snapshots = snapshots
    }
}

// MARK: - 4-Tier Temporal Decimation Extension

public extension Array where Element == SSDHistorySnapshot {

    /// Prunes historical samples according to a 4-tier temporal decimation policy:
    /// - < 24 Hours: 100% of raw samples retained
    /// - 24 Hours to 7 Days: 1 sample per hour
    /// - 7 Days to 365 Days: 1 sample per day
    /// - > 365 Days: 1 sample per week
    func decimated(relativeTo now: Date = Date()) -> [SSDHistorySnapshot] {
        guard self.count > 1 else { return self }

        let sorted = self.sorted { $0.timestamp < $1.timestamp }
        let oneDayAgo = now.addingTimeInterval(-86_400.0)
        let sevenDaysAgo = now.addingTimeInterval(-7.0 * 86_400.0)
        let oneYearAgo = now.addingTimeInterval(-365.0 * 86_400.0)

        var result: [SSDHistorySnapshot] = []
        var lastKeptHourBucket: Int?
        var lastKeptDayBucket: Int?
        var lastKeptWeekBucket: Int?

        let calendar = Calendar.current

        for sample in sorted {
            let t = sample.timestamp

            if t >= oneDayAgo {
                // Tier 1: Retain all raw samples within the last 24 hours
                result.append(sample)
            } else if t >= sevenDaysAgo {
                // Tier 2: Retain 1 sample per hour (24h to 7d)
                let hourBucket = calendar.component(.hour, from: t) + (calendar.ordinality(of: .day, in: .year, for: t) ?? 0) * 24
                if hourBucket != lastKeptHourBucket {
                    result.append(sample)
                    lastKeptHourBucket = hourBucket
                }
            } else if t >= oneYearAgo {
                // Tier 3: Retain 1 sample per day (7d to 365d)
                let dayBucket = calendar.ordinality(of: .day, in: .era, for: t) ?? 0
                if dayBucket != lastKeptDayBucket {
                    result.append(sample)
                    lastKeptDayBucket = dayBucket
                }
            } else {
                // Tier 4: Retain 1 sample per week (> 365d)
                let weekBucket = calendar.component(.weekOfYear, from: t) + calendar.component(.yearForWeekOfYear, from: t) * 52
                if weekBucket != lastKeptWeekBucket {
                    result.append(sample)
                    lastKeptWeekBucket = weekBucket
                }
            }
        }

        return result
    }
}
