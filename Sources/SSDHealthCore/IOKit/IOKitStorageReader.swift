import Foundation
import IOKit
import CoreFoundation

/// Native macOS storage reader using IOKit UserClient and IORegistry.
///
/// Communicates directly with the Apple NVMe controller via `IOCFPlugIn` and `IONVMeSMARTInterface`
/// to read standard 512-byte SMART logs (Log ID 0x02). If direct hardware access is blocked
/// (e.g. within an App Sandbox), it seamlessly falls back to querying `IORegistry` properties
/// and driver I/O counters without throwing unhandled exceptions.
public final class IOKitStorageReader: SSDStorageReading, @unchecked Sendable {

    public init() {}

    // MARK: - Public API

    /// Returns `true` if native NVMe SMART UserClient hardware access is currently available.
    public func isLiveHardwareAccessAvailable() -> Bool {
        do {
            _ = try readRawBytesFromHardware()
            return true
        } catch {
            return false
        }
    }

    /// Reads and parses the raw 512-byte NVMe SMART log page directly from hardware.
    public func readRawSmartLog() async throws -> NVMESmartLog {
        let rawData = try readRawBytesFromHardware()
        guard let log = NVMESmartLog(data: rawData) else {
            throw StorageReaderError.invalidDataLength(expected: 512, actual: rawData.count)
        }
        return log
    }

    /// Reads consolidated SSD health metrics, combining SMART telemetry with registry metadata.
    public func readHealthMetrics() async throws -> SSDHealthMetrics {
        do {
            let log = try await readRawSmartLog()
            let registryInfo = try readRegistryMetadata()

            return SSDHealthMetrics(
                bsdName: registryInfo.bsdName,
                modelName: registryInfo.modelName,
                serialNumber: registryInfo.serialNumber,
                firmwareRevision: registryInfo.firmwareRevision,
                interconnect: registryInfo.interconnect,
                capacityBytes: registryInfo.capacityBytes > 0 ? registryInfo.capacityBytes : 256_000_000_000,
                healthScorePercent: log.healthScorePercent,
                wearPercentage: Int(log.percentageUsed),
                temperatureCelsius: log.temperatureCelsius,
                availableSparePercent: Int(log.availableSparePercent),
                availableSpareThresholdPercent: Int(log.availableSpareThresholdPercent),
                terabytesWritten: log.totalTerabytesWritten,
                terabytesRead: log.totalTerabytesRead,
                powerOnHours: log.powerOnHours.low,
                powerCycles: log.powerCycles.low,
                unsafeShutdowns: log.unsafeShutdowns.low,
                mediaErrors: log.mediaErrors.low,
                errorLogEntries: log.numErrorInfoLogEntries.low,
                criticalWarnings: log.criticalWarning,
                timestamp: Date(),
                isFallbackData: false
            )
        } catch {
            // Graceful Fallback for non-privileged / sandboxed runtimes
            return try readFallbackRegistryMetrics(underlyingError: error)
        }
    }

    // MARK: - Low-Level NVMe SMART UserClient Query via IOCFPlugIn

    private func readRawBytesFromHardware() throws -> Data {
        let matching = IOServiceMatching(IOKitKeys.blockStorageDeviceClass)
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            throw StorageReaderError.deviceNotFound
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        var lastError: StorageReaderError? = nil

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>? = nil
            var score: Int32 = 0

            let plugInRes = IOCreatePlugInInterfaceForService(
                service,
                IOKitKeys.nvmeSMARTUserClientTypeID,
                IOKitKeys.cfPlugInInterfaceID,
                &plugInInterface,
                &score
            )

            guard plugInRes == kIOReturnSuccess, let plugIn = plugInInterface else {
                if plugInRes != kIOReturnSuccess && plugInRes != kIOReturnUnsupported {
                    lastError = .plugInCreationFailed(kernReturn: plugInRes)
                }
                continue
            }
            defer { _ = IODestroyPlugInInterface(plugIn) }

            var smartInterfacePtr: UnsafeMutableRawPointer? = nil
            let queryRes = plugIn.pointee?.pointee.QueryInterface(
                plugIn,
                CFUUIDGetUUIDBytes(IOKitKeys.nvmeSMARTInterfaceID),
                &smartInterfacePtr
            )

            guard queryRes == 0, let rawSmart = smartInterfacePtr else {
                if let qr = queryRes, qr != 0 {
                    lastError = .interfaceQueryFailed(hresult: qr)
                }
                continue
            }

            typealias SMARTReadDataFunc = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> IOReturn
            typealias ReleaseFunc = @convention(c) (UnsafeMutableRawPointer) -> UInt32

            let interfaceStructPtr = rawSmart.assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutableRawPointer>.self).pointee
            let smartReadDataPtr = UnsafeMutableRawPointer(interfaceStructPtr.advanced(by: 5)).assumingMemoryBound(to: SMARTReadDataFunc.self).pointee
            let releaseFunc = UnsafeMutableRawPointer(interfaceStructPtr.advanced(by: 3)).assumingMemoryBound(to: ReleaseFunc.self).pointee
            defer { _ = releaseFunc(rawSmart) }

            var buffer = [UInt8](repeating: 0, count: 512)
            let smartKr = smartReadDataPtr(rawSmart, &buffer)
            guard smartKr == kIOReturnSuccess else {
                lastError = .smartReadFailed(kernReturn: smartKr)
                continue
            }

            return Data(buffer)
        }

        if let err = lastError {
            throw err
        }
        throw StorageReaderError.deviceNotFound
    }

    // MARK: - Registry Metadata Query

    public struct RegistryMetadata: Sendable {
        public var bsdName: String = "disk0"
        public var modelName: String = "Apple Internal SSD"
        public var serialNumber: String = ""
        public var firmwareRevision: String = ""
        public var interconnect: String = "Apple Fabric"
        public var capacityBytes: UInt64 = 0
    }

    public func readRegistryMetadata() throws -> RegistryMetadata {
        var meta = RegistryMetadata()
        let matching = IOServiceMatching(IOKitKeys.blockStorageDeviceClass)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return meta
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var unmanagedProps: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = unmanagedProps?.takeRetainedValue() as? [String: Any] {
                if let devChars = props[IOKitKeys.deviceCharacteristics] as? [String: Any] {
                    if let pName = devChars[IOKitKeys.productName] as? String, !pName.isEmpty {
                        meta.modelName = pName
                    }
                    if let sNum = devChars[IOKitKeys.serialNumber] as? String, !sNum.isEmpty {
                        meta.serialNumber = sNum
                    }
                    if let rev = devChars[IOKitKeys.productRevisionLevel] as? String, !rev.isEmpty {
                        meta.firmwareRevision = rev
                    }
                }
                if let protoChars = props[IOKitKeys.protocolCharacteristics] as? [String: Any] {
                    if let inter = protoChars[IOKitKeys.physicalInterconnect] as? String, !inter.isEmpty {
                        meta.interconnect = inter
                    }
                }
            }

            // Inspect parent controller node
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                var parentProps: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(parent, &parentProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let pprops = parentProps?.takeRetainedValue() as? [String: Any] {
                    if let mNum = pprops[IOKitKeys.modelNumber] as? String, meta.modelName == "Apple Internal SSD" {
                        meta.modelName = mNum
                    }
                    if let sNum = pprops[IOKitKeys.serialNumber] as? String, meta.serialNumber.isEmpty {
                        meta.serialNumber = sNum
                    }
                    if let rev = pprops[IOKitKeys.firmwareRevision] as? String, meta.firmwareRevision.isEmpty {
                        meta.firmwareRevision = rev
                    }
                }
                IOObjectRelease(parent)
            }

            // Inspect child media for BSD Name and Capacity Size
            var childIterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == KERN_SUCCESS {
                var child = IOIteratorNext(childIterator)
                while child != 0 {
                    var childProps: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(child, &childProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let cprops = childProps?.takeRetainedValue() as? [String: Any] {
                        if let bsd = cprops[IOKitKeys.bsdName] as? String, !bsd.isEmpty {
                            meta.bsdName = bsd
                        }
                        if let sz = cprops[IOKitKeys.size] as? UInt64, sz > 0 {
                            meta.capacityBytes = sz
                        }
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(childIterator)
                }
                IOObjectRelease(childIterator)
            }
        }
        return meta
    }

    // MARK: - Graceful Fallback Telemetry (Non-Privileged / Sandbox)

    public func readFallbackRegistryMetrics(underlyingError: Error) throws -> SSDHealthMetrics {
        let meta = try readRegistryMetadata()

        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        var readErrors: UInt64 = 0
        var writeErrors: UInt64 = 0

        let matching = IOServiceMatching(IOKitKeys.blockStorageDriverClass)
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
            var driver = IOIteratorNext(iterator)
            while driver != 0 {
                var unmanagedProps: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(driver, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let props = unmanagedProps?.takeRetainedValue() as? [String: Any],
                   let stats = props[IOKitKeys.driverStatistics] as? [String: Any] {
                    bytesRead += (stats[IOKitKeys.bytesRead] as? UInt64) ?? 0
                    bytesWritten += (stats[IOKitKeys.bytesWritten] as? UInt64) ?? 0
                    readErrors += (stats[IOKitKeys.errorsRead] as? UInt64) ?? 0
                    writeErrors += (stats[IOKitKeys.errorsWrite] as? UInt64) ?? 0
                }
                IOObjectRelease(driver)
                driver = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        let tbWritten = Double(bytesWritten) / 1_000_000_000_000.0
        let tbRead = Double(bytesRead) / 1_000_000_000_000.0

        return SSDHealthMetrics(
            bsdName: meta.bsdName,
            modelName: meta.modelName,
            serialNumber: meta.serialNumber.isEmpty ? "REGISTRY-FALLBACK" : meta.serialNumber,
            firmwareRevision: meta.firmwareRevision.isEmpty ? "N/A" : meta.firmwareRevision,
            interconnect: meta.interconnect,
            capacityBytes: meta.capacityBytes > 0 ? meta.capacityBytes : 256_000_000_000,
            healthScorePercent: 100, // Non-intrusive fallback baseline
            wearPercentage: 0,
            temperatureCelsius: 38.0, // Ambient baseline
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: tbWritten,
            terabytesRead: tbRead,
            powerOnHours: 0,
            powerCycles: 0,
            unsafeShutdowns: 0,
            mediaErrors: readErrors + writeErrors,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: Date(),
            isFallbackData: true
        )
    }
}
