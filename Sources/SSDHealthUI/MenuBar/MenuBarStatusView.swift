import SwiftUI
import SSDHealthCore

/// Declarative SwiftUI view representing the menu bar item status with dynamic icon and anti-jitter typography.
public struct MenuBarStatusView: View {
    public let status: HealthStatus
    public let title: String
    public let iconName: String

    public init(status: HealthStatus, title: String, iconName: String? = nil) {
        self.status = status
        self.title = title
        self.iconName = iconName ?? status.iconName
    }

    public init(metrics: SSDHealthMetrics?, mode: MenuBarDisplayMode, unit: TemperatureUnit = .celsius) {
        self.status = HealthStatus.evaluate(metrics: metrics)
        self.iconName = status.iconName

        if let m = metrics {
            let tempStr = unit == .celsius ? "\(Int(round(m.temperatureCelsius)))°C" : "\(Int(round(m.temperatureCelsius * 1.8 + 32.0)))°F"
            switch mode {
            case .iconOnly:
                self.title = ""
            case .healthPercent:
                self.title = "\(m.healthScorePercent)%"
            case .temperature:
                self.title = tempStr
            case .combined:
                self.title = "\(m.healthScorePercent)% · \(tempStr)"
            }
        } else {
            self.title = "--%"
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(status.color)
                .font(.system(size: 13, weight: .medium))

            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SSD Health Status: \(status.rawValue), \(title)")
    }
}

#Preview("Combined Mode") {
    HStack(spacing: 20) {
        MenuBarStatusView(status: .good, title: "98% · 41°C")
        MenuBarStatusView(status: .warning, title: "78% · 58°C")
        MenuBarStatusView(status: .critical, title: "8% · 68°C")
    }
    .padding()
}

#Preview("Icon Only Mode") {
    HStack(spacing: 20) {
        MenuBarStatusView(status: .good, title: "")
        MenuBarStatusView(status: .warning, title: "")
        MenuBarStatusView(status: .critical, title: "")
    }
    .padding()
}
