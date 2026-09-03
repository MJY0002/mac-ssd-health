import XCTest
import SwiftUI
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

@MainActor
final class SettingsViewTests: XCTestCase {

    var settings: AppSettings!
    var userDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        let suiteName = "test.suite.settings.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        settings = AppSettings(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        userDefaults = nil
        settings = nil
        try await super.tearDown()
    }

    // MARK: - Threshold Validation

    func testSettings_ThresholdValidation_DefaultValuesAreValid() {
        XCTAssertTrue(settings.validateThresholds())
    }

    func testSettings_ThresholdValidation_RejectsInvalidThermalRanges() {
        // Warning >= Critical is invalid
        settings.thermalWarningThresholdCelsius = 70.0
        settings.thermalCriticalThresholdCelsius = 65.0
        XCTAssertFalse(settings.validateThresholds())

        // Negative or sub-30 warning is invalid
        settings.thermalWarningThresholdCelsius = 20.0
        settings.thermalCriticalThresholdCelsius = 65.0
        XCTAssertFalse(settings.validateThresholds())
    }

    func testSettings_ThresholdValidation_RejectsInvalidWearAndSpare() {
        // Wear > 100%
        settings.wearWarningThresholdPercent = 105
        XCTAssertFalse(settings.validateThresholds())

        // Spare > 50%
        settings.spareWarningThresholdPercent = 60
        XCTAssertFalse(settings.validateThresholds())
    }

    // MARK: - Preset Serialization

    func testSettings_MockPresetMapping_ConvertsAllPresets() {
        let presets: [MockSSDStorageReader.Preset] = [
            .healthy,
            .warning,
            .overheating,
            .criticalWear,
            .degradedSpare,
            .permissionDenied,
            .deviceNotFound
        ]

        for p in presets {
            let str = AppSettings.presetToString(p)
            let parsed = AppSettings.stringToPreset(str)
            XCTAssertEqual(AppSettings.presetToString(parsed), str)
        }
    }

    // MARK: - Reset Defaults

    func testSettings_ResetToDefaults_RestoresInitialValues() {
        settings.displayMode = .iconOnly
        settings.temperatureUnit = .fahrenheit
        settings.pollingIntervalMinutes = 60
        settings.thermalWarningThresholdCelsius = 72.0
        settings.thermalCriticalThresholdCelsius = 85.0
        settings.wearWarningThresholdPercent = 90
        settings.spareWarningThresholdPercent = 20
        settings.ratedTBWOverride = 500.0

        settings.resetToDefaults()

        XCTAssertEqual(settings.displayMode, .healthPercent)
        XCTAssertEqual(settings.temperatureUnit, .celsius)
        XCTAssertEqual(settings.pollingIntervalSeconds, AppSettings.defaultPollingInterval)
        XCTAssertEqual(settings.thermalWarningThresholdCelsius, AppSettings.defaultThermalWarning)
        XCTAssertEqual(settings.thermalCriticalThresholdCelsius, AppSettings.defaultThermalCritical)
        XCTAssertEqual(settings.wearWarningThresholdPercent, AppSettings.defaultWearWarning)
        XCTAssertEqual(settings.spareWarningThresholdPercent, AppSettings.defaultSpareWarning)
        XCTAssertNil(settings.ratedTBWOverride)
    }

    // MARK: - Rated TBW Override

    func testSettings_RatedTBWOverride_PersistsAndRemoves() {
        XCTAssertNil(settings.ratedTBWOverride)

        settings.ratedTBWOverride = 600.0
        XCTAssertEqual(settings.ratedTBWOverride, 600.0)

        // Setting to nil removes key
        settings.ratedTBWOverride = nil
        XCTAssertNil(settings.ratedTBWOverride)
    }
}
