import Foundation
import XCTest
@testable import SSDHealthCore

// MARK: - Synthetic NVMe 512-Byte Binary Test Fixtures

/// Authoritative generator of standard 512-byte NVMe SMART / Health Information Log Pages (Log ID 0x02).
/// Conforms to NVM Express Base Specification Revision 1.0c through 2.0.
public enum SyntheticNVMeFixtures {

    /// Constructs a fully customized 512-byte raw binary NVMe SMART log buffer.
    public static func makeBuffer(
        criticalWarning: UInt8 = 0,
        temperatureKelvin: UInt16 = 311, // 37.85°C (38°C)
        availableSparePercent: UInt8 = 100,
        availableSpareThresholdPercent: UInt8 = 10,
        percentageUsed: UInt8 = 0,
        enduranceGroupSummary: UInt8 = 0,
        dataUnitsRead: UInt128Value = UInt128Value(low: 0, high: 0),
        dataUnitsWritten: UInt128Value = UInt128Value(low: 0, high: 0),
        hostReadCommands: UInt128Value = UInt128Value(low: 0, high: 0),
        hostWriteCommands: UInt128Value = UInt128Value(low: 0, high: 0),
        controllerBusyTimeMinutes: UInt128Value = UInt128Value(low: 0, high: 0),
        powerCycles: UInt128Value = UInt128Value(low: 0, high: 0),
        powerOnHours: UInt128Value = UInt128Value(low: 0, high: 0),
        unsafeShutdowns: UInt128Value = UInt128Value(low: 0, high: 0),
        mediaErrors: UInt128Value = UInt128Value(low: 0, high: 0),
        numErrorInfoLogEntries: UInt128Value = UInt128Value(low: 0, high: 0),
        warningCompositeTempTimeMinutes: UInt32 = 0,
        criticalCompositeTempTimeMinutes: UInt32 = 0,
        temperatureSensorsKelvin: [UInt16] = [0, 0, 0, 0, 0, 0, 0, 0],
        thermalManagementTemp1TransitionCount: UInt32 = 0,
        thermalManagementTemp2TransitionCount: UInt32 = 0,
        totalTimeForThermalManagementTemp1Seconds: UInt32 = 0,
        totalTimeForThermalManagementTemp2Seconds: UInt32 = 0
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)

        bytes[0] = criticalWarning

        func writeUInt16(offset: Int, val: UInt16) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<2 { bytes[offset + i] = raw[i] }
            }
        }

        func writeUInt32(offset: Int, val: UInt32) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<4 { bytes[offset + i] = raw[i] }
            }
        }

        func writeUInt64(offset: Int, val: UInt64) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<8 { bytes[offset + i] = raw[i] }
            }
        }

        func writeUInt128(offset: Int, val: UInt128Value) {
            writeUInt64(offset: offset, val: val.low)
            writeUInt64(offset: offset + 8, val: val.high)
        }

        writeUInt16(offset: 1, val: temperatureKelvin)
        bytes[3] = availableSparePercent
        bytes[4] = availableSpareThresholdPercent
        bytes[5] = percentageUsed
        bytes[6] = enduranceGroupSummary

        writeUInt128(offset: 32, val: dataUnitsRead)
        writeUInt128(offset: 48, val: dataUnitsWritten)
        writeUInt128(offset: 64, val: hostReadCommands)
        writeUInt128(offset: 80, val: hostWriteCommands)
        writeUInt128(offset: 96, val: controllerBusyTimeMinutes)
        writeUInt128(offset: 112, val: powerCycles)
        writeUInt128(offset: 128, val: powerOnHours)
        writeUInt128(offset: 144, val: unsafeShutdowns)
        writeUInt128(offset: 160, val: mediaErrors)
        writeUInt128(offset: 176, val: numErrorInfoLogEntries)

        writeUInt32(offset: 192, val: warningCompositeTempTimeMinutes)
        writeUInt32(offset: 196, val: criticalCompositeTempTimeMinutes)

        for i in 0..<min(8, temperatureSensorsKelvin.count) {
            writeUInt16(offset: 200 + i * 2, val: temperatureSensorsKelvin[i])
        }

        writeUInt32(offset: 216, val: thermalManagementTemp1TransitionCount)
        writeUInt32(offset: 220, val: thermalManagementTemp2TransitionCount)
        writeUInt32(offset: 224, val: totalTimeForThermalManagementTemp1Seconds)
        writeUInt32(offset: 228, val: totalTimeForThermalManagementTemp2Seconds)

        return Data(bytes)
    }

    /// Pristine out-of-box SSD: 0% wear, 32°C (305 K), 100% spare, ~0.5 TBW.
    public static func makePristineBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x00,
            temperatureKelvin: 305, // 31.85°C (~32°C)
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: 0,
            dataUnitsRead: UInt128Value(low: 1_200_000), // ~0.614 TB
            dataUnitsWritten: UInt128Value(low: 976_562), // ~0.500 TB
            hostReadCommands: UInt128Value(low: 50_000),
            hostWriteCommands: UInt128Value(low: 40_000),
            controllerBusyTimeMinutes: UInt128Value(low: 15),
            powerCycles: UInt128Value(low: 45),
            powerOnHours: UInt128Value(low: 120),
            unsafeShutdowns: UInt128Value(low: 1),
            mediaErrors: UInt128Value(low: 0),
            numErrorInfoLogEntries: UInt128Value(low: 0),
            temperatureSensorsKelvin: [304, 306, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Developer Workload SSD: 18% wear, 38°C (311 K), 100% spare, ~24.2 TBW.
    public static func makeDeveloperWorkloadBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x00,
            temperatureKelvin: 311, // 37.85°C (~38°C)
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            percentageUsed: 18,
            dataUnitsRead: UInt128Value(low: 58_392_100), // ~29.90 TB
            dataUnitsWritten: UInt128Value(low: 47_258_900), // ~24.20 TB
            hostReadCommands: UInt128Value(low: 328_190_442),
            hostWriteCommands: UInt128Value(low: 289_451_090),
            controllerBusyTimeMinutes: UInt128Value(low: 1_420),
            powerCycles: UInt128Value(low: 842),
            powerOnHours: UInt128Value(low: 4_120),
            unsafeShutdowns: UInt128Value(low: 14),
            mediaErrors: UInt128Value(low: 0),
            numErrorInfoLogEntries: UInt128Value(low: 0),
            temperatureSensorsKelvin: [310, 312, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Thermal Spike SSD: 68°C (341 K), Critical Warning Bit 1 (0x02) active.
    public static func makeThermalSpikeBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x02, // Temperature Exceeds Threshold
            temperatureKelvin: 341, // 67.85°C (~68°C)
            availableSparePercent: 98,
            availableSpareThresholdPercent: 10,
            percentageUsed: 18,
            dataUnitsRead: UInt128Value(low: 60_000_000),
            dataUnitsWritten: UInt128Value(low: 48_000_000),
            hostReadCommands: UInt128Value(low: 330_000_000),
            hostWriteCommands: UInt128Value(low: 290_000_000),
            controllerBusyTimeMinutes: UInt128Value(low: 1_450),
            powerCycles: UInt128Value(low: 850),
            powerOnHours: UInt128Value(low: 4_150),
            unsafeShutdowns: UInt128Value(low: 14),
            mediaErrors: UInt128Value(low: 0),
            numErrorInfoLogEntries: UInt128Value(low: 0),
            warningCompositeTempTimeMinutes: 45,
            criticalCompositeTempTimeMinutes: 5,
            temperatureSensorsKelvin: [339, 343, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Near End-of-Life SSD: 96% wear, 6% spare (< 10% thresh), 14 media errors, Critical Bits 0 and 2 set.
    public static func makeNearEOLBuffer() -> Data {
        makeBuffer(
            criticalWarning: 0x05, // Available Spare Low (0x01) + Reliability Degraded (0x04)
            temperatureKelvin: 321, // 47.85°C (~48°C)
            availableSparePercent: 6,
            availableSpareThresholdPercent: 10,
            percentageUsed: 96,
            dataUnitsRead: UInt128Value(low: 610_800_000),
            dataUnitsWritten: UInt128Value(low: 495_600_000),
            hostReadCommands: UInt128Value(low: 3_800_000_000),
            hostWriteCommands: UInt128Value(low: 3_200_000_000),
            controllerBusyTimeMinutes: UInt128Value(low: 18_900),
            powerCycles: UInt128Value(low: 3_200),
            powerOnHours: UInt128Value(low: 19_800),
            unsafeShutdowns: UInt128Value(low: 84),
            mediaErrors: UInt128Value(low: 14),
            numErrorInfoLogEntries: UInt128Value(low: 32),
            warningCompositeTempTimeMinutes: 120,
            criticalCompositeTempTimeMinutes: 12,
            temperatureSensorsKelvin: [319, 323, 0, 0, 0, 0, 0, 0]
        )
    }

    /// All zeros buffer: 512 bytes of 0x00.
    public static func makeAllZerosBuffer() -> Data {
        Data(repeating: 0, count: 512)
    }

    /// All ones buffer: 512 bytes of 0xFF.
    public static func makeAllOnesBuffer() -> Data {
        Data(repeating: 0xFF, count: 512)
    }
}

// MARK: - E2E Historical Snapshot & Persistence Models

/// Historical measurement snapshot capturing key SMART indicators over time.
public struct SSDHistorySnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let healthScorePercent: Int
    public let wearPercentage: Int
    public let temperatureCelsius: Double
    public let terabytesWritten: Double
    public let availableSparePercent: Int
    public let criticalWarningsRaw: UInt8
    public let mediaErrors: UInt64

    public init(
        timestamp: Date,
        healthScorePercent: Int,
        wearPercentage: Int,
        temperatureCelsius: Double,
        terabytesWritten: Double,
        availableSparePercent: Int,
        criticalWarningsRaw: UInt8 = 0,
        mediaErrors: UInt64 = 0
    ) {
        self.timestamp = timestamp
        self.healthScorePercent = healthScorePercent
        self.wearPercentage = wearPercentage
        self.temperatureCelsius = temperatureCelsius
        self.terabytesWritten = terabytesWritten
        self.availableSparePercent = availableSparePercent
        self.criticalWarningsRaw = criticalWarningsRaw
        self.mediaErrors = mediaErrors
    }

    /// Convenience initializer converting from SSDHealthMetrics.
    public init(from metrics: SSDHealthMetrics) {
        self.timestamp = metrics.timestamp
        self.healthScorePercent = metrics.healthScorePercent
        self.wearPercentage = metrics.wearPercentage
        self.temperatureCelsius = metrics.temperatureCelsius
        self.terabytesWritten = metrics.terabytesWritten
        self.availableSparePercent = metrics.availableSparePercent
        self.criticalWarningsRaw = metrics.criticalWarnings.rawValue
        self.mediaErrors = metrics.mediaErrors
    }
}

/// Root history container for disk serialization.
public struct SSDHistoryStoreDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let driveIdentifier: String
    public let firstRecorded: Date
    public var lastUpdated: Date
    public var ratedTBW: Double
    public var snapshots: [SSDHistorySnapshot]

    public init(
        schemaVersion: Int = 1,
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

// MARK: - Mathematical Forecasting Result & Status

public enum DegradationStatus: String, Codable, Sendable {
    case insufficientData = "insufficient_data"
    case stable = "stable"
    case moderateWear = "moderate_wear"
    case acceleratedWear = "accelerated_wear"
    case criticalWear = "critical_wear"
    case exceededEndurance = "exceeded_endurance"
}

public struct SSDForecastResult: Sendable, Equatable {
    public let dailyWriteRate7dGB: Double
    public let dailyWriteRate30dGB: Double
    public let dailyWriteRateLifetimeGB: Double
    public let primaryDailyWriteRateGB: Double
    public let estimatedDaysRemaining: Double
    public let estimatedYearsRemaining: Double
    public let estimatedExhaustionDate: Date?
    public let degradationStatus: DegradationStatus
    public let confidenceInterval95: (lowerGB: Double, upperGB: Double)

    public static func == (lhs: SSDForecastResult, rhs: SSDForecastResult) -> Bool {
        abs(lhs.dailyWriteRate7dGB - rhs.dailyWriteRate7dGB) < 1e-4 &&
        abs(lhs.dailyWriteRate30dGB - rhs.dailyWriteRate30dGB) < 1e-4 &&
        abs(lhs.dailyWriteRateLifetimeGB - rhs.dailyWriteRateLifetimeGB) < 1e-4 &&
        abs(lhs.primaryDailyWriteRateGB - rhs.primaryDailyWriteRateGB) < 1e-4 &&
        abs(lhs.estimatedDaysRemaining - rhs.estimatedDaysRemaining) < 1e-2 &&
        abs(lhs.estimatedYearsRemaining - rhs.estimatedYearsRemaining) < 1e-2 &&
        lhs.degradationStatus == rhs.degradationStatus &&
        abs(lhs.confidenceInterval95.lowerGB - rhs.confidenceInterval95.lowerGB) < 1e-4 &&
        abs(lhs.confidenceInterval95.upperGB - rhs.confidenceInterval95.upperGB) < 1e-4
    }
}

// MARK: - Alerting & Notification Models

public enum AlertSeverity: String, Codable, Sendable {
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"
    case emergency = "Emergency"
}

public struct AlertRule: Sendable {
    public let ruleKey: String
    public let severity: AlertSeverity
    public let cooldownSeconds: TimeInterval

    public init(ruleKey: String, severity: AlertSeverity, cooldownSeconds: TimeInterval) {
        self.ruleKey = ruleKey
        self.severity = severity
        self.cooldownSeconds = cooldownSeconds
    }
}

// MARK: - UI & Display Enums & Formats

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case iconOnly = "Icon Only"
    case iconAndHealth = "Icon + Health %"
    case iconAndTemp = "Icon + Temperature"
    case iconHealthAndTemp = "Icon + Health & Temp"

    public var id: String { rawValue }
}

public enum HealthStatus: String, Codable, Sendable {
    case good = "Good"
    case warning = "Warning"
    case critical = "Critical"

    public var iconName: String {
        switch self {
        case .good: return "internaldrive"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

public enum TemperatureUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case celsius = "Celsius (°C)"
    case fahrenheit = "Fahrenheit (°F)"

    public var id: String { rawValue }
}

public enum ParameterStatus: String, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
    case info = "Info"
}

public struct SMARTParameterRow: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let rawHex: String
    public let rawValueString: String
    public let formattedValue: String
    public let status: ParameterStatus

    public init(id: Int, name: String, rawHex: String, rawValueString: String, formattedValue: String, status: ParameterStatus) {
        self.id = id
        self.name = name
        self.rawHex = rawHex
        self.rawValueString = rawValueString
        self.formattedValue = formattedValue
        self.status = status
    }
}

// MARK: - Reference Implementation Oracles (Derivation Sources)

/// Independent reference implementation of OLS linear regression and dual-model lifespan extrapolation.
public final class ReferenceForecastEngine: Sendable {
    public init() {}

    public func calculateForecast(
        current: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        ratedTBW: Double?,
        referenceDate: Date = Date()
    ) -> SSDForecastResult {
        let effectiveRatedTBW = ratedTBW ?? (Double(current.capacityBytes) / 1_000_000_000.0 * 0.6)
        let sorted = history.sorted { $0.timestamp < $1.timestamp }

        // 1. Lifetime Rate
        let lifetimeGB = current.terabytesWritten * 1_000.0
        let lifetimeHours = max(1.0, Double(current.powerOnHours))
        let lifetimeRateGBPerDay = (lifetimeGB / lifetimeHours) * 24.0

        // 2. OLS Windowed Rates
        let rate7d = calculateOLSRate(history: sorted, windowDays: 7.0, referenceDate: referenceDate)
        let rate30d = calculateOLSRate(history: sorted, windowDays: 30.0, referenceDate: referenceDate)

        let primaryRateGB: Double
        if let r30 = rate30d {
            primaryRateGB = r30.rateGBPerDay
        } else if let r7 = rate7d {
            primaryRateGB = r7.rateGBPerDay
        } else {
            primaryRateGB = lifetimeRateGBPerDay
        }

        // 3. Lifespan Calculation (Model A vs Model B)
        var daysRemaining: Double = Double.infinity
        var usedModelA = false

        // Check if wear changed in history
        if sorted.count >= 2, let first = sorted.first, let last = sorted.last {
            let wearDelta = Double(last.wearPercentage - first.wearPercentage)
            let timeDeltaSec = last.timestamp.timeIntervalSince(first.timestamp)
            if wearDelta >= 1.0 && timeDeltaSec >= 3600.0 {
                let dailyWear = (wearDelta / timeDeltaSec) * 86_400.0
                if dailyWear > 0 {
                    daysRemaining = max(0.0, Double(100 - current.wearPercentage)) / dailyWear
                    usedModelA = true
                }
            }
        }

        if !usedModelA {
            // Model B: Rated TBW endurance
            let remainingTBW = max(0.0, effectiveRatedTBW - current.terabytesWritten)
            let dailyTBWRate = primaryRateGB / 1_000.0
            if dailyTBWRate > 0 {
                daysRemaining = remainingTBW / dailyTBWRate
            } else {
                daysRemaining = Double.infinity
            }
        }

        let yearsRemaining = daysRemaining.isInfinite ? Double.infinity : (daysRemaining / 365.25)
        let exhaustionDate = daysRemaining.isInfinite || daysRemaining > (100 * 365.25) ? nil : referenceDate.addingTimeInterval(daysRemaining * 86_400)

        // 4. Degradation Status
        let status: DegradationStatus
        let totalSpan = (sorted.last?.timestamp.timeIntervalSince(sorted.first?.timestamp ?? referenceDate)) ?? 0
        if sorted.count < 3 || totalSpan < 86_400.0 {
            status = .insufficientData
        } else if current.wearPercentage >= 100 || current.terabytesWritten >= effectiveRatedTBW {
            status = .exceededEndurance
        } else if current.wearPercentage >= 90 || daysRemaining < 90.0 {
            status = .criticalWear
        } else if daysRemaining < (2.0 * 365.25) || primaryRateGB > 200.0 {
            status = .acceleratedWear
        } else if daysRemaining < (5.0 * 365.25) {
            status = .moderateWear
        } else {
            status = .stable
        }

        let ci = rate30d?.ci95 ?? rate7d?.ci95 ?? (lowerGB: primaryRateGB * 0.9, upperGB: primaryRateGB * 1.1)

        return SSDForecastResult(
            dailyWriteRate7dGB: rate7d?.rateGBPerDay ?? lifetimeRateGBPerDay,
            dailyWriteRate30dGB: rate30d?.rateGBPerDay ?? lifetimeRateGBPerDay,
            dailyWriteRateLifetimeGB: lifetimeRateGBPerDay,
            primaryDailyWriteRateGB: primaryRateGB,
            estimatedDaysRemaining: daysRemaining,
            estimatedYearsRemaining: yearsRemaining,
            estimatedExhaustionDate: exhaustionDate,
            degradationStatus: status,
            confidenceInterval95: ci
        )
    }

    private func calculateOLSRate(
        history: [SSDHistorySnapshot],
        windowDays: Double,
        referenceDate: Date
    ) -> (rateGBPerDay: Double, ci95: (lowerGB: Double, upperGB: Double))? {
        let cutoff = referenceDate.addingTimeInterval(-windowDays * 86_400.0)
        let windowSamples = history.filter { $0.timestamp >= cutoff }
        guard windowSamples.count >= 2 else { return nil }

        let n = Double(windowSamples.count)
        let t0 = windowSamples.first!.timestamp.timeIntervalSince1970
        let points = windowSamples.map { (t: $0.timestamp.timeIntervalSince1970 - t0, w: $0.terabytesWritten * 1_000_000_000_000.0) }

        let sumT = points.reduce(0.0) { $0 + $1.t }
        let sumW = points.reduce(0.0) { $0 + $1.w }
        let meanT = sumT / n
        let meanW = sumW / n

        var num = 0.0
        var den = 0.0
        for p in points {
            let dt = p.t - meanT
            num += dt * (p.w - meanW)
            den += dt * dt
        }

        guard den > 0 else { return nil }
        let beta = num / den // bytes/sec
        guard beta >= 0 else { return (rateGBPerDay: 0.0, ci95: (0.0, 0.0)) }

        let dailyRateGB = (beta * 86_400.0) / 1_000_000_000.0

        if n >= 3 {
            var ssq = 0.0
            for p in points {
                let wHat = meanW + beta * (p.t - meanT)
                ssq += (p.w - wHat) * (p.w - wHat)
            }
            let seBeta = sqrt(ssq / (n - 2.0)) / sqrt(den)
            let seDailyGB = (seBeta * 86_400.0) / 1_000_000_000.0
            let lower = max(0.0, dailyRateGB - 1.96 * seDailyGB)
            let upper = dailyRateGB + 1.96 * seDailyGB
            return (rateGBPerDay: dailyRateGB, ci95: (lowerGB: lower, upperGB: upper))
        } else {
            return (rateGBPerDay: dailyRateGB, ci95: (lowerGB: dailyRateGB * 0.85, upperGB: dailyRateGB * 1.15))
        }
    }
}

/// Independent reference implementation of 4-tier temporal sample decimation.
public enum ReferenceDecimationEngine {
    public static func decimate(samples: [SSDHistorySnapshot], relativeTo now: Date = Date()) -> [SSDHistorySnapshot] {
        guard samples.count > 1 else { return samples }

        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
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
                // Tier 1: Retain 100% of raw samples within last 24h
                result.append(sample)
            } else if t >= sevenDaysAgo {
                // Tier 2: Retain 1 sample per hour
                let hourBucket = calendar.component(.hour, from: t) + (calendar.ordinality(of: .day, in: .year, for: t) ?? 0) * 24
                if hourBucket != lastKeptHourBucket {
                    result.append(sample)
                    lastKeptHourBucket = hourBucket
                }
            } else if t >= oneYearAgo {
                // Tier 3: Retain 1 sample per day
                let dayBucket = calendar.ordinality(of: .day, in: .era, for: t) ?? 0
                if dayBucket != lastKeptDayBucket {
                    result.append(sample)
                    lastKeptDayBucket = dayBucket
                }
            } else {
                // Tier 4: Retain 1 sample per week
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

/// Reference implementation for Alert Evaluation and Cooldown State Machine.
public final class ReferenceNotificationEngine: @unchecked Sendable {
    private var lastTriggered: [String: Date] = [:]
    private var acknowledgedMilestones: Set<Int> = []
    private var lastMediaErrors: UInt64 = 0

    public init() {}

    public func evaluateAlerts(
        metrics: SSDHealthMetrics,
        tempWarnThreshold: Double = 60.0,
        tempCritThreshold: Double = 65.0,
        wearWarnThreshold: Int = 80,
        spareWarnThreshold: Int = 10,
        now: Date = Date()
    ) -> [String] {
        var triggered: [String] = []

        // 1. Thermal alerts
        if metrics.temperatureCelsius >= tempCritThreshold {
            if shouldTrigger(key: "temp_crit", cooldown: 900.0, now: now) {
                recordTrigger(key: "temp_crit", now: now)
                triggered.append("CRITICAL_TEMPERATURE: \(metrics.temperatureFormatted)")
            }
        } else if metrics.temperatureCelsius >= tempWarnThreshold {
            if shouldTrigger(key: "temp_warn", cooldown: 1800.0, now: now) {
                recordTrigger(key: "temp_warn", now: now)
                triggered.append("HIGH_TEMPERATURE: \(metrics.temperatureFormatted)")
            }
        }

        // 2. Wear milestone alerts (one-shot per milestone)
        let milestones = [80, 90, 95, 100]
        for m in milestones where metrics.wearPercentage >= m {
            if !acknowledgedMilestones.contains(m) {
                acknowledgedMilestones.insert(m)
                triggered.append("WEAR_MILESTONE_\(m): \(metrics.wearFormatted)")
            }
        }

        // 3. Spare below threshold
        if metrics.availableSparePercent < spareWarnThreshold || metrics.criticalWarnings.contains(.availableSpareBelowThreshold) {
            if shouldTrigger(key: "spare_low", cooldown: 86400.0, now: now) {
                recordTrigger(key: "spare_low", now: now)
                triggered.append("SPARE_CAPACITY_LOW: \(metrics.availableSparePercent)%")
            }
        }

        // 4. Critical Warning bitmask flags
        if metrics.criticalWarnings.contains(.reliabilityDegraded) {
            if shouldTrigger(key: "crit_reliability", cooldown: 86400.0, now: now) {
                recordTrigger(key: "crit_reliability", now: now)
                triggered.append("CRITICAL_RELIABILITY_DEGRADED")
            }
        }
        if metrics.criticalWarnings.contains(.readOnly) {
            if shouldTrigger(key: "crit_readonly", cooldown: 86400.0, now: now) {
                recordTrigger(key: "crit_readonly", now: now)
                triggered.append("CRITICAL_DRIVE_READ_ONLY")
            }
        }

        // 5. Media Errors Delta
        if metrics.mediaErrors > lastMediaErrors {
            triggered.append("MEDIA_ERRORS_DETECTED: \(metrics.mediaErrors)")
            lastMediaErrors = metrics.mediaErrors
        }

        return triggered
    }

    private func shouldTrigger(key: String, cooldown: TimeInterval, now: Date) -> Bool {
        guard let last = lastTriggered[key] else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    private func recordTrigger(key: String, now: Date) {
        lastTriggered[key] = now
    }
}

/// Reference Diagnostic Exporter (JSON, RFC 4180 CSV, ASCII Report).
public enum ReferenceDiagnosticExporter {

    public static func exportJSON(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?,
        ratedTBW: Double = 300.0,
        now: Date = Date()
    ) throws -> String {
        let isoFormatter = ISO8601DateFormatter()

        var root: [String: Any] = [:]
        root["metadata"] = [
            "exportTimestamp": isoFormatter.string(from: now),
            "appVersion": "1.0.0",
            "buildNumber": "100",
            "macOSVersion": "14.5.0",
            "hardwareModel": "Apple Silicon Mac",
            "architecture": "arm64"
        ]

        root["drive"] = [
            "bsdName": metrics.bsdName,
            "productName": metrics.modelName,
            "serialNumber": metrics.serialNumber,
            "revision": metrics.firmwareRevision,
            "capacityBytes": metrics.capacityBytes,
            "capacityFormatted": metrics.capacityFormatted,
            "ratedTBW": ratedTBW
        ]

        root["currentMetrics"] = [
            "healthScore": metrics.healthScorePercent,
            "percentageUsed": metrics.wearPercentage,
            "temperatureCelsius": metrics.temperatureCelsius,
            "terabytesWritten": metrics.terabytesWritten,
            "terabytesRead": metrics.terabytesRead,
            "powerOnHours": metrics.powerOnHours,
            "powerCycles": metrics.powerCycles,
            "unsafeShutdowns": metrics.unsafeShutdowns,
            "availableSparePercent": metrics.availableSparePercent,
            "availableSpareThresholdPercent": metrics.availableSpareThresholdPercent,
            "criticalWarningBitmask": metrics.criticalWarnings.rawValue,
            "mediaErrors": metrics.mediaErrors,
            "errorLogEntries": metrics.errorLogEntries,
            "isFallbackData": metrics.isFallbackData
        ]

        if let f = forecast {
            var fDict: [String: Any] = [
                "dailyWriteRate7dGB": f.dailyWriteRate7dGB,
                "dailyWriteRate30dGB": f.dailyWriteRate30dGB,
                "dailyWriteRateLifetimeGB": f.dailyWriteRateLifetimeGB,
                "estimatedDaysRemaining": f.estimatedDaysRemaining.isInfinite ? -1.0 : f.estimatedDaysRemaining,
                "estimatedYearsRemaining": f.estimatedYearsRemaining.isInfinite ? -1.0 : f.estimatedYearsRemaining,
                "degradationStatus": f.degradationStatus.rawValue,
                "confidenceInterval95": [
                    "lowerBoundDailyGB": f.confidenceInterval95.lowerGB,
                    "upperBoundDailyGB": f.confidenceInterval95.upperGB
                ]
            ]
            if let eDate = f.estimatedExhaustionDate {
                fDict["estimatedExhaustionDate"] = isoFormatter.string(from: eDate)
            }
            root["forecast"] = fDict
        }

        root["historySampleCount"] = history.count
        root["history"] = history.map { s in
            [
                "timestamp": isoFormatter.string(from: s.timestamp),
                "healthScore": s.healthScorePercent,
                "percentageUsed": s.wearPercentage,
                "temperatureCelsius": s.temperatureCelsius,
                "terabytesWritten": s.terabytesWritten,
                "availableSparePercent": s.availableSparePercent,
                "mediaErrors": s.mediaErrors
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SSDExportError", code: 1, userInfo: nil)
        }
        return str
    }

    public static func exportCSV(history: [SSDHistorySnapshot]) -> String {
        let isoFormatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("Timestamp_ISO8601,Timestamp_Unix,Percentage_Used,Health_Score_Pct,Temperature_C,TBW_Decimal,Available_Spare_Pct,Critical_Warning_Flags,Media_Errors")

        for s in history.sorted(by: { $0.timestamp < $1.timestamp }) {
            let iso = isoFormatter.string(from: s.timestamp)
            let unix = Int(s.timestamp.timeIntervalSince1970)
            let flagsHex = String(format: "0x%02X", s.criticalWarningsRaw)
            let row = "\(iso),\(unix),\(s.wearPercentage),\(s.healthScorePercent),\(String(format: "%.1f", s.temperatureCelsius)),\(String(format: "%.3f", s.terabytesWritten)),\(s.availableSparePercent),\(flagsHex),\(s.mediaErrors)"
            lines.append(row)
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportTextReport(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?,
        ratedTBW: Double = 300.0,
        now: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var out = ""
        out += "================================================================================\n"
        out += "                    macOS SSD HEALTH & SMART DIAGNOSTIC REPORT\n"
        out += "================================================================================\n"
        out += "Generated: \(formatter.string(from: now)) | App Version: 1.0.0 (Build 100)\n"
        out += "Host System: Apple Silicon Mac (arm64) | OS: macOS 14+\n\n"

        out += "--------------------------------------------------------------------------------\n"
        out += "1. STORAGE DEVICE IDENTIFICATION\n"
        out += "--------------------------------------------------------------------------------\n"
        out += "Device Name:              \(metrics.modelName) (\(metrics.bsdName))\n"
        out += "Serial Number:            \(metrics.serialNumber)\n"
        out += "Firmware Revision:        \(metrics.firmwareRevision)\n"
        out += "Interconnect:             \(metrics.interconnect)\n"
        out += "Capacity:                 \(metrics.capacityFormatted) (\(metrics.capacityBytes) Bytes)\n"
        out += "Rated Endurance:          \(String(format: "%.1f", ratedTBW)) TBW\n\n"

        out += "--------------------------------------------------------------------------------\n"
        out += "2. HEALTH & LIFESPAN SUMMARY\n"
        out += "--------------------------------------------------------------------------------\n"
        out += "Overall Health Score:     \(metrics.healthScorePercent)% (\(metrics.healthScorePercent > 80 ? "Good" : (metrics.healthScorePercent > 20 ? "Warning" : "Critical")))\n"
        out += "Percentage Used:          \(metrics.wearPercentage)%\n"
        out += "Total Bytes Written:      \(metrics.tbwFormatted)\n"
        out += "Total Bytes Read:         \(metrics.tbrFormatted)\n"
        out += "Power-On Time:            \(metrics.powerOnHours) Hours\n"
        out += "Power Cycles:             \(metrics.powerCycles) Cycles\n"
        out += "Unsafe Shutdowns:         \(metrics.unsafeShutdowns)\n"
        out += "Media Integrity Errors:   \(metrics.mediaErrors)\n\n"

        out += "--------------------------------------------------------------------------------\n"
        out += "3. FORECAST & WEAR PROJECTION\n"
        out += "--------------------------------------------------------------------------------\n"
        if let f = forecast {
            out += "Daily Write Rate (7d):    \(String(format: "%.2f", f.dailyWriteRate7dGB)) GB/day\n"
            out += "Daily Write Rate (30d):   \(String(format: "%.2f", f.dailyWriteRate30dGB)) GB/day\n"
            out += "Daily Write Rate (All):   \(String(format: "%.2f", f.dailyWriteRateLifetimeGB)) GB/day\n"
            out += "Degradation Trajectory:   \(f.degradationStatus.rawValue.uppercased())\n"
            out += "Estimated Lifespan:       \(f.estimatedYearsRemaining.isInfinite ? "Infinite" : String(format: "~%.1f Years", f.estimatedYearsRemaining))\n"
            out += "Confidence Interval (95%): \(String(format: "%.2f", f.confidenceInterval95.lowerGB)) GB/day to \(String(format: "%.2f", f.confidenceInterval95.upperGB)) GB/day\n"
        } else {
            out += "Prognosis:                Insufficient historical data\n"
        }
        out += "\n--------------------------------------------------------------------------------\n"
        out += "4. HARDWARE RELIABILITY FLAGS & WARNINGS\n"
        out += "--------------------------------------------------------------------------------\n"
        out += "[\(metrics.availableSparePercent >= metrics.availableSpareThresholdPercent ? "x" : " ")] Available Spare (\(metrics.availableSparePercent)% >= \(metrics.availableSpareThresholdPercent)% threshold)\n"
        out += "[\(metrics.temperatureCelsius < 65.0 ? "x" : " ")] Thermal Status (\(metrics.temperatureFormatted) < 65.0 °C threshold)\n"
        out += "[\(!metrics.criticalWarnings.contains(.reliabilityDegraded) ? "x" : " ")] NVM Subsystem Reliability Intact\n"
        out += "[\(!metrics.criticalWarnings.contains(.readOnly) ? "x" : " ")] Drive Media Writable\n"
        out += "[\(metrics.mediaErrors == 0 ? "x" : " ")] Zero Media Errors\n"
        out += "================================================================================\n"

        return out
    }
}

// MARK: - Reference Formatters for UI & SMART Table

public enum ReferenceMenuBarFormatter {
    public static func formatTitle(
        metrics: SSDHealthMetrics?,
        mode: MenuBarDisplayMode,
        unit: TemperatureUnit = .celsius
    ) -> String {
        guard let m = metrics else { return "--%" }

        let tempStr: String
        if unit == .celsius {
            tempStr = "\(Int(round(m.temperatureCelsius)))°C"
        } else {
            let f = m.temperatureCelsius * 1.8 + 32.0
            tempStr = "\(Int(round(f)))°F"
        }

        switch mode {
        case .iconOnly:
            return ""
        case .iconAndHealth:
            return "\(m.healthScorePercent)%"
        case .iconAndTemp:
            return tempStr
        case .iconHealthAndTemp:
            return "\(m.healthScorePercent)% · \(tempStr)"
        }
    }

    public static func resolveStatus(metrics: SSDHealthMetrics?) -> HealthStatus {
        guard let m = metrics else { return .good }
        if !m.criticalWarnings.isClean || m.healthScorePercent <= 10 || m.availableSparePercent < m.availableSpareThresholdPercent || m.temperatureCelsius >= 65.0 {
            return .critical
        } else if m.healthScorePercent <= 20 || m.availableSparePercent < 20 || m.temperatureCelsius >= 55.0 {
            return .warning
        } else {
            return .good
        }
    }
}

public enum ReferenceSMARTTableFormatter {
    public static func buildTableRows(from log: NVMESmartLog) -> [SMARTParameterRow] {
        var rows: [SMARTParameterRow] = []

        rows.append(SMARTParameterRow(
            id: 1,
            name: "Critical Warning",
            rawHex: String(format: "0x%02X", log.criticalWarning.rawValue),
            rawValueString: "\(log.criticalWarning.rawValue)",
            formattedValue: log.criticalWarning.isClean ? "0 (No Flags Set)" : log.criticalWarning.activeWarnings.joined(separator: ", "),
            status: log.criticalWarning.isClean ? .normal : .critical
        ))

        rows.append(SMARTParameterRow(
            id: 2,
            name: "Composite Temperature",
            rawHex: String(format: "0x%04X", log.compositeTemperatureKelvin),
            rawValueString: "\(log.compositeTemperatureKelvin) K",
            formattedValue: String(format: "%.1f °C (%.1f °F)", log.temperatureCelsius, log.temperatureFahrenheit),
            status: log.temperatureCelsius >= 65.0 ? .critical : (log.temperatureCelsius >= 55.0 ? .warning : .normal)
        ))

        rows.append(SMARTParameterRow(
            id: 3,
            name: "Available Spare",
            rawHex: String(format: "0x%02X", log.availableSparePercent),
            rawValueString: "\(log.availableSparePercent)%",
            formattedValue: "\(log.availableSparePercent)% (Thresh: \(log.availableSpareThresholdPercent)%)",
            status: log.availableSparePercent < log.availableSpareThresholdPercent ? .critical : .normal
        ))

        rows.append(SMARTParameterRow(
            id: 4,
            name: "Available Spare Threshold",
            rawHex: String(format: "0x%02X", log.availableSpareThresholdPercent),
            rawValueString: "\(log.availableSpareThresholdPercent)%",
            formattedValue: "\(log.availableSpareThresholdPercent)%",
            status: .normal
        ))

        rows.append(SMARTParameterRow(
            id: 5,
            name: "Percentage Used",
            rawHex: String(format: "0x%02X", log.percentageUsed),
            rawValueString: "\(log.percentageUsed)%",
            formattedValue: "\(log.percentageUsed)% Used (\(log.healthScorePercent)% Health)",
            status: log.percentageUsed >= 90 ? .critical : (log.percentageUsed >= 80 ? .warning : .normal)
        ))

        rows.append(SMARTParameterRow(
            id: 6,
            name: "Data Units Read",
            rawHex: String(format: "0x%016llX%016llX", log.dataUnitsRead.high, log.dataUnitsRead.low),
            rawValueString: "\(log.dataUnitsRead.low)",
            formattedValue: String(format: "%.2f TBR", log.totalTerabytesRead),
            status: .info
        ))

        rows.append(SMARTParameterRow(
            id: 7,
            name: "Data Units Written",
            rawHex: String(format: "0x%016llX%016llX", log.dataUnitsWritten.high, log.dataUnitsWritten.low),
            rawValueString: "\(log.dataUnitsWritten.low)",
            formattedValue: String(format: "%.2f TBW", log.totalTerabytesWritten),
            status: .info
        ))

        rows.append(SMARTParameterRow(
            id: 8,
            name: "Host Read Commands",
            rawHex: String(format: "0x%016llX%016llX", log.hostReadCommands.high, log.hostReadCommands.low),
            rawValueString: "\(log.hostReadCommands.low)",
            formattedValue: "\(log.hostReadCommands.low) commands",
            status: .info
        ))

        rows.append(SMARTParameterRow(
            id: 9,
            name: "Host Write Commands",
            rawHex: String(format: "0x%016llX%016llX", log.hostWriteCommands.high, log.hostWriteCommands.low),
            rawValueString: "\(log.hostWriteCommands.low)",
            formattedValue: "\(log.hostWriteCommands.low) commands",
            status: .info
        ))

        rows.append(SMARTParameterRow(
            id: 10,
            name: "Controller Busy Time",
            rawHex: String(format: "0x%016llX%016llX", log.controllerBusyTimeMinutes.high, log.controllerBusyTimeMinutes.low),
            rawValueString: "\(log.controllerBusyTimeMinutes.low) min",
            formattedValue: String(format: "%.1f Hours", Double(log.controllerBusyTimeMinutes.low) / 60.0),
            status: .info
        ))

        rows.append(SMARTParameterRow(
            id: 11,
            name: "Power Cycles",
            rawHex: String(format: "0x%016llX%016llX", log.powerCycles.high, log.powerCycles.low),
            rawValueString: "\(log.powerCycles.low)",
            formattedValue: "\(log.powerCycles.low) cycles",
            status: .info
        ))

        rows.append(SMARTParameterRow(
            id: 12,
            name: "Power-On Hours",
            rawHex: String(format: "0x%016llX%016llX", log.powerOnHours.high, log.powerOnHours.low),
            rawValueString: "\(log.powerOnHours.low) hrs",
            formattedValue: "\(log.powerOnHours.low) Hours",
            status: .info
        ))

        rows.append(SMARTParameterRow(
            id: 13,
            name: "Unsafe Shutdowns",
            rawHex: String(format: "0x%016llX%016llX", log.unsafeShutdowns.high, log.unsafeShutdowns.low),
            rawValueString: "\(log.unsafeShutdowns.low)",
            formattedValue: "\(log.unsafeShutdowns.low) shutdowns",
            status: log.unsafeShutdowns.low > 50 ? .warning : .normal
        ))

        rows.append(SMARTParameterRow(
            id: 14,
            name: "Media and Data Integrity Errors",
            rawHex: String(format: "0x%016llX%016llX", log.mediaErrors.high, log.mediaErrors.low),
            rawValueString: "\(log.mediaErrors.low)",
            formattedValue: "\(log.mediaErrors.low) Errors",
            status: log.mediaErrors.low > 0 ? .critical : .normal
        ))

        rows.append(SMARTParameterRow(
            id: 15,
            name: "Number of Error Information Log Entries",
            rawHex: String(format: "0x%016llX%016llX", log.numErrorInfoLogEntries.high, log.numErrorInfoLogEntries.low),
            rawValueString: "\(log.numErrorInfoLogEntries.low)",
            formattedValue: "\(log.numErrorInfoLogEntries.low) Entries",
            status: log.numErrorInfoLogEntries.low > 0 ? .warning : .normal
        ))

        rows.append(SMARTParameterRow(
            id: 16,
            name: "Warning Composite Temperature Time",
            rawHex: String(format: "0x%08X", log.warningCompositeTempTimeMinutes),
            rawValueString: "\(log.warningCompositeTempTimeMinutes) min",
            formattedValue: "\(log.warningCompositeTempTimeMinutes) Minutes",
            status: log.warningCompositeTempTimeMinutes > 0 ? .warning : .normal
        ))

        rows.append(SMARTParameterRow(
            id: 17,
            name: "Critical Composite Temperature Time",
            rawHex: String(format: "0x%08X", log.criticalCompositeTempTimeMinutes),
            rawValueString: "\(log.criticalCompositeTempTimeMinutes) min",
            formattedValue: "\(log.criticalCompositeTempTimeMinutes) Minutes",
            status: log.criticalCompositeTempTimeMinutes > 0 ? .critical : .normal
        ))

        for i in 0..<min(8, log.temperatureSensorsKelvin.count) {
            let sK = log.temperatureSensorsKelvin[i]
            if sK > 0 {
                let sC = Double(sK) - 273.15
                rows.append(SMARTParameterRow(
                    id: 18 + i,
                    name: "Temperature Sensor \(i + 1)",
                    rawHex: String(format: "0x%04X", sK),
                    rawValueString: "\(sK) K",
                    formattedValue: String(format: "%.1f °C", sC),
                    status: sC >= 65.0 ? .critical : (sC >= 55.0 ? .warning : .normal)
                ))
            }
        }

        return rows
    }
}

// MARK: - Assertion & Verification Helpers

public func assertDoubleEqual(_ actual: Double, _ expected: Double, accuracy: Double = 1e-4, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(actual, expected, accuracy: accuracy, "Expected \(expected), got \(actual) (diff: \(abs(actual - expected)))", file: file, line: line)
}

public func assertDateClose(_ actual: Date?, _ expected: Date?, toleranceSeconds: TimeInterval = 2.0, file: StaticString = #file, line: UInt = #line) {
    guard let a = actual, let e = expected else {
        XCTAssertEqual(actual, expected, "One or both dates are nil", file: file, line: line)
        return
    }
    let diff = abs(a.timeIntervalSince(e))
    XCTAssertLessThanOrEqual(diff, toleranceSeconds, "Date \(a) differs from \(e) by \(diff) seconds (tolerance: \(toleranceSeconds)s)", file: file, line: line)
}

public func assertCSVValid(_ csvString: String, expectedRowCount: Int? = nil, file: StaticString = #file, line: UInt = #line) {
    let lines = csvString.components(separatedBy: "\r\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    XCTAssertGreaterThanOrEqual(lines.count, 1, "CSV must contain at least a header row", file: file, line: line)

    let headerCols = lines[0].components(separatedBy: ",")
    XCTAssertGreaterThanOrEqual(headerCols.count, 5, "Header must have at least 5 columns", file: file, line: line)

    if let expRows = expectedRowCount {
        XCTAssertEqual(lines.count - 1, expRows, "Expected \(expRows) data rows in CSV, got \(lines.count - 1)", file: file, line: line)
    }

    for (idx, lineStr) in lines.enumerated() {
        let cols = lineStr.components(separatedBy: ",")
        XCTAssertEqual(cols.count, headerCols.count, "Row \(idx) column count \(cols.count) mismatch with header \(headerCols.count)", file: file, line: line)
    }
}

public func assertJSONValid(_ jsonString: String, requiredTopLevelKeys: [String] = [], file: StaticString = #file, line: UInt = #line) {
    guard let data = jsonString.data(using: .utf8) else {
        XCTFail("Failed to convert JSON string to Data", file: file, line: line)
        return
    }

    do {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Root JSON is not a dictionary", file: file, line: line)
            return
        }

        for key in requiredTopLevelKeys {
            XCTAssertNotNil(dict[key], "Required JSON key '\(key)' missing in root object", file: file, line: line)
        }
    } catch {
        XCTFail("JSON parsing failed with error: \(error)", file: file, line: line)
    }
}
