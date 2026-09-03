import Foundation

/// Represents the NVMe SMART Critical Warning byte (Byte 0 of Log ID 0x02).
///
/// Indicates critical device-level alerts including spare degradation, thermal threshold
/// violations, NVM subsystem reliability degradation, read-only locking, and backup power failure.
public struct CriticalWarningFlags: OptionSet, Sendable, Codable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Bit 0: Available spare capacity has fallen below the normalized threshold.
    public static let availableSpareBelowThreshold = CriticalWarningFlags(rawValue: 1 << 0) // 0x01

    /// Bit 1: Temperature is greater than or equal to an over-temperature threshold or less than an under-temperature threshold.
    public static let temperatureExceedsThreshold   = CriticalWarningFlags(rawValue: 1 << 1) // 0x02

    /// Bit 2: NVM subsystem reliability is degraded due to significant media errors or internal hardware failure.
    public static let reliabilityDegraded           = CriticalWarningFlags(rawValue: 1 << 2) // 0x04

    /// Bit 3: Media has been placed in Read-Only mode by controller to protect existing data.
    public static let readOnly                      = CriticalWarningFlags(rawValue: 1 << 3) // 0x08

    /// Bit 4: Volatile memory backup device (e.g. power-loss protection capacitor) has failed.
    public static let volatileMemoryBackupFailed    = CriticalWarningFlags(rawValue: 1 << 4) // 0x10

    /// Bit 5: Persistent memory region has become read-only or unreliable (NVMe 1.4+).
    public static let persistentMemoryUnreliable    = CriticalWarningFlags(rawValue: 1 << 5) // 0x20

    /// All defined standard flags mask (Bits 0–5).
    public static let allDefinedFlags: CriticalWarningFlags = [
        .availableSpareBelowThreshold,
        .temperatureExceedsThreshold,
        .reliabilityDegraded,
        .readOnly,
        .volatileMemoryBackupFailed,
        .persistentMemoryUnreliable
    ]

    /// Returns `true` if no warning bits are set.
    public var isClean: Bool {
        rawValue == 0
    }

    /// Returns `true` if any severe, non-transient hardware failure flag is set.
    public var isSevereHardwareAlert: Bool {
        contains(.reliabilityDegraded) || contains(.readOnly) || contains(.volatileMemoryBackupFailed)
    }

    /// Human-readable list of currently active warning descriptions.
    public var activeWarnings: [String] {
        var list: [String] = []
        if contains(.availableSpareBelowThreshold) {
            list.append("Available Spare Below Threshold")
        }
        if contains(.temperatureExceedsThreshold) {
            list.append("Temperature Exceeds Threshold")
        }
        if contains(.reliabilityDegraded) {
            list.append("NVM Subsystem Reliability Degraded")
        }
        if contains(.readOnly) {
            list.append("Drive in Read-Only Mode")
        }
        if contains(.volatileMemoryBackupFailed) {
            list.append("Volatile Memory Backup Device Failed")
        }
        if contains(.persistentMemoryUnreliable) {
            list.append("Persistent Memory Unreliable")
        }
        return list
    }

    public var description: String {
        if isClean {
            return "Clean (0x00)"
        }
        return "Critical Warnings (0x\(String(format: "%02X", rawValue))): " + activeWarnings.joined(separator: ", ")
    }
}
