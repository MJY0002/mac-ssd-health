import XCTest
import Foundation
@testable import SSDHealthCore

final class MockStorageReaderTests: XCTestCase {

    func testHealthyPreset() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        XCTAssertTrue(reader.isLiveHardwareAccessAvailable())

        let metrics = try await reader.readHealthMetrics()
        XCTAssertEqual(metrics.healthScorePercent, 98)
        XCTAssertEqual(metrics.wearPercentage, 2)
        XCTAssertEqual(metrics.availableSparePercent, 100)
        XCTAssertEqual(metrics.temperatureCelsius, 33.5)
        XCTAssertTrue(metrics.criticalWarnings.isClean)
        XCTAssertFalse(metrics.isFallbackData)
        XCTAssertTrue(metrics.isHealthy)

        let rawLog = try await reader.readRawSmartLog()
        XCTAssertEqual(rawLog.percentageUsed, 2)
        XCTAssertEqual(rawLog.availableSparePercent, 100)
        XCTAssertTrue(rawLog.criticalWarning.isClean)
    }

    func testWarningPreset() async throws {
        let reader = MockSSDStorageReader(preset: .warning)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.healthScorePercent, 72)
        XCTAssertEqual(metrics.wearPercentage, 28)
        XCTAssertEqual(metrics.temperatureCelsius, 56.0)
        XCTAssertEqual(metrics.availableSparePercent, 88)
        XCTAssertEqual(metrics.errorLogEntries, 2)
        XCTAssertTrue(metrics.isHealthy) // Still above 20% health and spare above threshold
    }

    func testOverheatingPreset() async throws {
        let reader = MockSSDStorageReader(preset: .overheating)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.temperatureCelsius, 76.5)
        XCTAssertTrue(metrics.criticalWarnings.contains(.temperatureExceedsThreshold))
        XCTAssertFalse(metrics.isHealthy) // Fails due to high temperature and critical warning

        let rawLog = try await reader.readRawSmartLog()
        XCTAssertTrue(rawLog.criticalWarning.contains(.temperatureExceedsThreshold))
    }

    func testCriticalWearPreset() async throws {
        let reader = MockSSDStorageReader(preset: .criticalWear)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.healthScorePercent, 4)
        XCTAssertEqual(metrics.wearPercentage, 96)
        XCTAssertEqual(metrics.availableSparePercent, 8)
        XCTAssertEqual(metrics.availableSpareThresholdPercent, 10)
        XCTAssertTrue(metrics.criticalWarnings.contains(.availableSpareBelowThreshold))
        XCTAssertFalse(metrics.isHealthy)
    }

    func testDegradedSparePreset() async throws {
        let reader = MockSSDStorageReader(preset: .degradedSpare)
        let metrics = try await reader.readHealthMetrics()

        XCTAssertEqual(metrics.availableSparePercent, 5)
        XCTAssertTrue(metrics.criticalWarnings.contains(.availableSpareBelowThreshold))
        XCTAssertTrue(metrics.criticalWarnings.contains(.reliabilityDegraded))
        XCTAssertFalse(metrics.isHealthy)
        XCTAssertTrue(metrics.criticalWarnings.isSevereHardwareAlert)
    }

    func testSimulatedErrorPreset() async {
        let reader = MockSSDStorageReader(preset: .deviceNotFound)
        XCTAssertFalse(reader.isLiveHardwareAccessAvailable())

        do {
            _ = try await reader.readHealthMetrics()
            XCTFail("Expected deviceNotFound error to be thrown")
        } catch let err as StorageReaderError {
            XCTAssertEqual(err, .deviceNotFound)
            XCTAssertNotNil(err.errorDescription)
        } catch {
            XCTFail("Unexpected error type thrown: \(error)")
        }

        do {
            _ = try await reader.readRawSmartLog()
            XCTFail("Expected error on readRawSmartLog")
        } catch let err as StorageReaderError {
            XCTAssertEqual(err, .deviceNotFound)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPermissionDeniedPreset() async {
        let reader = MockSSDStorageReader(preset: .permissionDenied)
        XCTAssertFalse(reader.isLiveHardwareAccessAvailable())

        do {
            _ = try await reader.readHealthMetrics()
            XCTFail("Expected permission denied error")
        } catch let err as StorageReaderError {
            if case .permissionDenied = err {
                // Expected
            } else {
                XCTFail("Expected permissionDenied, got \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomMetricsInjection() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        let custom = SSDHealthMetrics(
            bsdName: "disk1",
            modelName: "TEST CUSTOM SSD",
            serialNumber: "CUSTOM-999",
            firmwareRevision: "1.0",
            interconnect: "PCI-Express",
            capacityBytes: 1_000_000_000_000,
            healthScorePercent: 50,
            wearPercentage: 50,
            temperatureCelsius: 40.0,
            availableSparePercent: 90,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 100.0,
            terabytesRead: 150.0,
            powerOnHours: 5000,
            powerCycles: 500,
            unsafeShutdowns: 10,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: Date(),
            isFallbackData: false
        )

        reader.setCustomMetrics(custom)
        let result = try await reader.readHealthMetrics()
        XCTAssertEqual(result.serialNumber, "CUSTOM-999")
        XCTAssertEqual(result.modelName, "TEST CUSTOM SSD")
        XCTAssertEqual(result.healthScorePercent, 50)
    }

    func testMetricsFormattedHelpers() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD",
            serialNumber: "SN123",
            firmwareRevision: "FW1",
            interconnect: "Apple Fabric",
            capacityBytes: 500_107_862_016,
            healthScorePercent: 95,
            wearPercentage: 5,
            temperatureCelsius: 36.4,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: 42.50,
            terabytesRead: 85.12,
            powerOnHours: 1000,
            powerCycles: 200,
            unsafeShutdowns: 5,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0),
            timestamp: Date(),
            isFallbackData: false
        )

        XCTAssertEqual(metrics.id, "SN123")
        XCTAssertEqual(metrics.temperatureFormatted, "36.4 °C")
        XCTAssertEqual(metrics.tbwFormatted, "42.50 TBW")
        XCTAssertEqual(metrics.tbrFormatted, "85.12 TB Read")
        XCTAssertEqual(metrics.wearFormatted, "5%")
        XCTAssertEqual(metrics.healthScoreFormatted, "95%")
        XCTAssertTrue(metrics.capacityFormatted.contains("500"))
        XCTAssertTrue(metrics.isHealthy)
    }
}
