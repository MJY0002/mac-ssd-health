import SwiftUI
import SSDHealthCore
import SSDHealthService

// MARK: - Parameter Status Enum

public enum ParameterStatus: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
    case info = "Info"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .all: return .primary
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .info: return .blue
        }
    }

    public var iconName: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }
}

// MARK: - SMART Parameter Row Model

public struct SMARTParameterRow: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let rawHex: String
    public let rawValueString: String
    public let formattedValue: String
    public let status: ParameterStatus

    public init(
        id: Int,
        name: String,
        rawHex: String,
        rawValueString: String,
        formattedValue: String,
        status: ParameterStatus
    ) {
        self.id = id
        self.name = name
        self.rawHex = rawHex
        self.rawValueString = rawValueString
        self.formattedValue = formattedValue
        self.status = status
    }
}

// MARK: - SMART Table View

public struct SMARTTableView: View {
    @Bindable public var appState: AppState
    @State private var searchText: String = ""
    @State private var selectedFilter: ParameterStatus = .all
    @State private var selectedRowID: Int?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var allRows: [SMARTParameterRow] {
        // No raw log means SMART is unreachable; never show synthesized values as hardware data
        guard let log = appState.rawSmartLog else {
            return []
        }
        return buildRows(from: log)
    }

    public var filteredRows: [SMARTParameterRow] {
        allRows.filter { row in
            let matchesFilter: Bool = {
                if selectedFilter == .all { return true }
                return row.status == selectedFilter
            }()

            let matchesSearch: Bool = {
                if searchText.isEmpty { return true }
                let q = searchText.lowercased()
                return row.name.lowercased().contains(q) ||
                       row.rawHex.lowercased().contains(q) ||
                       row.formattedValue.lowercased().contains(q) ||
                       row.rawValueString.lowercased().contains(q)
            }()

            return matchesFilter && matchesSearch
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search & Filter Bar
            filterToolbar
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Table Content
            if filteredRows.isEmpty {
                emptyPlaceholder
            } else {
                tableContent
            }
        }
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            // Search Input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search SMART parameters...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Spacer()

            // Filter Picker
            Picker("Status Filter", selection: $selectedFilter) {
                ForEach(ParameterStatus.allCases) { filter in
                    Label(filter.rawValue, systemImage: filter.iconName)
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
    }

    // MARK: - Table Content

    private var tableContent: some View {
        Table(filteredRows, selection: $selectedRowID) {
            TableColumn("Parameter Name") { row in
                HStack(spacing: 8) {
                    Image(systemName: row.status.iconName)
                        .foregroundColor(row.status.color)
                        .font(.system(size: 12))

                    Text(row.name)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .width(min: 220, ideal: 260)

            TableColumn("Raw Value (Hex)") { row in
                Text(row.rawHex)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Raw Value (Dec)") { row in
                Text(row.rawValueString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Formatted Value") { row in
                Text(row.formattedValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .width(min: 180, ideal: 220)

            TableColumn("Status") { row in
                statusPill(status: row.status)
            }
            .width(min: 90, ideal: 100)
        }
    }

    private func statusPill(status: ParameterStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(appState.rawSmartLog == nil ? "SMART Log Unavailable" : "No SMART Parameters Found")
                .font(.system(size: 14, weight: .semibold))
            Text(appState.rawSmartLog == nil
                 ? "The NVMe SMART log could not be read from the drive."
                 : "Try changing search keywords or resetting the status filter.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Row Builder (19+ Parameters)

    public func buildRows(from log: NVMESmartLog) -> [SMARTParameterRow] {
        var rows: [SMARTParameterRow] = []
        let warnC = appState.settings.thermalWarningThresholdCelsius
        let critC = appState.settings.thermalCriticalThresholdCelsius
        let wearWarn = appState.settings.wearWarningThresholdPercent

        // 1. Critical Warning
        rows.append(SMARTParameterRow(
            id: 1,
            name: "Critical Warning",
            rawHex: String(format: "0x%02X", log.criticalWarning.rawValue),
            rawValueString: "\(log.criticalWarning.rawValue)",
            formattedValue: log.criticalWarning.isClean ? "0 (No Flags Set)" : log.criticalWarning.activeWarnings.joined(separator: ", "),
            status: log.criticalWarning.isClean ? .normal : .critical
        ))

        // 2. Composite Temperature
        rows.append(SMARTParameterRow(
            id: 2,
            name: "Composite Temperature",
            rawHex: String(format: "0x%04X", log.compositeTemperatureKelvin),
            rawValueString: "\(log.compositeTemperatureKelvin) K",
            formattedValue: String(format: "%.1f °C (%.1f °F)", log.temperatureCelsius, log.temperatureFahrenheit),
            status: log.temperatureCelsius >= critC ? .critical : (log.temperatureCelsius >= warnC ? .warning : .normal)
        ))

        // 3. Available Spare
        rows.append(SMARTParameterRow(
            id: 3,
            name: "Available Spare",
            rawHex: String(format: "0x%02X", log.availableSparePercent),
            rawValueString: "\(log.availableSparePercent)%",
            formattedValue: "\(log.availableSparePercent)% (Thresh: \(log.availableSpareThresholdPercent)%)",
            status: log.availableSparePercent < log.availableSpareThresholdPercent ? .critical : .normal
        ))

        // 4. Available Spare Threshold
        rows.append(SMARTParameterRow(
            id: 4,
            name: "Available Spare Threshold",
            rawHex: String(format: "0x%02X", log.availableSpareThresholdPercent),
            rawValueString: "\(log.availableSpareThresholdPercent)%",
            formattedValue: "\(log.availableSpareThresholdPercent)%",
            status: .normal
        ))

        // 5. Percentage Used
        rows.append(SMARTParameterRow(
            id: 5,
            name: "Percentage Used",
            rawHex: String(format: "0x%02X", log.percentageUsed),
            rawValueString: "\(log.percentageUsed)%",
            formattedValue: "\(log.percentageUsed)% Used (\(log.healthScorePercent)% Health)",
            status: log.percentageUsed >= 90 ? .critical : (Int(log.percentageUsed) >= wearWarn ? .warning : .normal)
        ))

        // 6. Data Units Read
        rows.append(SMARTParameterRow(
            id: 6,
            name: "Data Units Read",
            rawHex: String(format: "0x%016llX%016llX", log.dataUnitsRead.high, log.dataUnitsRead.low),
            rawValueString: "\(log.dataUnitsRead.low)",
            formattedValue: String(format: "%.2f TBR", log.totalTerabytesRead),
            status: .info
        ))

        // 7. Data Units Written
        rows.append(SMARTParameterRow(
            id: 7,
            name: "Data Units Written",
            rawHex: String(format: "0x%016llX%016llX", log.dataUnitsWritten.high, log.dataUnitsWritten.low),
            rawValueString: "\(log.dataUnitsWritten.low)",
            formattedValue: String(format: "%.2f TBW", log.totalTerabytesWritten),
            status: .info
        ))

        // 8. Host Read Commands
        rows.append(SMARTParameterRow(
            id: 8,
            name: "Host Read Commands",
            rawHex: String(format: "0x%016llX%016llX", log.hostReadCommands.high, log.hostReadCommands.low),
            rawValueString: "\(log.hostReadCommands.low)",
            formattedValue: "\(log.hostReadCommands.low) commands",
            status: .info
        ))

        // 9. Host Write Commands
        rows.append(SMARTParameterRow(
            id: 9,
            name: "Host Write Commands",
            rawHex: String(format: "0x%016llX%016llX", log.hostWriteCommands.high, log.hostWriteCommands.low),
            rawValueString: "\(log.hostWriteCommands.low)",
            formattedValue: "\(log.hostWriteCommands.low) commands",
            status: .info
        ))

        // 10. Controller Busy Time
        rows.append(SMARTParameterRow(
            id: 10,
            name: "Controller Busy Time",
            rawHex: String(format: "0x%016llX%016llX", log.controllerBusyTimeMinutes.high, log.controllerBusyTimeMinutes.low),
            rawValueString: "\(log.controllerBusyTimeMinutes.low) min",
            formattedValue: String(format: "%.1f Hours", Double(log.controllerBusyTimeMinutes.low) / 60.0),
            status: .info
        ))

        // 11. Power Cycles
        rows.append(SMARTParameterRow(
            id: 11,
            name: "Power Cycles",
            rawHex: String(format: "0x%016llX%016llX", log.powerCycles.high, log.powerCycles.low),
            rawValueString: "\(log.powerCycles.low)",
            formattedValue: "\(log.powerCycles.low) cycles",
            status: .info
        ))

        // 12. Power-On Hours
        rows.append(SMARTParameterRow(
            id: 12,
            name: "Power-On Hours",
            rawHex: String(format: "0x%016llX%016llX", log.powerOnHours.high, log.powerOnHours.low),
            rawValueString: "\(log.powerOnHours.low) hrs",
            formattedValue: "\(log.powerOnHours.low) Hours",
            status: .info
        ))

        // 13. Unsafe Shutdowns
        rows.append(SMARTParameterRow(
            id: 13,
            name: "Unsafe Shutdowns",
            rawHex: String(format: "0x%016llX%016llX", log.unsafeShutdowns.high, log.unsafeShutdowns.low),
            rawValueString: "\(log.unsafeShutdowns.low)",
            formattedValue: "\(log.unsafeShutdowns.low) shutdowns",
            status: log.unsafeShutdowns.low > 50 ? .warning : .normal
        ))

        // 14. Media and Data Integrity Errors
        rows.append(SMARTParameterRow(
            id: 14,
            name: "Media and Data Integrity Errors",
            rawHex: String(format: "0x%016llX%016llX", log.mediaErrors.high, log.mediaErrors.low),
            rawValueString: "\(log.mediaErrors.low)",
            formattedValue: "\(log.mediaErrors.low) Errors",
            status: log.mediaErrors.low > 0 ? .critical : .normal
        ))

        // 15. Number of Error Information Log Entries
        rows.append(SMARTParameterRow(
            id: 15,
            name: "Number of Error Information Log Entries",
            rawHex: String(format: "0x%016llX%016llX", log.numErrorInfoLogEntries.high, log.numErrorInfoLogEntries.low),
            rawValueString: "\(log.numErrorInfoLogEntries.low)",
            formattedValue: "\(log.numErrorInfoLogEntries.low) Entries",
            status: log.numErrorInfoLogEntries.low > 0 ? .warning : .normal
        ))

        // 16. Warning Composite Temperature Time
        rows.append(SMARTParameterRow(
            id: 16,
            name: "Warning Composite Temperature Time",
            rawHex: String(format: "0x%08X", log.warningCompositeTempTimeMinutes),
            rawValueString: "\(log.warningCompositeTempTimeMinutes) min",
            formattedValue: "\(log.warningCompositeTempTimeMinutes) Minutes",
            status: log.warningCompositeTempTimeMinutes > 0 ? .warning : .normal
        ))

        // 17. Critical Composite Temperature Time
        rows.append(SMARTParameterRow(
            id: 17,
            name: "Critical Composite Temperature Time",
            rawHex: String(format: "0x%08X", log.criticalCompositeTempTimeMinutes),
            rawValueString: "\(log.criticalCompositeTempTimeMinutes) min",
            formattedValue: "\(log.criticalCompositeTempTimeMinutes) Minutes",
            status: log.criticalCompositeTempTimeMinutes > 0 ? .critical : .normal
        ))

        // 18..25. Temperature Sensors 1..8
        for i in 0..<min(8, log.temperatureSensorsKelvin.count) {
            let sK = log.temperatureSensorsKelvin[i]
            if sK > 0 {
                let sC = Double(sK) - 273.15
                rows.append(SMARTParameterRow(
                    id: 18 + i,
                    name: "Temperature Sensor \(i + 1)",
                    rawHex: String(format: "0x%04X", sK),
                    rawValueString: "\(sK) K",
                    formattedValue: String(format: "%.1f °C", sC),
                    status: sC >= critC ? .critical : (sC >= warnC ? .warning : .normal)
                ))
            }
        }

        return rows
    }
}

#Preview("SMART Table View") {
    let mock = MockSSDStorageReader(preset: .healthy)
    let state = AppState(storageReader: mock)
    SMARTTableView(appState: state)
        .onAppear {
            state.loadInitialData()
        }
        .frame(width: 800, height: 500)
}
