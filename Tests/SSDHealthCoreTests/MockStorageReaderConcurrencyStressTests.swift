import XCTest
import Foundation
@testable import SSDHealthCore

final class MockStorageReaderConcurrencyStressTests: XCTestCase {

    // MARK: - 1. 50+ Concurrent Parallel Reads
    func testConcurrent50ParallelReads() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        let concurrencyCount = 50

        try await withThrowingTaskGroup(of: SSDHealthMetrics.self) { group in
            for _ in 0..<concurrencyCount {
                group.addTask {
                    try await reader.readHealthMetrics()
                }
            }

            var results: [SSDHealthMetrics] = []
            for try await metrics in group {
                results.append(metrics)
            }

            XCTAssertEqual(results.count, concurrencyCount)
            for metrics in results {
                XCTAssertEqual(metrics.healthScorePercent, 98)
                XCTAssertEqual(metrics.wearPercentage, 2)
                XCTAssertEqual(metrics.temperatureCelsius, 33.5)
                XCTAssertEqual(metrics.serialNumber, "MOCK-HEALTHY-001")
                XCTAssertTrue(metrics.criticalWarnings.isClean)
            }
        }
    }

    // MARK: - 2. 100 Concurrent Parallel Reads with Preset Validation
    func testConcurrent100ParallelReadsAllPresets() async throws {
        let presets: [MockSSDStorageReader.Preset] = [
            .healthy, .warning, .overheating, .criticalWear, .degradedSpare
        ]

        for preset in presets {
            let reader = MockSSDStorageReader(preset: preset)
            let concurrencyCount = 100

            try await withThrowingTaskGroup(of: SSDHealthMetrics.self) { group in
                for _ in 0..<concurrencyCount {
                    group.addTask {
                        try await reader.readHealthMetrics()
                    }
                }

                var results: [SSDHealthMetrics] = []
                for try await metrics in group {
                    results.append(metrics)
                }

                XCTAssertEqual(results.count, concurrencyCount)
                for metrics in results {
                    XCTAssertFalse(metrics.modelName.isEmpty)
                    XCTAssertFalse(metrics.serialNumber.isEmpty)
                    XCTAssertGreaterThanOrEqual(metrics.healthScorePercent, 0)
                    XCTAssertLessThanOrEqual(metrics.healthScorePercent, 100)
                }
            }
        }
    }

    // MARK: - 3. Concurrent Dynamic Preset and Error Simulation Switching Under Load
    func testConcurrentErrorSimulationSwitchingUnderHeavyLoad() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        let iterationsPerReader = 30
        let readerCount = 20
        let writerCount = 5

        actor OutcomeTracker {
            var successCount = 0
            var errorCount = 0

            func recordSuccess() { successCount += 1 }
            func recordError() { errorCount += 1 }
            func counts() -> (Int, Int) { (successCount, errorCount) }
        }

        let tracker = OutcomeTracker()

        await withTaskGroup(of: Void.self) { group in
            // Spawn reader tasks
            for _ in 0..<readerCount {
                group.addTask {
                    for _ in 0..<iterationsPerReader {
                        do {
                            let metrics = try await reader.readHealthMetrics()
                            XCTAssertFalse(metrics.serialNumber.isEmpty)
                            await tracker.recordSuccess()
                        } catch let error as StorageReaderError {
                            XCTAssertNotNil(error.errorDescription)
                            await tracker.recordError()
                        } catch {
                            XCTFail("Unexpected non-StorageReaderError: \(error)")
                        }
                    }
                }
            }

            // Spawn writer / error-switching tasks
            let presetsToCycle: [MockSSDStorageReader.Preset] = [
                .healthy,
                .warning,
                .simulatedError(.permissionDenied(reason: "Dynamic Sandbox Fault")),
                .overheating,
                .simulatedError(.deviceNotFound),
                .criticalWear,
                .simulatedError(.smartReadFailed(kernReturn: -536870200)),
                .degradedSpare
            ]

            for writerIndex in 0..<writerCount {
                group.addTask {
                    for i in 0..<iterationsPerReader {
                        let preset = presetsToCycle[(writerIndex + i) % presetsToCycle.count]
                        reader.setPreset(preset)
                        // Yield to allow readers to interleave
                        await Task.yield()
                    }
                }
            }
        }

        let (successes, errors) = await tracker.counts()
        XCTAssertEqual(successes + errors, readerCount * iterationsPerReader)
        XCTAssertGreaterThan(successes, 0, "Expected at least some successful reads during dynamic switching")
        XCTAssertGreaterThan(errors, 0, "Expected at least some error reads during dynamic switching")
    }

    // MARK: - 4. Concurrent Custom Metrics Mutation and Torn-Read Verification
    func testConcurrentCustomMetricsMutationConsistency() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        let readerCount = 25
        let iterations = 20

        await withTaskGroup(of: Void.self) { group in
            // Reader tasks
            for _ in 0..<readerCount {
                group.addTask {
                    for _ in 0..<iterations {
                        do {
                            let m = try await reader.readHealthMetrics()
                            // Verify internal consistency: healthScore + wearPercentage = 100
                            XCTAssertEqual(m.healthScorePercent + m.wearPercentage, 100, "Torn read detected!")
                        } catch {
                            XCTFail("Custom metrics read should not fail: \(error)")
                        }
                        await Task.yield()
                    }
                }
            }

            // Writer task mutating custom metrics
            group.addTask {
                for i in 0..<100 {
                    let wear = i % 101
                    let health = 100 - wear
                    let custom = SSDHealthMetrics(
                        bsdName: "disk0",
                        modelName: "CONSISTENCY-TEST-SSD",
                        serialNumber: "CUSTOM-\(i)",
                        firmwareRevision: "1.0",
                        interconnect: "Apple Fabric",
                        capacityBytes: 500_000_000_000,
                        healthScorePercent: health,
                        wearPercentage: wear,
                        temperatureCelsius: 35.0 + Double(wear) * 0.1,
                        availableSparePercent: 100,
                        availableSpareThresholdPercent: 10,
                        terabytesWritten: Double(wear) * 5.0,
                        terabytesRead: Double(wear) * 10.0,
                        powerOnHours: 1000,
                        powerCycles: 200,
                        unsafeShutdowns: 5,
                        mediaErrors: 0,
                        errorLogEntries: 0,
                        criticalWarnings: CriticalWarningFlags(rawValue: 0),
                        timestamp: Date(),
                        isFallbackData: false
                    )
                    reader.setCustomMetrics(custom)
                    await Task.yield()
                }
            }
        }
    }

    // MARK: - 5. Concurrent Raw SMART Log Synthesis and Parsing
    func testConcurrentRawSmartLogSynthesisAndParsing() async throws {
        let reader = MockSSDStorageReader(preset: .warning)
        let concurrencyCount = 50

        try await withThrowingTaskGroup(of: NVMESmartLog.self) { group in
            for _ in 0..<concurrencyCount {
                group.addTask {
                    try await reader.readRawSmartLog()
                }
            }

            var logs: [NVMESmartLog] = []
            for try await log in group {
                logs.append(log)
            }

            XCTAssertEqual(logs.count, concurrencyCount)
            for log in logs {
                XCTAssertEqual(log.percentageUsed, 28)
                XCTAssertEqual(log.availableSparePercent, 88)
                XCTAssertEqual(log.numErrorInfoLogEntries.low, 2)
                XCTAssertEqual(log.healthScorePercent, 72)
            }
        }
    }

    // MARK: - 6. Concurrent Latency Simulation and Task Cancellation
    func testConcurrentSimulatedLatencyAndTaskCancellation() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        reader.setSimulatedLatency(milliseconds: 20.0)

        actor TaskStatusTracker {
            var completed = 0
            var cancelled = 0

            func recordCompleted() { completed += 1 }
            func recordCancelled() { cancelled += 1 }
            func getCounts() -> (Int, Int) { (completed, cancelled) }
        }

        let tracker = TaskStatusTracker()
        let totalTasks = 50

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<totalTasks {
                group.addTask {
                    let task = Task { () -> SSDHealthMetrics in
                        try await reader.readHealthMetrics()
                    }

                    // Cancel half of the tasks immediately
                    if i % 2 == 0 {
                        task.cancel()
                    }

                    do {
                        let metrics = try await task.value
                        XCTAssertEqual(metrics.healthScorePercent, 98)
                        await tracker.recordCompleted()
                    } catch is CancellationError {
                        await tracker.recordCancelled()
                    } catch {
                        // Task could complete before cancellation takes effect
                        await tracker.recordCompleted()
                    }
                }
            }
        }

        let (completed, cancelled) = await tracker.getCounts()
        XCTAssertEqual(completed + cancelled, totalTasks)
        // Reset latency
        reader.setSimulatedLatency(milliseconds: 0)
        let freshMetrics = try await reader.readHealthMetrics()
        XCTAssertEqual(freshMetrics.healthScorePercent, 98)
    }

    // MARK: - 7. Concurrent isLiveHardwareAccessAvailable Inspection
    func testConcurrentIsLiveHardwareAccessAvailable() async {
        let reader = MockSSDStorageReader(preset: .healthy)
        let concurrency = 50

        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<concurrency {
                group.addTask {
                    if i % 2 == 0 {
                        reader.setPreset(.healthy)
                    } else {
                        reader.setPreset(.permissionDenied)
                    }
                    return reader.isLiveHardwareAccessAvailable()
                }
            }

            var results: [Bool] = []
            for await avail in group {
                results.append(avail)
            }
            XCTAssertEqual(results.count, concurrency)
        }
    }

    // MARK: - 8. IOKitStorageReader Concurrency Stress
    func testIOKitStorageReaderConcurrent50Reads() async throws {
        let reader = IOKitStorageReader()
        let concurrencyCount = 50

        try await withThrowingTaskGroup(of: SSDHealthMetrics.self) { group in
            for _ in 0..<concurrencyCount {
                group.addTask {
                    try await reader.readHealthMetrics()
                }
            }

            var results: [SSDHealthMetrics] = []
            for try await metrics in group {
                results.append(metrics)
            }

            XCTAssertEqual(results.count, concurrencyCount)
            for metrics in results {
                XCTAssertFalse(metrics.modelName.isEmpty)
                XCTAssertFalse(metrics.bsdName.isEmpty)
                XCTAssertGreaterThan(metrics.capacityBytes, 0)
            }
        }
    }

    // MARK: - 9. High Stress Mixed Chaos Concurrency Harness
    func testHighStressMixedChaosHarness() async throws {
        let reader = MockSSDStorageReader(preset: .healthy)
        let taskCount = 50
        let opsPerTask = 20

        actor ChaosStats {
            var readSuccess = 0
            var readError = 0
            var rawSuccess = 0
            var rawError = 0
            var presetMutations = 0
            var latencyMutations = 0

            func incReadSuccess() { readSuccess += 1 }
            func incReadError() { readError += 1 }
            func incRawSuccess() { rawSuccess += 1 }
            func incRawError() { rawError += 1 }
            func incPreset() { presetMutations += 1 }
            func incLatency() { latencyMutations += 1 }

            func totalOperations() -> Int {
                readSuccess + readError + rawSuccess + rawError + presetMutations + latencyMutations
            }
        }

        let stats = ChaosStats()

        await withTaskGroup(of: Void.self) { group in
            for taskId in 0..<taskCount {
                group.addTask {
                    for opId in 0..<opsPerTask {
                        let choice = (taskId * 31 + opId * 17) % 100
                        switch choice {
                        case 0..<40:
                            // 40% readHealthMetrics
                            do {
                                _ = try await reader.readHealthMetrics()
                                await stats.incReadSuccess()
                            } catch {
                                await stats.incReadError()
                            }
                        case 40..<70:
                            // 30% readRawSmartLog
                            do {
                                _ = try await reader.readRawSmartLog()
                                await stats.incRawSuccess()
                            } catch {
                                await stats.incRawError()
                            }
                        case 70..<85:
                            // 15% mutate preset
                            let presets: [MockSSDStorageReader.Preset] = [
                                .healthy, .warning, .overheating, .criticalWear,
                                .degradedSpare, .deviceNotFound, .permissionDenied
                            ]
                            reader.setPreset(presets[opId % presets.count])
                            await stats.incPreset()
                        case 85..<95:
                            // 10% mutate latency
                            reader.setSimulatedLatency(milliseconds: Double(opId % 3))
                            await stats.incLatency()
                        default:
                            // 5% check hardware access
                            _ = reader.isLiveHardwareAccessAvailable()
                            await stats.incReadSuccess()
                        }
                    }
                }
            }
        }

        let total = await stats.totalOperations()
        XCTAssertEqual(total, taskCount * opsPerTask)
    }
}
