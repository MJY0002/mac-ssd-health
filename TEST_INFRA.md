# E2E Test Infra: Native macOS SSD Health

## Test Philosophy
- **Opaque-box & Requirement-driven**: Derived strictly from `ORIGINAL_REQUEST.md` and user specifications, not internal implementation details.
- **Methodology**: Category-Partition, Boundary Value Analysis (BVA), Pairwise Combinatorial Testing, and Realistic Workload Simulations.
- **Target Platform**: macOS 14.0+, Swift 5.9+, `swift test` and `xcodebuild`.

## Feature Inventory Mapping
| # | Feature | Requirement Source | Tier 1 | Tier 2 | Tier 3 |
|---|---------|-------------------|:------:|:------:|:------:|
| F1 | NVMe 512-Byte SMART Parser | R2. NVMe SMART Log Page | 5 | 5 | ✓ |
| F2 | IOKit Native Storage Client | R2. IOKit Driver Client | 5 | 5 | ✓ |
| F3 | IORegistry Fallback & Error Handling | Acceptance Criteria | 5 | 5 | ✓ |
| F4 | Data Models & 128-Bit Arithmetic | R2. Data Units & Counters | 5 | 5 | ✓ |
| F5 | Mock Data Provider Presets | R2. Mock Data Provider | 5 | 5 | ✓ |
| F6 | OLS Daily Write Rate Algorithm | R3. Daily Write Load | 5 | 5 | ✓ |
| F7 | Lifespan Prognosis & CI Bounds | R3. Remaining Lifespan | 5 | 5 | ✓ |
| F8 | Local History Persistence & Decimation | R3. Local Measurement Storage | 5 | 5 | ✓ |
| F9 | Notification Engine & Debounce | R3. Background Polling & Alerts | 5 | 5 | ✓ |
| F10 | Diagnostic Export (JSON/CSV/Text) | R3. Export Functionality | 5 | 5 | ✓ |
| F11 | Menu Bar StatusItem & Display Modes | R1. NSStatusItem & Display | 5 | 5 | ✓ |
| F12 | Popover QuickView Summary | R1. Popover Schnellansicht | 5 | 5 | ✓ |
| F13 | Dashboard Window & SMART Table | R1. Detail- & Analyse-Fenster | 5 | 5 | ✓ |
| F14 | Swift Charts Visualizations | R1. Zeitreihen-Diagramme | 5 | 5 | ✓ |
| F15 | Settings & Threshold Configuration | R1. Einstellungsmenü | 5 | 5 | ✓ |

## Test Architecture
- **Test Runner**: `swift test` and `xcodebuild test -scheme SSDHealth`
- **Pass/Fail Semantics**: All test suites must execute with 0 failures, 0 unexpected crashes, and valid assertions.
- **Synthetic Test Fixtures**:
  - Valid binary NVMe SMART logs (512-byte blocks with known endianness and values).
  - Edge-case byte dumps (all-zeros, all-ones, maximum integers, boundary temperatures).
  - Corrupted and truncated byte buffers.
  - Multi-day historical telemetry time series with linear and non-linear wear profiles.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | **Fresh Drive Out-of-Box Lifecycle**: 0% wear, 100% spare, pristine SMART values, estimating forecast | F1, F4, F5, F6, F7, F8, F10 | Medium |
| 2 | **Heavy Workload Developer SSD**: High daily TBW writes (50GB/day), accelerated wear (30%), 65°C thermal spike, history decimation, alerts | F1, F6, F7, F8, F9, F10, F12, F13 | High |
| 3 | **Near End-of-Life SSD**: 98% wear, available spare below threshold (8%), critical warning flags active, urgent notifications, emergency export | F1, F4, F7, F8, F9, F10, F11, F13 | High |
| 4 | **Restricted / Sandboxed Environment**: Non-privileged execution without UserClient entitlements, graceful fallback to IORegistry driver stats | F2, F3, F5, F8, F11, F12, F13 | Medium |
| 5 | **Long-Term Multi-Month History Decimation & Export**: 1,000+ hourly samples decimated across 4 retention tiers, CSV and JSON roundtrip integrity | F6, F7, F8, F10, F14 | High |

## Coverage Thresholds
- **Total Features (N)**: 15
- **Tier 1 (Feature Coverage)**: $\ge 5 \times 15 = 75$ test assertions
- **Tier 2 (Boundary & Corner Cases)**: $\ge 5 \times 15 = 75$ test assertions
- **Tier 3 (Cross-Feature Combinations)**: Pairwise coverage across core features ($\ge 15$ test cases)
- **Tier 4 (Real-World Scenarios)**: $\ge 5$ end-to-end workload workflows
- **Tier 5 (Adversarial Coverage Hardening)**: White-box fuzzing, concurrency stress, memory safety audits
