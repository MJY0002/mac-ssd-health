import SwiftUI
import Charts
import SSDHealthCore
import SSDHealthService

// MARK: - Time Range Filter

public enum TimeRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case day = "24H"
    case week = "7D"
    case month = "30D"
    case quarter = "90D"
    case year = "1Y"
    case all = "All"

    public var id: String { rawValue }

    public var durationSeconds: TimeInterval? {
        switch self {
        case .day: return 86_400.0
        case .week: return 7.0 * 86_400.0
        case .month: return 30.0 * 86_400.0
        case .quarter: return 90.0 * 86_400.0
        case .year: return 365.25 * 86_400.0
        case .all: return nil
        }
    }
}

// MARK: - Selected Chart Metric Type

public enum ChartMetricType: String, CaseIterable, Identifiable, Sendable {
    case wear = "Wear Level"
    case tbw = "TBW Accumulation"
    case thermal = "Temperature"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .wear: return "percent"
        case .tbw: return "arrow.up.doc"
        case .thermal: return "thermometer.medium"
        }
    }
}

// MARK: - Health Charts View

public struct HealthChartsView: View {
    @Bindable public var appState: AppState
    @State private var selectedRange: TimeRangeFilter = .month
    @State private var selectedMetric: ChartMetricType = .wear
    @State private var hoveredTimestamp: Date?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var filteredSamples: [SSDHistorySnapshot] {
        let sorted = appState.history.sorted { $0.timestamp < $1.timestamp }
        guard let duration = selectedRange.durationSeconds else { return sorted }
        let cutoff = Date().addingTimeInterval(-duration)
        return sorted.filter { $0.timestamp >= cutoff }
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Chart Category & Range Selectors
            toolbarSection

            Divider()

            // Chart Content Area
            if filteredSamples.count < 2 {
                emptyStateView
            } else {
                chartContainerView
            }
        }
        .padding(16)
    }

    // MARK: - Toolbar Section

    private var toolbarSection: some View {
        HStack {
            // Metric Switcher
            Picker("Metric", selection: $selectedMetric) {
                ForEach(ChartMetricType.allCases) { metric in
                    Label(metric.rawValue, systemImage: metric.iconName)
                        .tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            Spacer()

            // Time Range Switcher
            Picker("Range", selection: $selectedRange) {
                ForEach(TimeRangeFilter.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
    }

    // MARK: - Chart Container

    private var chartContainerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selected Point Legend / Header
            legendHeader

            // Render Active Chart
            switch selectedMetric {
            case .wear:
                wearProgressionChart
            case .tbw:
                tbwAccumulationChart
            case .thermal:
                thermalHistoryChart
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - Chart Header & Tooltip

    private var legendHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedMetric.rawValue)
                    .font(.system(size: 14, weight: .bold))

                if let hovered = hoveredSample {
                    Text("Selected: \(formatDate(hovered.timestamp)) — \(formatHoveredValue(hovered))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                } else if let latest = filteredSamples.last {
                    Text("Latest: \(formatDate(latest.timestamp)) — \(formatHoveredValue(latest))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(filteredSamples.count) data points")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var hoveredSample: SSDHistorySnapshot? {
        guard let hoveredDate = hoveredTimestamp else { return nil }
        return filteredSamples.min(by: { abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate)) })
    }

    private func formatHoveredValue(_ sample: SSDHistorySnapshot) -> String {
        switch selectedMetric {
        case .wear:
            return "\(sample.wearPercentage)% Used (\(sample.healthScorePercent)% Health)"
        case .tbw:
            return String(format: "%.2f TBW", sample.terabytesWritten)
        case .thermal:
            return appState.settings.temperatureUnit.format(celsius: sample.temperatureCelsius)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - 1. Wear Progression Chart

    private var wearProgressionChart: some View {
        Chart {
            ForEach(filteredSamples) { sample in
                AreaMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("Wear", sample.wearPercentage)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange.opacity(0.4), .orange.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("Wear", sample.wearPercentage)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("Wear", sample.wearPercentage)
                )
                .foregroundStyle(.orange)
                .symbolSize(18)
            }

            // Wear Warning Rule (80%)
            RuleMark(y: .value("Warning Threshold", appState.settings.wearWarningThresholdPercent))
                .foregroundStyle(.orange.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Warning (80%)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                }

            // Critical 100% Rule
            RuleMark(y: .value("Endurance Limit", 100))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Rated 100% Wear")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.red)
                }
        }
        .chartYScale(domain: 0...max(105, (filteredSamples.map(\.wearPercentage).max() ?? 0) + 10))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day().hour())
            }
        }
        .frame(height: 280)
    }

    // MARK: - 2. TBW Accumulation Chart

    private var tbwAccumulationChart: some View {
        Chart {
            ForEach(filteredSamples) { sample in
                LineMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("TBW", sample.terabytesWritten)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("TBW", sample.terabytesWritten)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                PointMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("TBW", sample.terabytesWritten)
                )
                .foregroundStyle(.blue)
                .symbolSize(18)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day().hour())
            }
        }
        .frame(height: 280)
    }

    // MARK: - 3. Thermal History Chart

    private var thermalHistoryChart: some View {
        Chart {
            ForEach(filteredSamples) { sample in
                LineMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("Temperature", sample.temperatureCelsius)
                )
                .foregroundStyle(.mint)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Timestamp", sample.timestamp),
                    y: .value("Temperature", sample.temperatureCelsius)
                )
                .foregroundStyle(sample.temperatureCelsius >= appState.settings.thermalCriticalThresholdCelsius ? .red : (sample.temperatureCelsius >= appState.settings.thermalWarningThresholdCelsius ? .orange : .mint))
                .symbolSize(22)
            }

            // Warning Temperature Rule (60°C)
            RuleMark(y: .value("Warning Temp", appState.settings.thermalWarningThresholdCelsius))
                .foregroundStyle(.orange.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Warn (\(Int(appState.settings.thermalWarningThresholdCelsius))°C)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                }

            // Critical Temperature Rule (65°C)
            RuleMark(y: .value("Critical Temp", appState.settings.thermalCriticalThresholdCelsius))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Crit (\(Int(appState.settings.thermalCriticalThresholdCelsius))°C)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.red)
                }
        }
        .chartYScale(domain: 20...max(80, (filteredSamples.map(\.temperatureCelsius).max() ?? 60.0) + 10.0))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day().hour())
            }
        }
        .frame(height: 280)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.7))

            Text("Insufficient Historical Data")
                .font(.system(size: 15, weight: .bold))

            Text("Collecting historical measurements over time.\nMinimum 2 samples required for time-series trend analysis.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
    }
}

#Preview("Charts View with History") {
    let mock = MockSSDStorageReader(preset: .healthy)
    let state = AppState(storageReader: mock)
    HealthChartsView(appState: state)
        .onAppear {
            state.loadInitialData()
        }
        .frame(width: 800, height: 500)
}
