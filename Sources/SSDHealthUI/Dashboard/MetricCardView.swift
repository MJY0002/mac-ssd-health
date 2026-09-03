import SwiftUI
import SSDHealthCore

/// KPI Metric Card presenting a single hardware telemetry indicator with icon, values, and status tint.
public struct MetricCardView: View {
    public let title: String
    public let value: String
    public let subtitle: String?
    public let systemImage: String
    public let statusColor: Color
    public let statusBadge: String?

    public init(
        title: String,
        value: String,
        subtitle: String? = nil,
        systemImage: String,
        statusColor: Color = .primary,
        statusBadge: String? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.statusColor = statusColor
        self.statusBadge = statusBadge
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row: Icon + Title + Status Badge
            HStack(alignment: .center) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusColor)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if let badge = statusBadge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.12))
                        .foregroundColor(statusColor)
                        .clipShape(Capsule())
                }
            }

            // Primary Metric Value
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Subtitle / Secondary Context
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.2), lineWidth: statusColor == .primary ? 0 : 1)
        )
    }
}

#Preview("Metric Cards") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        MetricCardView(
            title: "Health Score",
            value: "98%",
            subtitle: "Wear: 2% (Rated OK)",
            systemImage: "internaldrive",
            statusColor: .green,
            statusBadge: "Optimal"
        )
        MetricCardView(
            title: "Available Spare",
            value: "100%",
            subtitle: "Threshold: 10%",
            systemImage: "square.stack.3d.up",
            statusColor: .green
        )
        MetricCardView(
            title: "Data Units Written",
            value: "34.22 TBW",
            subtitle: "Read: 48.15 TBR",
            systemImage: "arrow.up.doc",
            statusColor: .blue
        )
    }
    .padding()
}
