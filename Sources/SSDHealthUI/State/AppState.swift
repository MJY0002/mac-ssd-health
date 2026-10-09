import Foundation
import SwiftUI
import Observation
import SSDHealthCore
import SSDHealthService

// MARK: - Dashboard Tab Enum

public enum DashboardTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case smartTable = "SMART Table"
    case charts = "Charts & History"
    case forecast = "Forecast"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.bottom.50percent"
        case .smartTable: return "tablecells"
        case .charts: return "chart.xyaxis.line"
        case .forecast: return "hourglass.bottomhalf.filled"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Main Application State Controller

@Observable
@MainActor
public final class AppState: @unchecked Sendable {
    // MARK: - Dependencies
    public var settings: AppSettings
    public var storageReader: any SSDStorageReading
    public let mockReader: MockSSDStorageReader
    public let liveReader: IOKitStorageReader
    public let forecastEngine: any ForecastEngineProtocol
    public let persistence: any HistoryPersistenceProtocol
    public let notificationService: NotificationService
    public let diagnosticExporter: any DiagnosticExporting

    // MARK: - Telemetry & Domain State
    public var currentMetrics: SSDHealthMetrics?
    public var rawSmartLog: NVMESmartLog?
    public var history: [SSDHistorySnapshot] = []
    public var forecast: SSDForecastResult?

    public var isLoading: Bool = false
    public var isRefreshing: Bool = false
    public var errorMessage: String?
    public var lastUpdated: Date?
    public var selectedTab: DashboardTab = .overview

    /// Callback invoked when telemetry data or metrics are updated.
    public var onStateChange: (@MainActor () -> Void)?

    // Polling State
    private var pollingTask: Task<Void, Never>?
    private var isPollingActive: Bool = false
    private var inFlightFetch: Task<Void, Never>?

    // MARK: - Initializer

    public init(
        storageReader: (any SSDStorageReading)? = nil,
        mockReader: MockSSDStorageReader = MockSSDStorageReader(),
        liveReader: IOKitStorageReader = IOKitStorageReader(),
        forecastEngine: any ForecastEngineProtocol = ForecastEngine(),
        persistence: any HistoryPersistenceProtocol = HistoryPersistenceActor(),
        notificationService: NotificationService = NotificationService.shared,
        diagnosticExporter: any DiagnosticExporting = DiagnosticExporter(),
        settings: AppSettings? = nil
    ) {
        let resolvedSettings = settings ?? AppSettings.shared
        self.mockReader = mockReader
        self.liveReader = liveReader
        self.forecastEngine = forecastEngine
        self.persistence = persistence
        self.notificationService = notificationService
        self.diagnosticExporter = diagnosticExporter
        self.settings = resolvedSettings

        if let explicit = storageReader {
            self.storageReader = explicit
        } else if resolvedSettings.useMockReader {
            self.storageReader = mockReader
        } else {
            self.storageReader = liveReader
        }
    }

    // MARK: - Lifecycle & Data Loading

    public func start() {
        guard !isPollingActive else { return }
        isPollingActive = true
        loadInitialData()
        startPollingTimer()
    }

    public func stop() {
        isPollingActive = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func loadInitialData() {
        Task { [weak self] in
            guard let self = self else { return }
            self.isLoading = true
            self.errorMessage = nil
            await self.fetchTelemetryAndSync(recordSnapshot: true)
            self.isLoading = false
        }
    }

    public func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        self.errorMessage = nil
        await fetchTelemetryAndSync(recordSnapshot: true)
        isRefreshing = false
    }

    /// Demo data and registry fallback placeholders must never reach the persisted history
    /// or the persisted alert state, otherwise they corrupt forecasts and suppress real alerts.
    private func isTrustedTelemetry(_ metrics: SSDHealthMetrics) -> Bool {
        !settings.useMockReader && !metrics.isFallbackData
    }

    /// Polling, initial load and manual refresh share this path. Runs are serialized (not dropped),
    /// so two callers never interleave reads, history writes and alert evaluation.
    private func fetchTelemetryAndSync(recordSnapshot: Bool) async {
        let previous = inFlightFetch
        let task = Task {
            await previous?.value
            await self.performFetch(recordSnapshot: recordSnapshot)
        }
        inFlightFetch = task
        await task.value
    }

    private func performFetch(recordSnapshot: Bool) async {
        do {
            // 1. Read Health Metrics
            let metrics = try await storageReader.readHealthMetrics()
            self.currentMetrics = metrics
            let trusted = isTrustedTelemetry(metrics)

            // 2. Read Raw SMART Log (nil when unavailable; never show fabricated raw data)
            if metrics.isFallbackData {
                self.rawSmartLog = nil
            } else {
                self.rawSmartLog = try? await storageReader.readRawSmartLog()
            }

            // 3. Record snapshot to persistence actor
            if recordSnapshot && trusted {
                let snapshot = SSDHistorySnapshot(from: metrics)
                try? await persistence.record(snapshot: snapshot)
            }

            // 4. Load synced history
            let loadedHistory = (try? await persistence.loadHistory()) ?? []
            self.history = loadedHistory

            // 5. Calculate forecast (placeholder fallback values cannot be extrapolated)
            if metrics.isFallbackData {
                self.forecast = nil
            } else {
                self.forecast = forecastEngine.calculateForecast(
                    current: metrics,
                    history: settings.useMockReader ? [] : loadedHistory,
                    ratedTBW: settings.ratedTBWOverride
                )
            }

            // 6. Evaluate and dispatch notifications if enabled
            if settings.showNotifications && trusted {
                await notificationService.evaluateAndDispatch(
                    metrics: metrics,
                    tempWarnThreshold: settings.thermalWarningThresholdCelsius,
                    tempCritThreshold: settings.thermalCriticalThresholdCelsius,
                    wearWarnThreshold: settings.wearWarningThresholdPercent,
                    spareWarnThreshold: settings.spareWarningThresholdPercent,
                    now: Date()
                )
            }

            self.lastUpdated = Date()
            self.errorMessage = nil
            self.onStateChange?()
        } catch {
            self.errorMessage = error.localizedDescription
            self.onStateChange?()
        }
    }

    // MARK: - Polling Management

    public func startPollingTimer() {
        pollingTask?.cancel()
        let interval = max(5.0, settings.pollingIntervalSeconds)

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000.0))
                guard !Task.isCancelled, let self = self else { break }
                await self.fetchTelemetryAndSync(recordSnapshot: true)
            }
        }
    }

    public func updatePollingInterval(_ intervalSeconds: TimeInterval) {
        settings.pollingIntervalSeconds = intervalSeconds
        startPollingTimer()
    }

    // MARK: - Mock / Live Reader Switching

    public func toggleMockReader(_ enabled: Bool) {
        settings.useMockReader = enabled
        if enabled {
            mockReader.setPreset(settings.mockPreset)
            self.storageReader = mockReader
        } else {
            self.storageReader = liveReader
        }
        Task {
            await refreshNow()
        }
    }

    public func setMockPreset(_ preset: MockSSDStorageReader.Preset) {
        settings.mockPreset = preset
        mockReader.setPreset(preset)
        if settings.useMockReader {
            Task {
                await refreshNow()
            }
        }
    }

    /// Recomputes the forecast from the current reading and loaded history without polling hardware.
    public func recalculateForecast() {
        guard let metrics = currentMetrics, !metrics.isFallbackData else { return }
        self.forecast = forecastEngine.calculateForecast(
            current: metrics,
            history: settings.useMockReader ? [] : history,
            ratedTBW: settings.ratedTBWOverride
        )
        self.onStateChange?()
    }

    /// Resets settings and re-applies the side effects a plain settings reset would skip:
    /// switching back to the live reader, restarting the poll timer, recomputing the forecast.
    public func resetSettingsToDefaults() {
        let wasMock = settings.useMockReader
        settings.resetToDefaults()
        if wasMock {
            toggleMockReader(false)
        }
        if isPollingActive {
            startPollingTimer()
        }
        recalculateForecast()
    }

    // MARK: - History Management

    public func purgeHistory() async {
        try? await persistence.purgeAll()
        notificationService.cooldownManager.reset()
        self.history = []
        if let metrics = currentMetrics {
            self.forecast = forecastEngine.calculateForecast(
                current: metrics,
                history: [],
                ratedTBW: settings.ratedTBWOverride
            )
        }
        self.onStateChange?()
    }

    // MARK: - Export Generation

    public func exportJSON() throws -> String {
        guard let metrics = currentMetrics else {
            throw NSError(domain: "SSDHealth", code: 404, userInfo: [NSLocalizedDescriptionKey: "No active metrics available to export."])
        }
        let effectiveRatedTBW = ForecastEngine.effectiveRatedTBW(for: metrics, override: settings.ratedTBWOverride)
        if let exp = diagnosticExporter as? DiagnosticExporter {
            return try exp.exportJSON(metrics: metrics, history: history, forecast: forecast, ratedTBW: effectiveRatedTBW, now: Date())
        }
        return try diagnosticExporter.exportJSON(metrics: metrics, history: history, forecast: forecast)
    }

    public func exportCSV() throws -> String {
        try diagnosticExporter.exportCSV(history: history)
    }

    public func exportTextReport() -> String {
        guard let metrics = currentMetrics else {
            return "No SSD metrics available."
        }
        let effectiveRatedTBW = ForecastEngine.effectiveRatedTBW(for: metrics, override: settings.ratedTBWOverride)
        if let exp = diagnosticExporter as? DiagnosticExporter {
            return exp.exportTextReport(metrics: metrics, history: history, forecast: forecast, ratedTBW: effectiveRatedTBW, now: Date())
        }
        return diagnosticExporter.exportTextReport(metrics: metrics, history: history, forecast: forecast)
    }

    // MARK: - Menu Bar Formatting Helpers

    public var menuBarTitle: String {
        guard let m = currentMetrics else { return "--%" }
        // Fallback health and temperature are placeholders, not measurements
        if m.isFallbackData {
            return settings.displayMode == .iconOnly ? "" : "--%"
        }

        let tempStr: String
        if settings.temperatureUnit == .celsius {
            tempStr = "\(Int(round(m.temperatureCelsius)))°C"
        } else {
            let f = m.temperatureCelsius * 1.8 + 32.0
            tempStr = "\(Int(round(f)))°F"
        }

        switch settings.displayMode {
        case .iconOnly:
            return ""
        case .healthPercent:
            return "\(m.healthScorePercent)%"
        case .temperature:
            return tempStr
        case .combined:
            return "\(m.healthScorePercent)% · \(tempStr)"
        }
    }

    public var menuBarStatus: HealthStatus {
        HealthStatus.evaluate(
            metrics: currentMetrics,
            thermalWarningCelsius: settings.thermalWarningThresholdCelsius,
            thermalCriticalCelsius: settings.thermalCriticalThresholdCelsius
        )
    }

    public var menuBarIconName: String {
        menuBarStatus.iconName
    }

    public var isFallbackData: Bool {
        currentMetrics?.isFallbackData ?? false
    }

    public var driveDisplayName: String {
        if let m = currentMetrics, !m.modelName.isEmpty {
            return "\(m.modelName) (\(m.capacityFormatted))"
        }
        return "Apple NVMe SSD"
    }
}
