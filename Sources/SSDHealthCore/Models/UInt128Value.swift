import Foundation

/// A 128-bit unsigned integer value composed of two 64-bit words in little-endian order.
///
/// Designed for high-precision NVMe SMART counters (e.g., Data Units Written/Read, Power-On Hours,
/// Host Commands) preventing overflow issues when handling large cumulative storage telemetry.
public struct UInt128Value: Sendable, Codable, Equatable, Comparable, Hashable, CustomStringConvertible {
    /// Low-order 64 bits (Bytes 0–7)
    public let low: UInt64

    /// High-order 64 bits (Bytes 8–15)
    public let high: UInt64

    /// Multiplier constant $2^{64}$ as Double ($18,446,744,073,709,551,616.0$)
    private static let twoTo64: Double = 18446744073709551616.0

    // MARK: - Initializers

    public init(low: UInt64, high: UInt64 = 0) {
        self.low = low
        self.high = high
    }

    /// Initializes a 128-bit value from 16 bytes in little-endian byte order.
    public init(littleEndianBytes bytes: [UInt8], offset: Int = 0) {
        guard bytes.count >= offset + 16 else {
            self.low = 0
            self.high = 0
            return
        }

        var lowVal: UInt64 = 0
        var highVal: UInt64 = 0

        for i in 0..<8 {
            lowVal |= (UInt64(bytes[offset + i]) << (i * 8))
            highVal |= (UInt64(bytes[offset + 8 + i]) << (i * 8))
        }

        self.low = lowVal
        self.high = highVal
    }

    /// Initializes a 128-bit value from binary Data at the specified offset.
    public init(data: Data, offset: Int = 0) {
        guard data.count >= offset + 16 else {
            self.low = 0
            self.high = 0
            return
        }

        let lowVal = data.withUnsafeBytes { raw in
            UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
        }
        let highVal = data.withUnsafeBytes { raw in
            UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self))
        }

        self.low = lowVal
        self.high = highVal
    }

    // MARK: - Standard Constants

    public static let zero = UInt128Value(low: 0, high: 0)
    public static let min = UInt128Value(low: 0, high: 0)
    public static let max = UInt128Value(low: .max, high: .max)

    // MARK: - Value Conversions

    /// Floating-point representation for large metric arithmetic and rate calculations.
    public var doubleValue: Double {
        Double(high) * Self.twoTo64 + Double(low)
    }

    /// Returns `true` if both low and high words are zero.
    public var isZero: Bool {
        low == 0 && high == 0
    }

    /// Formats the 128-bit integer into a decimal string representation.
    public var formattedDecimalString: String {
        if high == 0 {
            return String(low)
        }
        // Approximate high precision formatting for large counters
        let d = doubleValue
        if d < 1e15 {
            return String(format: "%.0f", d)
        } else {
            return String(format: "%.6e", d)
        }
    }

    /// Formats the 128-bit integer into a full 32-character hexadecimal string.
    public var hexString: String {
        String(format: "0x%016llX_%016llX", high, low)
    }

    /// Returns the 16 bytes in little-endian order.
    public var littleEndianData: Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        var l = low.littleEndian
        var h = high.littleEndian
        withUnsafeBytes(of: &l) { raw in
            for i in 0..<8 { bytes[i] = raw[i] }
        }
        withUnsafeBytes(of: &h) { raw in
            for i in 0..<8 { bytes[8 + i] = raw[i] }
        }
        return Data(bytes)
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        if high == 0 {
            return "\(low)"
        }
        return "\(hexString) (≈\(formattedDecimalString))"
    }

    // MARK: - Comparable

    public static func < (lhs: UInt128Value, rhs: UInt128Value) -> Bool {
        if lhs.high != rhs.high {
            return lhs.high < rhs.high
        }
        return lhs.low < rhs.low
    }

    // MARK: - Arithmetic

    public static func + (lhs: UInt128Value, rhs: UInt128Value) -> UInt128Value {
        let (lowSum, overflow) = lhs.low.addingReportingOverflow(rhs.low)
        var highSum = lhs.high &+ rhs.high
        if overflow {
            highSum = highSum &+ 1
        }
        return UInt128Value(low: lowSum, high: highSum)
    }

    public static func - (lhs: UInt128Value, rhs: UInt128Value) -> UInt128Value {
        let (lowDiff, overflow) = lhs.low.subtractingReportingOverflow(rhs.low)
        var highDiff = lhs.high &- rhs.high
        if overflow {
            highDiff = highDiff &- 1
        }
        return UInt128Value(low: lowDiff, high: highDiff)
    }
}
