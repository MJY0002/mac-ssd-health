import Foundation

/// Severity level of SSD diagnostic alerts and notifications.
public enum AlertSeverity: String, Codable, Sendable, Comparable, CaseIterable {
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"
    case emergency = "Emergency"

    private var rank: Int {
        switch self {
        case .info: return 1
        case .warning: return 2
        case .critical: return 3
        case .emergency: return 4
        }
    }

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Rule definition specifying trigger conditions, alert severity, and debounce cooldown intervals.
public struct AlertRule: Sendable, Equatable {
    public let ruleKey: String
    public let severity: AlertSeverity
    public let cooldownSeconds: TimeInterval
    public let title: String
    public let description: String

    public init(
        ruleKey: String,
        severity: AlertSeverity,
        cooldownSeconds: TimeInterval,
        title: String = "",
        description: String = ""
    ) {
        self.ruleKey = ruleKey
        self.severity = severity
        self.cooldownSeconds = cooldownSeconds
        self.title = title
        self.description = description
    }
}

/// Discrete alert notification event dispatched when a threshold rule is triggered.
public struct AlertEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let ruleKey: String
    public let title: String
    public let message: String
    public let severity: AlertSeverity
    public let timestamp: Date
    public let rawCode: String

    public init(
        id: UUID = UUID(),
        ruleKey: String,
        title: String,
        message: String,
        severity: AlertSeverity,
        timestamp: Date = Date(),
        rawCode: String = ""
    ) {
        self.id = id
        self.ruleKey = ruleKey
        self.title = title
        self.message = message
        self.severity = severity
        self.timestamp = timestamp
        self.rawCode = rawCode.isEmpty ? ruleKey : rawCode
    }
}

/// Persistent state model tracking alert cooldown timestamps and acknowledged milestones.
public struct AlertState: Codable, Sendable, Equatable {
    public var lastTriggeredTimestamps: [String: Date] = [:]
    public var lastAcknowledgedMilestones: Set<Int> = []
    public var lastMediaErrors: UInt64 = 0
    /// Drive the media error baseline belongs to (optional so older persisted state still decodes).
    public var lastMediaErrorsDriveID: String? = nil

    public init(
        lastTriggeredTimestamps: [String: Date] = [:],
        lastAcknowledgedMilestones: Set<Int> = [],
        lastMediaErrors: UInt64 = 0,
        lastMediaErrorsDriveID: String? = nil
    ) {
        self.lastTriggeredTimestamps = lastTriggeredTimestamps
        self.lastAcknowledgedMilestones = lastAcknowledgedMilestones
        self.lastMediaErrors = lastMediaErrors
        self.lastMediaErrorsDriveID = lastMediaErrorsDriveID
    }
}

/// Manages cooldown timers and prevents notification spam across application restarts.
public final class AlertCooldownManager: @unchecked Sendable {
    private let userDefaults: UserDefaults?
    private let storageKey: String
    private var state: AlertState
    private let lock = NSLock()

    public init(userDefaults: UserDefaults? = nil, storageKey: String = "com.ssdhealth.alert_cooldown_state") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        if let ud = userDefaults,
           let data = ud.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode(AlertState.self, from: data) {
            self.state = loaded
        } else {
            self.state = AlertState()
        }
    }

    public func shouldTrigger(key: String, cooldownSeconds: TimeInterval, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let last = state.lastTriggeredTimestamps[key] else {
            return true
        }
        return now.timeIntervalSince(last) >= cooldownSeconds
    }

    public func recordTrigger(key: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        state.lastTriggeredTimestamps[key] = now
        persistState()
    }

    public func shouldTriggerWearMilestone(_ milestone: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return !state.lastAcknowledgedMilestones.contains(milestone)
    }

    public func acknowledgeWearMilestone(_ milestone: Int) {
        lock.lock()
        defer { lock.unlock() }

        state.lastAcknowledgedMilestones.insert(milestone)
        persistState()
    }

    public func lastMediaErrorCount() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return state.lastMediaErrors
    }

    public func updateMediaErrorCount(_ count: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        state.lastMediaErrors = count
        persistState()
    }

    public func lastMediaErrorDriveID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return state.lastMediaErrorsDriveID
    }

    public func updateMediaErrorCount(_ count: UInt64, driveID: String) {
        lock.lock()
        defer { lock.unlock() }
        state.lastMediaErrors = count
        state.lastMediaErrorsDriveID = driveID
        persistState()
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = AlertState()
        persistState()
    }

    private func persistState() {
        guard let ud = userDefaults else { return }
        if let data = try? JSONEncoder().encode(state) {
            ud.set(data, forKey: storageKey)
        }
    }
}
