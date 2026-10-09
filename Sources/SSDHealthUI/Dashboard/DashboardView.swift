import SwiftUI
import SSDHealthCore
import SSDHealthService

/// Main analytics dashboard window hosting Overview, SMART Table, Charts, Forecast, and Settings.
public struct DashboardView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar Navigation
            List(DashboardTab.allCases, selection: $appState.selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.iconName)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            // Detail Content
            VStack(spacing: 0) {
                if appState.isFallbackData || appState.settings.useMockReader {
                    dataSourceBanner
                }
                if let error = appState.errorMessage {
                    readErrorBanner(error)
                }

                switch appState.selectedTab {
                case .overview:
                    overviewView
                case .smartTable:
                    SMARTTableView(appState: appState)
                case .charts:
                    HealthChartsView(appState: appState)
                case .forecast:
                    ForecastView(appState: appState)
                case .settings:
                    SettingsView(appState: appState)
                }
            }
            .navigationTitle(appState.selectedTab.rawValue)
            .toolbar {
                toolbarItems
            }
        }
        .frame(minWidth: 800, minHeight: 560)
    }

    // MARK: - Data Source Banner

    /// Warns that the shown values are not live SMART data and are excluded from history and alerts.
    private var dataSourceBanner: some View {
        let isDemo = appState.settings.useMockReader
        return HStack(spacing: 8) {
            Image(systemName: isDemo ? "testtube.2" : "exclamationmark.triangle.fill")
            Text(isDemo
                 ? "Demo data active. Values are simulated and are not recorded to history or alerts."
                 : "SMART access unavailable. Health, temperature and spare values are placeholders; history, forecast and alerts are paused.")
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    /// Last read failed; values shown below are from the previous successful read, if any.
    private func readErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
            Text(appState.currentMetrics == nil ? "Telemetry read failed: \(message)" : "Last refresh failed, showing previous reading: \(message)")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Spacer()
        }
        .foregroundColor(.red)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.10))
    }

    // MARK: - Overview Tab View

    private var overviewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Drive Identity Header Banner
                driveHeaderBanner

                // 3x2 KPI Metric Card Grid
                kpiMetricGrid

                // Lifespan & Forecast Summary Strip
                forecastSummaryStrip

                // Recent Telemetry Highlights
                recentTelemetryHighlights
            }
            .padding(16)
        }
    }

    // MARK: - Drive Header Banner

    private var driveHeaderBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: appState.menuBarIconName)
                .font(.system(size: 34))
                .foregroundColor(appState.menuBarStatus.color)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(appState.currentMetrics?.modelName ?? "Apple Internal NVMe SSD")
                        .font(.system(size: 16, weight: .bold))

                    statusBadge(status: appState.menuBarStatus)

                    if appState.settings.useMockReader {
                        Text("SIMULATED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text("BSD: \(appState.currentMetrics?.bsdName ?? "disk0")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("• S/N: \(appState.currentMetrics?.serialNumber ?? "N/A")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("• Rev: \(appState.currentMetrics?.firmwareRevision ?? "N/A")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let cap = appState.currentMetrics?.capacityFormatted {
                        Text("• \(cap)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Circular Mini-Gauge
            if let metrics = appState.currentMetrics {
                CircularGaugeView(score: metrics.healthScorePercent, size: 54, lineWidth: 6, title: "HEALTH")
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
    }

    private func statusBadge(status: HealthStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - 3x2 KPI Metric Grid

    private var kpiMetricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // 1. Health Score
            MetricCardView(
                title: "Health Score",
                value: "\(appState.currentMetrics?.healthScorePercent ?? 0)%",
                subtitle: "Wear: \(appState.currentMetrics?.wearPercentage ?? 0)% Used",
                systemImage: "internaldrive",
                statusColor: appState.menuBarStatus.color,
                statusBadge: appState.menuBarStatus.rawValue
            )

            // 2. Available Spare
            MetricCardView(
                title: "Available Spare",
                value: "\(appState.currentMetrics?.availableSparePercent ?? 0)%",
                subtitle: "Threshold: \(appState.currentMetrics?.availableSpareThresholdPercent ?? 10)%",
                systemImage: "square.stack.3d.up",
                statusColor: (appState.currentMetrics?.availableSparePercent ?? 100) < (appState.currentMetrics?.availableSpareThresholdPercent ?? 10) ? .red : .green
            )

            // 3. Data Units Written (TBW)
            MetricCardView(
                title: "Data Units Written",
                value: appState.currentMetrics?.tbwFormatted ?? "0.00 TBW",
                subtitle: "Read: \(appState.currentMetrics?.tbrFormatted ?? "0.00 TBR")",
                systemImage: "arrow.up.doc",
                statusColor: .blue
            )

            // 4. Power-On Time
            MetricCardView(
                title: "Power-On Time",
                value: "\(appState.currentMetrics?.powerOnHours ?? 0) Hours",
                subtitle: formatPowerOnTime(hours: appState.currentMetrics?.powerOnHours ?? 0),
                systemImage: "clock",
                statusColor: .purple
            )

            // 5. Unsafe Shutdowns
            MetricCardView(
                title: "Unsafe Shutdowns",
                value: "\(appState.currentMetrics?.unsafeShutdowns ?? 0)",
                subtitle: "\(appState.currentMetrics?.powerCycles ?? 0) Total Power Cycles",
                systemImage: "power",
                statusColor: (appState.currentMetrics?.unsafeShutdowns ?? 0) > 50 ? .orange : .green
            )

            // 6. Media Integrity Errors
            MetricCardView(
                title: "Media Errors",
                value: "\(appState.currentMetrics?.mediaErrors ?? 0) Errors",
                subtitle: "\(appState.currentMetrics?.errorLogEntries ?? 0) Error Log Entries",
                systemImage: "shield.lefthalf.filled",
                statusColor: (appState.currentMetrics?.mediaErrors ?? 0) > 0 ? .red : .green
            )
        }
    }

    private func formatPowerOnTime(hours: UInt64) -> String {
        let days = hours / 24
        let remainingHours = hours % 24
        return "\(days) Days, \(remainingHours) Hrs"
    }

    // MARK: - Forecast Summary Strip

    private var forecastSummaryStrip: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Projected Lifespan", systemImage: "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(appState.forecast?.lifespanFormatted ?? "Estimating...")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            Divider().frame(height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Label("Target Exhaustion Date", systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(appState.forecast?.exhaustionDateFormatted ?? "N/A")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            Divider().frame(height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Label("Daily Write Load", systemImage: "arrow.up.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(appState.forecast?.dailyRateFormatted ?? "0.00 GB/day")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            Spacer()

            Button("View Full Forecast") {
                appState.selectedTab = .forecast
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Recent Telemetry Highlights

    private var recentTelemetryHighlights: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                    .foregroundColor(.orange)
                Text("Current Temp:")
                    .foregroundColor(.secondary)
                Text(appState.settings.temperatureUnit.format(celsius: appState.currentMetrics?.temperatureCelsius ?? 0))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }

            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundColor(.blue)
                Text("Controller Busy:")
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f hrs", Double((appState.rawSmartLog?.controllerBusyTimeMinutes.low ?? 0)) / 60.0))
                    .font(.system(size: 12, weight: .semibold))
            }

            Spacer()

            if let updated = appState.lastUpdated {
                Text("Updated \(updated, style: .time)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 4)
    }

    // MARK: - Toolbar Items

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: {
                Task {
                    await appState.refreshNow()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isRefreshing)
            .help("Refresh NVMe SMART Telemetry")

            Menu {
                Button("Export JSON Telemetry...") {
                    ExportPanel.run(.json, appState: appState)
                }
                Button("Export CSV Time Series...") {
                    ExportPanel.run(.csv, appState: appState)
                }
                Button("Export Diagnostic Report...") {
                    ExportPanel.run(.textReport, appState: appState)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }
}

#Preview("Main Dashboard View") {
    let mock = MockSSDStorageReader(preset: .healthy)
    let state = AppState(storageReader: mock)
    DashboardView(appState: state)
        .onAppear {
            state.loadInitialData()
        }
        .frame(width: 960, height: 680)
}
