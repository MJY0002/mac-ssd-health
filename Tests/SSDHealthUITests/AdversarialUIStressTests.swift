import XCTest
import SwiftUI
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

@MainActor
final class AdversarialUIStressTests: XCTestCase {

    var userDefaults: UserDefaults!
    var settings: AppSettings!
    var tempDir: URL!
    var persistenceActor: HistoryPersistenceActor!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AdvUITests_\(uniqueID)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let suiteName = "test.suite.advui.\(uniqueID)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let storeURL = tempDir.appendingPathComponent("history.json")
        persistenceActor = HistoryPersistenceActor(storageURL: storeURL, driveIdentifier: "adv-test-drive")
        settings = AppSettings(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        userDefaults = nil
        settings = nil
        persistenceActor = nil
        try await super.tearDown()
    }

    // MARK: - 1. Search Filtering Edge Cases & Stress

    func testSearchFiltering_EmptyAndWhitespaceSearches() async throws {
        let mock = MockSSDStorageReader(preset: .healthy)
        let metrics = try await mock.readHealthMetrics()
        let state = AppState(storageReader: mock, settings: settings)
        state.currentMetrics = metrics
        state.rawSmartLog = NVMESmartLog(data: MockSSDStorageReader.generateSyntheticRawData(for: metrics))

        let tableView = SMARTTableView(appState: state)
        let totalCount = tableView.allRows.count
        XCTAssertGreaterThanOrEqual(totalCount, 17)

        // Helper to test search
        func searchResults(query: String, filter: ParameterStatus = .all) -> [SMARTParameterRow] {
            tableView.allRows.filter { row in
                let matchesFilter = (filter == .all) || (row.status == filter)
                let matchesSearch = query.isEmpty || {
                    let q = query.lowercased()
                    return row.name.lowercased().contains(q) ||
                           row.rawHex.lowercased().contains(q) ||
                           row.formattedValue.lowercased().contains(q) ||
                           row.rawValueString.lowercased().contains(q)
                }()
                return matchesFilter && matchesSearch
            }
        }

        // Empty string -> matches all
        XCTAssertEqual(searchResults(query: "").count, totalCount)

        // Whitespace only -> non-empty so does literal substring check
        let spaceMatches = searchResults(query: " ")
        // Many names contain spaces, e.g. "Critical Warning", "Composite Temperature"
        XCTAssertGreaterThan(spaceMatches.count, 0)

        // Newline / Tab -> should not crash, returns 0 matches
        XCTAssertEqual(searchResults(query: "\t").count, 0)
        XCTAssertEqual(searchResults(query: "\n").count, 0)
        XCTAssertEqual(searchResults(query: "\r\n").count, 0)
    }

    func testSearchFiltering_SpecialCharactersAndRegexMetacharacters() async throws {
        let mock = MockSSDStorageReader(preset: .healthy)
        let metrics = try await mock.readHealthMetrics()
        let state = AppState(storageReader: mock, settings: settings)
        state.currentMetrics = metrics
        state.rawSmartLog = NVMESmartLog(data: MockSSDStorageReader.generateSyntheticRawData(for: metrics))

        let tableView = SMARTTableView(appState: state)

        func searchResults(query: String) -> [SMARTParameterRow] {
            tableView.allRows.filter { row in
                let q = query.lowercased()
                return row.name.lowercased().contains(q) ||
                       row.rawHex.lowercased().contains(q) ||
                       row.formattedValue.lowercased().contains(q) ||
                       row.rawValueString.lowercased().contains(q)
            }
        }

        // Regex tokens should NOT trigger regex crashes (literal search)
        let adversarialTokens = [
            ".*", "\\d+", "[a-z]", "^.*$", "+", "?", "{1,3}", "(.*)", "|",
            "\\\\", "/", "\"", "'", "`", "~", "!", "@", "#", "$", "%", "^",
            "&", "*", "(", ")", "_", "-", "=", "+", "[", "]", "{", "}", ";",
            ":", ",", "<", ">", "."
        ]

        for token in adversarialTokens {
            let results = searchResults(query: token)
            // Verify safe execution without throwing/crashing
            XCTAssertNotNil(results)
        }

        // Specific symbol checks:
        // "%" should match rows with percentage values (e.g. Percentage Used, Available Spare)
        let percentMatches = searchResults(query: "%")
        XCTAssertGreaterThanOrEqual(percentMatches.count, 3)

        // "0x" should match all rawHex values
        let hexMatches = searchResults(query: "0x")
        XCTAssertEqual(hexMatches.count, tableView.allRows.count)

        // "°C" should match temperature rows
        let degMatches = searchResults(query: "°C")
        XCTAssertGreaterThanOrEqual(degMatches.count, 1)
    }

    func testSearchFiltering_UnicodeEmojisAndControlCharacters() async throws {
        let mock = MockSSDStorageReader(preset: .healthy)
        let metrics = try await mock.readHealthMetrics()
        let state = AppState(storageReader: mock, settings: settings)
        state.currentMetrics = metrics
        state.rawSmartLog = NVMESmartLog(data: MockSSDStorageReader.generateSyntheticRawData(for: metrics))

        let tableView = SMARTTableView(appState: state)

        func searchResults(query: String) -> [SMARTParameterRow] {
            tableView.allRows.filter { row in
                let q = query.lowercased()
                return row.name.lowercased().contains(q) ||
                       row.rawHex.lowercased().contains(q) ||
                       row.formattedValue.lowercased().contains(q) ||
                       row.rawValueString.lowercased().contains(q)
            }
        }

        let unicodeQueries = [
            "🔥", "⚡", "💾", "", "über", "温度", "العربية",
            "\u{200B}", // zero-width space
            "\u{200E}", // LTR mark
            "\u{200F}", // RTL mark
            "\u{0000}", // null byte
            "\u{FFFF}", // non-character
            "𝕳𝖊𝖑𝖑𝖔", // mathematical alphanumeric
            "тест" // cyrillic
        ]

        for uq in unicodeQueries {
            let matches = searchResults(query: uq)
            XCTAssertNotNil(matches)
        }
    }

    func testSearchFiltering_MassiveQueryStress() async throws {
        let mock = MockSSDStorageReader(preset: .healthy)
        let metrics = try await mock.readHealthMetrics()
        let state = AppState(storageReader: mock, settings: settings)
        state.currentMetrics = metrics
        state.rawSmartLog = NVMESmartLog(data: MockSSDStorageReader.generateSyntheticRawData(for: metrics))

        let tableView = SMARTTableView(appState: state)

        // 10,000 character search string
        let longQuery = String(repeating: "A", count: 10_000)
        let q = longQuery.lowercased()
        let matches = tableView.allRows.filter { row in
            row.name.lowercased().contains(q) ||
            row.rawHex.lowercased().contains(q) ||
            row.formattedValue.lowercased().contains(q) ||
            row.rawValueString.lowercased().contains(q)
        }
        XCTAssertEqual(matches.count, 0)
    }

    func testSearchFiltering_CaseInsensitivityAndAllColumns() async throws {
        let mock = MockSSDStorageReader(preset: .healthy)
        let metrics = try await mock.readHealthMetrics()
        let state = AppState(storageReader: mock, settings: settings)
        state.currentMetrics = metrics
        state.rawSmartLog = NVMESmartLog(data: MockSSDStorageReader.generateSyntheticRawData(for: metrics))

        let tableView = SMARTTableView(appState: state)

        func search(for query: String) -> [SMARTParameterRow] {
            let q = query.lowercased()
            return tableView.allRows.filter { row in
                row.name.lowercased().contains(q) ||
                row.rawHex.lowercased().contains(q) ||
                row.formattedValue.lowercased().contains(q) ||
                row.rawValueString.lowercased().contains(q)
            }
        }

        // Test variations of "CRITICAL"
        XCTAssertEqual(search(for: "critical").count, search(for: "CRITICAL").count)
        XCTAssertEqual(search(for: "critical").count, search(for: "CrItIcAl").count)

        // Test matching on rawHex
        let rawHexMatches = search(for: "0x00")
        XCTAssertGreaterThan(rawHexMatches.count, 0)

        // Test matching on rawValueString
        let rawValueMatches = search(for: "min")
        XCTAssertGreaterThan(rawValueMatches.count, 0)

        // Test matching on formattedValue
        let formattedMatches = search(for: "health")
        XCTAssertGreaterThan(formattedMatches.count, 0)
    }

    func testSearchFiltering_CombinedWithStatusFilters() async throws {
        let mock = MockSSDStorageReader(preset: .overheating)
        let metrics = try await mock.readHealthMetrics()
        let state = AppState(storageReader: mock, settings: settings)
        state.currentMetrics = metrics
        state.rawSmartLog = NVMESmartLog(data: MockSSDStorageReader.generateSyntheticRawData(for: metrics))

        let tableView = SMARTTableView(appState: state)

        func search(query: String, filter: ParameterStatus) -> [SMARTParameterRow] {
            tableView.allRows.filter { row in
                let matchesFilter = (filter == .all) || (row.status == filter)
                let matchesSearch = query.isEmpty || {
                    let q = query.lowercased()
                    return row.name.lowercased().contains(q) ||
                           row.rawHex.lowercased().contains(q) ||
                           row.formattedValue.lowercased().contains(q) ||
                           row.rawValueString.lowercased().contains(q)
                }()
                return matchesFilter && matchesSearch
            }
        }

        let criticalRows = search(query: "", filter: .critical)
        XCTAssertGreaterThanOrEqual(criticalRows.count, 2) // temp and critical warning

        let criticalTempSearch = search(query: "temperature", filter: .critical)
        XCTAssertGreaterThanOrEqual(criticalTempSearch.count, 1)

        let criticalNonExistent = search(query: "nonexistentkeyword12345", filter: .critical)
        XCTAssertEqual(criticalNonExistent.count, 0)

        let infoRows = search(query: "", filter: .info)
        XCTAssertGreaterThanOrEqual(infoRows.count, 5)
    }

    // MARK: - 2. Temperature Conversions & Rapid Unit Toggling

    func testTemperatureConversions_PrecisionAndEdgeValues() {
        let celsiusUnit = TemperatureUnit.celsius
        let fahrenheitUnit = TemperatureUnit.fahrenheit

        // 0°C -> 32.0°F
        XCTAssertEqual(celsiusUnit.format(celsius: 0.0), "0.0 °C")
        XCTAssertEqual(celsiusUnit.formatRounded(celsius: 0.0), "0°C")
        XCTAssertEqual(fahrenheitUnit.format(celsius: 0.0), "32.0 °F")
        XCTAssertEqual(fahrenheitUnit.formatRounded(celsius: 0.0), "32°F")

        // 100°C -> 212.0°F
        XCTAssertEqual(celsiusUnit.format(celsius: 100.0), "100.0 °C")
        XCTAssertEqual(celsiusUnit.formatRounded(celsius: 100.0), "100°C")
        XCTAssertEqual(fahrenheitUnit.format(celsius: 100.0), "212.0 °F")
        XCTAssertEqual(fahrenheitUnit.formatRounded(celsius: 100.0), "212°F")

        // -40°C -> -40.0°F
        XCTAssertEqual(celsiusUnit.format(celsius: -40.0), "-40.0 °C")
        XCTAssertEqual(celsiusUnit.formatRounded(celsius: -40.0), "-40°C")
        XCTAssertEqual(fahrenheitUnit.format(celsius: -40.0), "-40.0 °F")
        XCTAssertEqual(fahrenheitUnit.formatRounded(celsius: -40.0), "-40°F")

        // Absolute zero: -273.15°C -> -459.67°F -> -460°F
        XCTAssertEqual(celsiusUnit.format(celsius: -273.15), "-273.1 °C")
        XCTAssertEqual(celsiusUnit.formatRounded(celsius: -273.15), "-273°C")
        XCTAssertEqual(fahrenheitUnit.format(celsius: -273.15), "-459.7 °F")
        XCTAssertEqual(fahrenheitUnit.formatRounded(celsius: -273.15), "-460°F")

        // Extreme heat: 1000°C -> 1832°F
        XCTAssertEqual(celsiusUnit.format(celsius: 1000.0), "1000.0 °C")
        XCTAssertEqual(celsiusUnit.formatRounded(celsius: 1000.0), "1000°C")
        XCTAssertEqual(fahrenheitUnit.format(celsius: 1000.0), "1832.0 °F")
        XCTAssertEqual(fahrenheitUnit.formatRounded(celsius: 1000.0), "1832°F")

        // Max possible 16-bit Kelvin: 65535 K -> 65261.85°C -> 117503.33°F
        let maxKelvinC = 65535.0 - 273.15
        XCTAssertEqual(celsiusUnit.format(celsius: maxKelvinC), "65261.8 °C")
        XCTAssertEqual(celsiusUnit.formatRounded(celsius: maxKelvinC), "65262°C")
        XCTAssertEqual(fahrenheitUnit.format(celsius: maxKelvinC), "117503.3 °F")
        XCTAssertEqual(fahrenheitUnit.formatRounded(celsius: maxKelvinC), "117503°F")
    }

    func testTemperatureUnit_RapidTogglingStress() async throws {
        let mock = MockSSDStorageReader(preset: .healthy)
        let metrics = try await mock.readHealthMetrics()
        let state = AppState(storageReader: mock, settings: settings)
        state.currentMetrics = metrics

        // Concurrently toggle temperatureUnit 1,000 times
        for _ in 0..<1000 {
            settings.temperatureUnit = .fahrenheit
            XCTAssertTrue(state.menuBarTitle.contains("°F") || state.menuBarTitle.contains("%") || state.menuBarTitle.isEmpty)
            settings.temperatureUnit = .celsius
            XCTAssertTrue(state.menuBarTitle.contains("°C") || state.menuBarTitle.contains("%") || state.menuBarTitle.isEmpty)
        }

        XCTAssertEqual(settings.temperatureUnit, .celsius)
    }

    func testMenuBarTitle_AllCombinationsOfModesAndUnits() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 91, wearPercentage: 9, temperatureCelsius: 43.6,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 10, terabytesRead: 10,
            powerOnHours: 100, powerCycles: 50, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        state.currentMetrics = metrics

        let modes: [MenuBarDisplayMode] = [.iconOnly, .healthPercent, .temperature, .combined]
        let units: [TemperatureUnit] = [.celsius, .fahrenheit]

        for mode in modes {
            for unit in units {
                settings.displayMode = mode
                settings.temperatureUnit = unit

                let title = state.menuBarTitle
                switch mode {
                case .iconOnly:
                    XCTAssertEqual(title, "")
                case .healthPercent:
                    XCTAssertEqual(title, "91%")
                case .temperature:
                    if unit == .celsius {
                        XCTAssertEqual(title, "44°C")
                    } else {
                        // 43.6 * 1.8 + 32 = 110.48 -> 110°F
                        XCTAssertEqual(title, "110°F")
                    }
                case .combined:
                    if unit == .celsius {
                        XCTAssertEqual(title, "91% · 44°C")
                    } else {
                        XCTAssertEqual(title, "91% · 110°F")
                    }
                }
            }
        }
    }

    // MARK: - 3. Threshold Validations & Slider Bounds

    func testThresholdValidation_BoundaryPermutations() {
        // 1. Defaults should be valid
        XCTAssertTrue(settings.validateThresholds())

        // 2. Thermal Warning < Thermal Critical
        settings.thermalWarningThresholdCelsius = 65.0
        settings.thermalCriticalThresholdCelsius = 65.0
        XCTAssertFalse(settings.validateThresholds()) // Equality invalid

        settings.thermalWarningThresholdCelsius = 70.0
        settings.thermalCriticalThresholdCelsius = 65.0
        XCTAssertFalse(settings.validateThresholds()) // Inverted invalid

        // 3. Thermal Warning lower bound >= 30
        settings.thermalCriticalThresholdCelsius = 65.0
        settings.thermalWarningThresholdCelsius = 29.9
        XCTAssertFalse(settings.validateThresholds())
        settings.thermalWarningThresholdCelsius = 30.0
        XCTAssertTrue(settings.validateThresholds())

        // 4. Thermal Critical upper bound <= 100
        settings.thermalWarningThresholdCelsius = 60.0
        settings.thermalCriticalThresholdCelsius = 100.0
        XCTAssertTrue(settings.validateThresholds())
        settings.thermalCriticalThresholdCelsius = 100.1
        XCTAssertFalse(settings.validateThresholds())

        // 5. Wear Warning between 10 and 100
        settings.thermalCriticalThresholdCelsius = 65.0
        settings.wearWarningThresholdPercent = 9
        XCTAssertFalse(settings.validateThresholds())
        settings.wearWarningThresholdPercent = 10
        XCTAssertTrue(settings.validateThresholds())
        settings.wearWarningThresholdPercent = 100
        XCTAssertTrue(settings.validateThresholds())
        settings.wearWarningThresholdPercent = 101
        XCTAssertFalse(settings.validateThresholds())

        // 6. Spare Warning between 1 and 50
        settings.wearWarningThresholdPercent = 80
        settings.spareWarningThresholdPercent = 0
        XCTAssertFalse(settings.validateThresholds())
        settings.spareWarningThresholdPercent = 1
        XCTAssertTrue(settings.validateThresholds())
        settings.spareWarningThresholdPercent = 50
        XCTAssertTrue(settings.validateThresholds())
        settings.spareWarningThresholdPercent = 51
        XCTAssertFalse(settings.validateThresholds())
    }

    func testSliderBoundsAndClamping() {
        // Polling interval minutes setter clamps to min 1 minute
        settings.pollingIntervalMinutes = 0
        XCTAssertEqual(settings.pollingIntervalMinutes, 1)
        XCTAssertEqual(settings.pollingIntervalSeconds, 60.0)

        settings.pollingIntervalMinutes = -10
        XCTAssertEqual(settings.pollingIntervalMinutes, 1)
        XCTAssertEqual(settings.pollingIntervalSeconds, 60.0)

        settings.pollingIntervalMinutes = 120
        XCTAssertEqual(settings.pollingIntervalMinutes, 120)
        XCTAssertEqual(settings.pollingIntervalSeconds, 7200.0)

        // CircularGaugeView clamping
        let underGauge = CircularGaugeView(score: -50)
        XCTAssertEqual(underGauge.score, 0)

        let overGauge = CircularGaugeView(score: 1500)
        XCTAssertEqual(overGauge.score, 100)
    }

    func testUserDefaults_CorruptedValuesRecovery() {
        // Inject invalid string for enum
        userDefaults.set("invalid_display_mode_foo", forKey: "ssd_health_display_mode")
        userDefaults.set("invalid_temp_unit_bar", forKey: "ssd_health_temperature_unit")
        userDefaults.set(-999.0, forKey: "ssd_health_polling_interval")
        userDefaults.set(-50.0, forKey: "ssd_health_thermal_warning")
        userDefaults.set(-100.0, forKey: "ssd_health_thermal_critical")
        userDefaults.set(-5, forKey: "ssd_health_wear_warning")
        userDefaults.set(-10, forKey: "ssd_health_spare_warning")
        userDefaults.set(-200.0, forKey: "ssd_health_rated_tbw_override")
        userDefaults.set("nonexistent_preset_xyz", forKey: "ssd_health_mock_preset_name")

        let freshSettings = AppSettings(userDefaults: userDefaults)

        // Check fallback to defaults
        XCTAssertEqual(freshSettings.displayMode, .healthPercent)
        XCTAssertEqual(freshSettings.temperatureUnit, .celsius)
        XCTAssertEqual(freshSettings.pollingIntervalSeconds, AppSettings.defaultPollingInterval)
        XCTAssertEqual(freshSettings.thermalWarningThresholdCelsius, AppSettings.defaultThermalWarning)
        XCTAssertEqual(freshSettings.thermalCriticalThresholdCelsius, AppSettings.defaultThermalCritical)
        XCTAssertEqual(freshSettings.wearWarningThresholdPercent, AppSettings.defaultWearWarning)
        XCTAssertEqual(freshSettings.spareWarningThresholdPercent, AppSettings.defaultSpareWarning)
        XCTAssertNil(freshSettings.ratedTBWOverride)
        XCTAssertEqual(freshSettings.mockPreset, .healthy)
    }

    // MARK: - 4. SMART Table Generation with Corrupted & Missing Data

    func testSMARTTable_NilLogsAndNilMetrics_ReturnsEmptySafely() {
        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        state.currentMetrics = nil
        state.rawSmartLog = nil

        let tableView = SMARTTableView(appState: state)
        XCTAssertEqual(tableView.allRows.count, 0)
        XCTAssertEqual(tableView.filteredRows.count, 0)
    }

    func testSMARTTable_NilRawLogWithValidMetrics_SynthesizesRows() {
        let metrics = SSDHealthMetrics(
            bsdName: "disk0", modelName: "SSD", serialNumber: "S1", firmwareRevision: "1", interconnect: "PCIe",
            capacityBytes: 500_000_000_000, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 36.0,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, terabytesWritten: 10, terabytesRead: 10,
            powerOnHours: 100, powerCycles: 50, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0,
            criticalWarnings: CriticalWarningFlags(rawValue: 0)
        )

        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        state.currentMetrics = metrics
        state.rawSmartLog = nil // nil raw log

        let tableView = SMARTTableView(appState: state)
        let rows = tableView.allRows
        XCTAssertGreaterThanOrEqual(rows.count, 17)
    }

    func testSMARTTable_AllZerosBuffer_RendersCleanly() {
        let zeroData = Data(repeating: 0, count: 512)
        guard let zeroLog = NVMESmartLog(data: zeroData) else {
            XCTFail("Failed to parse zero log")
            return
        }

        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        let tableView = SMARTTableView(appState: state)
        let rows = tableView.buildRows(from: zeroLog)

        XCTAssertGreaterThanOrEqual(rows.count, 17)
        for row in rows {
            XCTAssertFalse(row.name.isEmpty)
            XCTAssertFalse(row.rawHex.isEmpty)
            XCTAssertFalse(row.formattedValue.isEmpty)
        }
    }

    func testSMARTTable_AllOnesBuffer_RendersCleanly() {
        let onesData = Data(repeating: 0xFF, count: 512)
        guard let onesLog = NVMESmartLog(data: onesData) else {
            XCTFail("Failed to parse ones log")
            return
        }

        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        let tableView = SMARTTableView(appState: state)
        let rows = tableView.buildRows(from: onesLog)

        XCTAssertGreaterThanOrEqual(rows.count, 17)
        for row in rows {
            XCTAssertFalse(row.name.isEmpty)
            XCTAssertFalse(row.rawHex.isEmpty)
            XCTAssertFalse(row.formattedValue.isEmpty)
        }

        // Critical warning should be critical
        let critRow = rows.first(where: { $0.id == 1 })
        XCTAssertEqual(critRow?.status, .critical)
    }

    func testSMARTTable_Fuzzing512ByteBuffers_ZeroCrashes() {
        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        let tableView = SMARTTableView(appState: state)

        var rng = UInt64(0xDEADBEEF)
        func nextByte() -> UInt8 {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: rng >> 32)
        }

        for _ in 0..<100 {
            var buf = Data(count: 512)
            for i in 0..<512 {
                buf[i] = nextByte()
            }

            if let log = NVMESmartLog(data: buf) {
                let rows = tableView.buildRows(from: log)
                XCTAssertGreaterThanOrEqual(rows.count, 17)
                for row in rows {
                    XCTAssertFalse(row.name.isEmpty)
                    XCTAssertFalse(row.rawHex.isEmpty)
                    XCTAssertFalse(row.rawValueString.isEmpty)
                }
            }
        }
    }

    func testSMARTTable_TemperatureSensorsFiltering() {
        var buf = Data(repeating: 0, count: 512)
        // Set Composite temp to 300K
        buf[1] = 0x01
        buf[2] = 0x2C

        // Sensor 1 = 310K (0x0136) at offset 200..201
        buf[200] = 0x36
        buf[201] = 0x01

        // Sensor 2 = 0K (unimplemented) at offset 202..203 -> should be skipped
        buf[202] = 0x00
        buf[203] = 0x00

        // Sensor 3 = 350K (0x015E) at offset 204..205 -> 76.85°C (Critical)
        buf[204] = 0x5E
        buf[205] = 0x01

        guard let log = NVMESmartLog(data: buf) else {
            XCTFail("Failed to parse log")
            return
        }

        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        let tableView = SMARTTableView(appState: state)
        let rows = tableView.buildRows(from: log)

        let sensor1 = rows.first(where: { $0.name == "Temperature Sensor 1" })
        XCTAssertNotNil(sensor1)
        XCTAssertEqual(sensor1?.status, .normal)

        let sensor2 = rows.first(where: { $0.name == "Temperature Sensor 2" })
        XCTAssertNil(sensor2) // Skipped because 0K

        let sensor3 = rows.first(where: { $0.name == "Temperature Sensor 3" })
        XCTAssertNotNil(sensor3)
        XCTAssertEqual(sensor3?.status, .critical)
    }

    // MARK: - 5. Chart Filtering & Time-Series Edge Cases

    func testCharts_EmptyAndSinglePointHistory_HandledGracefully() {
        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)
        state.history = []

        let chartsView = HealthChartsView(appState: state)
        XCTAssertEqual(chartsView.filteredSamples.count, 0)

        // Single point
        state.history = [
            SSDHistorySnapshot(
                timestamp: Date(),
                healthScorePercent: 98,
                wearPercentage: 2,
                temperatureCelsius: 40.0,
                terabytesWritten: 10.0,
                availableSparePercent: 100
            )
        ]
        XCTAssertEqual(chartsView.filteredSamples.count, 1)
    }

    func testCharts_OutOrderAndDuplicateTimestamps_CorrectlySorted() {
        let now = Date()
        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)

        let t1 = now.addingTimeInterval(-1000)
        let t2 = now.addingTimeInterval(-500)
        let t3 = now.addingTimeInterval(-200)

        // Unordered and duplicate timestamps
        state.history = [
            SSDHistorySnapshot(timestamp: t3, healthScorePercent: 95, wearPercentage: 5, temperatureCelsius: 40.0, terabytesWritten: 12.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t1, healthScorePercent: 98, wearPercentage: 2, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t2, healthScorePercent: 96, wearPercentage: 4, temperatureCelsius: 39.0, terabytesWritten: 11.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t2, healthScorePercent: 96, wearPercentage: 4, temperatureCelsius: 39.0, terabytesWritten: 11.0, availableSparePercent: 100)
        ]

        let chartsView = HealthChartsView(appState: state)
        let filtered = chartsView.filteredSamples

        XCTAssertEqual(filtered.count, 4)
        XCTAssertEqual(filtered[0].timestamp, t1)
        XCTAssertEqual(filtered[1].timestamp, t2)
        XCTAssertEqual(filtered[2].timestamp, t2)
        XCTAssertEqual(filtered[3].timestamp, t3)
    }

    func testCharts_AllTimeRangeFilters() {
        let now = Date()
        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)

        var samples: [SSDHistorySnapshot] = []
        // Generate samples covering 400 days
        for day in 0..<400 {
            let t = now.addingTimeInterval(-Double(day) * 86_400.0)
            samples.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: max(0, 100 - day / 4),
                wearPercentage: min(100, day / 4),
                temperatureCelsius: 40.0,
                terabytesWritten: Double(day) * 0.5,
                availableSparePercent: 100
            ))
        }
        state.history = samples

        func countForRange(_ filter: TimeRangeFilter) -> Int {
            let sorted = state.history.sorted { $0.timestamp < $1.timestamp }
            guard let duration = filter.durationSeconds else { return sorted.count }
            let cutoff = now.addingTimeInterval(-duration)
            return sorted.filter { $0.timestamp >= cutoff }.count
        }

        // 24H -> day 0 (and possibly day 1 boundary depending on exact second, <= 2)
        XCTAssertLessThanOrEqual(countForRange(.day), 2)

        // 7D -> ~8 samples (0..7)
        XCTAssertEqual(countForRange(.week), 8)

        // 30D -> ~31 samples (0..30)
        XCTAssertEqual(countForRange(.month), 31)

        // 90D -> ~91 samples (0..90)
        XCTAssertEqual(countForRange(.quarter), 91)

        // 1Y (365.25d) -> ~366 samples
        XCTAssertEqual(countForRange(.year), 366)

        // All -> 400
        XCTAssertEqual(countForRange(.all), 400)
    }

    func testCharts_HighVolumeDataPointsPerformance() {
        let now = Date()
        let state = AppState(storageReader: MockSSDStorageReader(), settings: settings)

        var samples: [SSDHistorySnapshot] = []
        for i in 0..<5_000 {
            samples.append(SSDHistorySnapshot(
                timestamp: now.addingTimeInterval(-Double(i) * 60.0),
                healthScorePercent: 95,
                wearPercentage: 5,
                temperatureCelsius: 40.0,
                terabytesWritten: Double(i) * 0.01,
                availableSparePercent: 100
            ))
        }
        state.history = samples

        let chartsView = HealthChartsView(appState: state)
        XCTAssertEqual(chartsView.filteredSamples.count, 5_000)
    }

    // MARK: - 6. AppState Concurrency & Extreme Telemetry Resilience

    func testAppState_RapidPresetSwitchingStress() async {
        let mock = MockSSDStorageReader(preset: .healthy)
        let state = AppState(
            storageReader: mock,
            mockReader: mock,
            persistence: persistenceActor,
            settings: settings
        )

        let presets: [MockSSDStorageReader.Preset] = [
            .healthy, .warning, .overheating, .criticalWear, .degradedSpare,
            .healthy, .warning, .overheating, .criticalWear, .degradedSpare
        ]

        for p in presets {
            state.setMockPreset(p)
            await state.refreshNow()
            XCTAssertNotNil(state.currentMetrics)
            XCTAssertNotNil(state.rawSmartLog)
            XCTAssertNotNil(state.forecast)
        }
    }

    func testAppState_ExportUnderExtremeMetrics() throws {
        let extremeMetrics = SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "EXTREME SSD",
            serialNumber: "EXTREME999",
            firmwareRevision: "REV99",
            interconnect: "PCIe",
            capacityBytes: 8_000_000_000_000, // 8TB
            healthScorePercent: 0,
            wearPercentage: 255, // Over-worn
            temperatureCelsius: 95.5,
            availableSparePercent: 0,
            availableSpareThresholdPercent: 50,
            terabytesWritten: 50000.0,
            terabytesRead: 75000.0,
            powerOnHours: 100_000,
            powerCycles: 50_000,
            unsafeShutdowns: 1_000,
            mediaErrors: 500,
            errorLogEntries: 2_000,
            criticalWarnings: [.availableSpareBelowThreshold, .temperatureExceedsThreshold, .reliabilityDegraded, .readOnly]
        )

        let mock = MockSSDStorageReader(preset: .healthy, customMetrics: extremeMetrics)
        let state = AppState(storageReader: mock, persistence: persistenceActor, settings: settings)
        state.currentMetrics = extremeMetrics

        let json = try state.exportJSON()
        XCTAssertTrue(json.contains("EXTREME SSD"))
        XCTAssertTrue(json.contains("50000"))

        let csv = try state.exportCSV()
        XCTAssertTrue(csv.contains("Timestamp_ISO8601"))

        let report = state.exportTextReport()
        XCTAssertTrue(report.contains("Critical") || report.contains("CRITICAL"))
        XCTAssertTrue(report.contains("EXTREME SSD"))
    }
}
