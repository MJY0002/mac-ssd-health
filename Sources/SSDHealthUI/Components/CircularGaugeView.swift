import SwiftUI
import SSDHealthCore

/// Circular health gauge progress ring displaying SSD health percentage with dynamic status coloring.
public struct CircularGaugeView: View {
    public let score: Int // 0 - 100%
    public let size: CGFloat
    public let lineWidth: CGFloat
    public let showLabel: Bool
    public let title: String
    public let subtitle: String?

    public init(
        score: Int,
        size: CGFloat = 120,
        lineWidth: CGFloat = 12,
        showLabel: Bool = true,
        title: String = "HEALTH",
        subtitle: String? = nil
    ) {
        self.score = max(0, min(100, score))
        self.size = size
        self.lineWidth = lineWidth
        self.showLabel = showLabel
        self.title = title
        self.subtitle = subtitle
    }

    private var progress: Double {
        Double(score) / 100.0
    }

    private var statusColor: Color {
        if score > 80 {
            return .green
        } else if score > 20 {
            return .orange
        } else {
            return .red
        }
    }

    private var gradient: AngularGradient {
        if score > 80 {
            return AngularGradient(
                colors: [.green.opacity(0.8), .green, .mint],
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            )
        } else if score > 20 {
            return AngularGradient(
                colors: [.yellow, .orange, .orange.opacity(0.9)],
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            )
        } else {
            return AngularGradient(
                colors: [.red.opacity(0.8), .red, .pink],
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            )
        }
    }

    public var body: some View {
        ZStack {
            // Background Track
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Dynamic Progress Stroke
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
                .frame(width: size, height: size)

            // Inner Content
            if showLabel {
                VStack(spacing: size > 90 ? 2 : 0) {
                    Text("\(score)%")
                        .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Text(title)
                        .font(.system(size: max(8, size * 0.09), weight: .semibold, design: .default))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    if let sub = subtitle, size >= 110 {
                        Text(sub)
                            .font(.system(size: max(8, size * 0.08), weight: .regular))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SSD Health Score: \(score) percent")
    }
}

#Preview("Healthy (98%)") {
    CircularGaugeView(score: 98, size: 140, lineWidth: 14, subtitle: "2% Wear Level")
        .padding()
}

#Preview("Warning (45%)") {
    CircularGaugeView(score: 45, size: 140, lineWidth: 14, subtitle: "55% Wear Level")
        .padding()
}

#Preview("Critical (8%)") {
    CircularGaugeView(score: 8, size: 140, lineWidth: 14, subtitle: "92% Wear Level")
        .padding()
}
