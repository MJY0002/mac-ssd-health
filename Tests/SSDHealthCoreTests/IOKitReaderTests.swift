import XCTest
import Foundation
import IOKit
@testable import SSDHealthCore

final class IOKitReaderTests: XCTestCase {

    func testLiveReaderExecutionOrGracefulFallback() async throws {
        let reader = IOKitStorageReader()
        let metrics = try await reader.readHealthMetrics()

        // Verify that metrics are populated and valid regardless of sandbox/permissions
        XCTAssertFalse(metrics.modelName.isEmpty)
        XCTAssertFalse(metrics.bsdName.isEmpty)
        XCTAssertGreaterThan(metrics.capacityBytes, 0)
        XCTAssertGreaterThanOrEqual(metrics.healthScorePercent, 0)
        XCTAssertLessThanOrEqual(metrics.healthScorePercent, 100)
        XCTAssertGreaterThanOrEqual(metrics.wearPercentage, 0)
        XCTAssertGreaterThan(metrics.temperatureCelsius, -50.0)
        XCTAssertLessThan(metrics.temperatureCelsius, 150.0)

        // Timestamp freshness
        let elapsed = abs(metrics.timestamp.timeIntervalSinceNow)
        XCTAssertLessThan(elapsed, 10.0)

        // If hardware is accessible, isFallbackData should be false and raw SMART log readable
        if reader.isLiveHardwareAccessAvailable() {
            XCTAssertFalse(metrics.isFallbackData)
            let rawLog = try await reader.readRawSmartLog()
            XCTAssertGreaterThan(rawLog.compositeTemperatureKelvin, 200)
            XCTAssertLessThan(rawLog.compositeTemperatureKelvin, 450)
        } else {
            XCTAssertTrue(metrics.isFallbackData)
        }
    }

    func testRegistryMetadataExtraction() throws {
        let reader = IOKitStorageReader()
        let meta = try reader.readRegistryMetadata()

        XCTAssertFalse(meta.bsdName.isEmpty)
        XCTAssertFalse(meta.modelName.isEmpty)
        XCTAssertFalse(meta.interconnect.isEmpty)
    }

    /// Cross-checks the recursive registry search against an independent lookup: the BSD name it found
    /// must resolve via IOBSDNameMatching to a whole-disk IOMedia whose Size equals the reported capacity.
    /// Fails if the search stopped at a partition, at another device, or fell back to defaults.
    func testRegistryMetadata_MatchesWholeDiskMediaOfSameDevice() throws {
        let reader = IOKitStorageReader()
        let meta = try reader.readRegistryMetadata()
        print("IOKit primary device: bsd=\(meta.bsdName) model=\(meta.modelName) capacity=\(meta.capacityBytes) interconnect=\(meta.interconnect) liveSMART=\(reader.isLiveHardwareAccessAvailable())")

        XCTAssertGreaterThan(meta.capacityBytes, 0, "Capacity must come from IOMedia, not a default")

        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, meta.bsdName) else {
            return XCTFail("IOBSDNameMatching returned nil for \(meta.bsdName)")
        }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        XCTAssertNotEqual(media, 0, "Reported BSD name \(meta.bsdName) must exist in IORegistry")
        guard media != 0 else { return }
        defer { IOObjectRelease(media) }

        let whole = IORegistryEntryCreateCFProperty(media, "Whole" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
        let size = (IORegistryEntryCreateCFProperty(media, "Size" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.uint64Value
        XCTAssertEqual(whole, true, "\(meta.bsdName) must be the whole disk, not a partition")
        XCTAssertEqual(size, meta.capacityBytes)
    }

    func testFallbackMetricsGeneration() throws {
        let reader = IOKitStorageReader()
        let simulatedError = StorageReaderError.permissionDenied(reason: "Unit test sandbox simulation")
        let fallback = try reader.readFallbackRegistryMetrics(underlyingError: simulatedError)

        XCTAssertTrue(fallback.isFallbackData)
        XCTAssertFalse(fallback.modelName.isEmpty)
        XCTAssertFalse(fallback.bsdName.isEmpty)
        XCTAssertGreaterThan(fallback.capacityBytes, 0)
        XCTAssertEqual(fallback.healthScorePercent, 100)
        XCTAssertEqual(fallback.wearPercentage, 0)
        XCTAssertEqual(fallback.temperatureCelsius, 38.0)
        XCTAssertEqual(fallback.availableSparePercent, 100)
        XCTAssertEqual(fallback.availableSpareThresholdPercent, 10)
    }

    func testStorageReaderErrorDescriptions() {
        let errors: [StorageReaderError] = [
            .deviceNotFound,
            .plugInCreationFailed(kernReturn: -536870206),
            .interfaceQueryFailed(hresult: -2147467262),
            .smartReadFailed(kernReturn: -536870200),
            .permissionDenied(reason: "Access denied"),
            .unsupportedDevice(reason: "Non-NVMe drive"),
            .invalidDataLength(expected: 512, actual: 256),
            .registryReadFailed(reason: "Service matching failed")
        ]

        for err in errors {
            guard let desc = err.errorDescription else {
                XCTFail("Missing error description for \(err)")
                continue
            }
            XCTAssertFalse(desc.isEmpty)
        }
    }
}
