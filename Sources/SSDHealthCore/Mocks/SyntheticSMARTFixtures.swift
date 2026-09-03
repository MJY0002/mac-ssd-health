import Foundation

/// Provides standardized synthetic 512-byte binary NVMe SMART buffers for testing, previews, and fuzzing.
public enum SyntheticSMARTFixtures {

    /// Constructs a customized 512-byte NVMe SMART binary buffer with exact byte layout.
    public static func makeCustomBuffer(
        criticalWarning: UInt8 = 0,
        temperatureKelvin: UInt16 = 305, // 31.85 °C
        availableSpare: UInt8 = 100,
        availableSpareThreshold: UInt8 = 10,
        percentageUsed: UInt8 = 0,
        enduranceGroupSummary: UInt8 = 0,
        dataUnitsRead: UInt64 = 1_000_000,
        dataUnitsWritten: UInt64 = 500_000,
        dataUnitsWrittenHigh: UInt64 = 0,
        hostReadCommands: UInt64 = 2_000_000,
        hostWriteCommands: UInt64 = 1_000_000,
        controllerBusyTimeMinutes: UInt64 = 600,
        powerCycles: UInt64 = 150,
        powerOnHours: UInt64 = 800,
        unsafeShutdowns: UInt64 = 3,
        mediaErrors: UInt64 = 0,
        numErrorInfoLogEntries: UInt64 = 0,
        warningCompTempTime: UInt32 = 0,
        criticalCompTempTime: UInt32 = 0,
        temperatureSensorsKelvin: [UInt16] = [305, 303, 0, 0, 0, 0, 0, 0],
        thermalManagementTemp1TransitionCount: UInt32 = 0,
        thermalManagementTemp2TransitionCount: UInt32 = 0,
        totalTimeForThermalManagementTemp1Seconds: UInt32 = 0,
        totalTimeForThermalManagementTemp2Seconds: UInt32 = 0
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)

        bytes[0] = criticalWarning

        func write16(offset: Int, val: UInt16) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<2 { bytes[offset + i] = raw[i] }
            }
        }

        func write32(offset: Int, val: UInt32) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<4 { bytes[offset + i] = raw[i] }
            }
        }

        func write64(offset: Int, val: UInt64) {
            var v = val.littleEndian
            withUnsafeBytes(of: &v) { raw in
                for i in 0..<8 { bytes[offset + i] = raw[i] }
            }
        }

        write16(offset: 1, val: temperatureKelvin)
        bytes[3] = availableSpare
        bytes[4] = availableSpareThreshold
        bytes[5] = percentageUsed
        bytes[6] = enduranceGroupSummary

        write64(offset: 32, val: dataUnitsRead)
        write64(offset: 40, val: 0)

        write64(offset: 48, val: dataUnitsWritten)
        write64(offset: 56, val: dataUnitsWrittenHigh)

        write64(offset: 64, val: hostReadCommands)
        write64(offset: 72, val: 0)

        write64(offset: 80, val: hostWriteCommands)
        write64(offset: 88, val: 0)

        write64(offset: 96, val: controllerBusyTimeMinutes)
        write64(offset: 104, val: 0)

        write64(offset: 112, val: powerCycles)
        write64(offset: 120, val: 0)

        write64(offset: 128, val: powerOnHours)
        write64(offset: 136, val: 0)

        write64(offset: 144, val: unsafeShutdowns)
        write64(offset: 152, val: 0)

        write64(offset: 160, val: mediaErrors)
        write64(offset: 168, val: 0)

        write64(offset: 176, val: numErrorInfoLogEntries)
        write64(offset: 184, val: 0)

        write32(offset: 192, val: warningCompTempTime)
        write32(offset: 196, val: criticalCompTempTime)

        for i in 0..<min(8, temperatureSensorsKelvin.count) {
            write16(offset: 200 + i * 2, val: temperatureSensorsKelvin[i])
        }

        write32(offset: 216, val: thermalManagementTemp1TransitionCount)
        write32(offset: 220, val: thermalManagementTemp2TransitionCount)
        write32(offset: 224, val: totalTimeForThermalManagementTemp1Seconds)
        write32(offset: 228, val: totalTimeForThermalManagementTemp2Seconds)

        return Data(bytes)
    }

    /// Healthy NVMe drive (2% wear, 33.5 °C, 100% spare, 0 warnings).
    public static func healthyRawBuffer() -> Data {
        let tempK = UInt16(round(33.5 + 273.15)) // 307 K
        let tbwUnits = UInt64(round((14.82 * 1_000_000_000_000.0) / 512_000.0)) // ~28,945,313 units
        let tbrUnits = UInt64(round((28.51 * 1_000_000_000_000.0) / 512_000.0)) // ~55,683,594 units

        return makeCustomBuffer(
            criticalWarning: 0x00,
            temperatureKelvin: tempK,
            availableSpare: 100,
            availableSpareThreshold: 10,
            percentageUsed: 2,
            dataUnitsRead: tbrUnits,
            dataUnitsWritten: tbwUnits,
            powerCycles: 310,
            powerOnHours: 1240,
            unsafeShutdowns: 4,
            mediaErrors: 0,
            numErrorInfoLogEntries: 0,
            temperatureSensorsKelvin: [tempK, tempK - 2, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Warning condition (28% wear, 56.0 °C, 88% spare).
    public static func warningRawBuffer() -> Data {
        let tempK = UInt16(round(56.0 + 273.15)) // 329 K
        let tbwUnits = UInt64(round((182.40 * 1_000_000_000_000.0) / 512_000.0))
        let tbrUnits = UInt64(round((245.10 * 1_000_000_000_000.0) / 512_000.0))

        return makeCustomBuffer(
            criticalWarning: 0x00,
            temperatureKelvin: tempK,
            availableSpare: 88,
            availableSpareThreshold: 10,
            percentageUsed: 28,
            dataUnitsRead: tbrUnits,
            dataUnitsWritten: tbwUnits,
            powerCycles: 1420,
            powerOnHours: 8940,
            unsafeShutdowns: 38,
            mediaErrors: 0,
            numErrorInfoLogEntries: 2,
            temperatureSensorsKelvin: [tempK, tempK - 3, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Overheating condition (76.5 °C, temperature warning bit active).
    public static func overheatingRawBuffer() -> Data {
        let tempK = UInt16(round(76.5 + 273.15)) // 350 K
        let tbwUnits = UInt64(round((75.30 * 1_000_000_000_000.0) / 512_000.0))
        let tbrUnits = UInt64(round((110.20 * 1_000_000_000_000.0) / 512_000.0))

        return makeCustomBuffer(
            criticalWarning: 0x02, // temperatureExceedsThreshold
            temperatureKelvin: tempK,
            availableSpare: 95,
            availableSpareThreshold: 10,
            percentageUsed: 15,
            dataUnitsRead: tbrUnits,
            dataUnitsWritten: tbwUnits,
            powerCycles: 850,
            powerOnHours: 4200,
            unsafeShutdowns: 12,
            mediaErrors: 0,
            numErrorInfoLogEntries: 1,
            warningCompTempTime: 45,
            criticalCompTempTime: 5,
            temperatureSensorsKelvin: [tempK, tempK + 2, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Critical wear condition (96% wear, spare capacity low 8%).
    public static func criticalWearRawBuffer() -> Data {
        let tempK = UInt16(round(48.0 + 273.15)) // 321 K
        let tbwUnits = UInt64(round((495.60 * 1_000_000_000_000.0) / 512_000.0))
        let tbrUnits = UInt64(round((610.80 * 1_000_000_000_000.0) / 512_000.0))

        return makeCustomBuffer(
            criticalWarning: 0x01, // availableSpareBelowThreshold
            temperatureKelvin: tempK,
            availableSpare: 8,
            availableSpareThreshold: 10,
            percentageUsed: 96,
            dataUnitsRead: tbrUnits,
            dataUnitsWritten: tbwUnits,
            powerCycles: 3200,
            powerOnHours: 19800,
            unsafeShutdowns: 84,
            mediaErrors: 14,
            numErrorInfoLogEntries: 32,
            temperatureSensorsKelvin: [tempK, tempK - 1, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Degraded spare condition (5% spare, reliability degraded warning bit).
    public static func degradedSpareRawBuffer() -> Data {
        let tempK = UInt16(round(44.0 + 273.15)) // 317 K
        let tbwUnits = UInt64(round((310.20 * 1_000_000_000_000.0) / 512_000.0))
        let tbrUnits = UInt64(round((450.00 * 1_000_000_000_000.0) / 512_000.0))

        return makeCustomBuffer(
            criticalWarning: 0x05, // availableSpareBelowThreshold + reliabilityDegraded
            temperatureKelvin: tempK,
            availableSpare: 5,
            availableSpareThreshold: 10,
            percentageUsed: 65,
            dataUnitsRead: tbrUnits,
            dataUnitsWritten: tbwUnits,
            powerCycles: 2100,
            powerOnHours: 14200,
            unsafeShutdowns: 55,
            mediaErrors: 42,
            numErrorInfoLogEntries: 89,
            temperatureSensorsKelvin: [tempK, tempK - 1, 0, 0, 0, 0, 0, 0]
        )
    }

    /// Maximum boundary test buffer with all critical bits set, 255% wear, and 64-bit high words populated.
    public static func maxValuesRawBuffer() -> Data {
        return makeCustomBuffer(
            criticalWarning: 0x3F, // All 6 warning bits
            temperatureKelvin: 400, // 126.85 °C
            availableSpare: 0,
            availableSpareThreshold: 100,
            percentageUsed: 255,
            enduranceGroupSummary: 0xFF,
            dataUnitsRead: UInt64.max,
            dataUnitsWritten: UInt64.max,
            dataUnitsWrittenHigh: 100, // High word set
            hostReadCommands: UInt64.max,
            hostWriteCommands: UInt64.max,
            controllerBusyTimeMinutes: UInt64.max,
            powerCycles: UInt64.max,
            powerOnHours: UInt64.max,
            unsafeShutdowns: UInt64.max,
            mediaErrors: UInt64.max,
            numErrorInfoLogEntries: UInt64.max,
            warningCompTempTime: UInt32.max,
            criticalCompTempTime: UInt32.max,
            temperatureSensorsKelvin: [400, 395, 390, 385, 380, 375, 370, 365]
        )
    }

    /// All-zeros 512-byte buffer.
    public static func allZerosBuffer() -> Data {
        Data(repeating: 0, count: 512)
    }

    /// Truncated buffer (less than 512 bytes) for error rejection testing.
    public static func truncatedBuffer(length: Int = 256) -> Data {
        Data(repeating: 0xAA, count: length)
    }
}
