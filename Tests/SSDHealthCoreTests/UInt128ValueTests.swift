import XCTest
import Foundation
@testable import SSDHealthCore

final class UInt128ValueTests: XCTestCase {

    func testInitializationAndProperties() {
        let val1 = UInt128Value(low: 42, high: 0)
        XCTAssertEqual(val1.low, 42)
        XCTAssertEqual(val1.high, 0)
        XCTAssertFalse(val1.isZero)
        XCTAssertEqual(val1.doubleValue, 42.0)

        let zeroVal = UInt128Value.zero
        XCTAssertEqual(zeroVal.low, 0)
        XCTAssertEqual(zeroVal.high, 0)
        XCTAssertTrue(zeroVal.isZero)
        XCTAssertEqual(zeroVal.doubleValue, 0.0)

        let maxVal = UInt128Value.max
        XCTAssertEqual(maxVal.low, UInt64.max)
        XCTAssertEqual(maxVal.high, UInt64.max)
        XCTAssertFalse(maxVal.isZero)
        XCTAssertGreaterThan(maxVal.doubleValue, 3.4e38)
    }

    func testLittleEndianBytesInitialization() {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x01
        bytes[1] = 0x02
        bytes[8] = 0x03

        let val = UInt128Value(littleEndianBytes: bytes)
        XCTAssertEqual(val.low, 0x0201)
        XCTAssertEqual(val.high, 0x03)

        // Short buffer fallback
        let shortVal = UInt128Value(littleEndianBytes: [1, 2, 3])
        XCTAssertTrue(shortVal.isZero)
    }

    func testDataOffsetInitialization() {
        var data = Data(repeating: 0, count: 32)
        let lowVal: UInt64 = 0x1122334455667788
        let highVal: UInt64 = 0xAABBCCDDEEFF0011

        var lowLE = lowVal.littleEndian
        var highLE = highVal.littleEndian

        withUnsafeBytes(of: &lowLE) { raw in
            for i in 0..<8 { data[8 + i] = raw[i] }
        }
        withUnsafeBytes(of: &highLE) { raw in
            for i in 0..<8 { data[16 + i] = raw[i] }
        }

        let parsed = UInt128Value(data: data, offset: 8)
        XCTAssertEqual(parsed.low, lowVal)
        XCTAssertEqual(parsed.high, highVal)

        // Short data offset
        let outOfBounds = UInt128Value(data: data, offset: 25)
        XCTAssertTrue(outOfBounds.isZero)
    }

    func testDoubleValuePrecisionAndHighWord() {
        // High = 1, Low = 0 -> 2^64 = 18446744073709551616
        let oneHigh = UInt128Value(low: 0, high: 1)
        XCTAssertEqual(oneHigh.doubleValue, 18446744073709551616.0)

        // High = 2, Low = 1000
        let twoHigh = UInt128Value(low: 1000, high: 2)
        XCTAssertEqual(twoHigh.doubleValue, 2.0 * 18446744073709551616.0 + 1000.0)
    }

    func testComparable() {
        let a = UInt128Value(low: 100, high: 0)
        let b = UInt128Value(low: 200, high: 0)
        let c = UInt128Value(low: 50, high: 1)
        let d = UInt128Value(low: 100, high: 1)
        let e = UInt128Value(low: 100, high: 0)

        XCTAssertTrue(a < b)
        XCTAssertTrue(b < c)
        XCTAssertTrue(c < d)
        XCTAssertFalse(d < c)
        XCTAssertEqual(a, e)
        XCTAssertTrue(a <= e)
        XCTAssertTrue(d > a)
    }

    func testArithmeticOperations() {
        // Addition without overflow
        let valA = UInt128Value(low: 500, high: 1)
        let valB = UInt128Value(low: 300, high: 2)
        let sum1 = valA + valB
        XCTAssertEqual(sum1.low, 800)
        XCTAssertEqual(sum1.high, 3)

        // Addition with low-word overflow carry to high-word
        let maxLow = UInt128Value(low: UInt64.max, high: 0)
        let one = UInt128Value(low: 1, high: 0)
        let sumOverflow = maxLow + one
        XCTAssertEqual(sumOverflow.low, 0)
        XCTAssertEqual(sumOverflow.high, 1)

        // Subtraction without overflow
        let diff1 = sum1 - valA
        XCTAssertEqual(diff1.low, 300)
        XCTAssertEqual(diff1.high, 2)

        // Subtraction with high borrow
        let oneHigh = UInt128Value(low: 0, high: 1)
        let diffBorrow = oneHigh - one
        XCTAssertEqual(diffBorrow.low, UInt64.max)
        XCTAssertEqual(diffBorrow.high, 0)
    }

    func testFormattingAndDescriptions() {
        let small = UInt128Value(low: 12345, high: 0)
        XCTAssertEqual(small.formattedDecimalString, "12345")
        XCTAssertEqual(small.description, "12345")

        let large = UInt128Value(low: 0x1122334455667788, high: 0xAABBCCDDEEFF0011)
        XCTAssertEqual(large.hexString, "0xAABBCCDDEEFF0011_1122334455667788")
        XCTAssertTrue(large.description.contains("0xAABBCCDDEEFF0011_1122334455667788"))
    }

    func testLittleEndianDataRoundtrip() {
        let original = UInt128Value(low: 0x0123456789ABCDEF, high: 0xFEDCBA9876543210)
        let data = original.littleEndianData
        XCTAssertEqual(data.count, 16)

        let parsed = UInt128Value(data: data)
        XCTAssertEqual(parsed, original)
    }

    func testCodableSerialization() throws {
        let original = UInt128Value(low: 987654321, high: 12345)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UInt128Value.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
