import SwiftUI
import AppKit
import SSDHealthCore
import SSDHealthService

/// Preferences and diagnostic export control panel.
public struct SettingsView: View {
    @Bindable public var appState: AppState
    @State private var showPurgeConfirmation: Bool = false
    @State private var exportStatusMessage: String?
    @State private var customTBWString: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Menu Bar & Monitoring Display
                displaySettingsSection

                Divider()

                // Section 2: Alert Thresholds
                thresholdSettingsSection

                Divider()

                // Section 3: Storage Driver & Simulation
                driverSettingsSection

                Divider()

                // Section 4: Data Export
                exportSection

                Divider()

                // Section 5: Maintenance & Data Store
                maintenanceSection
            }
            .padding(20)
        }
        .confirmationDialog(
            "Purge All Historical Data?",
            isPresented: $showPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Purge All Records", role: .destructive) {
                Task {
                    await appState.purgeHistory()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all stored time-series SMART snapshots and reset regression write rate calculations.")
        }
    }

    // MARK: - Section 1: Display & Polling

    private var displaySettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Display & Polling", systemImage: "menubar.rectangle")
                .font(.system(size: 14, weight: .bold))

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Menu Bar Mode:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Picker("", selection: $appState.settings.displayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                GridRow {
                    Text("Temperature Unit:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Picker("", selection: $appState.settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                GridRow {
                    Text("Polling Interval:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Picker("", selection: $appState.settings.pollingIntervalMinutes) {
                        Text("1 Minute").tag(1)
                        Text("5 Minutes").tag(5)
                        Text("15 Minutes").tag(15)
                        Text("30 Minutes").tag(30)
                        Text("1 Hour").tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    .onChange(of: appState.settings.pollingIntervalMinutes) { _, newValue in
                        appState.updatePollingInterval(Double(newValue) * 60.0)
                    }
                }
            }
        }
    }

    // MARK: - Section 2: Alert Thresholds

    private var thresholdSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Alert Notification Thresholds", systemImage: "bell.badge")
                .font(.system(size: 14, weight: .bold))

            Toggle("Enable macOS System Notifications", isOn: $appState.settings.showNotifications)
                .font(.system(size: 12, weight: .medium))

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text("Thermal Warning:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: $appState.settings.thermalWarningThresholdCelsius, in: 40...75, step: 1)
                        Text("\(Int(appState.settings.thermalWarningThresholdCelsius)) °C")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .frame(width: 260)
                }

                GridRow {
                    Text("Thermal Critical:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: $appState.settings.thermalCriticalThresholdCelsius, in: 55...90, step: 1)
                        Text("\(Int(appState.settings.thermalCriticalThresholdCelsius)) °C")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .frame(width: 260)
                }

                GridRow {
                    Text("Wear Warning:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(appState.settings.wearWarningThresholdPercent) },
                                set: { appState.settings.wearWarningThresholdPercent = Int($0) }
                            ),
                            in: 50...95,
                            step: 5
                        )
                        Text("\(appState.settings.wearWarningThresholdPercent)%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .frame(width: 260)
                }

                GridRow {
                    Text("Spare Warning:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(appState.settings.spareWarningThresholdPercent) },
                                set: { appState.settings.spareWarningThresholdPercent = Int($0) }
                            ),
                            in: 5...25,
                            step: 1
                        )
                        Text("\(appState.settings.spareWarningThresholdPercent)%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .frame(width: 260)
                }
            }
        }
    }

    // MARK: - Section 3: Driver & Mock Simulation

    private var driverSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Driver & Telemetry Source", systemImage: "cpu")
                .font(.system(size: 14, weight: .bold))

            Toggle("Use Simulated Mock Data Provider (for Previews/Testing)", isOn: Binding(
                get: { appState.settings.useMockReader },
                set: { appState.toggleMockReader($0) }
            ))
            .font(.system(size: 12, weight: .medium))

            if appState.settings.useMockReader {
                HStack(spacing: 12) {
                    Text("Mock Preset:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.settings.mockPreset },
                        set: { appState.setMockPreset($0) }
                    )) {
                        Text("Healthy Apple Silicon").tag(MockSSDStorageReader.Preset.healthy)
                        Text("Warning (High Wear)").tag(MockSSDStorageReader.Preset.warning)
                        Text("Overheating (76.5°C)").tag(MockSSDStorageReader.Preset.overheating)
                        Text("Critical Wear (96%)").tag(MockSSDStorageReader.Preset.criticalWear)
                        Text("Degraded Spare (5%)").tag(MockSSDStorageReader.Preset.degradedSpare)
                        Text("Permission Denied Error").tag(MockSSDStorageReader.Preset.permissionDenied)
                        Text("Device Not Found Error").tag(MockSSDStorageReader.Preset.deviceNotFound)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 240)
                }
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - Section 4: Data Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Diagnostic & Telemetry Export", systemImage: "square.and.arrow.up")
                .font(.system(size: 14, weight: .bold))

            Text("Export collected NVMe SMART parameters, time-series measurements, and lifespan regression analysis.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button(action: exportJSONAction) {
                    Label("Export JSON", systemImage: "curlybraces")
                }
                .buttonStyle(.bordered)

                Button(action: exportCSVAction) {
                    Label("Export CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)

                Button(action: exportTextReportAction) {
                    Label("Export Diagnostic Report", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
            }

            if let msg = exportStatusMessage {
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Section 5: Maintenance

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Store Maintenance", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 14, weight: .bold))

            HStack {
                Text("Stored Snapshot Records: \(appState.history.count)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Purge History...", role: .destructive) {
                    showPurgeConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Reset Defaults") {
                    appState.settings.resetToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Export File Actions

    private func exportJSONAction() {
        do {
            let json = try appState.exportJSON()
            saveToFile(content: json, defaultName: "SSDHealth_Export_\(dateStamp()).json")
        } catch {
            exportStatusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportCSVAction() {
        do {
            let csv = try appState.exportCSV()
            saveToFile(content: csv, defaultName: "SSDHealth_History_\(dateStamp()).csv")
        } catch {
            exportStatusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportTextReportAction() {
        let report = appState.exportTextReport()
        saveToFile(content: report, defaultName: "SSDHealth_DiagnosticReport_\(dateStamp()).txt")
    }

    private func saveToFile(content: String, defaultName: String) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                exportStatusMessage = "Successfully exported to \(url.lastPathComponent)"
            } catch {
                exportStatusMessage = "Save error: \(error.localizedDescription)"
            }
        }
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

#Preview("Settings View") {
    let mock = MockSSDStorageReader(preset: .healthy)
    let state = AppState(storageReader: mock)
    SettingsView(appState: state)
        .frame(width: 700, height: 650)
}
