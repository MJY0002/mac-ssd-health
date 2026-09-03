import Foundation

/// Errors that may occur during native IOKit or NVMe SMART telemetry reading.
public enum StorageReaderError: Error, LocalizedError, Sendable, Equatable, Hashable {
    case deviceNotFound
    case plugInCreationFailed(kernReturn: Int32)
    case interfaceQueryFailed(hresult: Int32)
    case smartReadFailed(kernReturn: Int32)
    case permissionDenied(reason: String)
    case unsupportedDevice(reason: String)
    case invalidDataLength(expected: Int, actual: Int)
    case registryReadFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No NVMe or Block Storage device found in IORegistry."
        case .plugInCreationFailed(let kr):
            return "Failed to create IOCFPlugIn interface (IOReturn: 0x\(String(format: "%08X", kr)))."
        case .interfaceQueryFailed(let hr):
            return "Failed to query IONVMeSMARTInterface (HRESULT: 0x\(String(format: "%08X", hr)))."
        case .smartReadFailed(let kr):
            return "NVMe SMART read command failed (IOReturn: 0x\(String(format: "%08X", kr)))."
        case .permissionDenied(let reason):
            return "Permission denied accessing NVMe SMART metrics: \(reason)"
        case .unsupportedDevice(let reason):
            return "Unsupported storage device: \(reason)"
        case .invalidDataLength(let expected, let actual):
            return "Invalid NVMe SMART log buffer size: expected \(expected) bytes, got \(actual) bytes."
        case .registryReadFailed(let reason):
            return "Failed to query IORegistry properties: \(reason)"
        }
    }
}

/// Abstract contract for reading SSD health metrics and raw SMART logs.
///
/// Implemented by `IOKitStorageReader` for live hardware and `MockSSDStorageReader` for previews and testing.
public protocol SSDStorageReading: Sendable {
    /// Reads comprehensive SSD health metrics asynchronously.
    func readHealthMetrics() async throws -> SSDHealthMetrics

    /// Reads the raw 512-byte NVMe SMART log page (Log ID 0x02).
    func readRawSmartLog() async throws -> NVMESmartLog

    /// Probes whether live native NVMe SMART UserClient hardware access is available.
    func isLiveHardwareAccessAvailable() -> Bool
}
