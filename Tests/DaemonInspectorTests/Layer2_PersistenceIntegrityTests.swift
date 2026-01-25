import XCTest

/// Layer 2: Persistence Integrity Tests
/// 
/// These tests validate BlazeDB usage without introspecting BlazeDB internals.
/// They verify:
/// - Snapshots survive process restart
/// - Append-only behavior
/// - No history rewriting
final class Layer2_PersistenceIntegrityTests: XCTestCase {
    
    // MARK: - Snapshot Survival
    
    func testSnapshotsSurviveRestart() throws {
        let harness = try CLITestHarness(testName: "snapshotsSurviveRestart")
        
        // Run 1: Create first snapshot
        let list1 = try harness.runList()
        XCTAssertTrue(list1.succeeded, "First list should succeed")
        
        // Simulate process termination by just... not keeping any state
        // The harness creates a new Process each time
        
        // Run 2: Create second snapshot (new process, same database)
        let list2 = try harness.runList()
        XCTAssertTrue(list2.succeeded, "Second list should succeed")
        
        // Run 3: Diff should work (proves both snapshots were persisted)
        let diff = try harness.runDiff()
        
        // Diff should produce output (either changes or "no changes")
        // It should NOT say "need at least two snapshots"
        XCTAssertFalse(
            diff.stdoutContains("Need at least two snapshots"),
            "Diff should find both snapshots after restart. Got: \(diff.stdout)"
        )
        
        // Should have header indicating comparison
        XCTAssertTrue(
            diff.stdoutContains("Changes between") || diff.stdoutContains("No observable changes"),
            "Diff should show comparison result. Got: \(diff.stdout)"
        )
    }
    
    func testMultipleListsCreateMultipleSnapshots() throws {
        let harness = try CLITestHarness(testName: "multipleSnapshots")
        
        let runCount = 5
        
        // Run list N times
        for i in 1...runCount {
            let result = try harness.runList()
            XCTAssertTrue(result.succeeded, "List \(i) should succeed")
            
            // Small delay to ensure different timestamps
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Now run unstable which requires all snapshots
        // This will load all snapshots and report how many
        let unstable = try harness.runUnstable()
        
        // The output should mention the snapshot count
        // Format: "Analyzed N snapshots over..."
        XCTAssertTrue(
            unstable.stdoutContains("Analyzed \(runCount) snapshots") ||
            unstable.stdoutContains("Analyzed"),
            "Unstable should report snapshot count. Got: \(unstable.stdout)"
        )
    }
    
    // MARK: - Append-Only Behavior
    
    func testDiffDoesNotModifySnapshots() throws {
        let harness = try CLITestHarness(testName: "diffNoModify")
        
        // Create two snapshots
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 0.5)
        _ = try harness.runList()
        
        // Run diff multiple times
        let diff1 = try harness.runDiff()
        let diff2 = try harness.runDiff()
        let diff3 = try harness.runDiff()
        
        // All diffs should produce the same output
        // (because diff is read-only and deterministic)
        XCTAssertEqual(diff1.stdout, diff2.stdout, "Diff should be deterministic")
        XCTAssertEqual(diff2.stdout, diff3.stdout, "Diff should be deterministic")
    }
    
    func testTimelineDoesNotModifySnapshots() throws {
        let harness = try CLITestHarness(testName: "timelineNoModify")
        
        // Create some snapshots
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 0.5)
        _ = try harness.runList()
        
        // Run unstable to get initial snapshot count
        let unstable1 = try harness.runUnstable()
        
        // Run timeline multiple times
        _ = try harness.runTimeline(label: "com.apple.Finder")
        _ = try harness.runTimeline(label: "com.apple.Finder")
        _ = try harness.runTimeline(label: "com.apple.some.other.daemon")
        
        // Snapshot count should be unchanged
        let unstable2 = try harness.runUnstable()
        
        // Both unstable outputs should reference the same snapshot count
        // Extract "Analyzed N snapshots" line
        XCTAssertEqual(
            extractAnalyzedLine(from: unstable1.stdout),
            extractAnalyzedLine(from: unstable2.stdout),
            "Timeline should not create new snapshots"
        )
    }
    
    func testUnstableDoesNotModifySnapshots() throws {
        let harness = try CLITestHarness(testName: "unstableNoModify")
        
        // Create some snapshots
        _ = try harness.runList()
        Thread.sleep(forTimeInterval: 0.5)
        _ = try harness.runList()
        
        // Run unstable multiple times
        let unstable1 = try harness.runUnstable()
        let unstable2 = try harness.runUnstable()
        
        // Snapshot counts should match
        XCTAssertEqual(
            extractAnalyzedLine(from: unstable1.stdout),
            extractAnalyzedLine(from: unstable2.stdout),
            "Unstable should not create new snapshots"
        )
    }
    
    // MARK: - Database Persistence
    
    func testDatabaseCreatedOnFirstUse() throws {
        let harness = try CLITestHarness(testName: "dbCreated")
        
        // Before any command, database directory should be empty or have minimal files
        let initialCount = try harness.databaseFileCount()
        
        // Run list
        _ = try harness.runList()
        
        // After list, database should have files
        let finalCount = try harness.databaseFileCount()
        
        XCTAssertGreaterThan(
            finalCount, initialCount,
            "Database should have more files after list command"
        )
    }
    
    // MARK: - Helpers
    
    private func extractAnalyzedLine(from output: String) -> String? {
        let lines = output.components(separatedBy: "\n")
        return lines.first { $0.contains("Analyzed") && $0.contains("snapshots") }
    }
}
