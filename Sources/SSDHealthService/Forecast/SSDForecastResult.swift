import Foundation

/// Classification of SSD wear trajectory and degradation urgency.
public enum DegradationStatus: String, Codable, Sendable, CaseIterable {
    case insufficientData = "insufficient_data"
    case stable = "stable"
    case moderateWear = "moderate_wear"
    case acceleratedWear = "accelerated_wear"
    case criticalWear = "critical_wear"
    case exceededEndurance = "exceeded_endurance"

    // Convenience aliases
    public static let good: DegradationStatus = .stable
    public static let critical: DegradationStatus = .criticalWear
    public static let estimating: DegradationStatus = .insufficientData

    /// Human-readable title describing the degradation state.
    public var title: String {
        switch self {
        case .insufficientData:
            return "Estimating..."
        case .stable:
            return "Stable"
        case .moderateWear:
            return "Moderate Wear"
        case .acceleratedWear:
            return "Accelerated Wear"
        case .criticalWear:
            return "Critical Wear"
        case .exceededEndurance:
            return "Endurance Exceeded"
        }
    }

    /// Detailed description for UI display and reports.
    public var detailedDescription: String {
        switch self {
        case .insufficientData:
            return "Collecting historical write samples for accurate projection."
        case .stable:
            return "Healthy wear pattern. Projected lifespan exceeds 5 years."
        case .moderateWear:
            return "Normal daily write workload. Lifespan between 2 and 5 years."
        case .acceleratedWear:
            return "High daily write throughput. Estimated lifespan under 2 years."
        case .criticalWear:
            return "Critical wear level or estimated lifespan under 90 days."
        case .exceededEndurance:
            return "Rated TBW endurance limit or 100% wear exceeded."
        }
    }
}

/// 95% Confidence Interval for daily write rate regression.
public struct ConfidenceInterval95: Codable, Sendable, Equatable {
    public let lowerGB: Double
    public let upperGB: Double

    public init(lowerGB: Double, upperGB: Double) {
        self.lowerGB = max(0.0, lowerGB)
        self.upperGB = max(self.lowerGB, upperGB)
    }
}

/// Mathematical prediction of SSD lifespan, daily write rate, and exhaustion timeline.
public struct SSDForecastResult: Codable, Sendable, Equatable {
    /// 7-day moving average daily write rate in Gigabytes/day.
    public let dailyWriteRate7dGB: Double

    /// 30-day moving average daily write rate in Gigabytes/day.
    public let dailyWriteRate30dGB: Double

    /// Lifetime average daily write rate across total power-on hours in Gigabytes/day.
    public let dailyWriteRateLifetimeGB: Double

    /// Primary active daily write rate used for calculations.
    public let primaryDailyWriteRateGB: Double

    /// Estimated days remaining until rated TBW endurance or 100% wear.
    public let estimatedDaysRemaining: Double

    /// Estimated years remaining until rated TBW endurance or 100% wear.
    public let estimatedYearsRemaining: Double

    /// Projected calendar date when rated endurance is reached, or nil if infinite / >100 years.
    public let estimatedExhaustionDate: Date?

    /// Wear degradation and trajectory classification.
    public let degradationStatus: DegradationStatus

    /// 95% confidence interval bounds for daily write rate.
    public let confidenceInterval95: ConfidenceInterval95

    public init(
        dailyWriteRate7dGB: Double,
        dailyWriteRate30dGB: Double,
        dailyWriteRateLifetimeGB: Double,
        primaryDailyWriteRateGB: Double,
        estimatedDaysRemaining: Double,
        estimatedYearsRemaining: Double,
        estimatedExhaustionDate: Date?,
        degradationStatus: DegradationStatus,
        confidenceInterval95: ConfidenceInterval95
    ) {
        self.dailyWriteRate7dGB = dailyWriteRate7dGB
        self.dailyWriteRate30dGB = dailyWriteRate30dGB
        self.dailyWriteRateLifetimeGB = dailyWriteRateLifetimeGB
        self.primaryDailyWriteRateGB = primaryDailyWriteRateGB
        self.estimatedDaysRemaining = estimatedDaysRemaining
        self.estimatedYearsRemaining = estimatedYearsRemaining
        self.estimatedExhaustionDate = estimatedExhaustionDate
        self.degradationStatus = degradationStatus
        self.confidenceInterval95 = confidenceInterval95
    }

    /// Convenience initializer accepting a tuple for confidence interval.
    public init(
        dailyWriteRate7dGB: Double,
        dailyWriteRate30dGB: Double,
        dailyWriteRateLifetimeGB: Double,
        primaryDailyWriteRateGB: Double,
        estimatedDaysRemaining: Double,
        estimatedYearsRemaining: Double,
        estimatedExhaustionDate: Date?,
        degradationStatus: DegradationStatus,
        confidenceInterval95: (lowerGB: Double, upperGB: Double)
    ) {
        self.init(
            dailyWriteRate7dGB: dailyWriteRate7dGB,
            dailyWriteRate30dGB: dailyWriteRate30dGB,
            dailyWriteRateLifetimeGB: dailyWriteRateLifetimeGB,
            primaryDailyWriteRateGB: primaryDailyWriteRateGB,
            estimatedDaysRemaining: estimatedDaysRemaining,
            estimatedYearsRemaining: estimatedYearsRemaining,
            estimatedExhaustionDate: estimatedExhaustionDate,
            degradationStatus: degradationStatus,
            confidenceInterval95: ConfidenceInterval95(lowerGB: confidenceInterval95.lowerGB, upperGB: confidenceInterval95.upperGB)
        )
    }

    // MARK: - Formatted Helpers

    /// Formatted daily write rate string (e.g. "18.45 GB/day").
    public var dailyRateFormatted: String {
        String(format: "%.2f GB/day", primaryDailyWriteRateGB)
    }

    /// Formatted estimated lifespan string (e.g. "~12.4 Years" or "Exhausted").
    public var lifespanFormatted: String {
        if degradationStatus == .exceededEndurance || estimatedDaysRemaining <= 0 {
            return "Endurance Exceeded"
        } else if estimatedDaysRemaining.isInfinite || estimatedYearsRemaining > 100 {
            return "Infinite (> 100 Years)"
        } else if estimatedDaysRemaining < 365.25 {
            return String(format: "%d Days", Int(round(estimatedDaysRemaining)))
        } else {
            return String(format: "~%.1f Years", estimatedYearsRemaining)
        }
    }

    /// Formatted exhaustion date string (e.g. "August 10, 2047").
    public var exhaustionDateFormatted: String {
        guard let date = estimatedExhaustionDate else {
            return "N/A"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Equatable Conformance

    public static func == (lhs: SSDForecastResult, rhs: SSDForecastResult) -> Bool {
        abs(lhs.dailyWriteRate7dGB - rhs.dailyWriteRate7dGB) < 1e-4 &&
        abs(lhs.dailyWriteRate30dGB - rhs.dailyWriteRate30dGB) < 1e-4 &&
        abs(lhs.dailyWriteRateLifetimeGB - rhs.dailyWriteRateLifetimeGB) < 1e-4 &&
        abs(lhs.primaryDailyWriteRateGB - rhs.primaryDailyWriteRateGB) < 1e-4 &&
        abs(lhs.estimatedDaysRemaining - rhs.estimatedDaysRemaining) < 1e-2 &&
        abs(lhs.estimatedYearsRemaining - rhs.estimatedYearsRemaining) < 1e-2 &&
        lhs.degradationStatus == rhs.degradationStatus &&
        lhs.confidenceInterval95 == rhs.confidenceInterval95
    }
}
