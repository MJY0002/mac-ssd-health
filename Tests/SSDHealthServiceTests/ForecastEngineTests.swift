import Foundation
import XCTest
@testable import SSDHealthCore
@testable import SSDHealthService

final class ForecastEngineTests: XCTestCase {

    var engine: ForecastEngine!
    var baseDate: Date = Date(timeIntervalSince1970: 1787832000)

    override func setUp() {
        super.setUp()
        engine = ForecastEngine()
        baseDate = Date(timeIntervalSince1970: 1787832000)
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeMetrics(
        capacityBytes: UInt64 = 512_000_000_000,
        healthScorePercent: Int = 90,
        wearPercentage: Int = 10,
        temperatureCelsius: Double = 38.0,
        terabytesWritten: Double = 10.0,
        powerOnHours: UInt64 = 2400,
        criticalWarnings: CriticalWarningFlags = CriticalWarningFlags(rawValue: 0),
        timestamp: Date? = nil
    ) -> SSDHealthMetrics {
        SSDHealthMetrics(
            bsdName: "disk0",
            modelName: "APPLE SSD AP0512Q",
            serialNumber: "SN-TEST-FORECAST",
            firmwareRevision: "561.100.",
            interconnect: "Apple Fabric",
            capacityBytes: capacityBytes,
            healthScorePercent: healthScorePercent,
            wearPercentage: wearPercentage,
            temperatureCelsius: temperatureCelsius,
            availableSparePercent: 100,
            availableSpareThresholdPercent: 10,
            terabytesWritten: terabytesWritten,
            terabytesRead: terabytesWritten * 1.2,
            powerOnHours: powerOnHours,
            powerCycles: 300,
            unsafeShutdowns: 4,
            mediaErrors: 0,
            errorLogEntries: 0,
            criticalWarnings: criticalWarnings,
            timestamp: timestamp ?? baseDate
        )
    }

    // MARK: - OLS Linear Regression Slope Precision

    func test_OLSLinearRegression_CalculatesExactSlopeOnLinearData() {
        // Generate 14 days of exact 25.0 GB/day writes (0.025 TB/day)
        var history: [SSDHistorySnapshot] = []
        let dailyGB = 25.0
        let dailyTB = dailyGB / 1000.0

        for day in 0..<14 {
            let t = baseDate.addingTimeInterval(Double(day - 13) * 86_400.0)
            let tbw = 10.0 + Double(day) * dailyTB
            history.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: 90,
                wearPercentage: 10,
                temperatureCelsius: 38.0,
                terabytesWritten: tbw,
                availableSparePercent: 100
            ))
        }

        let metrics = makeMetrics(terabytesWritten: 10.0 + 13.0 * dailyTB, powerOnHours: 2400)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.primaryDailyWriteRateGB, 25.0, accuracy: 0.05)
        XCTAssertEqual(forecast.dailyWriteRate7dGB, 25.0, accuracy: 0.05)
        XCTAssertEqual(forecast.dailyWriteRate30dGB, 25.0, accuracy: 0.05)
    }

    func test_WindowedRateFiltering_7DayBurstVs30DaySteady() {
        var history: [SSDHistorySnapshot] = []

        // Past 30 days: 10 GB/day baseline; Past 7 days: 60 GB/day burst
        for day in 0..<30 {
            let t = baseDate.addingTimeInterval(Double(day - 29) * 86_400.0)
            let tbw: Double
            if day < 23 {
                tbw = 10.0 + Double(day) * 0.01 // 10 GB/day
            } else {
                tbw = 10.23 + Double(day - 22) * 0.06 // 60 GB/day
            }
            history.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: 90,
                wearPercentage: 10,
                temperatureCelsius: 38.0,
                terabytesWritten: tbw,
                availableSparePercent: 100
            ))
        }

        let metrics = makeMetrics(terabytesWritten: 10.65, powerOnHours: 3000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.dailyWriteRate7dGB, 60.0, accuracy: 2.0)
        XCTAssertLessThan(forecast.dailyWriteRate30dGB, forecast.dailyWriteRate7dGB)
        XCTAssertGreaterThan(forecast.dailyWriteRate30dGB, 15.0)
    }

    func test_TwoPointDeltaFallback_WhenNIsTwo() {
        let t1 = baseDate.addingTimeInterval(-86_400.0 * 2)
        let t2 = baseDate

        let history = [
            SSDHistorySnapshot(timestamp: t1, healthScorePercent: 99, wearPercentage: 1, temperatureCelsius: 35.0, terabytesWritten: 5.000, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t2, healthScorePercent: 99, wearPercentage: 1, temperatureCelsius: 35.0, terabytesWritten: 5.080, availableSparePercent: 100) // 80 GB over 2 days = 40 GB/day
        ]

        let metrics = makeMetrics(terabytesWritten: 5.080, powerOnHours: 500)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.primaryDailyWriteRateGB, 40.0, accuracy: 0.1)
        XCTAssertEqual(forecast.confidenceInterval95.lowerGB, 40.0 * 0.85, accuracy: 0.1)
        XCTAssertEqual(forecast.confidenceInterval95.upperGB, 40.0 * 1.15, accuracy: 0.1)
    }

    func test_LifetimeAverageRateCalculation() {
        // 24.0 TB written over 4000 hours
        // Rate = (24,000 GB / 4000 hours) * 24 hours/day = 144.0 GB/day
        let metrics = makeMetrics(terabytesWritten: 24.0, powerOnHours: 4000)
        let forecast = engine.calculateForecast(current: metrics, history: [], ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.dailyWriteRateLifetimeGB, 144.0, accuracy: 0.01)
        XCTAssertEqual(forecast.primaryDailyWriteRateGB, 144.0, accuracy: 0.01)
        XCTAssertEqual(forecast.degradationStatus, .insufficientData)
        XCTAssertEqual(forecast.lifespanFormatted, "Estimating...")
    }

    // MARK: - Dual Lifespan Extrapolation Models (Model A vs Model B)

    func test_ModelA_WearRateExtrapolation_WhenWearIncreases() {
        // Wear changed from 10% to 15% over 100 days
        let t1 = baseDate.addingTimeInterval(-100 * 86_400.0)
        let t2 = baseDate

        let history = [
            SSDHistorySnapshot(timestamp: t1, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 20.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t2, healthScorePercent: 85, wearPercentage: 15, temperatureCelsius: 38.0, terabytesWritten: 35.0, availableSparePercent: 100)
        ]

        let metrics = makeMetrics(wearPercentage: 15, terabytesWritten: 35.0, powerOnHours: 5000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        // Daily wear = (15 - 10) / 100 = 0.05% / day
        // Remaining wear = 100 - 15 = 85%
        // Days remaining = 85 / 0.05 = 1700 days
        XCTAssertEqual(forecast.estimatedDaysRemaining, 1700.0, accuracy: 5.0)
        XCTAssertEqual(forecast.estimatedYearsRemaining, 1700.0 / 365.25, accuracy: 0.1)
        XCTAssertNotNil(forecast.estimatedExhaustionDate)
    }

    func test_ModelA_IgnoresSinglePercentTickOverShortWindow() {
        // 9% -> 10% one hour apart is integer rounding, not 24%/day of wear
        let history = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-2 * 86_400), healthScorePercent: 91, wearPercentage: 9, temperatureCelsius: 38.0, terabytesWritten: 20.00, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-86_400), healthScorePercent: 91, wearPercentage: 9, temperatureCelsius: 38.0, terabytesWritten: 20.02, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 20.04, availableSparePercent: 100)
        ]
        let metrics = makeMetrics(wearPercentage: 10, terabytesWritten: 20.04, powerOnHours: 3000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertNotEqual(forecast.degradationStatus, .criticalWear)
        XCTAssertGreaterThan(forecast.estimatedDaysRemaining, 365.0)
    }

    func test_HighWear_IsReportedEvenWithoutHistory() {
        let worn = makeMetrics(wearPercentage: 100, terabytesWritten: 150.0)
        XCTAssertEqual(engine.calculateForecast(current: worn, history: [], ratedTBW: 300.0, referenceDate: baseDate).degradationStatus, .exceededEndurance)

        let nearlyWorn = makeMetrics(wearPercentage: 93, terabytesWritten: 150.0)
        XCTAssertEqual(engine.calculateForecast(current: nearlyWorn, history: [], ratedTBW: 300.0, referenceDate: baseDate).degradationStatus, .criticalWear)
    }

    func test_EffectiveRatedTBW_DerivedFromDriveWearCounter() {
        // 40 TB written at 20% wear implies ~200 TB endurance, regardless of capacity guess
        let metrics = makeMetrics(capacityBytes: 2_000_000_000_000, wearPercentage: 20, terabytesWritten: 40.0)
        XCTAssertEqual(ForecastEngine.effectiveRatedTBW(for: metrics, override: nil), 200.0, accuracy: 0.001)
        XCTAssertEqual(ForecastEngine.effectiveRatedTBW(for: metrics, override: 600.0), 600.0, accuracy: 0.001)

        // Below 3% wear the counter is too coarse; fall back to capacity (0.6 TBW per GB)
        let fresh = makeMetrics(capacityBytes: 2_000_000_000_000, wearPercentage: 1, terabytesWritten: 3.0)
        XCTAssertEqual(ForecastEngine.effectiveRatedTBW(for: fresh, override: nil), 1200.0, accuracy: 0.001)
    }

    func test_ModelB_TBWEnduranceExtrapolation_WhenWearIsUnchanged() {
        var history: [SSDHistorySnapshot] = []
        // 10 days of 20 GB/day writes with unchanged 2% wear
        for day in 0..<10 {
            let t = baseDate.addingTimeInterval(Double(day - 9) * 86_400.0)
            history.append(SSDHistorySnapshot(
                timestamp: t,
                healthScorePercent: 98,
                wearPercentage: 2,
                temperatureCelsius: 35.0,
                terabytesWritten: 10.0 + Double(day) * 0.02,
                availableSparePercent: 100
            ))
        }

        let metrics = makeMetrics(wearPercentage: 2, terabytesWritten: 10.18, powerOnHours: 2000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        // Rated TBW = 300 TB, Current TBW = 10.18 TB -> Remaining TBW = 289.82 TB
        // Daily rate = 20 GB/day = 0.02 TB/day
        // Days remaining = 289.82 / 0.02 = 14491 days (~39.67 years)
        XCTAssertEqual(forecast.estimatedDaysRemaining, 14491.0, accuracy: 20.0)
        XCTAssertEqual(forecast.estimatedYearsRemaining, 14491.0 / 365.25, accuracy: 0.1)
    }

    func test_AutomaticRatedTBWCalculation_FromDriveCapacity() {
        // 1 TB drive (1,000,000,000,000 bytes) -> 0.6 * 1000 = 600 TBW
        let metrics = makeMetrics(capacityBytes: 1_000_000_000_000, terabytesWritten: 60.0, powerOnHours: 1000)
        let forecast = engine.calculateForecast(current: metrics, history: [], ratedTBW: nil, referenceDate: baseDate)

        // Remaining = 600 - 60 = 540 TB
        // Daily rate = (60,000 / 1000) * 24 = 1440 GB/day = 1.44 TB/day
        // Days remaining = 540 / 1.44 = 375 days
        XCTAssertEqual(forecast.estimatedDaysRemaining, 375.0, accuracy: 5.0)
    }

    // MARK: - Confidence Intervals & Error Calculation

    func test_ConfidenceInterval95_PrecisionWithNoisyData() {
        var history: [SSDHistorySnapshot] = []
        let meanDailyGB = 30.0
        let noiseOffsets = [0.0, 2.0, -1.5, 3.0, -2.5, 1.0, -0.5, 2.5, -1.0, 0.5]

        for (day, noise) in noiseOffsets.enumerated() {
            let t = baseDate.addingTimeInterval(Double(day - 9) * 86_400.0)
            let tbw = 10.0 + (Double(day) * meanDailyGB + noise) / 1000.0
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 90, wearPercentage: 10,
                temperatureCelsius: 38.0, terabytesWritten: tbw, availableSparePercent: 100
            ))
        }

        let metrics = makeMetrics(terabytesWritten: 10.3, powerOnHours: 2000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.primaryDailyWriteRateGB, 30.0, accuracy: 1.5)
        XCTAssertLessThan(forecast.confidenceInterval95.lowerGB, forecast.primaryDailyWriteRateGB)
        XCTAssertGreaterThan(forecast.confidenceInterval95.upperGB, forecast.primaryDailyWriteRateGB)
        XCTAssertGreaterThan(forecast.confidenceInterval95.lowerGB, 0.0)
    }

    // MARK: - Edge Cases & Boundary Conditions

    func test_ZeroDailyWriteRate_GracefulInfiniteLifespan() {
        var history: [SSDHistorySnapshot] = []
        for day in 0..<10 {
            let t = baseDate.addingTimeInterval(Double(day - 9) * 86_400.0)
            history.append(SSDHistorySnapshot(
                timestamp: t, healthScorePercent: 99, wearPercentage: 1,
                temperatureCelsius: 30.0, terabytesWritten: 5.000, availableSparePercent: 100 // Flatline 0 writes
            ))
        }

        let metrics = makeMetrics(terabytesWritten: 5.000, powerOnHours: 1000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.primaryDailyWriteRateGB, 0.0, accuracy: 0.001)
        XCTAssertTrue(forecast.estimatedDaysRemaining.isInfinite)
        XCTAssertTrue(forecast.estimatedYearsRemaining.isInfinite)
        XCTAssertNil(forecast.estimatedExhaustionDate)
        XCTAssertEqual(forecast.degradationStatus, .stable)
    }

    func test_NegativeSlopeRejection_GracefullyClampedToZero() {
        // Anomaly: TBW decreases (e.g. clock anomaly or corrupt record)
        let t1 = baseDate.addingTimeInterval(-86_400.0 * 2)
        let t2 = baseDate

        let history = [
            SSDHistorySnapshot(timestamp: t1, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 10.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: t2, healthScorePercent: 90, wearPercentage: 10, temperatureCelsius: 38.0, terabytesWritten: 8.0, availableSparePercent: 100)
        ]

        let metrics = makeMetrics(terabytesWritten: 8.0, powerOnHours: 1000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.primaryDailyWriteRateGB, 0.0, accuracy: 0.001)
    }

    func test_ExhaustedEndurance_SetsZeroDaysAndExceededStatus() {
        let history = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-200_000), healthScorePercent: 0, wearPercentage: 104, temperatureCelsius: 45.0, terabytesWritten: 349.0, availableSparePercent: 80),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-100_000), healthScorePercent: 0, wearPercentage: 105, temperatureCelsius: 45.0, terabytesWritten: 349.5, availableSparePercent: 80),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 0, wearPercentage: 105, temperatureCelsius: 45.0, terabytesWritten: 350.0, availableSparePercent: 80)
        ]
        let metrics = makeMetrics(wearPercentage: 105, terabytesWritten: 350.0, powerOnHours: 15000)
        let forecast = engine.calculateForecast(current: metrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)

        XCTAssertEqual(forecast.degradationStatus, .exceededEndurance)
        XCTAssertEqual(forecast.estimatedDaysRemaining, 0.0, accuracy: 0.001)
        XCTAssertEqual(forecast.lifespanFormatted, "Endurance Exceeded")
    }

    func test_DegradationStatusThresholds() {
        let history = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-200_000), healthScorePercent: 10, wearPercentage: 90, temperatureCelsius: 38.0, terabytesWritten: 268.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-100_000), healthScorePercent: 8, wearPercentage: 92, temperatureCelsius: 38.0, terabytesWritten: 269.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 8, wearPercentage: 92, temperatureCelsius: 38.0, terabytesWritten: 270.0, availableSparePercent: 100)
        ]

        // Critical wear (wear >= 90%)
        let critMetrics = makeMetrics(wearPercentage: 92, terabytesWritten: 270.0, powerOnHours: 8000)
        let critForecast = engine.calculateForecast(current: critMetrics, history: history, ratedTBW: 300.0, referenceDate: baseDate)
        XCTAssertEqual(critForecast.degradationStatus, .criticalWear)

        // Accelerated wear (> 200 GB/day or lifespan < 2 years, > 90 days)
        let heavyHistory = [
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-200_000), healthScorePercent: 71, wearPercentage: 29, temperatureCelsius: 38.0, terabytesWritten: 148.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate.addingTimeInterval(-100_000), healthScorePercent: 70, wearPercentage: 30, temperatureCelsius: 38.0, terabytesWritten: 149.0, availableSparePercent: 100),
            SSDHistorySnapshot(timestamp: baseDate, healthScorePercent: 70, wearPercentage: 30, temperatureCelsius: 38.0, terabytesWritten: 150.0, availableSparePercent: 100)
        ]
        let heavyMetrics = makeMetrics(wearPercentage: 30, terabytesWritten: 150.0, powerOnHours: 1000)
        let heavyForecast = engine.calculateForecast(current: heavyMetrics, history: heavyHistory, ratedTBW: 300.0, referenceDate: baseDate)
        XCTAssertEqual(heavyForecast.degradationStatus, .acceleratedWear)
    }

    func test_FormattedHelpers_And_Equality() {
        let f1 = SSDForecastResult(
            dailyWriteRate7dGB: 15.5,
            dailyWriteRate30dGB: 16.0,
            dailyWriteRateLifetimeGB: 14.2,
            primaryDailyWriteRateGB: 16.0,
            estimatedDaysRemaining: 7305.0,
            estimatedYearsRemaining: 20.0,
            estimatedExhaustionDate: baseDate.addingTimeInterval(7305.0 * 86_400.0),
            degradationStatus: .stable,
            confidenceInterval95: (lowerGB: 14.0, upperGB: 18.0)
        )

        let f2 = SSDForecastResult(
            dailyWriteRate7dGB: 15.5,
            dailyWriteRate30dGB: 16.0,
            dailyWriteRateLifetimeGB: 14.2,
            primaryDailyWriteRateGB: 16.0,
            estimatedDaysRemaining: 7305.0,
            estimatedYearsRemaining: 20.0,
            estimatedExhaustionDate: baseDate.addingTimeInterval(7305.0 * 86_400.0),
            degradationStatus: .stable,
            confidenceInterval95: (lowerGB: 14.0, upperGB: 18.0)
        )

        XCTAssertEqual(f1, f2)
        XCTAssertEqual(f1.dailyRateFormatted, "16.00 GB/day")
        XCTAssertEqual(f1.lifespanFormatted, "~20.0 Years")
        XCTAssertFalse(f1.exhaustionDateFormatted.isEmpty)
    }
}
