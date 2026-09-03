import SwiftUI
import SSDHealthCore
import SSDHealthService

/// 340pt transient popover presenting immediate SSD health, temperature, TBW, and lifespan prognosis.
public struct QuickViewPopover: View {
    @Bindable public var appState: AppState
    public var onOpenDashboard: (() -> Void)?
    public var onOpenSettings: (() -> Void)?

    public init(
        appState: AppState,
        onOpenDashboard: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 12) {
            // MARK: - Header
            headerSection

            Divider()

            // MARK: - Core Telemetry Grid
            if let metrics = appState.currentMetrics {
                metricsSection(metrics: metrics)
            } else if appState.isLoading {
                loadingSection
            } else if let error = appState.errorMessage {
                errorSection(message: error)
            } else {
                emptySection
            }

            Divider()

            // MARK: - Footer & Action Toolbar
            footerSection
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial)
    }

    // MARK: - Header View

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: appState.menuBarIconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(appState.menuBarStatus.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.currentMetrics?.modelName ?? "Apple Internal SSD")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(appState.currentMetrics?.interconnect ?? "NVMe")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    if let cap = appState.currentMetrics?.capacityFormatted {
                        Text("• \(cap)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Status Pill Badge
            statusBadge(status: appState.menuBarStatus)
        }
    }

    private func statusBadge(status: HealthStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)

            Text(status.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Metrics Content

    private func metricsSection(metrics: SSDHealthMetrics) -> some View {
        VStack(spacing: 10) {
            // Row 1: Health Gauge + Temperature Card
            HStack(spacing: 12) {
                // Circular Health Gauge
                CircularGaugeView(
                    score: metrics.healthScorePercent,
                    size: 96,
                    lineWidth: 10,
                    subtitle: "\(metrics.wearPercentage)% Wear"
                )
                .frame(width: 100)

                // Temperature Telemetry Card
                VStack(alignment: .leading, spacing: 6) {
                    Label("Temperature", systemImage: "thermometer.medium")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(appState.settings.temperatureUnit.format(celsius: metrics.temperatureCelsius))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(temperatureColor(metrics.temperatureCelsius))

                    temperatureStatusBadge(celsius: metrics.temperatureCelsius)

                    if metrics.isFallbackData {
                        Text("Fallback Telemetry")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            // Row 2: Lifetime Written (TBW) + Remaining Lifespan
            HStack(spacing: 8) {
                // TBW Card
                VStack(alignment: .leading, spacing: 3) {
                    Label("Lifetime Written", systemImage: "arrow.up.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(metrics.tbwFormatted)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if let f = appState.forecast {
                        Text("Rate: \(f.dailyRateFormatted)")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)

                // Remaining Lifespan Card
                VStack(alignment: .leading, spacing: 3) {
                    Label("Lifespan Prognosis", systemImage: "hourglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(appState.forecast?.lifespanFormatted ?? "Estimating...")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(lifespanColor(status: appState.forecast?.degradationStatus))

                    Text(appState.forecast?.degradationStatus.title ?? "Collecting data")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }
        }
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        if celsius >= appState.settings.thermalCriticalThresholdCelsius {
            return .red
        } else if celsius >= appState.settings.thermalWarningThresholdCelsius {
            return .orange
        } else {
            return .primary
        }
    }

    private func temperatureStatusBadge(celsius: Double) -> some View {
        let (label, color): (String, Color) = {
            if celsius >= appState.settings.thermalCriticalThresholdCelsius {
                return ("Critical Hot", .red)
            } else if celsius >= appState.settings.thermalWarningThresholdCelsius {
                return ("Elevated", .orange)
            } else {
                return ("Optimal", .green)
            }
        }()

        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(color)
        }
    }

    private func lifespanColor(status: DegradationStatus?) -> Color {
        switch status {
        case .criticalWear, .exceededEndurance:
            return .red
        case .acceleratedWear, .moderateWear:
            return .orange
        case .stable:
            return .green
        default:
            return .primary
        }
    }

    // MARK: - Loading & Error Placeholders

    private var loadingSection: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Reading NVMe SMART Telemetry...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(height: 120)
    }

    private func errorSection(message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text("Telemetry Unavailable")
                .font(.system(size: 12, weight: .bold))
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(height: 120)
    }

    private var emptySection: some View {
        VStack(spacing: 6) {
            Text("No Drive Data")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(height: 120)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            HStack {
                if let updated = appState.lastUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Text("Ready")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    Task {
                        await appState.refreshNow()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(appState.isRefreshing ? 360 : 0))
                            .animation(appState.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.isRefreshing)
                        Text("Refresh")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .disabled(appState.isRefreshing)
            }

            // Action Buttons
            HStack(spacing: 6) {
                Button(action: {
                    onOpenDashboard?()
                }) {
                    HStack {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        Text("Dashboard")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: {
                    onOpenSettings?()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Settings")

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Quit Application")
            }
        }
    }
}

#Preview("Healthy Popover") {
    let mockReader = MockSSDStorageReader(preset: .healthy)
    let state = AppState(storageReader: mockReader)
    QuickViewPopover(appState: state)
        .onAppear {
            state.loadInitialData()
        }
}

#Preview("Warning Popover") {
    let mockReader = MockSSDStorageReader(preset: .warning)
    let state = AppState(storageReader: mockReader)
    QuickViewPopover(appState: state)
        .onAppear {
            state.loadInitialData()
        }
}
