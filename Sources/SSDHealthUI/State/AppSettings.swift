import Foundation
import SwiftUI
import Observation
import SSDHealthCore
import SSDHealthService

// MARK: - Menu Bar Display Mode

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case iconOnly = "Icon Only"
    case healthPercent = "Icon + Health %"
    case temperature = "Icon + Temperature"
    case combined = "Icon + Health & Temp"

    public var id: String { rawValue }

    // Backward-compatibility / semantic aliases
    public static let iconAndHealth: MenuBarDisplayMode = .healthPercent
    public static let iconAndTemp: MenuBarDisplayMode = .temperature
    public static let iconHealthAndTemp: MenuBarDisplayMode = .combined
}

// MARK: - Temperature Unit

public enum TemperatureUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case celsius = "Celsius (°C)"
    case fahrenheit = "Fahrenheit (°F)"

    public var id: String { rawValue }

    public func format(celsius: Double) -> String {
        switch self {
        case .celsius:
            return String(format: "%.1f °C", celsius)
        case .fahrenheit:
            let f = celsius * 1.8 + 32.0
            return String(format: "%.1f °F", f)
        }
    }

    public func formatRounded(celsius: Double) -> String {
        switch self {
        case .celsius:
            return "\(Int(round(celsius)))°C"
        case .fahrenheit:
            let f = celsius * 1.8 + 32.0
            return "\(Int(round(f)))°F"
        }
    }
}

// MARK: - Health Status UI Mapping

public enum HealthStatus: String, Codable, Sendable {
    case good = "Good"
    case warning = "Warning"
    case critical = "Critical"

    public var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    public var iconName: String {
        switch self {
        case .good: return "internaldrive"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    public static func evaluate(
        metrics: SSDHealthMetrics?,
        thermalWarningCelsius: Double = 55.0,
        thermalCriticalCelsius: Double = 65.0
    ) -> HealthStatus {
        guard let m = metrics else { return .good }
        if !m.criticalWarnings.isClean || m.healthScorePercent <= 10 || m.availableSparePercent < m.availableSpareThresholdPercent || m.temperatureCelsius >= thermalCriticalCelsius {
            return .critical
        } else if m.healthScorePercent <= 20 || m.availableSparePercent < 20 || m.temperatureCelsius >= thermalWarningCelsius {
            return .warning
        } else {
            return .good
        }
    }
}

// MARK: - App Settings Model

@Observable
@MainActor
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private let userDefaults: UserDefaults

    // Storage Keys
    private enum Keys {
        static let displayMode = "ssd_health_display_mode"
        static let temperatureUnit = "ssd_health_temperature_unit"
        static let pollingInterval = "ssd_health_polling_interval"
        static let thermalWarning = "ssd_health_thermal_warning"
        static let thermalCritical = "ssd_health_thermal_critical"
        static let wearWarning = "ssd_health_wear_warning"
        static let spareWarning = "ssd_health_spare_warning"
        static let ratedTBWOverride = "ssd_health_rated_tbw_override"
        static let launchAtLogin = "ssd_health_launch_at_login"
        static let showNotifications = "ssd_health_show_notifications"
        static let useMockReader = "ssd_health_use_mock_reader"
        static let mockPresetName = "ssd_health_mock_preset_name"
    }

    // Default Values
    public static let defaultPollingInterval: TimeInterval = 900.0 // 15 minutes
    public static let defaultThermalWarning: Double = 60.0
    public static let defaultThermalCritical: Double = 65.0
    public static let defaultWearWarning: Int = 80
    public static let defaultSpareWarning: Int = 10

    // Properties
    public var displayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(displayMode.rawValue, forKey: Keys.displayMode)
        }
    }

    public var temperatureUnit: TemperatureUnit {
        didSet {
            userDefaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit)
        }
    }

    public var pollingIntervalSeconds: TimeInterval {
        didSet {
            userDefaults.set(pollingIntervalSeconds, forKey: Keys.pollingInterval)
        }
    }

    public var pollingIntervalMinutes: Int {
        get { Int(pollingIntervalSeconds / 60.0) }
        set { pollingIntervalSeconds = Double(max(1, newValue)) * 60.0 }
    }

    public var thermalWarningThresholdCelsius: Double {
        didSet {
            userDefaults.set(thermalWarningThresholdCelsius, forKey: Keys.thermalWarning)
        }
    }

    public var thermalCriticalThresholdCelsius: Double {
        didSet {
            userDefaults.set(thermalCriticalThresholdCelsius, forKey: Keys.thermalCritical)
        }
    }

    public var wearWarningThresholdPercent: Int {
        didSet {
            userDefaults.set(wearWarningThresholdPercent, forKey: Keys.wearWarning)
        }
    }

    public var spareWarningThresholdPercent: Int {
        didSet {
            userDefaults.set(spareWarningThresholdPercent, forKey: Keys.spareWarning)
        }
    }

    public var ratedTBWOverride: Double? {
        didSet {
            if let val = ratedTBWOverride, val > 0 {
                userDefaults.set(val, forKey: Keys.ratedTBWOverride)
            } else {
                userDefaults.removeObject(forKey: Keys.ratedTBWOverride)
            }
        }
    }

    public var launchAtLogin: Bool {
        didSet {
            userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    public var showNotifications: Bool {
        didSet {
            userDefaults.set(showNotifications, forKey: Keys.showNotifications)
        }
    }

    public var useMockReader: Bool {
        didSet {
            userDefaults.set(useMockReader, forKey: Keys.useMockReader)
        }
    }

    public var mockPreset: MockSSDStorageReader.Preset {
        didSet {
            userDefaults.set(Self.presetToString(mockPreset), forKey: Keys.mockPresetName)
        }
    }

    // MARK: - Initializer

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let raw = userDefaults.string(forKey: Keys.displayMode),
           let mode = MenuBarDisplayMode(rawValue: raw) {
            self.displayMode = mode
        } else {
            self.displayMode = .healthPercent
        }

        if let raw = userDefaults.string(forKey: Keys.temperatureUnit),
           let unit = TemperatureUnit(rawValue: raw) {
            self.temperatureUnit = unit
        } else {
            self.temperatureUnit = .celsius
        }

        let interval = userDefaults.double(forKey: Keys.pollingInterval)
        self.pollingIntervalSeconds = interval > 0 ? interval : Self.defaultPollingInterval

        let tw = userDefaults.double(forKey: Keys.thermalWarning)
        self.thermalWarningThresholdCelsius = tw > 0 ? tw : Self.defaultThermalWarning

        let tc = userDefaults.double(forKey: Keys.thermalCritical)
        self.thermalCriticalThresholdCelsius = tc > 0 ? tc : Self.defaultThermalCritical

        let ww = userDefaults.integer(forKey: Keys.wearWarning)
        self.wearWarningThresholdPercent = ww > 0 ? ww : Self.defaultWearWarning

        let sw = userDefaults.integer(forKey: Keys.spareWarning)
        self.spareWarningThresholdPercent = sw > 0 ? sw : Self.defaultSpareWarning

        let tbw = userDefaults.double(forKey: Keys.ratedTBWOverride)
        self.ratedTBWOverride = tbw > 0 ? tbw : nil

        self.launchAtLogin = userDefaults.bool(forKey: Keys.launchAtLogin)
        self.showNotifications = userDefaults.object(forKey: Keys.showNotifications) != nil ? userDefaults.bool(forKey: Keys.showNotifications) : true
        self.useMockReader = userDefaults.bool(forKey: Keys.useMockReader)

        if let presetStr = userDefaults.string(forKey: Keys.mockPresetName) {
            self.mockPreset = Self.stringToPreset(presetStr)
        } else {
            self.mockPreset = .healthy
        }
    }

    // MARK: - Preset Mapping Helpers

    public static func presetToString(_ preset: MockSSDStorageReader.Preset) -> String {
        switch preset {
        case .healthy: return "healthy"
        case .warning: return "warning"
        case .overheating: return "overheating"
        case .criticalWear: return "criticalWear"
        case .degradedSpare: return "degradedSpare"
        case .simulatedError(let err):
            switch err {
            case .permissionDenied: return "permissionDenied"
            case .deviceNotFound: return "deviceNotFound"
            default: return "simulatedError"
            }
        }
    }

    public static func stringToPreset(_ str: String) -> MockSSDStorageReader.Preset {
        switch str {
        case "healthy": return .healthy
        case "warning": return .warning
        case "overheating": return .overheating
        case "criticalWear": return .criticalWear
        case "degradedSpare": return .degradedSpare
        case "permissionDenied": return .permissionDenied
        case "deviceNotFound": return .deviceNotFound
        default: return .healthy
        }
    }

    public func resetToDefaults() {
        displayMode = .healthPercent
        temperatureUnit = .celsius
        pollingIntervalSeconds = Self.defaultPollingInterval
        thermalWarningThresholdCelsius = Self.defaultThermalWarning
        thermalCriticalThresholdCelsius = Self.defaultThermalCritical
        wearWarningThresholdPercent = Self.defaultWearWarning
        spareWarningThresholdPercent = Self.defaultSpareWarning
        ratedTBWOverride = nil
        showNotifications = true
        useMockReader = false
        mockPreset = .healthy
    }

    public func validateThresholds() -> Bool {
        thermalWarningThresholdCelsius < thermalCriticalThresholdCelsius &&
        thermalWarningThresholdCelsius >= 30.0 &&
        thermalCriticalThresholdCelsius <= 100.0 &&
        wearWarningThresholdPercent >= 10 &&
        wearWarningThresholdPercent <= 100 &&
        spareWarningThresholdPercent >= 1 &&
        spareWarningThresholdPercent <= 50
    }
}
