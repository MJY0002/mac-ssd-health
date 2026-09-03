import Foundation

/// Parsed NVMe SMART / Health Information Log Page (Log ID 0x02, 512 Bytes).
///
/// Compliant with NVM Express Base Specification Revision 1.0c through 2.0.
public struct NVMESmartLog: Sendable, Codable, Equatable {
    // Byte 0
    public let criticalWarning: CriticalWarningFlags

    // Bytes 1–2 (Kelvin)
    public let compositeTemperatureKelvin: UInt16

    // Byte 3
    public let availableSparePercent: UInt8

    // Byte 4
    public let availableSpareThresholdPercent: UInt8

    // Byte 5
    public let percentageUsed: UInt8

    // Byte 6
    public let enduranceGroupSummary: UInt8

    // Bytes 32–47
    public let dataUnitsRead: UInt128Value

    // Bytes 48–63
    public let dataUnitsWritten: UInt128Value

    // Bytes 64–79
    public let hostReadCommands: UInt128Value

    // Bytes 80–95
    public let hostWriteCommands: UInt128Value

    // Bytes 96–111
    public let controllerBusyTimeMinutes: UInt128Value

    // Bytes 112–127
    public let powerCycles: UInt128Value

    // Bytes 128–143
    public let powerOnHours: UInt128Value

    // Bytes 144–159
    public let unsafeShutdowns: UInt128Value

    // Bytes 160–175
    public let mediaErrors: UInt128Value

    // Bytes 176–191
    public let numErrorInfoLogEntries: UInt128Value

    // Bytes 192–195
    public let warningCompositeTempTimeMinutes: UInt32

    // Bytes 196–199
    public let criticalCompositeTempTimeMinutes: UInt32

    // Bytes 200–215 (8 sensors of 2 bytes each in Kelvin)
    public let temperatureSensorsKelvin: [UInt16]

    // Bytes 216–219
    public let thermalManagementTemp1TransitionCount: UInt32

    // Bytes 220–223
    public let thermalManagementTemp2TransitionCount: UInt32

    // Bytes 224–227
    public let totalTimeForThermalManagementTemp1Seconds: UInt32

    // Bytes 228–231
    public let totalTimeForThermalManagementTemp2Seconds: UInt32

    // MARK: - Initializers

    public init(
        criticalWarning: CriticalWarningFlags,
        compositeTemperatureKelvin: UInt16,
        availableSparePercent: UInt8,
        availableSpareThresholdPercent: UInt8,
        percentageUsed: UInt8,
        enduranceGroupSummary: UInt8 = 0,
        dataUnitsRead: UInt128Value,
        dataUnitsWritten: UInt128Value,
        hostReadCommands: UInt128Value = .zero,
        hostWriteCommands: UInt128Value = .zero,
        controllerBusyTimeMinutes: UInt128Value = .zero,
        powerCycles: UInt128Value,
        powerOnHours: UInt128Value,
        unsafeShutdowns: UInt128Value,
        mediaErrors: UInt128Value,
        numErrorInfoLogEntries: UInt128Value,
        warningCompositeTempTimeMinutes: UInt32 = 0,
        criticalCompositeTempTimeMinutes: UInt32 = 0,
        temperatureSensorsKelvin: [UInt16] = [0, 0, 0, 0, 0, 0, 0, 0],
        thermalManagementTemp1TransitionCount: UInt32 = 0,
        thermalManagementTemp2TransitionCount: UInt32 = 0,
        totalTimeForThermalManagementTemp1Seconds: UInt32 = 0,
        totalTimeForThermalManagementTemp2Seconds: UInt32 = 0
    ) {
        self.criticalWarning = criticalWarning
        self.compositeTemperatureKelvin = compositeTemperatureKelvin
        self.availableSparePercent = availableSparePercent
        self.availableSpareThresholdPercent = availableSpareThresholdPercent
        self.percentageUsed = percentageUsed
        self.enduranceGroupSummary = enduranceGroupSummary
        self.dataUnitsRead = dataUnitsRead
        self.dataUnitsWritten = dataUnitsWritten
        self.hostReadCommands = hostReadCommands
        self.hostWriteCommands = hostWriteCommands
        self.controllerBusyTimeMinutes = controllerBusyTimeMinutes
        self.powerCycles = powerCycles
        self.powerOnHours = powerOnHours
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.numErrorInfoLogEntries = numErrorInfoLogEntries
        self.warningCompositeTempTimeMinutes = warningCompositeTempTimeMinutes
        self.criticalCompositeTempTimeMinutes = criticalCompositeTempTimeMinutes
        self.temperatureSensorsKelvin = temperatureSensorsKelvin.count == 8 ? temperatureSensorsKelvin : Array(temperatureSensorsKelvin.prefix(8)) + Array(repeating: UInt16(0), count: max(0, 8 - temperatureSensorsKelvin.count))
        self.thermalManagementTemp1TransitionCount = thermalManagementTemp1TransitionCount
        self.thermalManagementTemp2TransitionCount = thermalManagementTemp2TransitionCount
        self.totalTimeForThermalManagementTemp1Seconds = totalTimeForThermalManagementTemp1Seconds
        self.totalTimeForThermalManagementTemp2Seconds = totalTimeForThermalManagementTemp2Seconds
    }

    /// Decodes a 512-byte raw NVMe SMART log buffer (Log ID 0x02).
    ///
    /// Returns `nil` if `data.count < 512`.
    public init?(data: Data) {
        guard data.count >= 512 else {
            return nil
        }

        func readUInt16(offset: Int) -> UInt16 {
            data.withUnsafeBytes { raw in
                UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            }
        }

        func readUInt32(offset: Int) -> UInt32 {
            data.withUnsafeBytes { raw in
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }

        func readUInt64(offset: Int) -> UInt64 {
            data.withUnsafeBytes { raw in
                UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            }
        }

        func readUInt128(offset: Int) -> UInt128Value {
            let low = readUInt64(offset: offset)
            let high = readUInt64(offset: offset + 8)
            return UInt128Value(low: low, high: high)
        }

        self.criticalWarning = CriticalWarningFlags(rawValue: data[0])
        self.compositeTemperatureKelvin = readUInt16(offset: 1)
        self.availableSparePercent = data[3]
        self.availableSpareThresholdPercent = data[4]
        self.percentageUsed = data[5]
        self.enduranceGroupSummary = data[6]

        self.dataUnitsRead = readUInt128(offset: 32)
        self.dataUnitsWritten = readUInt128(offset: 48)
        self.hostReadCommands = readUInt128(offset: 64)
        self.hostWriteCommands = readUInt128(offset: 80)
        self.controllerBusyTimeMinutes = readUInt128(offset: 96)
        self.powerCycles = readUInt128(offset: 112)
        self.powerOnHours = readUInt128(offset: 128)
        self.unsafeShutdowns = readUInt128(offset: 144)
        self.mediaErrors = readUInt128(offset: 160)
        self.numErrorInfoLogEntries = readUInt128(offset: 176)

        self.warningCompositeTempTimeMinutes = readUInt32(offset: 192)
        self.criticalCompositeTempTimeMinutes = readUInt32(offset: 196)

        var sensors: [UInt16] = []
        for i in 0..<8 {
            sensors.append(readUInt16(offset: 200 + i * 2))
        }
        self.temperatureSensorsKelvin = sensors

        self.thermalManagementTemp1TransitionCount = readUInt32(offset: 216)
        self.thermalManagementTemp2TransitionCount = readUInt32(offset: 220)
        self.totalTimeForThermalManagementTemp1Seconds = readUInt32(offset: 224)
        self.totalTimeForThermalManagementTemp2Seconds = readUInt32(offset: 228)
    }

    // MARK: - Binary Serialization

    /// Encodes the model back into standard 512-byte binary format.
    public func toData() -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)

        bytes[0] = criticalWarning.rawValue

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

        writeUInt16(offset: 1, val: compositeTemperatureKelvin)
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

    // MARK: - Computed Properties & Conversions

    /// Composite temperature in Celsius ($T_{Celsius} = T_{Kelvin} - 273.15$).
    public var temperatureCelsius: Double {
        guard compositeTemperatureKelvin > 0 else { return 0.0 }
        return Double(compositeTemperatureKelvin) - 273.15
    }

    /// Composite temperature in Fahrenheit.
    public var temperatureFahrenheit: Double {
        temperatureCelsius * 1.8 + 32.0
    }

    /// Computed Health Score percentage ($100\% \to 0\%$).
    /// Clamped to $0\%$ if `percentageUsed > 100`.
    public var healthScorePercent: Int {
        max(0, 100 - Int(percentageUsed))
    }

    /// Total bytes written to storage ($1 \text{ unit} = 1000 \times 512\text{ bytes} = 512,000\text{ bytes}$).
    public var totalBytesWritten: Double {
        dataUnitsWritten.doubleValue * 512_000.0
    }

    /// Total Terabytes Written (TBW, base 10: $10^{12}$ bytes).
    public var totalTerabytesWritten: Double {
        totalBytesWritten / 1_000_000_000_000.0
    }

    /// Total Gigabytes Written (GB, base 10: $10^9$ bytes).
    public var totalGigabytesWritten: Double {
        totalBytesWritten / 1_000_000_000.0
    }

    /// Total bytes read from storage ($1 \text{ unit} = 512,000\text{ bytes}$).
    public var totalBytesRead: Double {
        dataUnitsRead.doubleValue * 512_000.0
    }

    /// Total Terabytes Read (TBR, base 10: $10^{12}$ bytes).
    public var totalTerabytesRead: Double {
        totalBytesRead / 1_000_000_000_000.0
    }

    /// Total Gigabytes Read (GB, base 10: $10^9$ bytes).
    public var totalGigabytesRead: Double {
        totalBytesRead / 1_000_000_000.0
    }

    /// Active temperature sensors converted to Celsius (filtering out unimplemented 0 K sensors).
    public var activeTemperatureSensorsCelsius: [Double] {
        temperatureSensorsKelvin
            .filter { $0 > 0 }
            .map { Double($0) - 273.15 }
    }
}
