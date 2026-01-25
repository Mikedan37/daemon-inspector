import XCTest

/// Layer 4: Event Derivation Correctness
/// 
/// These tests operate on real snapshots, not mocks.
/// They validate:
/// - Events are derived correctly from real system state
/// - Time windows are preserved (not point timestamps)
/// - Unknown values are handled correctly
final class Layer4_EventDerivationTests: XCTestCase {
    
    // MARK: - Basic Event Derivation
    
    func testDiffProducesTimeWindows() throws {
        let harness = try CLITestHarness(testName: "diffTimeWindows")
        
        // Create two snapshots with some time between them
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 2.0)
        _ = try harness.runList()
        
        let diff = try harness.runDiff()
        
        // If there are any changes, they should have time windows
        // Format: "window: [timestamp → timestamp]"
        if diff.stdoutContains("window:") {
            XCTAssertTrue(
                diff.stdoutContains("→"),
                "Time windows should use arrow notation. Got: \(diff.stdout)"
            )
        }
        
        // Check the header shows a range, not a single timestamp
        XCTAssertTrue(
            diff.stdoutContains("Changes between") || diff.stdoutContains("No observable changes"),
            "Should show comparison between two times"
        )
    }
    
    func testDiffShowsChangesOrNoChanges() throws {
        let harness = try CLITestHarness(testName: "diffChangesOrNot")
        
        // Create two snapshots
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 1.0)
        _ = try harness.runList()
        
        let diff = try harness.runDiff()
        
        XCTAssertTrue(diff.succeeded)
        
        // Should explicitly say either there are changes or not
        let hasChangesSection = 
            diff.stdoutContains("Appeared:") ||
            diff.stdoutContains("Disappeared:") ||
            diff.stdoutContains("State changes:") ||
            diff.stdoutContains("No observable changes")
        
        XCTAssertTrue(
            hasChangesSection,
            "Diff should explicitly indicate changes or no changes. Got: \(diff.stdout)"
        )
    }
    
    // MARK: - Event Types
    
    func testEventTypesAreRecognized() throws {
        let harness = try CLITestHarness(testName: "eventTypes")
        
        // Take multiple samples to increase chance of observing events
        _ = try harness.runSample(every: "1s", forDuration: "5s")
        
        let diff = try harness.runDiff()
        
        // We can't guarantee specific events, but if any exist
        // they should be categorized correctly
        if !diff.stdoutContains("No observable changes") {
            // Should have recognized event categories
            let hasKnownCategory =
                diff.stdoutContains("Appeared") ||
                diff.stdoutContains("Disappeared") ||
                diff.stdoutContains("State changes") ||
                diff.stdoutContains("started") ||
                diff.stdoutContains("stopped") ||
                diff.stdoutContains("pidChanged")
            
            XCTAssertTrue(
                hasKnownCategory,
                "Events should be categorized. Got: \(diff.stdout)"
            )
        }
    }
    
    // MARK: - Timeline Event Consistency
    
    func testTimelineShowsChronologicalEvents() throws {
        let harness = try CLITestHarness(testName: "timelineChronological")
        
        // Take multiple samples
        _ = try harness.runSample(every: "1s", forDuration: "4s")
        
        // Find a daemon that likely exists (Finder is always running)
        let timeline = try harness.runTimeline(label: "com.apple.Finder")
        
        // Should show observation across snapshots
        XCTAssertTrue(
            timeline.stdoutContains("Observed across"),
            "Timeline should show observation count. Got: \(timeline.stdout)"
        )
        
        // Should have summary section
        XCTAssertTrue(
            timeline.stdoutContains("Summary:"),
            "Timeline should have summary section"
        )
        
        // Should have first/last observed times
        XCTAssertTrue(
            timeline.stdoutContains("First observed:") && timeline.stdoutContains("Last observed:"),
            "Timeline should show observation window"
        )
    }
    
    func testTimelinePreservesRestartCounts() throws {
        let harness = try CLITestHarness(testName: "timelineRestarts")
        
        // Take samples
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let timeline = try harness.runTimeline(label: "com.apple.Finder")
        
        // Restart count should be a non-negative integer
        XCTAssertTrue(
            timeline.stdoutContains("Restart count:"),
            "Timeline should show restart count"
        )
        
        // PID changes should be a non-negative integer
        XCTAssertTrue(
            timeline.stdoutContains("PID changes:"),
            "Timeline should show PID change count"
        )
    }
    
    // MARK: - Unstable Report Correctness
    
    func testUnstableReportShowsCounts() throws {
        let harness = try CLITestHarness(testName: "unstableCounts")
        
        // Take samples to get some data
        _ = try harness.runSample(every: "1s", forDuration: "4s")
        
        let unstable = try harness.runUnstable()
        
        XCTAssertTrue(unstable.succeeded)
        
        // Should have header with analysis window
        XCTAssertTrue(
            unstable.stdoutContains("Analyzed") && unstable.stdoutContains("snapshots"),
            "Unstable should report analysis scope. Got: \(unstable.stdout)"
        )
        
        // Should show time window
        XCTAssertTrue(
            unstable.stdoutContains("Window:") || unstable.stdoutContains("No instability"),
            "Unstable should show analysis window"
        )
    }
    
    func testUnstableReportShowsObservationWindow() throws {
        let harness = try CLITestHarness(testName: "unstableWindow")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let unstable = try harness.runUnstable()
        
        // If any daemons are listed, they should have observation windows
        if unstable.stdoutContains("Total events:") {
            XCTAssertTrue(
                unstable.stdoutContains("Observation window:"),
                "Unstable entries should show observation window"
            )
        }
    }
    
    // MARK: - Determinism
    
    func testEventDerivationIsDeterministic() throws {
        let harness = try CLITestHarness(testName: "eventDeterminism")
        
        // Create snapshots
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 1.0)
        _ = try harness.runList()
        
        // Run diff multiple times
        let diff1 = try harness.runDiff()
        let diff2 = try harness.runDiff()
        let diff3 = try harness.runDiff()
        
        // All should produce identical output
        XCTAssertEqual(diff1.stdout, diff2.stdout, "Diff should be deterministic (run 1 vs 2)")
        XCTAssertEqual(diff2.stdout, diff3.stdout, "Diff should be deterministic (run 2 vs 3)")
    }
    
    func testTimelineIsDeterministic() throws {
        let harness = try CLITestHarness(testName: "timelineDeterminism")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let timeline1 = try harness.runTimeline(label: "com.apple.Finder")
        let timeline2 = try harness.runTimeline(label: "com.apple.Finder")
        
        XCTAssertEqual(timeline1.stdout, timeline2.stdout, "Timeline should be deterministic")
    }
    
    func testUnstableIsDeterministic() throws {
        let harness = try CLITestHarness(testName: "unstableDeterminism")
        
        _ = try harness.runSample(every: "1s", forDuration: "3s")
        
        let unstable1 = try harness.runUnstable()
        let unstable2 = try harness.runUnstable()
        
        XCTAssertEqual(unstable1.stdout, unstable2.stdout, "Unstable should be deterministic")
    }
}
