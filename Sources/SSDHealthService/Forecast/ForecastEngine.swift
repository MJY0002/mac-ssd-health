import Foundation
import SSDHealthCore

/// Protocol defining the contract for SSD lifespan and write rate forecast calculation.
public protocol ForecastEngineProtocol: Sendable {
    /// Calculates write rate trends, projected lifespan, and degradation status.
    func calculateForecast(current: SSDHealthMetrics, history: [SSDHistorySnapshot], ratedTBW: Double?) -> SSDForecastResult
}

/// Authoritative forecasting engine implementing Ordinary Least Squares (OLS) regression,
/// dual-model lifespan extrapolation (Wear Rate & Rated TBW), and 95% confidence intervals.
public final class ForecastEngine: ForecastEngineProtocol, Sendable {

    public init() {}

    /// Calculates write rate trends, projected lifespan, and degradation status against a reference date.
    public func calculateForecast(
        current: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        ratedTBW: Double?,
        referenceDate: Date
    ) -> SSDForecastResult {
        let effectiveRatedTBW = Self.effectiveRatedTBW(for: current, override: ratedTBW)

        let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }

        // 1. Lifetime Write Rate
        let lifetimeGB = current.terabytesWritten * 1_000.0
        let lifetimeHours = max(1.0, Double(current.powerOnHours))
        let lifetimeRateGBPerDay = (lifetimeGB / lifetimeHours) * 24.0

        // 2. Windowed Rates via OLS
        let rate7d = calculateOLSRate(history: sortedHistory, windowDays: 7.0, referenceDate: referenceDate)
        let rate30d = calculateOLSRate(history: sortedHistory, windowDays: 30.0, referenceDate: referenceDate)

        let primaryRateGB: Double
        if let r30 = rate30d {
            primaryRateGB = r30.rateGBPerDay
        } else if let r7 = rate7d {
            primaryRateGB = r7.rateGBPerDay
        } else {
            primaryRateGB = lifetimeRateGBPerDay
        }

        // 3. Lifespan Calculation (Model A vs Model B)
        var daysRemaining: Double = Double.infinity
        var usedModelA = false

        // Model A: Percentage Used Wear Extrapolation
        if sortedHistory.count >= 2, let first = sortedHistory.first, let last = sortedHistory.last {
            let wearDelta = Double(last.wearPercentage - first.wearPercentage)
            let timeDeltaSec = last.timestamp.timeIntervalSince(first.timestamp)
            // percentageUsed is an integer, so a delta of 1 carries up to 100% quantization error.
            // Only trust it once the delta is large enough or spread over a long enough window.
            let isSignificant = (wearDelta >= 2.0 && timeDeltaSec >= 86_400.0) ||
                (wearDelta >= 1.0 && timeDeltaSec >= 30.0 * 86_400.0)
            if isSignificant {
                let dailyWear = (wearDelta / timeDeltaSec) * 86_400.0
                if dailyWear > 0 {
                    daysRemaining = max(0.0, Double(100 - current.wearPercentage)) / dailyWear
                    usedModelA = true
                }
            }
        }

        // Model B: Rated TBW Endurance Extrapolation
        if !usedModelA {
            let remainingTBW = max(0.0, effectiveRatedTBW - current.terabytesWritten)
            let dailyTBWRate = primaryRateGB / 1_000.0
            if dailyTBWRate > 0 {
                daysRemaining = remainingTBW / dailyTBWRate
            } else {
                daysRemaining = Double.infinity
            }
        }

        let yearsRemaining: Double
        let exhaustionDate: Date?
        if daysRemaining.isInfinite || daysRemaining.isNaN {
            daysRemaining = Double.infinity
            yearsRemaining = Double.infinity
            exhaustionDate = nil
        } else {
            yearsRemaining = daysRemaining / 365.25
            if daysRemaining > (100.0 * 365.25) {
                exhaustionDate = nil
            } else {
                exhaustionDate = referenceDate.addingTimeInterval(daysRemaining * 86_400.0)
            }
        }

        // 4. Degradation Status Classification
        let status: DegradationStatus
        let totalSpan = (sortedHistory.last?.timestamp.timeIntervalSince(sortedHistory.first?.timestamp ?? referenceDate)) ?? 0
        // Wear reported by the drive itself is authoritative and must never hide behind "Collecting Data"
        if current.wearPercentage >= 100 || current.terabytesWritten >= effectiveRatedTBW {
            status = .exceededEndurance
        } else if current.wearPercentage >= 90 {
            status = .criticalWear
        } else if sortedHistory.count < 3 || totalSpan < 86_400.0 {
            status = .insufficientData
        } else if daysRemaining < 90.0 {
            status = .criticalWear
        } else if daysRemaining < (2.0 * 365.25) || primaryRateGB > 200.0 {
            status = .acceleratedWear
        } else if daysRemaining < (5.0 * 365.25) {
            status = .moderateWear
        } else {
            status = .stable
        }

        // 5. 95% Confidence Interval
        let ci: ConfidenceInterval95
        if let r30 = rate30d {
            ci = r30.ci95
        } else if let r7 = rate7d {
            ci = r7.ci95
        } else {
            ci = ConfidenceInterval95(lowerGB: primaryRateGB * 0.9, upperGB: primaryRateGB * 1.1)
        }

        return SSDForecastResult(
            dailyWriteRate7dGB: rate7d?.rateGBPerDay ?? lifetimeRateGBPerDay,
            dailyWriteRate30dGB: rate30d?.rateGBPerDay ?? lifetimeRateGBPerDay,
            dailyWriteRateLifetimeGB: lifetimeRateGBPerDay,
            primaryDailyWriteRateGB: primaryRateGB,
            estimatedDaysRemaining: daysRemaining,
            estimatedYearsRemaining: yearsRemaining,
            estimatedExhaustionDate: exhaustionDate,
            degradationStatus: status,
            confidenceInterval95: ci
        )
    }

    /// Convenience protocol implementation defaulting reference date to current system time.
    public func calculateForecast(
        current: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        ratedTBW: Double?
    ) -> SSDForecastResult {
        calculateForecast(current: current, history: history, ratedTBW: ratedTBW, referenceDate: Date())
    }

    /// Resolves the endurance budget used for TBW extrapolation.
    ///
    /// Priority: user override, then endurance implied by the drive's own wear counter
    /// (`TBW * 100 / percentageUsed`, once wear is high enough to be meaningful), then a
    /// capacity-based guess (0.6 TBW per GB), then 300 TBW.
    public static func effectiveRatedTBW(for metrics: SSDHealthMetrics, override: Double?) -> Double {
        if let userTBW = override, userTBW > 0 {
            return userTBW
        }
        if metrics.wearPercentage >= 3 && metrics.terabytesWritten > 0 {
            return metrics.terabytesWritten * 100.0 / Double(metrics.wearPercentage)
        }
        if metrics.capacityBytes > 0 {
            return (Double(metrics.capacityBytes) / 1_000_000_000.0) * 0.6
        }
        return 300.0
    }

    // MARK: - Private Regression Helpers

    private func calculateOLSRate(
        history: [SSDHistorySnapshot],
        windowDays: Double,
        referenceDate: Date
    ) -> (rateGBPerDay: Double, ci95: ConfidenceInterval95)? {
        let cutoff = referenceDate.addingTimeInterval(-windowDays * 86_400.0)
        let windowSamples = history.filter { $0.timestamp >= cutoff }
        guard windowSamples.count >= 2 else { return nil }

        let n = Double(windowSamples.count)
        guard let firstSample = windowSamples.first else { return nil }
        let t0 = firstSample.timestamp.timeIntervalSince1970
        let points = windowSamples.map { (t: $0.timestamp.timeIntervalSince1970 - t0, w: $0.terabytesWritten * 1_000_000_000_000.0) }

        let sumT = points.reduce(0.0) { $0 + $1.t }
        let sumW = points.reduce(0.0) { $0 + $1.w }
        let meanT = sumT / n
        let meanW = sumW / n

        var num = 0.0
        var den = 0.0
        for p in points {
            let dt = p.t - meanT
            num += dt * (p.w - meanW)
            den += dt * dt
        }

        guard den > 0 else { return nil }
        let beta = num / den // Bytes per second

        // Gracefully clamp negative rate to 0.0
        guard beta >= 0 else {
            return (rateGBPerDay: 0.0, ci95: ConfidenceInterval95(lowerGB: 0.0, upperGB: 0.0))
        }

        let dailyRateGB = (beta * 86_400.0) / 1_000_000_000.0

        if n >= 3 {
            var ssq = 0.0
            for p in points {
                let wHat = meanW + beta * (p.t - meanT)
                ssq += (p.w - wHat) * (p.w - wHat)
            }
            let seBeta = sqrt(ssq / (n - 2.0)) / sqrt(den)
            let seDailyGB = (seBeta * 86_400.0) / 1_000_000_000.0
            let lower = max(0.0, dailyRateGB - 1.96 * seDailyGB)
            let upper = dailyRateGB + 1.96 * seDailyGB
            return (rateGBPerDay: dailyRateGB, ci95: ConfidenceInterval95(lowerGB: lower, upperGB: upper))
        } else {
            // Two-point fallback bounds (+/- 15%)
            let lower = dailyRateGB * 0.85
            let upper = dailyRateGB * 1.15
            return (rateGBPerDay: dailyRateGB, ci95: ConfidenceInterval95(lowerGB: lower, upperGB: upper))
        }
    }
}
