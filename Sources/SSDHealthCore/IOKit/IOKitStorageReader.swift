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

    /// SMART page from the most recent `readHealthMetrics()`, so the `readRawSmartLog()` call that
    /// follows in the same poll reuses it instead of issuing a second hardware command.
    private let cacheLock = NSLock()
    private var cachedLog: (log: NVMESmartLog, readAt: Date)?
    private static let cacheLifetime: TimeInterval = 5.0

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
        if let cached = cacheLock.withLock({ cachedLog }),
           Date().timeIntervalSince(cached.readAt) < Self.cacheLifetime {
            return cached.log
        }
        let raw = try readRawBytesFromHardware()
        guard let log = NVMESmartLog(data: raw.data) else {
            throw StorageReaderError.invalidDataLength(expected: 512, actual: raw.data.count)
        }
        return log
    }

    /// Reads consolidated SSD health metrics, combining SMART telemetry with registry metadata.
    public func readHealthMetrics() async throws -> SSDHealthMetrics {
        do {
            let raw = try readRawBytesFromHardware()
            guard let log = NVMESmartLog(data: raw.data) else {
                throw StorageReaderError.invalidDataLength(expected: 512, actual: raw.data.count)
            }
            cacheLock.withLock { cachedLog = (log, Date()) }

            // Metadata must come from the same device the SMART log was read from
            let registryInfo = try readRegistryMetadata(registryEntryID: raw.registryEntryID)

            return SSDHealthMetrics(
                bsdName: registryInfo.bsdName,
                modelName: registryInfo.modelName,
                serialNumber: registryInfo.serialNumber,
                firmwareRevision: registryInfo.firmwareRevision,
                interconnect: registryInfo.interconnect,
                capacityBytes: registryInfo.capacityBytes,
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

    /// Reads the SMART page and returns it together with the registry entry ID of the device it came from.
    private func readRawBytesFromHardware() throws -> (data: Data, registryEntryID: UInt64) {
        let matching = IOServiceMatching(IOKitKeys.blockStorageDeviceClass)
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            throw StorageReaderError.deviceNotFound
        }
        defer { IOObjectRelease(iterator) }

        // Try internal devices first so an external NVMe enclosure never shadows the boot SSD
        var services: [io_service_t] = []
        var next = IOIteratorNext(iterator)
        while next != 0 {
            services.append(next)
            next = IOIteratorNext(iterator)
        }
        defer { services.forEach { _ = IOObjectRelease($0) } }
        services.sort { Self.isInternal($0) && !Self.isInternal($1) }

        var lastError: StorageReaderError? = nil

        for service in services {
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

            var entryID: UInt64 = 0
            _ = IORegistryEntryGetRegistryEntryID(service, &entryID)
            return (Data(buffer), entryID)
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

    /// Reads metadata of the internal storage device (first internal block device, else the first one found).
    public func readRegistryMetadata() throws -> RegistryMetadata {
        guard let service = Self.primaryBlockStorageDevice() else {
            return RegistryMetadata()
        }
        defer { IOObjectRelease(service) }
        return Self.metadata(for: service)
    }

    /// Reads metadata of exactly the device identified by `registryEntryID`.
    public func readRegistryMetadata(registryEntryID: UInt64) throws -> RegistryMetadata {
        guard let matching = IORegistryEntryIDMatching(registryEntryID) else {
            return try readRegistryMetadata()
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return try readRegistryMetadata()
        }
        defer { IOObjectRelease(service) }
        return Self.metadata(for: service)
    }

    private static func metadata(for service: io_service_t) -> RegistryMetadata {
        var meta = RegistryMetadata()

        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let props = unmanagedProps?.takeRetainedValue() as? [String: Any] {
            if let devChars = props[IOKitKeys.deviceCharacteristics] as? [String: Any] {
                if let pName = devChars[IOKitKeys.productName] as? String, !pName.isEmpty {
                    meta.modelName = pName.trimmingCharacters(in: .whitespaces)
                }
                if let sNum = devChars[IOKitKeys.serialNumber] as? String, !sNum.isEmpty {
                    meta.serialNumber = sNum.trimmingCharacters(in: .whitespaces)
                }
                if let rev = devChars[IOKitKeys.productRevisionLevel] as? String, !rev.isEmpty {
                    meta.firmwareRevision = rev.trimmingCharacters(in: .whitespaces)
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

        // IOMedia (BSD Name, Size) sits below the IOBlockStorageDriver child, so search recursively.
        // The whole-disk IOMedia is the first hit in depth-first order, before any partition media.
        let searchOptions = IOOptionBits(kIORegistryIterateRecursively)
        if let bsd = IORegistryEntrySearchCFProperty(service, kIOServicePlane, IOKitKeys.bsdName as CFString, kCFAllocatorDefault, searchOptions) as? String,
           !bsd.isEmpty {
            meta.bsdName = bsd
        }
        if let size = IORegistryEntrySearchCFProperty(service, kIOServicePlane, IOKitKeys.size as CFString, kCFAllocatorDefault, searchOptions) as? NSNumber,
           size.uint64Value > 0 {
            meta.capacityBytes = size.uint64Value
        }

        return meta
    }

    /// Returns `true` if the device reports an internal physical interconnect location.
    private static func isInternal(_ service: io_service_t) -> Bool {
        guard let proto = IORegistryEntryCreateCFProperty(service, IOKitKeys.protocolCharacteristics as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return false
        }
        return (proto[IOKitKeys.physicalInterconnectLocation] as? String) == "Internal"
    }

    /// Returns a retained handle to the internal block storage device, or the first device if none reports internal.
    private static func primaryBlockStorageDevice() -> io_service_t? {
        let matching = IOServiceMatching(IOKitKeys.blockStorageDeviceClass)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var first: io_service_t? = nil
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if isInternal(service) {
                if let f = first { _ = IOObjectRelease(f) }
                return service
            }
            if first == nil {
                first = service
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }
        return first
    }

    // MARK: - Graceful Fallback Telemetry (Non-Privileged / Sandbox)

    /// Builds placeholder metrics from IORegistry when SMART is unreachable.
    ///
    /// Health, temperature and spare values are placeholders, and the byte counters only cover the
    /// time since boot. Callers must not persist, forecast or alert on these (`isFallbackData == true`).
    public func readFallbackRegistryMetrics(underlyingError: Error) throws -> SSDHealthMetrics {
        var meta = RegistryMetadata()
        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0

        if let device = Self.primaryBlockStorageDevice() {
            defer { IOObjectRelease(device) }
            meta = Self.metadata(for: device)

            // Driver statistics of this device only (the IOBlockStorageDriver is a direct child)
            var childIterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(device, kIOServicePlane, &childIterator) == KERN_SUCCESS {
                var child = IOIteratorNext(childIterator)
                while child != 0 {
                    if IOObjectConformsTo(child, IOKitKeys.blockStorageDriverClass) != 0,
                       let stats = IORegistryEntryCreateCFProperty(child, IOKitKeys.driverStatistics as CFString, kCFAllocatorDefault, 0)?
                           .takeRetainedValue() as? [String: Any] {
                        bytesRead += (stats[IOKitKeys.bytesRead] as? NSNumber)?.uint64Value ?? 0
                        bytesWritten += (stats[IOKitKeys.bytesWritten] as? NSNumber)?.uint64Value ?? 0
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(childIterator)
                }
                IOObjectRelease(childIterator)
            }
        }

        let tbWritten = Double(bytesWritten) / 1_000_000_000_000.0
        let tbRead = Double(bytesRead) / 1_000_000_000_000.0

        return SSDHealthMetrics(
            bsdName: meta.bsdName,
            modelName: meta.modelName,
            serialNumber: meta.serialNumber.isEmpty ? "REGISTRY-FALLBACK" : meta.serialNumber,
            firmwareRevision: meta.firmwareRevision.isEmpty ? "N/A" : meta.firmwareRevision,
            interconnect: meta.interconnect,
            capacityBytes: meta.capacityBytes,
            healthScorePercent: 100, // Placeholder, not measured
            wearPercentage: 0,
            temperatureCelsius: 38.0, // Placeholder, not measured
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: tbWritten,
            terabytesRead: tbRead,
            powerOnHours: 0,
            powerCycles: 0,
            unsafeShutdowns: 0,
            // Driver I/O errors are not NVMe media errors and reset on reboot; never report them as such
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: Date(),
            isFallbackData: true
        )
    }
}
