import SwiftUI
import SSDHealthCore
import SSDHealthService

/// Detailed extrapolation view presenting write rate trends, dual-model lifespan projections, and CI bounds.
public struct ForecastView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var forecast: SSDForecastResult? {
        appState.forecast
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status Banner
                statusBanner

                // Prognosis & Lifespan Cards (2x2 Grid)
                kpiGrid

                // 95% Confidence Interval Card
                confidenceIntervalCard

                // Extrapolation Methodology Card
                methodologyCard
            }
            .padding(16)
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        let status = forecast?.degradationStatus ?? .insufficientData
        let (color, icon): (Color, String) = {
            switch status {
            case .stable: return (.green, "checkmark.seal.fill")
            case .moderateWear: return (.blue, "info.circle.fill")
            case .acceleratedWear: return (.orange, "exclamationmark.triangle.fill")
            case .criticalWear, .exceededEndurance: return (.red, "exclamationmark.octagon.fill")
            case .insufficientData: return (.secondary, "hourglass")
            }
        }()

        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(status.title)
                        .font(.system(size: 16, weight: .bold))

                    Spacer()

                    Text(status.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12))
                        .foregroundColor(color)
                        .clipShape(Capsule())
                }

                Text(status.detailedDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(color.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - KPI Grid

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCardView(
                title: "Estimated Lifespan",
                value: forecast?.lifespanFormatted ?? "Estimating...",
                subtitle: forecast?.estimatedDaysRemaining != nil && !(forecast?.estimatedDaysRemaining.isInfinite ?? true) ? "\(Int(forecast!.estimatedDaysRemaining)) Days Remaining" : "Projected Remaining Time",
                systemImage: "hourglass",
                statusColor: forecast?.degradationStatus == .criticalWear ? .red : (forecast?.degradationStatus == .stable ? .green : .orange)
            )

            MetricCardView(
                title: "Exhaustion Date",
                value: forecast?.exhaustionDateFormatted ?? "N/A",
                subtitle: "Target Endurance Limit",
                systemImage: "calendar.badge.clock",
                statusColor: .blue
            )

            MetricCardView(
                title: "Primary Daily Write Rate",
                value: forecast?.dailyRateFormatted ?? "0.00 GB/day",
                subtitle: "Active Regression Slope",
                systemImage: "arrow.up.doc",
                statusColor: .purple
            )

            MetricCardView(
                title: "Rate Multi-Window Comparison",
                value: String(format: "7d: %.1f │ 30d: %.1f", forecast?.dailyWriteRate7dGB ?? 0.0, forecast?.dailyWriteRate30dGB ?? 0.0),
                subtitle: String(format: "Lifetime Avg: %.1f GB/day", forecast?.dailyWriteRateLifetimeGB ?? 0.0),
                systemImage: "chart.line.uptrend.xyaxis",
                statusColor: .secondary
            )
        }
    }

    // MARK: - Confidence Interval Card

    private var confidenceIntervalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Statistical 95% Confidence Bounds", systemImage: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .bold))

            if let ci = forecast?.confidenceInterval95 {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lower Bound (Best Case)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f GB/day", ci.lowerGB))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }

                    Divider().frame(height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mean Projected Rate")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(forecast?.dailyRateFormatted ?? "0.00 GB/day")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }

                    Divider().frame(height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upper Bound (Worst Case)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f GB/day", ci.upperGB))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)

                Text(#"Based on Ordinary Least Squares (OLS) regression over historical write deltas. Represents the 95% confidence interval (β ± 1.96 · SE_β) for sustained daily write throughput."#)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Insufficient historical samples to compute 95% confidence interval.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - Extrapolation Methodology

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Lifespan Extrapolation Models", systemImage: "function")
                .font(.system(size: 13, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(#"Model A: Wear Rate Delta (ΔWear / Δt)"#)
                            .font(.system(size: 12, weight: .semibold))
                        Text("Direct linear extrapolation based on measured percentage used increase over historical observation window.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(#"Model B: Rated TBW Endurance (Remaining TBW / Daily TBW Rate)"#)
                            .font(.system(size: 12, weight: .semibold))
                        Text("Manufacturer rated write endurance (e.g. 0.6 TBW per GB) combined with active OLS regression daily write throughput.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
    }
}

#Preview("Forecast View") {
    let mock = MockSSDStorageReader(preset: .healthy)
    let state = AppState(storageReader: mock)
    ForecastView(appState: state)
        .onAppear {
            state.loadInitialData()
        }
        .frame(width: 800, height: 600)
}
