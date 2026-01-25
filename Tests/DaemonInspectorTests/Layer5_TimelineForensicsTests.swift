import XCTest

/// Layer 5: Timeline Forensics
/// 
/// These tests validate the timeline command:
/// - Correct filtering by daemon label
/// - Chronological ordering
/// - Summary fields are derived, not stored
final class Layer5_TimelineForensicsTests: XCTestCase {
    
    // MARK: - Known Daemon Timeline
    
    func testTimelineForKnownDaemon() throws {
        let harness = try CLITestHarness(testName: "timelineKnown")
        
        // Take samples
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        // Finder is always running on macOS
        let result = try harness.runTimeline(label: "com.apple.Finder")
        
        XCTAssertTrue(result.succeeded)
        
        // Should show the label
        XCTAssertTrue(
            result.stdoutContains("com.apple.Finder"),
            "Timeline should show the daemon label"
        )
        
        // Should show observation count
        XCTAssertTrue(
            result.stdoutContains("Observed across"),
            "Timeline should show observation count"
        )
        
        // Should have summary
        XCTAssertTrue(
            result.stdoutContains("Summary:"),
            "Timeline should have summary section"
        )
    }
    
    func testTimelineShowsCorrectSnapshotCount() throws {
        let harness = try CLITestHarness(testName: "timelineCount")
        
        // Take exactly 4 samples (approximately)
        _ = try harness.runSample(every: "1s", forDuration: "4s")
        
        let timeline = try harness.runTimeline(label: "com.apple.Finder")
        
        // Should show observation count in range 3-5
        // (Finder is always present, so should be in all snapshots)
        let hasReasonableCount =
            timeline.stdoutContains("Observed across 3 snapshot") ||
            timeline.stdoutContains("Observed across 4 snapshot") ||
            timeline.stdoutContains("Observed across 5 snapshot")
        
        XCTAssertTrue(
            hasReasonableCount,
            "Timeline should show approximately 4 snapshots. Got: \(timeline.stdout)"
        )
    }
    
    // MARK: - Unknown Daemon
    
    func testTimelineForUnknownDaemon() throws {
        let harness = try CLITestHarness(testName: "timelineUnknown")
        
        // Take at least one sample
        _ = try harness.runList()
        
        let result = try harness.runTimeline(label: "com.definitely.not.a.real.daemon.xyz123")
        
        // Should indicate not found
        XCTAssertTrue(
            result.stdoutContains("No observations found"),
            "Timeline should indicate daemon not found. Got: \(result.stdout)"
        )
        
        // Should not crash
        XCTAssertFalse(result.stderrContains("fatal error"))
    }
    
    // MARK: - Summary Fields
    
    func testTimelineSummaryHasAllFields() throws {
        let harness = try CLITestHarness(testName: "timelineSummaryFields")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let timeline = try harness.runTimeline(label: "com.apple.Finder")
        
        // Check all required summary fields
        XCTAssertTrue(
            timeline.stdoutContains("First observed:"),
            "Summary should have First observed"
        )
        XCTAssertTrue(
            timeline.stdoutContains("Last observed:"),
            "Summary should have Last observed"
        )
        XCTAssertTrue(
            timeline.stdoutContains("Restart count:"),
            "Summary should have Restart count"
        )
        XCTAssertTrue(
            timeline.stdoutContains("PID changes:"),
            "Summary should have PID changes"
        )
    }
    
    func testTimelineSummaryCountsAreNonNegative() throws {
        let harness = try CLITestHarness(testName: "timelineSummaryNonNeg")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let timeline = try harness.runTimeline(label: "com.apple.Finder")
        
        // Extract counts and verify they're non-negative
        if let restartCount = extractCount(from: timeline.stdout, field: "Restart count:") {
            XCTAssertGreaterThanOrEqual(restartCount, 0, "Restart count should be non-negative")
        }
        
        if let pidChanges = extractCount(from: timeline.stdout, field: "PID changes:") {
            XCTAssertGreaterThanOrEqual(pidChanges, 0, "PID changes should be non-negative")
        }
    }
    
    // MARK: - Read-Only Validation
    
    func testTimelineIsReadOnly() throws {
        let harness = try CLITestHarness(testName: "timelineReadOnly")
        
        // Create initial snapshots
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 0.5)
        _ = try harness.runList()
        
        // Get baseline snapshot count via unstable
        let unstable1 = try harness.runUnstable()
        
        // Run timeline multiple times for different daemons
        _ = try harness.runTimeline(label: "com.apple.Finder")
        _ = try harness.runTimeline(label: "com.apple.launchd")
        _ = try harness.runTimeline(label: "com.apple.something")
        
        // Verify snapshot count unchanged
        let unstable2 = try harness.runUnstable()
        
        XCTAssertEqual(
            extractAnalyzedLine(from: unstable1.stdout),
            extractAnalyzedLine(from: unstable2.stdout),
            "Timeline should not modify snapshot count"
        )
    }
    
    // MARK: - Multiple Labels
    
    func testTimelinesDifferByLabel() throws {
        let harness = try CLITestHarness(testName: "timelinesDiffer")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let finderTimeline = try harness.runTimeline(label: "com.apple.Finder")
        let launchdTimeline = try harness.runTimeline(label: "com.apple.launchd")
        
        // Both should succeed
        XCTAssertTrue(finderTimeline.succeeded)
        XCTAssertTrue(launchdTimeline.succeeded)
        
        // They should show different labels
        XCTAssertTrue(finderTimeline.stdoutContains("com.apple.Finder"))
        XCTAssertTrue(launchdTimeline.stdoutContains("com.apple.launchd"))
        
        // At minimum, the first line (label) should differ
        XCTAssertNotEqual(
            finderTimeline.stdout.components(separatedBy: "\n").first,
            launchdTimeline.stdout.components(separatedBy: "\n").first,
            "Different labels should produce different first lines"
        )
    }
    
    // MARK: - Helpers
    
    private func extractCount(from output: String, field: String) -> Int? {
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains(field) {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    let numberPart = parts[1].trimmingCharacters(in: .whitespaces)
                    return Int(numberPart)
                }
            }
        }
        return nil
    }
    
    private func extractAnalyzedLine(from output: String) -> String? {
        let lines = output.components(separatedBy: "\n")
        return lines.first { $0.contains("Analyzed") && $0.contains("snapshots") }
    }
}
