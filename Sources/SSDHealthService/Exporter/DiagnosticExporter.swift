import Foundation
import SSDHealthCore

/// Protocol defining diagnostic export formats for SSD health telemetry.
public protocol DiagnosticExporting: Sendable {
    /// Exports telemetry, hardware info, and projections as a machine-readable JSON string.
    func exportJSON(metrics: SSDHealthMetrics, history: [SSDHistorySnapshot], forecast: SSDForecastResult?) throws -> String

    /// Exports historical telemetry time series as an RFC 4180 compliant CSV string.
    func exportCSV(history: [SSDHistorySnapshot]) throws -> String

    /// Exports a formatted human-readable ASCII diagnostic report.
    func exportTextReport(metrics: SSDHealthMetrics, history: [SSDHistorySnapshot], forecast: SSDForecastResult?) -> String
}

/// Authoritative diagnostic export engine generating JSON dumps, RFC 4180 CSV, and ASCII text reports.
public final class DiagnosticExporter: DiagnosticExporting, Sendable {

    public init() {}

    /// Exports structured telemetry, metadata, forecast, and history as a JSON string.
    public func exportJSON(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?,
        ratedTBW: Double = 300.0,
        now: Date = Date()
    ) throws -> String {
        let isoFormatter = ISO8601DateFormatter()

        var root: [String: Any] = [:]
        root["metadata"] = [
            "exportTimestamp": isoFormatter.string(from: now),
            "appVersion": SystemInfo.appVersion,
            "buildNumber": SystemInfo.buildNumber,
            "macOSVersion": SystemInfo.macOSVersion,
            "hardwareModel": SystemInfo.hardwareModel,
            "architecture": SystemInfo.architecture
        ]

        root["drive"] = [
            "bsdName": metrics.bsdName,
            "productName": metrics.modelName,
            "serialNumber": metrics.serialNumber,
            "revision": metrics.firmwareRevision,
            "capacityBytes": metrics.capacityBytes,
            "capacityFormatted": metrics.capacityFormatted,
            "ratedTBW": ratedTBW
        ]

        root["currentMetrics"] = [
            "healthScore": metrics.healthScorePercent,
            "percentageUsed": metrics.wearPercentage,
            "temperatureCelsius": metrics.temperatureCelsius,
            "terabytesWritten": metrics.terabytesWritten,
            "terabytesRead": metrics.terabytesRead,
            "powerOnHours": metrics.powerOnHours,
            "powerCycles": metrics.powerCycles,
            "unsafeShutdowns": metrics.unsafeShutdowns,
            "availableSparePercent": metrics.availableSparePercent,
            "availableSpareThresholdPercent": metrics.availableSpareThresholdPercent,
            "criticalWarningBitmask": metrics.criticalWarnings.rawValue,
            "mediaErrors": metrics.mediaErrors,
            "errorLogEntries": metrics.errorLogEntries,
            "isFallbackData": metrics.isFallbackData
        ]

        if let f = forecast {
            var fDict: [String: Any] = [
                "dailyWriteRate7dGB": f.dailyWriteRate7dGB,
                "dailyWriteRate30dGB": f.dailyWriteRate30dGB,
                "dailyWriteRateLifetimeGB": f.dailyWriteRateLifetimeGB,
                "estimatedDaysRemaining": f.estimatedDaysRemaining.isInfinite ? -1.0 : f.estimatedDaysRemaining,
                "estimatedYearsRemaining": f.estimatedYearsRemaining.isInfinite ? -1.0 : f.estimatedYearsRemaining,
                "degradationStatus": f.degradationStatus.rawValue,
                "confidenceInterval95": [
                    "lowerBoundDailyGB": f.confidenceInterval95.lowerGB,
                    "upperBoundDailyGB": f.confidenceInterval95.upperGB
                ]
            ]
            if let eDate = f.estimatedExhaustionDate {
                fDict["estimatedExhaustionDate"] = isoFormatter.string(from: eDate)
            }
            root["forecast"] = fDict
        }

        root["historySampleCount"] = history.count
        root["history"] = history.map { s in
            [
                "timestamp": isoFormatter.string(from: s.timestamp),
                "healthScore": s.healthScorePercent,
                "percentageUsed": s.wearPercentage,
                "temperatureCelsius": s.temperatureCelsius,
                "terabytesWritten": s.terabytesWritten,
                "availableSparePercent": s.availableSparePercent,
                "mediaErrors": s.mediaErrors
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "SSDExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode UTF-8 JSON string"])
        }
        return jsonString
    }

    /// Convenience protocol method using default rated TBW.
    public func exportJSON(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?
    ) throws -> String {
        try exportJSON(metrics: metrics, history: history, forecast: forecast, ratedTBW: 300.0, now: Date())
    }

    /// Exports time series history as an RFC 4180 compliant CSV string with CRLF line terminators.
    public func exportCSV(history: [SSDHistorySnapshot]) throws -> String {
        let isoFormatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("Timestamp_ISO8601,Timestamp_Unix,Percentage_Used,Health_Score_Pct,Temperature_C,TBW_Decimal,Available_Spare_Pct,Critical_Warning_Flags,Media_Errors")

        let sorted = history.sorted(by: { $0.timestamp < $1.timestamp })
        for s in sorted {
            let iso = isoFormatter.string(from: s.timestamp)
            let unix = Int(s.timestamp.timeIntervalSince1970)
            let flagsHex = String(format: "0x%02X", s.criticalWarningsRaw)
            let row = "\(iso),\(unix),\(s.wearPercentage),\(s.healthScorePercent),\(String(format: "%.1f", s.temperatureCelsius)),\(String(format: "%.3f", s.terabytesWritten)),\(s.availableSparePercent),\(flagsHex),\(s.mediaErrors)"
            lines.append(row)
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Generates a formatted ASCII diagnostic report suitable for export and diagnostics.
    public func exportTextReport(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?,
        ratedTBW: Double = 300.0,
        now: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var out = ""
        out += "================================================================================\n"
        out += "                    macOS SSD HEALTH & SMART DIAGNOSTIC REPORT\n"
        out += "================================================================================\n"
        out += "Generated: \(formatter.string(from: now)) | App Version: \(SystemInfo.appVersion) (Build \(SystemInfo.buildNumber))\n"
        out += "Host System: \(SystemInfo.hardwareModel) (\(SystemInfo.architecture)) | OS: macOS \(SystemInfo.macOSVersion)\n\n"

        out += "--------------------------------------------------------------------------------\n"
        out += "1. STORAGE DEVICE IDENTIFICATION\n"
        out += "--------------------------------------------------------------------------------\n"
        out += "Device Name:              \(metrics.modelName) (\(metrics.bsdName))\n"
        out += "Serial Number:            \(metrics.serialNumber)\n"
        out += "Firmware Revision:        \(metrics.firmwareRevision)\n"
        out += "Interconnect:             \(metrics.interconnect)\n"
        out += "Capacity:                 \(metrics.capacityFormatted) (\(metrics.capacityBytes) Bytes)\n"
        out += "Rated Endurance:          \(String(format: "%.1f", ratedTBW)) TBW\n\n"

        out += "--------------------------------------------------------------------------------\n"
        out += "2. HEALTH & LIFESPAN SUMMARY\n"
        out += "--------------------------------------------------------------------------------\n"
        out += "Overall Health Score:     \(metrics.healthScorePercent)% (\(metrics.healthScorePercent > 80 ? "Good" : (metrics.healthScorePercent > 20 ? "Warning" : "Critical")))\n"
        out += "Percentage Used:          \(metrics.wearPercentage)%\n"
        out += "Total Bytes Written:      \(metrics.tbwFormatted)\n"
        out += "Total Bytes Read:         \(metrics.tbrFormatted)\n"
        out += "Power-On Time:            \(metrics.powerOnHours) Hours\n"
        out += "Power Cycles:             \(metrics.powerCycles) Cycles\n"
        out += "Unsafe Shutdowns:         \(metrics.unsafeShutdowns)\n"
        out += "Media Integrity Errors:   \(metrics.mediaErrors)\n\n"

        out += "--------------------------------------------------------------------------------\n"
        out += "3. FORECAST & WEAR PROJECTION\n"
        out += "--------------------------------------------------------------------------------\n"
        if let f = forecast {
            out += "Daily Write Rate (7d):    \(String(format: "%.2f", f.dailyWriteRate7dGB)) GB/day\n"
            out += "Daily Write Rate (30d):   \(String(format: "%.2f", f.dailyWriteRate30dGB)) GB/day\n"
            out += "Daily Write Rate (All):   \(String(format: "%.2f", f.dailyWriteRateLifetimeGB)) GB/day\n"
            out += "Degradation Trajectory:   \(f.degradationStatus.rawValue.uppercased())\n"
            out += "Estimated Lifespan:       \(f.estimatedYearsRemaining.isInfinite ? "Infinite" : String(format: "~%.1f Years", f.estimatedYearsRemaining))\n"
            out += "Confidence Interval (95%): \(String(format: "%.2f", f.confidenceInterval95.lowerGB)) GB/day to \(String(format: "%.2f", f.confidenceInterval95.upperGB)) GB/day\n"
        } else {
            out += "Prognosis:                Insufficient historical data\n"
        }
        out += "\n--------------------------------------------------------------------------------\n"
        out += "4. HARDWARE RELIABILITY FLAGS & WARNINGS\n"
        out += "--------------------------------------------------------------------------------\n"
        out += "[\(metrics.availableSparePercent >= metrics.availableSpareThresholdPercent ? "x" : " ")] Available Spare (\(metrics.availableSparePercent)% >= \(metrics.availableSpareThresholdPercent)% threshold)\n"
        out += "[\(metrics.temperatureCelsius < 65.0 ? "x" : " ")] Thermal Status (\(metrics.temperatureFormatted) < 65.0 °C threshold)\n"
        out += "[\(!metrics.criticalWarnings.contains(.reliabilityDegraded) ? "x" : " ")] NVM Subsystem Reliability Intact\n"
        out += "[\(!metrics.criticalWarnings.contains(.readOnly) ? "x" : " ")] Drive Media Writable\n"
        out += "[\(metrics.mediaErrors == 0 ? "x" : " ")] Zero Media Errors\n"
        out += "================================================================================\n"

        return out
    }

    /// Convenience protocol method using default rated TBW.
    public func exportTextReport(
        metrics: SSDHealthMetrics,
        history: [SSDHistorySnapshot],
        forecast: SSDForecastResult?
    ) -> String {
        exportTextReport(metrics: metrics, history: history, forecast: forecast, ratedTBW: 300.0, now: Date())
    }
}

/// Runtime host and bundle information for diagnostic exports.
enum SystemInfo {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Hardware model identifier, e.g. "Mac14,2".
    static var hardwareModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
