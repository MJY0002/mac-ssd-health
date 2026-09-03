import Foundation
import CoreFoundation

/// Constants and identifiers for IOKit storage registry traversal and NVMe SMART queries.
public enum IOKitKeys {
    // MARK: - Service Classes
    public static let blockStorageDeviceClass = "IOBlockStorageDevice"
    public static let blockStorageDriverClass = "IOBlockStorageDriver"
    public static let mediaClass = "IOMedia"
    public static let appleANS3NVMeController = "AppleANS3NVMeController"
    public static let appleANS2NVMeController = "AppleANS2NVMeController"
    public static let ioNVMeController = "IONVMeController"

    // MARK: - Matching Properties
    public static let nvmeSMARTCapable = "NVMe SMART Capable"

    // MARK: - Device Characteristics (IOStorageDeviceCharacteristics.h)
    public static let deviceCharacteristics = "Device Characteristics"
    public static let vendorName = "Vendor Name"
    public static let productName = "Product Name"
    public static let productRevisionLevel = "Product Revision Level"
    public static let serialNumber = "Serial Number"
    public static let mediumType = "Medium Type"
    public static let physicalBlockSize = "Physical Block Size"
    public static let logicalBlockSize = "Logical Block Size"

    // MARK: - Protocol Characteristics (IOStorageProtocolCharacteristics.h)
    public static let protocolCharacteristics = "Protocol Characteristics"
    public static let physicalInterconnect = "Physical Interconnect"
    public static let physicalInterconnectLocation = "Physical Interconnect Location"

    // MARK: - Driver Statistics (IOBlockStorageDriver.h)
    public static let driverStatistics = "Statistics"
    public static let bytesRead = "Bytes (Read)"
    public static let bytesWritten = "Bytes (Write)"
    public static let operationsRead = "Operations (Read)"
    public static let operationsWrite = "Operations (Write)"
    public static let errorsRead = "Errors (Read)"
    public static let errorsWrite = "Errors (Write)"
    public static let totalTimeRead = "Total Time (Read)"
    public static let totalTimeWrite = "Total Time (Write)"

    // MARK: - Media Properties
    public static let bsdName = "BSD Name"
    public static let size = "Size"
    public static let preferredBlockSize = "Preferred Block Size"

    // MARK: - NVMe Controller Properties
    public static let modelNumber = "Model Number"
    public static let firmwareRevision = "Firmware Revision"

    // MARK: - CFUUID Identifiers for NVMe SMART Plugin & Interfaces

    /// AA0FA6F9-C2D6-457F-B10B-59A13253292F
    public static nonisolated(unsafe) let nvmeSMARTUserClientTypeID: CFUUID = CFUUIDGetConstantUUIDWithBytes(
        nil,
        0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F,
        0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F
    )

    /// C244E858-109C-11D4-91D4-0050E4C6426F
    public static nonisolated(unsafe) let cfPlugInInterfaceID: CFUUID = CFUUIDGetConstantUUIDWithBytes(
        nil,
        0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
        0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F
    )

    /// CCD1DB19-FD9A-4DAF-BF95-12454B230AB6
    public static nonisolated(unsafe) let nvmeSMARTInterfaceID: CFUUID = CFUUIDGetConstantUUIDWithBytes(
        nil,
        0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF,
        0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6
    )

    /// 68413F59-268A-4787-BC48-7F9960235647
    public static nonisolated(unsafe) let nvmeSMARTLibFactoryID: CFUUID = CFUUIDGetConstantUUIDWithBytes(
        nil,
        0x68, 0x41, 0x3F, 0x59, 0x26, 0x8A, 0x47, 0x87,
        0xBC, 0x48, 0x7F, 0x99, 0x60, 0x23, 0x56, 0x47
    )
}
