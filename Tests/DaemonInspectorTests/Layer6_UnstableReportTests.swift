import XCTest

/// Layer 6: Unstable Report Validation
/// 
/// These tests validate the unstable command:
/// - Output sorted by total churn descending
/// - Counts are non-negative integers
/// - Observation windows are present
/// - Read-only behavior
final class Layer6_UnstableReportTests: XCTestCase {
    
    // MARK: - Report Structure
    
    func testUnstableReportHasHeader() throws {
        let harness = try CLITestHarness(testName: "unstableHeader")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let result = try harness.runUnstable()
        
        XCTAssertTrue(result.succeeded)
        
        // Should have report header
        XCTAssertTrue(
            result.stdoutContains("Instability Report") || 
            result.stdoutContains("No instability detected"),
            "Unstable should have header. Got: \(result.stdout)"
        )
    }
    
    func testUnstableReportShowsAnalysisScope() throws {
        let harness = try CLITestHarness(testName: "unstableScope")
        
        _ = try harness.runSample(every: "1s", forDuration: "4s")
        
        let result = try harness.runUnstable()
        
        // Should show how many snapshots were analyzed
        XCTAssertTrue(
            result.stdoutContains("Analyzed") && result.stdoutContains("snapshots"),
            "Unstable should show analysis scope. Got: \(result.stdout)"
        )
        
        // Should show time window
        XCTAssertTrue(
            result.stdoutContains("Window:") || result.stdoutContains("No instability"),
            "Unstable should show time window"
        )
    }
    
    func testUnstableReportShowsDaemonCount() throws {
        let harness = try CLITestHarness(testName: "unstableDaemonCount")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let result = try harness.runUnstable()
        
        // Should show count of daemons with instability
        XCTAssertTrue(
            result.stdoutContains("Daemons with observed instability:") ||
            result.stdoutContains("No instability detected"),
            "Unstable should show daemon count. Got: \(result.stdout)"
        )
    }
    
    // MARK: - Sorting
    
    func testUnstableIsSortedByChurn() throws {
        let harness = try CLITestHarness(testName: "unstableSorted")
        
        // Take samples to get some events
        _ = try harness.runSample(every: "1s", forDuration: "5s")
        
        let result = try harness.runUnstable()
        
        // Extract "Total events: N" values in order
        let eventCounts = extractEventCounts(from: result.stdout)
        
        // If we have multiple entries, verify they're sorted descending
        if eventCounts.count >= 2 {
            var previousCount = Int.max
            for count in eventCounts {
                XCTAssertLessThanOrEqual(
                    count, previousCount,
                    "Unstable should be sorted by churn descending. Counts: \(eventCounts)"
                )
                previousCount = count
            }
        }
    }
    
    // MARK: - Entry Structure
    
    func testUnstableEntriesHaveRequiredFields() throws {
        let harness = try CLITestHarness(testName: "unstableEntryFields")
        
        _ = try harness.runSample(every: "1s", forDuration: "4s")
        
        let result = try harness.runUnstable()
        
        // If there are any daemon entries (indicated by "Total events:")
        if result.stdoutContains("Total events:") {
            // Should have breakdown
            XCTAssertTrue(
                result.stdoutContains("Breakdown:") || result.stdoutContains("Total events: 0"),
                "Entries with events should have breakdown"
            )
            
            // Should have observation window
            XCTAssertTrue(
                result.stdoutContains("Observation window:"),
                "Entries should have observation window"
            )
        }
    }
    
    func testUnstableCountsAreNonNegative() throws {
        let harness = try CLITestHarness(testName: "unstableNonNeg")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let result = try harness.runUnstable()
        
        // All "Total events:" values should be non-negative
        let counts = extractEventCounts(from: result.stdout)
        for count in counts {
            XCTAssertGreaterThanOrEqual(count, 0, "Event counts should be non-negative")
        }
    }
    
    // MARK: - Read-Only Behavior
    
    func testUnstableIsReadOnly() throws {
        let harness = try CLITestHarness(testName: "unstableReadOnly")
        
        // Create initial snapshots
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        // Get initial unstable output
        let unstable1 = try harness.runUnstable()
        let initialCount = extractSnapshotCount(from: unstable1.stdout)
        
        // Run unstable multiple times
        _ = try harness.runUnstable()
        _ = try harness.runUnstable()
        _ = try harness.runUnstable()
        
        // Get final unstable output
        let unstable2 = try harness.runUnstable()
        let finalCount = extractSnapshotCount(from: unstable2.stdout)
        
        // Snapshot count should be unchanged
        XCTAssertEqual(
            initialCount, finalCount,
            "Unstable should not modify snapshot count"
        )
    }
    
    // MARK: - Edge Cases
    
    func testUnstableWithMinimalData() throws {
        let harness = try CLITestHarness(testName: "unstableMinimal")
        
        // Just two snapshots
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 0.5)
        _ = try harness.runList()
        
        let result = try harness.runUnstable()
        
        XCTAssertTrue(result.succeeded)
        
        // Should produce valid output (either report or no instability)
        XCTAssertTrue(
            result.stdoutContains("Instability Report") ||
            result.stdoutContains("No instability detected") ||
            result.stdoutContains("Analyzed 2 snapshots"),
            "Unstable should handle minimal data gracefully"
        )
    }
    
    func testUnstableReportPreservesTimeWindows() throws {
        let harness = try CLITestHarness(testName: "unstableTimeWindows")
        
        _ = try harness.runSample(every: "1s", forDuration: "4s")
        
        let result = try harness.runUnstable()
        
        // Time window in header should use arrow notation
        if result.stdoutContains("Window:") {
            XCTAssertTrue(
                result.stdoutContains("→"),
                "Time windows should use arrow notation. Got: \(result.stdout)"
            )
        }
    }
    
    // MARK: - Determinism
    
    func testUnstableIsDeterministic() throws {
        let harness = try CLITestHarness(testName: "unstableDeterminism")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let result1 = try harness.runUnstable()
        let result2 = try harness.runUnstable()
        let result3 = try harness.runUnstable()
        
        XCTAssertEqual(result1.stdout, result2.stdout, "Unstable should be deterministic")
        XCTAssertEqual(result2.stdout, result3.stdout, "Unstable should be deterministic")
    }
    
    // MARK: - Helpers
    
    private func extractEventCounts(from output: String) -> [Int] {
        var counts: [Int] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains("Total events:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    let numberPart = parts[1].trimmingCharacters(in: .whitespaces)
                    if let count = Int(numberPart) {
                        counts.append(count)
                    }
                }
            }
        }
        return counts
    }
    
    private func extractSnapshotCount(from output: String) -> Int? {
        // Look for "Analyzed N snapshots"
        let pattern = "Analyzed (\\d+) snapshot"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            return Int(output[range])
        }
        return nil
    }
}
