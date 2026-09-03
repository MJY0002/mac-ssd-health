# Project: Native macOS SSD Health Menu Bar Application

## Architecture
A native macOS 14+ Menu Bar and Dashboard application built in Swift and SwiftUI, leveraging IOKit / IORegistry and the NVMe SMART Log Page specification directly without external tools.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        User Interface Layer                            │
│  ┌────────────────────────┐  ┌───────────────────────────────────────┐ │
│  │ NSStatusItem (Menu Bar)│  │ NSPopover / SwiftUI QuickView Popover │ │
│  └───────────┬────────────┘  └───────────────────┬───────────────────┘ │
│              │                                   │                     │
│              ▼                                   ▼                     │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ Full Dashboard Window (KPI Grid, SMART Table, Charts, Settings)   │ │
│  └───────────────────────────────────┬───────────────────────────────┘ │
└──────────────────────────────────────┼─────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼─────────────────────────────────┐
│                    Application & State Services                        │
│  ┌────────────────────────┐  ┌───────────────────────────────────────┐ │
│  │ AppState (Observable)  │  │ Polling & Notification Manager        │ │
│  └───────────┬────────────┘  └───────────────────┬───────────────────┘ │
│              │                                   │                     │
│  ┌───────────▼────────────┐  ┌───────────────────▼───────────────────┐ │
│  │ Mathematical Forecast  │  │ History Persistence Actor (Decimation)│ │
│  │ Engine (OLS / TBW / CI)│  │ JSON Storage in Application Support   │ │
│  └────────────────────────┘  └───────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ Diagnostic Exporter (JSON, CSV, Formatted ASCII Protocol)         │ │
│  └───────────────────────────────────┬───────────────────────────────┘ │
└──────────────────────────────────────┼─────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼─────────────────────────────────┐
│                      Core Hardware / Data Layer                        │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ SSDStorageReading Protocol                                         │ │
│  └─────────────────┬───────────────────────────────────┬─────────────┘ │
│                    │                                   │               │
│  ┌─────────────────▼──────────────┐  ┌─────────────────▼─────────────┐ │
│  │ IOKitStorageReader             │  │ MockSSDStorageReader          │ │
│  │ - NVMe SMART UserClient (0x02) │  │ - 7 Presets (Healthy, Warning,│ │
│  │ - IORegistry Property Fallback │  │   Overheating, Critical, etc.)│ │
│  │ - 512-Byte Binary SMART Parser │  │ - Synthetic Data Generator    │ │
│  └────────────────────────────────┘  └───────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | NVMe 512-Byte SMART Parser | Decodes 512-byte binary SMART log (Log ID 0x02), 128-bit integers, critical warnings, temperature | M1 | survey_1 |
| 2 | IOKit Native UserClient Reader | Native `IOCFPlugIn` / `IONVMeSMARTInterface` direct controller query without `smartctl` | M1 | survey_1 |
| 3 | IORegistry Property Fallback | Queries `IOBlockStorageDevice`, `IOBlockStorageDriver` for metadata and non-privileged fallback | M1 | survey_1 |
| 4 | Data Models & 128-Bit Arithmetic | `NVMESmartLog`, `SSDHealthMetrics`, `UInt128Value`, `CriticalWarningFlags` | M1 | survey_1 |
| 5 | Mock Data Provider | `MockSSDStorageReader` with 7 presets for SwiftUI Previews and headless testing | M1 | survey_1 |
| 6 | OLS Daily Write Rate Algorithm | Ordinary Least Squares regression slope over 7d/30d/all-time windows in GB/day | M2 | survey_3 |
| 7 | Dual Lifespan Extrapolation | Model A (wear rate) + Model B (rated TBW endurance) with 95% CI bounds & degradation state | M2 | survey_3 |
| 8 | History Persistence & Decimation | Atomic JSON storage with 4-tier temporal decimation (raw, hourly, daily, weekly) | M2 | survey_3 |
| 9 | Notification & Alerting Engine | `UNUserNotificationCenter` with thermal (>65°C), wear (>80%), and critical warning triggers | M2 | survey_3 |
| 10 | Diagnostic Export Engine | Machine JSON dump, RFC 4180 CSV time-series, formatted ASCII diagnostic report | M2 | survey_3 |
| 11 | Menu Bar StatusItem & Display Modes| `NSStatusItem` with dynamic icon, health %, temperature, combined modes, anti-jitter digits | M3 | survey_2 |
| 12 | Popover QuickView | Circular health gauge, temperature badge, total TBW, lifespan prognosis, action buttons | M3 | survey_2 |
| 13 | Full Dashboard Window & KPI Cards | 960x680 `NavigationSplitView` with 3x2 KPI grid, responsive layout | M3 | survey_2 |
| 14 | Complete SMART Parameter Table | 19+ parameters with name, raw byte/hex value, formatted unit value, status flags, search | M3 | survey_2 |
| 15 | Swift Charts Time-Series | Wear progression chart, TBW accumulation chart, temperature trend with threshold rules | M3 | survey_2 |
| 16 | Settings & Preferences Panel | Polling interval, alert threshold customization, notifications toggle, export trigger | M3 | survey_2 |
| 17 | App Assembly & SPM/Xcode Build | `Package.swift`, executable entry point, Xcode scheme, pure native build compatibility | M4 | survey_1/2/3 |
| 18 | 100% E2E Test Pass | Verification across all 4 tiers of opaque-box E2E tests | M4 | E2E Track |
| 19 | Adversarial Coverage Hardening | Stress testing, memory safety, boundary fuzzing, corrupted byte handling | M5 | E2E Track (Tier 5) |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| E2E | E2E Testing Track | Requirement-driven test harness, test fixtures, Tiers 1-4 test suites, TEST_READY.md | none | DONE |
| M1 | Core Storage Reader & SMART Models | Features 1-5: Binary SMART parser, IOKit reader, models, mock provider, unit tests | none | DONE |
| M2 | Forecast Engine, History & Alerts | Features 6-10: OLS write rate, lifespan models, history persistence, notifications, export | M1 | DONE |
| M3 | Menu Bar & SwiftUI Dashboard UI | Features 11-16: NSStatusItem, Popover QuickView, Full Dashboard Window, Swift Charts, Settings | M1, M2 | DONE |
| M4 | Integration, SPM Build & 100% E2E | Features 17-18: App wiring, Package.swift, Xcode project scheme, E2E test verification | M1, M2, M3, E2E | DONE |
| M5 | Adversarial Coverage Hardening | Feature 19: Tier 5 white-box stress testing, challenger-driven audit, edge case fuzzing | M4 | DONE |

## Interface Contracts
### `SSDStorageReading` (Core ↔ Application)
```swift
public protocol SSDStorageReading: Sendable {
    func readHealthMetrics() async throws -> SSDHealthMetrics
    func readRawSmartLog() async throws -> NVMESmartLog
    func isLiveHardwareAccessAvailable() -> Bool
}
```

### `ForecastEngineProtocol` (Forecast ↔ UI / Persistence)
```swift
public protocol ForecastEngineProtocol: Sendable {
    func calculateForecast(current: SSDHealthMetrics, history: [SSDHistorySnapshot], ratedTBW: Double?) -> SSDForecastResult
}
```

### `HistoryPersistenceProtocol` (Persistence ↔ AppState)
```swift
public protocol HistoryPersistenceProtocol: Sendable {
    func record(snapshot: SSDHistorySnapshot) async throws
    func loadHistory() async throws -> [SSDHistorySnapshot]
    func purgeAll() async throws
}
```

### `DiagnosticExporting` (Export ↔ UI)
```swift
public protocol DiagnosticExporting: Sendable {
    func exportJSON(metrics: SSDHealthMetrics, history: [SSDHistorySnapshot], forecast: SSDForecastResult?) throws -> String
    func exportCSV(history: [SSDHistorySnapshot]) throws -> String
    func exportTextReport(metrics: SSDHealthMetrics, history: [SSDHistorySnapshot], forecast: SSDForecastResult?) -> String
}
```

## Code Layout
```
mac_ssd_health/
├── Package.swift
├── Sources/
│   ├── SSDHealthCore/
│   │   ├── Models/
│   │   │   ├── CriticalWarningFlags.swift
│   │   │   ├── UInt128Value.swift
│   │   │   ├── NVMESmartLog.swift
│   │   │   └── SSDHealthMetrics.swift
│   │   ├── Protocols/
│   │   │   └── SSDStorageReading.swift
│   │   ├── IOKit/
│   │   │   ├── IOKitKeys.swift
│   │   │   └── IOKitStorageReader.swift
│   │   └── Mocks/
│   │       ├── MockSSDStorageReader.swift
│   │       └── SyntheticSMARTFixtures.swift
│   ├── SSDHealthService/
│   │   ├── Forecast/
│   │   │   ├── SSDForecastResult.swift
│   │   │   └── ForecastEngine.swift
│   │   ├── Persistence/
│   │   │   ├── SSDHistorySnapshot.swift
│   │   │   └── HistoryPersistenceActor.swift
│   │   ├── Notifications/
│   │   │   ├── AlertRule.swift
│   │   │   └── NotificationService.swift
│   │   └── Exporter/
│   │       └── DiagnosticExporter.swift
│   ├── SSDHealthUI/
│   │   ├── State/
│   │   │   ├── AppSettings.swift
│   │   │   └── AppState.swift
│   │   ├── MenuBar/
│   │   │   ├── MenuBarManager.swift
│   │   │   └── MenuBarStatusView.swift
│   │   ├── Popover/
│   │   │   └── QuickViewPopover.swift
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift
│   │   │   ├── MetricCardView.swift
│   │   │   ├── SMARTTableView.swift
│   │   │   ├── HealthChartsView.swift
│   │   │   ├── ForecastView.swift
│   │   │   └── SettingsView.swift
│   │   └── Components/
│   │       └── CircularGaugeView.swift
│   └── SSDHealthApp/
│       ├── App/
│       │   ├── AppDelegate.swift
│       │   └── SSDHealthApp.swift
│       └── Resources/
└── Tests/
    ├── SSDHealthCoreTests/
    │   ├── NVMESmartLogTests.swift
    │   ├── UInt128ValueTests.swift
    │   └── MockStorageReaderTests.swift
    ├── SSDHealthServiceTests/
    │   ├── ForecastEngineTests.swift
    │   ├── HistoryPersistenceTests.swift
    │   ├── NotificationServiceTests.swift
    │   └── DiagnosticExporterTests.swift
    └── SSDHealthE2ETests/
        ├── TestHarness.swift
        ├── Tier1_FeatureCoverageTests.swift
        ├── Tier2_BoundaryCornerTests.swift
        ├── Tier3_CrossFeatureTests.swift
        ├── Tier4_RealWorldScenarioTests.swift
        └── Tier5_AdversarialTests.swift
```
