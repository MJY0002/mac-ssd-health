import Foundation

/// Configurable mock SSD storage reader for SwiftUI Previews, UI tests, and headless unit tests.
public final class MockSSDStorageReader: SSDStorageReading, @unchecked Sendable {

    /// Available simulation presets representing various SSD operational states.
    public enum Preset: Sendable, Equatable, Hashable {
        case healthy
        case warning
        case overheating
        case criticalWear
        case degradedSpare
        case simulatedError(StorageReaderError)

        public static var permissionDenied: Preset {
            .simulatedError(.permissionDenied(reason: "App Sandbox restricted NVMe SMART UserClient access."))
        }

        public static var deviceNotFound: Preset {
            .simulatedError(.deviceNotFound)
        }
    }

    private let lock = NSLock()
    private var _currentPreset: Preset
    private var _customMetrics: SSDHealthMetrics?
    private var _simulatedLatencyNanoseconds: UInt64 = 0

    public var currentPreset: Preset {
        get { lock.withLock { _currentPreset } }
        set { lock.withLock { _currentPreset = newValue } }
    }

    public var customMetrics: SSDHealthMetrics? {
        get { lock.withLock { _customMetrics } }
        set { lock.withLock { _customMetrics = newValue } }
    }

    public var simulatedLatencyNanoseconds: UInt64 {
        get { lock.withLock { _simulatedLatencyNanoseconds } }
        set { lock.withLock { _simulatedLatencyNanoseconds = newValue } }
    }

    // MARK: - Initializer

    public init(preset: Preset = .healthy, customMetrics: SSDHealthMetrics? = nil) {
        self._currentPreset = preset
        self._customMetrics = customMetrics
    }

    // MARK: - Configuration Methods

    public func setPreset(_ preset: Preset) {
        lock.withLock {
            self._currentPreset = preset
            self._customMetrics = nil
        }
    }

    public func setCustomMetrics(_ metrics: SSDHealthMetrics?) {
        lock.withLock {
            self._customMetrics = metrics
        }
    }

    public func setSimulatedLatency(milliseconds: Double) {
        lock.withLock {
            self._simulatedLatencyNanoseconds = UInt64(milliseconds * 1_000_000.0)
        }
    }

    // MARK: - SSDStorageReading Protocol Implementation

    public func isLiveHardwareAccessAvailable() -> Bool {
        lock.withLock {
            if case .simulatedError = _currentPreset {
                return false
            }
            return true
        }
    }

    public func readHealthMetrics() async throws -> SSDHealthMetrics {
        let (preset, custom, latency) = lock.withLock {
            (_currentPreset, _customMetrics, _simulatedLatencyNanoseconds)
        }

        if latency > 0 {
            try? await Task.sleep(nanoseconds: latency)
        }

        if let custom = custom {
            return custom
        }

        switch preset {
        case .healthy:
            return SSDHealthMetrics(
                bsdName: "disk0",
                modelName: "APPLE SSD AP0512R",
                serialNumber: "MOCK-HEALTHY-001",
                firmwareRevision: "741.140.",
                interconnect: "Apple Fabric",
                capacityBytes: 500_107_862_016,
                healthScorePercent: 98,
                wearPercentage: 2,
                temperatureCelsius: 33.5,
                availableSparePercent: 100,
                availableSpareThresholdPercent: 10,
                terabytesWritten: 14.82,
                terabytesRead: 28.51,
                powerOnHours: 1240,
                powerCycles: 310,
                unsafeShutdowns: 4,
                mediaErrors: 0,
                errorLogEntries: 0,
                criticalWarnings: CriticalWarningFlags(rawValue: 0),
                timestamp: Date(),
                isFallbackData: false
            )

        case .warning:
            return SSDHealthMetrics(
                bsdName: "disk0",
                modelName: "APPLE SSD AP1024R",
                serialNumber: "MOCK-WARN-002",
                firmwareRevision: "741.140.",
                interconnect: "Apple Fabric",
                capacityBytes: 1_000_204_886_016,
                healthScorePercent: 72,
                wearPercentage: 28,
                temperatureCelsius: 56.0,
                availableSparePercent: 88,
                availableSpareThresholdPercent: 10,
                terabytesWritten: 182.40,
                terabytesRead: 245.10,
                powerOnHours: 8940,
                powerCycles: 1420,
                unsafeShutdowns: 38,
                mediaErrors: 0,
                errorLogEntries: 2,
                criticalWarnings: CriticalWarningFlags(rawValue: 0),
                timestamp: Date(),
                isFallbackData: false
            )

        case .overheating:
            return SSDHealthMetrics(
                bsdName: "disk0",
                modelName: "APPLE SSD AP0512R",
                serialNumber: "MOCK-HOT-003",
                firmwareRevision: "741.140.",
                interconnect: "Apple Fabric",
                capacityBytes: 500_107_862_016,
                healthScorePercent: 85,
                wearPercentage: 15,
                temperatureCelsius: 76.5,
                availableSparePercent: 95,
                availableSpareThresholdPercent: 10,
                terabytesWritten: 75.30,
                terabytesRead: 110.20,
                powerOnHours: 4200,
                powerCycles: 850,
                unsafeShutdowns: 12,
                mediaErrors: 0,
                errorLogEntries: 1,
                criticalWarnings: [.temperatureExceedsThreshold],
                timestamp: Date(),
                isFallbackData: false
            )

        case .criticalWear:
            return SSDHealthMetrics(
                bsdName: "disk0",
                modelName: "APPLE SSD AP0256Q",
                serialNumber: "MOCK-CRIT-004",
                firmwareRevision: "561.100.",
                interconnect: "Apple Fabric",
                capacityBytes: 251_000_193_024,
                healthScorePercent: 4,
                wearPercentage: 96,
                temperatureCelsius: 48.0,
                availableSparePercent: 8,
                availableSpareThresholdPercent: 10,
                terabytesWritten: 495.60,
                terabytesRead: 610.80,
                powerOnHours: 19800,
                powerCycles: 3200,
                unsafeShutdowns: 84,
                mediaErrors: 14,
                errorLogEntries: 32,
                criticalWarnings: [.availableSpareBelowThreshold],
                timestamp: Date(),
                isFallbackData: false
            )

        case .degradedSpare:
            return SSDHealthMetrics(
                bsdName: "disk0",
                modelName: "APPLE SSD AP0512R",
                serialNumber: "MOCK-DEGRADED-005",
                firmwareRevision: "741.140.",
                interconnect: "Apple Fabric",
                capacityBytes: 500_107_862_016,
                healthScorePercent: 35,
                wearPercentage: 65,
                temperatureCelsius: 44.0,
                availableSparePercent: 5,
                availableSpareThresholdPercent: 10,
                terabytesWritten: 310.20,
                terabytesRead: 450.00,
                powerOnHours: 14200,
                powerCycles: 2100,
                unsafeShutdowns: 55,
                mediaErrors: 42,
                errorLogEntries: 89,
                criticalWarnings: [.availableSpareBelowThreshold, .reliabilityDegraded],
                timestamp: Date(),
                isFallbackData: false
            )

        case .simulatedError(let error):
            throw error
        }
    }

    public func readRawSmartLog() async throws -> NVMESmartLog {
        let metrics = try await readHealthMetrics()
        let data = Self.generateSyntheticRawData(for: metrics)
        guard let log = NVMESmartLog(data: data) else {
            throw StorageReaderError.invalidDataLength(expected: 512, actual: data.count)
        }
        return log
    }

    // MARK: - Binary Synthesizer

    /// Generates a valid 512-byte binary NVMe SMART block matching the given health metrics.
    public static func generateSyntheticRawData(for metrics: SSDHealthMetrics) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)

        bytes[0] = metrics.criticalWarnings.rawValue

        let tempKelvin = UInt16(Self.clampedUInt64(metrics.temperatureCelsius + 273.15, max: Double(UInt16.max)))
        var tempKLE = tempKelvin.littleEndian
        withUnsafeBytes(of: &tempKLE) { raw in
            bytes[1] = raw[0]
            bytes[2] = raw[1]
        }

        bytes[3] = UInt8(clamping: metrics.availableSparePercent)
        bytes[4] = UInt8(clamping: metrics.availableSpareThresholdPercent)
        bytes[5] = UInt8(clamping: metrics.wearPercentage)

        let unitsWritten = Self.clampedUInt64((metrics.terabytesWritten * 1_000_000_000_000.0) / 512_000.0)
        let unitsRead = Self.clampedUInt64((metrics.terabytesRead * 1_000_000_000_000.0) / 512_000.0)

        func writeUInt64(offset: Int, val: UInt64) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<8 { bytes[offset + i] = raw[i] }
            }
        }

        writeUInt64(offset: 32, val: unitsRead)
        writeUInt64(offset: 48, val: unitsWritten)
        writeUInt64(offset: 112, val: metrics.powerCycles)
        writeUInt64(offset: 128, val: metrics.powerOnHours)
        writeUInt64(offset: 144, val: metrics.unsafeShutdowns)
        writeUInt64(offset: 160, val: metrics.mediaErrors)
        writeUInt64(offset: 176, val: metrics.errorLogEntries)

        // Set primary sensor
        withUnsafeBytes(of: &tempKLE) { raw in
            bytes[200] = raw[0]
            bytes[201] = raw[1]
        }

        return Data(bytes)
    }

    /// Rounds and clamps into `0...max`; NaN maps to 0. Plain `UInt64(_:)` traps on NaN, negatives and overflow.
    private static func clampedUInt64(_ value: Double, max upper: Double = 18_446_744_073_709_549_568.0) -> UInt64 {
        guard value.isFinite else { return value == .infinity ? UInt64(upper) : 0 }
        let rounded = value.rounded()
        if rounded <= 0 { return 0 }
        if rounded >= upper { return UInt64(upper) }
        return UInt64(rounded)
    }
}
