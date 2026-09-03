import Foundation

/// Consolidated snapshot of SSD hardware telemetry and SMART health metrics.
///
/// Combines low-level NVMe SMART parameters with IOKit registry device descriptors.
public struct SSDHealthMetrics: Sendable, Codable, Equatable, Identifiable {
    /// Unique identifier based on drive serial number or BSD device node name.
    public var id: String {
        serialNumber.isEmpty ? bsdName : serialNumber
    }

    // MARK: - Hardware Identification & Topology
    public let bsdName: String                   // e.g. "disk0"
    public let modelName: String                 // e.g. "APPLE SSD AP0256Q"
    public let serialNumber: String              // e.g. "0ba018e2018c480f"
    public let firmwareRevision: String          // e.g. "561.100."
    public let interconnect: String              // e.g. "Apple Fabric" / "PCI-Express"
    public let capacityBytes: UInt64             // e.g. 251000193024

    // MARK: - Wear & Health Indicators
    public let healthScorePercent: Int           // 0 - 100%
    public let wearPercentage: Int               // 0 - 255% (Percentage Used)
    public let temperatureCelsius: Double        // e.g. 39.0 °C
    public let availableSparePercent: Int        // e.g. 100%
    public let availableSpareThresholdPercent: Int // e.g. 10%

    // MARK: - Cumulative Lifetime Counters
    public let terabytesWritten: Double          // e.g. 131.69 TBW
    public let terabytesRead: Double             // e.g. 269.09 TB Read
    public let powerOnHours: UInt64              // e.g. 2472 hrs
    public let powerCycles: UInt64               // e.g. 413
    public let unsafeShutdowns: UInt64           // e.g. 23
    public let mediaErrors: UInt64               // e.g. 0
    public let errorLogEntries: UInt64           // e.g. 0

    // MARK: - Diagnostics & Metadata
    public let criticalWarnings: CriticalWarningFlags
    public let timestamp: Date
    public let isFallbackData: Bool

    // MARK: - Initializer

    public init(
        bsdName: String,
        modelName: String,
        serialNumber: String,
        firmwareRevision: String,
        interconnect: String,
        capacityBytes: UInt64,
        healthScorePercent: Int,
        wearPercentage: Int,
        temperatureCelsius: Double,
        availableSparePercent: Int,
        availableSpareThresholdPercent: Int,
        terabytesWritten: Double,
        terabytesRead: Double,
        powerOnHours: UInt64,
        powerCycles: UInt64,
        unsafeShutdowns: UInt64,
        mediaErrors: UInt64,
        errorLogEntries: UInt64,
        criticalWarnings: CriticalWarningFlags,
        timestamp: Date = Date(),
        isFallbackData: Bool = false
    ) {
        self.bsdName = bsdName
        self.modelName = modelName
        self.serialNumber = serialNumber
        self.firmwareRevision = firmwareRevision
        self.interconnect = interconnect
        self.capacityBytes = capacityBytes
        self.healthScorePercent = healthScorePercent
        self.wearPercentage = wearPercentage
        self.temperatureCelsius = temperatureCelsius
        self.availableSparePercent = availableSparePercent
        self.availableSpareThresholdPercent = availableSpareThresholdPercent
        self.terabytesWritten = terabytesWritten
        self.terabytesRead = terabytesRead
        self.powerOnHours = powerOnHours
        self.powerCycles = powerCycles
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.errorLogEntries = errorLogEntries
        self.criticalWarnings = criticalWarnings
        self.timestamp = timestamp
        self.isFallbackData = isFallbackData
    }

    // MARK: - Formatted Helpers

    /// Formatted capacity string (e.g. "251.0 GB" or "1.00 TB").
    public var capacityFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .decimal
        return formatter.string(fromByteCount: Int64(capacityBytes))
    }

    /// Formatted temperature string (e.g. "38.5 °C").
    public var temperatureFormatted: String {
        String(format: "%.1f °C", temperatureCelsius)
    }

    /// Formatted TBW string (e.g. "131.69 TBW").
    public var tbwFormatted: String {
        String(format: "%.2f TBW", terabytesWritten)
    }

    /// Formatted TB Read string (e.g. "269.09 TB Read").
    public var tbrFormatted: String {
        String(format: "%.2f TB Read", terabytesRead)
    }

    /// Formatted wear percentage (e.g. "9%").
    public var wearFormatted: String {
        "\(wearPercentage)%"
    }

    /// Formatted health score (e.g. "91%").
    public var healthScoreFormatted: String {
        "\(healthScorePercent)%"
    }

    /// Indicates whether the drive passes all primary health criteria.
    public var isHealthy: Bool {
        criticalWarnings.isClean &&
        healthScorePercent > 20 &&
        availableSparePercent >= availableSpareThresholdPercent &&
        temperatureCelsius < 65.0 &&
        mediaErrors == 0
    }
}
