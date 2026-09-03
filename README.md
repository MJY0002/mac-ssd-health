# 🍏 SSD Health — Native macOS Apple SSD Health & SMART Monitor

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Tests](https://img.shields.io/badge/tests-390%20passing-brightgreen.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT%2BAttribution-purple.svg)](LICENSE)

A lightweight, 100% native macOS Menu Bar application built in **Swift & SwiftUI** that reads, visualizes, and monitors the health, wear levels, and SMART / NVMe telemetry of your internal Apple Silicon and Intel SSD — **without requiring Homebrew, `smartctl`, kernel extensions, or external CLI tools**.

---

## ✨ Features

- **🚀 100% Native IOKit & NVMe SMART Engine**: Reads the 512-byte raw binary NVMe SMART log page (`AppleNVMeSMARTUserClient` & `IOBlockStorageDevice`) directly through macOS IOKit with sub-millisecond latency.
- **📊 Interactive SwiftUI Dashboard & Swift Charts**:
  - Live **Health Score %** (Wear Level gauge).
  - **Total Bytes Written (TBW)** & Total Bytes Read (converted from 128-bit NVMe counters).
  - **Real-Time SSD Temperature** with customizable °C / °F display.
  - Complete **19+ SMART Raw Parameter Table** with real-time search & filter.
  - Interactive **Time-Series Charts** tracking wear progression, daily write volumes, and thermal trends.
- **🔮 Mathematical Lifespan & Write-Rate Forecasting**:
  - **Ordinary Least Squares (OLS) Linear Regression** calculating daily write load (GB/day).
  - **Dual-Model Lifespan Extrapolation** projecting remaining drive lifespan in years and days with 95% confidence intervals.
- **🔔 macOS System Notifications**:
  - Background polling with automated alerts on thermal spikes (>65°C), high wear (>80%), low spare capacity (<10%), or critical hardware flags.
- **💾 Local History Persistence & Decimation**:
  - Thread-safe actor storage with 4-tier temporal decimation (<24h raw, 7d hourly, 365d daily, >1y weekly) for lightweight long-term monitoring.
- **📤 Comprehensive Diagnostic Export**:
  - One-click export to structured **JSON**, **RFC 4180 CSV**, and formatted **ASCII diagnostic reports**.

---

## 🏗️ Architecture

```
mac_ssd_health/
├── Package.swift                    # Swift Package definition (macOS 14+)
├── build_app.sh                     # Automated release bundler & codesigner
├── LICENSE                          # MIT License with Attribution Clause
├── Sources/
│   ├── SSDHealthCore/               # Pure Swift IOKit & NVMe SMART Parser
│   │   ├── IOKit/                   # IOKitStorageReader (AppleNVMeSMART client)
│   │   ├── Models/                  # NVMESmartLog, SSDHealthMetrics, UInt128Value
│   │   ├── Protocols/               # SSDStorageReading interface
│   │   └── Mocks/                   # MockSSDStorageReader & Synthetic SMART fixtures
│   ├── SSDHealthService/            # Forecast, Persistence, Alerts & Exporter
│   │   ├── Forecast/                # OLS Regression & Dual Lifespan Engine
│   │   ├── Persistence/             # HistoryPersistenceActor with 4-tier decimation
│   │   ├── Notifications/           # UNUserNotificationCenter alert manager
│   │   └── Exporter/                # DiagnosticExporter (JSON, CSV, Text)
│   ├── SSDHealthUI/                 # SwiftUI Views & Menu Bar Controller
│   │   ├── MenuBar/                 # NSStatusItem controller & reactive icon
│   │   ├── Popover/                 # QuickViewPopover (Menu bar dropdown)
│   │   ├── Dashboard/               # Full Dashboard (Swift Charts, SMART Table, Settings)
│   │   └── State/                   # AppState & AppSettings observable models
│   └── SSDHealthApp/                # Standalone macOS application target & AppDelegate
└── Tests/                           # 390 automated unit, UI, and E2E tests
```

---

## 🚀 Quickstart & Installation

### Option 1: Build & Run from Terminal
```bash
# Clone the repository
git clone https://github.com/MJY0002/mac-ssd-health.git
cd mac-ssd-health

# Compile and package the native .app bundle:
./build_app.sh

# Launch the app:
open "dist/SSD Health.app"
```

### Option 2: Open and Code in Xcode
1. Open the project in Xcode:
   ```bash
   xed .
   ```
2. Select the **`SSDHealthApp`** scheme at the top of Xcode (Target: *My Mac*).
3. Press **`⌘ + R`** to run the app in your menu bar.
4. Press **`⌘ + U`** to run the complete 390-test automated verification suite.

---

## 🧪 Testing & Verification

The project includes **390 automated tests** across 5 tiers:
- **Tier 1:** Full feature coverage (IOKit parsing, 128-bit math, regression, alerts).
- **Tier 2:** Extreme boundary & corner cases (truncated buffers, zero deltas, thermal extremes).
- **Tier 3:** Cross-feature data pipeline interactions.
- **Tier 4:** Real-world SSD lifecycle & heavy workload simulations.
- **Tier 5:** Adversarial fuzzing & corrupted buffer rejection.

Run all tests via Swift Package Manager:
```bash
swift test
```

---

## 📜 License & Project Attribution

This project is licensed under the **MIT License with Project Attribution Condition**.

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

1. The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

2. Project Attribution Condition: If this Software or any substantial portion
   thereof is modified, forked, redistributed, or incorporated into another project,
   the original project name "mac-ssd-health" (or "SSD Health") and credit to the
   original author (MJY0002) and repository must be clearly and prominently acknowledged
   in the documentation, source code headers, and any user-facing credits/about screens.
```

See the [LICENSE](LICENSE) file for the full text.
