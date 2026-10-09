import Foundation
import UserNotifications
import SSDHealthCore

/// Coordinates SSD health rule evaluations, cooldown debouncing, and macOS system notification delivery.
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    public static let shared = NotificationService()

    public static let categoryThermal = "SSD_THERMAL_ALERT"
    public static let categoryCriticalHardware = "SSD_CRITICAL_HARDWARE_ALERT"
    public static let categoryWearMilestone = "SSD_WEAR_MILESTONE"
    public static let categoryMediaError = "SSD_MEDIA_ERROR_ALERT"

    public let cooldownManager: AlertCooldownManager
    private let notificationCenter: UNUserNotificationCenter?

    /// Invoked when the user clicks a notification or one of its actions.
    /// Parameters: action identifier, category identifier.
    public var onNotificationResponse: ((String, String) -> Void)?

    public static var isRunningInsideAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    public static var defaultNotificationCenter: UNUserNotificationCenter? {
        guard isRunningInsideAppBundle else { return nil }
        return UNUserNotificationCenter.current()
    }

    public init(
        cooldownManager: AlertCooldownManager = AlertCooldownManager(userDefaults: .standard),
        notificationCenter: UNUserNotificationCenter? = NotificationService.defaultNotificationCenter
    ) {
        self.cooldownManager = cooldownManager
        self.notificationCenter = notificationCenter
        super.init()
        // Without a delegate, banners are suppressed while the app is active and actions are dropped
        notificationCenter?.delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Async variants: their imported signature is stable across SDKs, unlike the completion-handler
    // forms whose @Sendable annotation changed and would silently stop matching the optional requirement.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action != UNNotificationDismissActionIdentifier else { return }
        onNotificationResponse?(action, response.notification.request.content.categoryIdentifier)
    }

    /// Requests user authorization for macOS notifications.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard let center = notificationCenter else { return false }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                registerCategories()
            }
            return granted
        } catch {
            return false
        }
    }

    /// Registers actionable notification categories with UNUserNotificationCenter.
    public func registerCategories() {
        guard let center = notificationCenter else { return }

        let viewThermalAction = UNNotificationAction(
            identifier: "ACTION_VIEW_THERMAL",
            title: "Open Thermal Monitor",
            options: [.foreground]
        )
        let thermalCategory = UNNotificationCategory(
            identifier: Self.categoryThermal,
            actions: [viewThermalAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let viewDiagAction = UNNotificationAction(
            identifier: "ACTION_VIEW_DIAGNOSTICS",
            title: "View SMART Diagnostics",
            options: [.foreground]
        )
        let criticalCategory = UNNotificationCategory(
            identifier: Self.categoryCriticalHardware,
            actions: [viewDiagAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let viewForecastAction = UNNotificationAction(
            identifier: "ACTION_VIEW_FORECAST",
            title: "View Lifespan Forecast",
            options: [.foreground]
        )
        let wearCategory = UNNotificationCategory(
            identifier: Self.categoryWearMilestone,
            actions: [viewForecastAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let mediaCategory = UNNotificationCategory(
            identifier: Self.categoryMediaError,
            actions: [viewDiagAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([thermalCategory, criticalCategory, wearCategory, mediaCategory])
    }

    /// Evaluates current metrics against threshold rules and returns string identifiers for triggered alerts.
    public func evaluateAlerts(
        metrics: SSDHealthMetrics,
        tempWarnThreshold: Double = 60.0,
        tempCritThreshold: Double = 65.0,
        wearWarnThreshold: Int = 80,
        spareWarnThreshold: Int = 10,
        now: Date = Date()
    ) -> [String] {
        let events = evaluateAlertEvents(
            metrics: metrics,
            tempWarnThreshold: tempWarnThreshold,
            tempCritThreshold: tempCritThreshold,
            wearWarnThreshold: wearWarnThreshold,
            spareWarnThreshold: spareWarnThreshold,
            now: now
        )
        return events.map { $0.rawCode }
    }

    /// Evaluates current metrics against all alert threshold rules and returns full AlertEvent models.
    public func evaluateAlertEvents(
        metrics: SSDHealthMetrics,
        tempWarnThreshold: Double = 60.0,
        tempCritThreshold: Double = 65.0,
        wearWarnThreshold: Int = 80,
        spareWarnThreshold: Int = 10,
        now: Date = Date()
    ) -> [AlertEvent] {
        var triggered: [AlertEvent] = []

        // 1. Thermal Alerts
        let extremeThreshold = max(70.0, tempCritThreshold + 5.0)
        if metrics.temperatureCelsius >= extremeThreshold {
            if cooldownManager.tryTrigger(key: "temp_ext", cooldownSeconds: 600.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "temp_ext",
                    title: "Extreme SSD Temperature",
                    message: "SSD temperature has reached \(metrics.temperatureFormatted). Thermal throttling active.",
                    severity: .emergency,
                    timestamp: now,
                    rawCode: "CRITICAL_TEMPERATURE: \(metrics.temperatureFormatted)"
                ))
            }
        } else if metrics.temperatureCelsius >= tempCritThreshold {
            if cooldownManager.tryTrigger(key: "temp_crit", cooldownSeconds: 900.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "temp_crit",
                    title: "Critical SSD Temperature",
                    message: "SSD temperature is high (\(metrics.temperatureFormatted)). Ensure adequate ventilation.",
                    severity: .critical,
                    timestamp: now,
                    rawCode: "CRITICAL_TEMPERATURE: \(metrics.temperatureFormatted)"
                ))
            }
        } else if metrics.temperatureCelsius >= tempWarnThreshold {
            if cooldownManager.tryTrigger(key: "temp_warn", cooldownSeconds: 1800.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "temp_warn",
                    title: "Elevated SSD Temperature",
                    message: "SSD temperature is \(metrics.temperatureFormatted), exceeding warning threshold.",
                    severity: .warning,
                    timestamp: now,
                    rawCode: "HIGH_TEMPERATURE: \(metrics.temperatureFormatted)"
                ))
            }
        }

        // 2. Wear Milestone Alerts (One-shot per milestone)
        let firstMilestone = min(100, max(1, wearWarnThreshold))
        let milestones = Set([firstMilestone, 90, 95, 100].filter { $0 >= firstMilestone }).sorted()
        for m in milestones where metrics.wearPercentage >= m {
            if cooldownManager.tryAcknowledgeWearMilestone(m) {
                let severity: AlertSeverity = (m >= 95 ? .emergency : (m >= 90 ? .critical : .warning))
                triggered.append(AlertEvent(
                    ruleKey: "wear_m_\(m)",
                    title: "SSD Wear Milestone Reached",
                    message: "Drive has consumed \(m)% of rated endurance capacity (\(metrics.wearFormatted)).",
                    severity: severity,
                    timestamp: now,
                    rawCode: "WEAR_MILESTONE_\(m): \(metrics.wearFormatted)"
                ))
            }
        }

        // 3. Spare Capacity Alerts
        if metrics.availableSparePercent <= 5 {
            if cooldownManager.tryTrigger(key: "spare_crit", cooldownSeconds: 43200.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "spare_crit",
                    title: "Emergency: Available Spare Depleted",
                    message: "Available spare flash blocks are critically low at \(metrics.availableSparePercent)%.",
                    severity: .emergency,
                    timestamp: now,
                    rawCode: "SPARE_CAPACITY_LOW: \(metrics.availableSparePercent)%"
                ))
            }
        } else if metrics.availableSparePercent < spareWarnThreshold || metrics.criticalWarnings.contains(.availableSpareBelowThreshold) {
            if cooldownManager.tryTrigger(key: "spare_low", cooldownSeconds: 86400.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "spare_low",
                    title: "Available Spare Below Threshold",
                    message: "Available spare capacity is \(metrics.availableSparePercent)% (threshold: \(spareWarnThreshold)%).",
                    severity: .critical,
                    timestamp: now,
                    rawCode: "SPARE_CAPACITY_LOW: \(metrics.availableSparePercent)%"
                ))
            }
        }

        // 4. Critical Warning Bitmask Flags
        if metrics.criticalWarnings.contains(.reliabilityDegraded) {
            if cooldownManager.tryTrigger(key: "crit_reliability", cooldownSeconds: 86400.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "crit_reliability",
                    title: "NVM Subsystem Reliability Degraded",
                    message: "Internal hardware reliability degraded due to media or memory error.",
                    severity: .emergency,
                    timestamp: now,
                    rawCode: "CRITICAL_RELIABILITY_DEGRADED"
                ))
            }
        }

        if metrics.criticalWarnings.contains(.readOnly) {
            if cooldownManager.tryTrigger(key: "crit_readonly", cooldownSeconds: 86400.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "crit_readonly",
                    title: "SSD Locked in Read-Only Mode",
                    message: "Drive media placed in read-only mode to prevent data corruption. Back up immediately.",
                    severity: .emergency,
                    timestamp: now,
                    rawCode: "CRITICAL_DRIVE_READ_ONLY"
                ))
            }
        }

        if metrics.criticalWarnings.contains(.volatileMemoryBackupFailed) {
            if cooldownManager.tryTrigger(key: "crit_backup", cooldownSeconds: 86400.0, now: now) {
                triggered.append(AlertEvent(
                    ruleKey: "crit_backup",
                    title: "Volatile Memory Backup Failed",
                    message: "Capacitor backup device for volatile write buffer has failed.",
                    severity: .critical,
                    timestamp: now,
                    rawCode: "CRITICAL_BACKUP_FAILED"
                ))
            }
        }

        // 5. Media Errors Delta (baseline is per drive)
        if cooldownManager.recordMediaErrors(metrics.mediaErrors, driveID: metrics.id) {
            triggered.append(AlertEvent(
                ruleKey: "media_errors",
                title: "Media Integrity Errors Detected",
                message: "\(metrics.mediaErrors) uncorrectable media data integrity errors recorded.",
                severity: .critical,
                timestamp: now,
                rawCode: "MEDIA_ERRORS_DETECTED: \(metrics.mediaErrors)"
            ))
        }

        return triggered
    }

    /// Evaluates rules and dispatches system notifications for all triggered events.
    @discardableResult
    public func evaluateAndDispatch(
        metrics: SSDHealthMetrics,
        tempWarnThreshold: Double = 60.0,
        tempCritThreshold: Double = 65.0,
        wearWarnThreshold: Int = 80,
        spareWarnThreshold: Int = 10,
        now: Date = Date()
    ) async -> [AlertEvent] {
        let events = evaluateAlertEvents(
            metrics: metrics,
            tempWarnThreshold: tempWarnThreshold,
            tempCritThreshold: tempCritThreshold,
            wearWarnThreshold: wearWarnThreshold,
            spareWarnThreshold: spareWarnThreshold,
            now: now
        )

        for event in events {
            dispatchNotification(event: event)
        }

        return events
    }

    /// Dispatches a single alert event to the macOS notification system.
    public func dispatchNotification(event: AlertEvent) {
        guard let center = notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.message
        content.sound = (event.severity >= .critical ? .defaultCritical : .default)

        if event.ruleKey.starts(with: "temp") {
            content.categoryIdentifier = Self.categoryThermal
        } else if event.ruleKey.starts(with: "wear") {
            content.categoryIdentifier = Self.categoryWearMilestone
        } else if event.ruleKey.starts(with: "media") {
            content.categoryIdentifier = Self.categoryMediaError
        } else {
            content.categoryIdentifier = Self.categoryCriticalHardware
        }

        let request = UNNotificationRequest(
            identifier: "\(event.ruleKey)_\(event.id.uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request) { _ in }
    }
}
