import AppKit
import Foundation

/// Export formats offered by the dashboard toolbar and the settings tab.
public enum ExportKind: Sendable {
    case json
    case csv
    case textReport
}

/// Generates an export from `AppState` and asks the user where to save it.
@MainActor
public enum ExportPanel {
    /// Returns a status message, or `nil` when the user cancelled the save panel.
    @discardableResult
    public static func run(_ kind: ExportKind, appState: AppState) -> (message: String, isError: Bool)? {
        let content: String
        let defaultName: String
        do {
            switch kind {
            case .json:
                content = try appState.exportJSON()
                defaultName = "SSDHealth_Export_\(dateStamp()).json"
            case .csv:
                content = try appState.exportCSV()
                defaultName = "SSDHealth_History_\(dateStamp()).csv"
            case .textReport:
                content = appState.exportTextReport()
                defaultName = "SSDHealth_DiagnosticReport_\(dateStamp()).txt"
            }
        } catch {
            return ("Export failed: \(error.localizedDescription)", true)
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ("Successfully exported to \(url.lastPathComponent)", false)
        } catch {
            return ("Save error: \(error.localizedDescription)", true)
        }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
