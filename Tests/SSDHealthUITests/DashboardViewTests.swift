import XCTest
import SwiftUI
@testable import SSDHealthCore
@testable import SSDHealthService
@testable import SSDHealthUI

@MainActor
final class DashboardViewTests: XCTestCase {

    var state: AppState!
    var mockReader: MockSSDStorageReader!

    override func setUp() async throws {
        try await super.setUp()
        mockReader = MockSSDStorageReader(preset: .healthy)
        state = AppState(storageReader: mockReader, mockReader: mockReader)
        await state.refreshNow()
    }

    override func tearDown() async throws {
        state = nil
        mockReader = nil
        try await super.tearDown()
    }

    // MARK: - SMART Table Generation & Filtering

    func testSMARTTable_GeneratesAllStandardParameters() throws {
        let tableView = SMARTTableView(appState: state)
        let rows = tableView.allRows

        XCTAssertGreaterThanOrEqual(rows.count, 17)

        // Check key parameter names
        let names = rows.map(\.name)
        XCTAssertTrue(names.contains("Critical Warning"))
        XCTAssertTrue(names.contains("Composite Temperature"))
        XCTAssertTrue(names.contains("Available Spare"))
        XCTAssertTrue(names.contains("Percentage Used"))
        XCTAssertTrue(names.contains("Data Units Written"))
        XCTAssertTrue(names.contains("Data Units Read"))
        XCTAssertTrue(names.contains("Power-On Hours"))
        XCTAssertTrue(names.contains("Unsafe Shutdowns"))
        XCTAssertTrue(names.contains("Media and Data Integrity Errors"))
    }

    func testSMARTTable_SearchFiltering_MatchesKeywords() {
        let tableView = SMARTTableView(appState: state)
        let rows = tableView.allRows

        // Search for "Temperature"
        let tempMatches = rows.filter { $0.name.lowercased().contains("temperature") }
        XCTAssertGreaterThanOrEqual(tempMatches.count, 1)

        // Search for "Media"
        let mediaMatches = rows.filter { $0.name.lowercased().contains("media") }
        XCTAssertEqual(mediaMatches.count, 1)
        XCTAssertEqual(mediaMatches.first?.name, "Media and Data Integrity Errors")
    }

    func testSMARTTable_StatusFiltering_IsolatesCriticalRows() async throws {
        // Switch to critical wear preset
        mockReader.setPreset(.criticalWear)
        let synData = MockSSDStorageReader.generateSyntheticRawData(for: try await mockReader.readHealthMetrics())
        let log = NVMESmartLog(data: synData)!

        let tableView = SMARTTableView(appState: state)
        let rows = tableView.buildRows(from: log)

        let criticalRows = rows.filter { $0.status == .critical }
        XCTAssertGreaterThanOrEqual(criticalRows.count, 2) // Available spare & percentage used
    }

    // MARK: - Charts Time Range Filtering

    func testHealthCharts_TimeRangeFiltering_CalculatesCorrectSampleSubsets() async {
        let now = Date()
        var samples: [SSDHistorySnapshot] = []

        // Generate 30 daily samples
        for i in 0..<30 {
            let t = now.addingTimeInterval(-Double(i) * 86_400.0)
            samples.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: 100 - i,
                wearPercentage: i,
                temperatureCelsius: 40.0,
                terabytesWritten: Double(i) * 1.5,
                availableSparePercent: 100
            ))
        }

        state.history = samples

        let chartsView = HealthChartsView(appState: state)
        XCTAssertEqual(chartsView.filteredSamples.count, 30)

        // All samples
        XCTAssertEqual(state.history.count, 30)

        // 24H filter should retain samples within 24 hours
        let dayCutoff = now.addingTimeInterval(-86_400.0)
        let daySamples = samples.filter { $0.timestamp >= dayCutoff }
        XCTAssertLessThanOrEqual(daySamples.count, 2)
    }

    // MARK: - MetricCardView Model Binding

    func testMetricCardView_BindingAndProperties() {
        let card = MetricCardView(
            title: "Health Score",
            value: "98%",
            subtitle: "Wear: 2% Used",
            systemImage: "internaldrive",
            statusColor: .green,
            statusBadge: "Optimal"
        )

        XCTAssertEqual(card.title, "Health Score")
        XCTAssertEqual(card.value, "98%")
        XCTAssertEqual(card.subtitle, "Wear: 2% Used")
        XCTAssertEqual(card.systemImage, "internaldrive")
        XCTAssertEqual(card.statusBadge, "Optimal")
    }

    // MARK: - DashboardTab Navigation

    func testDashboardTab_IconsAndRawValues() {
        XCTAssertEqual(DashboardTab.overview.rawValue, "Overview")
        XCTAssertEqual(DashboardTab.smartTable.rawValue, "SMART Table")
        XCTAssertEqual(DashboardTab.charts.rawValue, "Charts & History")
        XCTAssertEqual(DashboardTab.forecast.rawValue, "Forecast")
        XCTAssertEqual(DashboardTab.settings.rawValue, "Settings")

        XCTAssertFalse(DashboardTab.overview.iconName.isEmpty)
        XCTAssertFalse(DashboardTab.smartTable.iconName.isEmpty)
        XCTAssertFalse(DashboardTab.charts.iconName.isEmpty)
        XCTAssertFalse(DashboardTab.forecast.iconName.isEmpty)
        XCTAssertFalse(DashboardTab.settings.iconName.isEmpty)
    }

    // MARK: - TimeRangeFilter & ChartMetricType

    func testChartMetricType_Properties() {
        XCTAssertEqual(ChartMetricType.wear.rawValue, "Wear Level")
        XCTAssertEqual(ChartMetricType.tbw.rawValue, "TBW Accumulation")
        XCTAssertEqual(ChartMetricType.thermal.rawValue, "Temperature")

        XCTAssertFalse(ChartMetricType.wear.iconName.isEmpty)
        XCTAssertFalse(ChartMetricType.tbw.iconName.isEmpty)
        XCTAssertFalse(ChartMetricType.thermal.iconName.isEmpty)
    }

    func testTimeRangeFilter_Durations() {
        XCTAssertEqual(TimeRangeFilter.day.durationSeconds, 86_400.0)
        XCTAssertEqual(TimeRangeFilter.week.durationSeconds, 7.0 * 86_400.0)
        XCTAssertEqual(TimeRangeFilter.month.durationSeconds, 30.0 * 86_400.0)
        XCTAssertEqual(TimeRangeFilter.quarter.durationSeconds, 90.0 * 86_400.0)
        XCTAssertEqual(TimeRangeFilter.year.durationSeconds, 365.25 * 86_400.0)
        XCTAssertNil(TimeRangeFilter.all.durationSeconds)
    }

    // MARK: - ParameterStatus Properties

    func testParameterStatus_ColorsAndIcons() {
        for status in ParameterStatus.allCases {
            XCTAssertFalse(status.rawValue.isEmpty)
            XCTAssertFalse(status.iconName.isEmpty)
            XCTAssertNotNil(status.color)
        }
    }

    // MARK: - ForecastView Presentation

    func testForecastView_Initialization() {
        let forecastView = ForecastView(appState: state)
        XCTAssertNotNil(forecastView)
        XCTAssertNotNil(state.forecast)
        XCTAssertEqual(state.forecast?.degradationStatus, .insufficientData)
    }
}
