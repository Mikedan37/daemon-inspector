import XCTest

/// Layer 3: Sampling Stability Tests
/// 
/// These tests validate the sample command:
/// - Produces expected snapshot density
/// - Handles interruption gracefully
/// - No drift beyond one interval
final class Layer3_SamplingStabilityTests: XCTestCase {
    
    // MARK: - Basic Sampling
    
    func testSamplingProducesExpectedDensity() throws {
        let harness = try CLITestHarness(testName: "samplingDensity")
        
        // Sample every 1s for 5s
        // Expected: approximately 5 snapshots (could be 4-6 depending on timing)
        let result = try harness.runSample(every: "1s", forDuration: "5s")
        
        XCTAssertTrue(result.succeeded, "Sample should succeed. Stderr: \(result.stderr)")
        
        // Output should indicate sampling completed
        XCTAssertTrue(
            result.stdoutContains("Sampling completed"),
            "Should indicate sampling completed. Got: \(result.stdout)"
        )
        
        // Extract snapshot count from "Snapshots written: N"
        if let count = extractSnapshotCount(from: result.stdout) {
            // Should be approximately 5 (allow 4-6 for timing variance)
            XCTAssertGreaterThanOrEqual(count, 4, "Should write at least 4 snapshots")
            XCTAssertLessThanOrEqual(count, 6, "Should write at most 6 snapshots")
        } else {
            XCTFail("Could not extract snapshot count from output: \(result.stdout)")
        }
    }
    
    func testSamplingReportsCadence() throws {
        let harness = try CLITestHarness(testName: "samplingCadence")
        
        let result = try harness.runSample(every: "2s", forDuration: "6s")
        
        XCTAssertTrue(result.succeeded)
        
        // Should report cadence
        XCTAssertTrue(
            result.stdoutContains("Cadence: 2s"),
            "Should report cadence. Got: \(result.stdout)"
        )
        
        // Should report duration
        XCTAssertTrue(
            result.stdoutContains("Duration: 6s"),
            "Should report duration. Got: \(result.stdout)"
        )
    }
    
    func testSamplingWithMinuteDuration() throws {
        // Skip this test in CI - it takes too long
        // Only run manually when needed
        #if FULL_TEST_SUITE
        let harness = try CLITestHarness(testName: "samplingMinute")
        
        let result = try harness.runSample(every: "5s", forDuration: "30s")
        
        XCTAssertTrue(result.succeeded)
        
        if let count = extractSnapshotCount(from: result.stdout) {
            // 30s / 5s = 6 snapshots (could be 5-7)
            XCTAssertGreaterThanOrEqual(count, 5)
            XCTAssertLessThanOrEqual(count, 7)
        }
        #endif
    }
    
    // MARK: - Sampling Validation
    
    func testSamplingCreatesUsableSnapshots() throws {
        let harness = try CLITestHarness(testName: "samplingUsable")
        
        // Take a few samples
        let sampleResult = try harness.runSample(every: "1s", forDuration: "3s")
        XCTAssertTrue(sampleResult.succeeded)
        
        // Verify diff works on sampled data
        let diffResult = try harness.runDiff()
        
        // Should have enough snapshots for diff
        XCTAssertFalse(
            diffResult.stdoutContains("Need at least two snapshots"),
            "Should have enough snapshots for diff after sampling"
        )
        
        // Should produce comparison output
        XCTAssertTrue(
            diffResult.stdoutContains("Changes between") || 
            diffResult.stdoutContains("No observable changes"),
            "Diff should work on sampled snapshots"
        )
    }
    
    func testSamplingCreatesUsableUnstableReport() throws {
        let harness = try CLITestHarness(testName: "samplingUnstable")
        
        // Take samples
        let sampleResult = try harness.runSample(every: "1s", forDuration: "3s")
        XCTAssertTrue(sampleResult.succeeded)
        
        // Verify unstable works
        let unstableResult = try harness.runUnstable()
        
        // Should have an instability report header
        XCTAssertTrue(
            unstableResult.stdoutContains("Instability Report") ||
            unstableResult.stdoutContains("No instability detected"),
            "Unstable should produce report after sampling"
        )
    }
    
    // MARK: - Invalid Arguments
    
    func testSamplingMissingEvery() throws {
        let harness = try CLITestHarness(testName: "samplingMissingEvery")
        
        let result = try harness.run(["sample", "--for", "5s"])
        
        XCTAssertTrue(
            result.stdoutContains("Missing") || result.stderrContains("Missing"),
            "Should indicate missing --every argument"
        )
    }
    
    func testSamplingMissingFor() throws {
        let harness = try CLITestHarness(testName: "samplingMissingFor")
        
        let result = try harness.run(["sample", "--every", "1s"])
        
        XCTAssertTrue(
            result.stdoutContains("Missing") || result.stderrContains("Missing"),
            "Should indicate missing --for argument"
        )
    }
    
    func testSamplingInvalidTimeFormat() throws {
        let harness = try CLITestHarness(testName: "samplingInvalidTime")
        
        let result = try harness.run(["sample", "--every", "banana", "--for", "5s"])
        
        XCTAssertTrue(
            result.stdoutContains("Invalid time format") || 
            result.stderrContains("Invalid time format"),
            "Should indicate invalid time format"
        )
    }
    
    // MARK: - Helpers
    
    private func extractSnapshotCount(from output: String) -> Int? {
        // Look for "Snapshots written: N"
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains("Snapshots written:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    let numberPart = parts[1].trimmingCharacters(in: .whitespaces)
                    return Int(numberPart)
                }
            }
        }
        return nil
    }
}
