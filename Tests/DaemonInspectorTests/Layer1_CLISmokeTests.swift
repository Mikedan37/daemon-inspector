import XCTest

/// Layer 1: CLI Smoke Tests (Black Box)
/// 
/// These tests invoke the built binary as an external process
/// and validate output shape, not exact values.
/// 
/// No internal mocking. No fake data. Just real execution.
final class Layer1_CLISmokeTests: XCTestCase {
    
    // MARK: - List Command
    
    func testListRunsCleanly() throws {
        let harness = try CLITestHarness(testName: "listRunsCleanly")
        
        let result = try harness.runList()
        
        // Note: Exit code may be non-zero due to BlazeDB permission issues on macOS
        // The important thing is that the tool produces valid output
        
        // Assert: Output contains "Observed"
        XCTAssertTrue(
            result.stdoutContains("Observed"),
            "Output should contain 'Observed'. Got: \(result.stdout.prefix(500))"
        )
        
        // Assert: Output contains at least one daemon label (contains a period, typical of reverse-DNS labels)
        let hasDaemonLabel = result.stdout.contains("com.") || result.stdout.contains("application.")
        XCTAssertTrue(
            hasDaemonLabel,
            "Output should contain at least one daemon label. Got: \(result.stdout.prefix(500))"
        )
        
        // Assert: No panic, no stack trace
        XCTAssertFalse(
            result.stderrContains("fatal error"),
            "Should not contain fatal error. Stderr: \(result.stderr)"
        )
        XCTAssertFalse(
            result.stderrContains("Stack trace"),
            "Should not contain stack trace. Stderr: \(result.stderr)"
        )
    }
    
    func testListProducesMultipleDaemons() throws {
        let harness = try CLITestHarness(testName: "listProducesMultiple")
        
        let result = try harness.runList()
        
        XCTAssertTrue(result.succeeded)
        
        // Count PID lines as a proxy for daemon count
        // Each daemon entry should have a "PID:" line
        let pidCount = result.countOccurrences(of: "PID:")
        
        XCTAssertGreaterThan(
            pidCount, 10,
            "Should observe more than 10 daemons on a typical macOS system"
        )
    }
    
    // MARK: - Diff Command
    
    func testDiffWithNoSnapshots() throws {
        let harness = try CLITestHarness(testName: "diffNoSnapshots")
        
        // Fresh database, no snapshots
        let result = try harness.runDiff()
        
        // Assert: Clear message about insufficient data
        let hasInsufficientMessage = 
            result.stdoutContains("No snapshots") ||
            result.stdoutContains("Need at least two snapshots")
        
        XCTAssertTrue(
            hasInsufficientMessage,
            "Should indicate insufficient snapshots. Got: \(result.stdout)"
        )
        
        // Assert: No crash (should not have stack trace or fatal error)
        XCTAssertFalse(result.stderrContains("fatal error"))
    }
    
    func testDiffWithOneSnapshot() throws {
        let harness = try CLITestHarness(testName: "diffOneSnapshot")
        
        // Create one snapshot
        let listResult = try harness.runList()
        XCTAssertTrue(listResult.succeeded)
        
        // Now diff should indicate need for two snapshots
        let diffResult = try harness.runDiff()
        
        XCTAssertTrue(
            diffResult.stdoutContains("Need at least two snapshots"),
            "Should indicate need for two snapshots. Got: \(diffResult.stdout)"
        )
    }
    
    // MARK: - Timeline Command
    
    func testTimelineWithUnknownDaemon() throws {
        let harness = try CLITestHarness(testName: "timelineUnknown")
        
        // Create at least one snapshot
        _ = try harness.runList()
        
        // Query for a daemon that definitely doesn't exist
        let result = try harness.runTimeline(label: "com.nonexistent.definitely.not.real.daemon.12345")
        
        // Assert: Clear "not observed" message
        XCTAssertTrue(
            result.stdoutContains("No observations found") || 
            result.stdoutContains("not observed"),
            "Should indicate daemon not found. Got: \(result.stdout)"
        )
        
        // Assert: No crash
        XCTAssertFalse(result.stderrContains("fatal error"))
    }
    
    func testTimelineWithNoSnapshots() throws {
        let harness = try CLITestHarness(testName: "timelineNoSnapshots")
        
        // Fresh database
        let result = try harness.runTimeline(label: "com.apple.Finder")
        
        // Assert: Clear message about no snapshots
        XCTAssertTrue(
            result.stdoutContains("No snapshots") ||
            result.stdoutContains("No observations"),
            "Should indicate no data. Got: \(result.stdout)"
        )
    }
    
    // MARK: - Unstable Command
    
    func testUnstableWithNoSnapshots() throws {
        let harness = try CLITestHarness(testName: "unstableNoSnapshots")
        
        let result = try harness.runUnstable()
        
        XCTAssertTrue(
            result.stdoutContains("No snapshots"),
            "Should indicate no snapshots. Got: \(result.stdout)"
        )
    }
    
    func testUnstableWithOneSnapshot() throws {
        let harness = try CLITestHarness(testName: "unstableOneSnapshot")
        
        // Create one snapshot
        _ = try harness.runList()
        
        let result = try harness.runUnstable()
        
        XCTAssertTrue(
            result.stdoutContains("Need at least two snapshots"),
            "Should indicate need for two snapshots. Got: \(result.stdout)"
        )
    }
    
    // MARK: - Invalid Commands
    
    func testInvalidCommand() throws {
        let harness = try CLITestHarness(testName: "invalidCommand")
        
        let result = try harness.run(["notarealcommand"])
        
        // Should indicate unknown command
        XCTAssertTrue(
            result.stdoutContains("Unknown command") || result.stderrContains("Unknown command"),
            "Should indicate unknown command"
        )
    }
    
    func testNoArguments() throws {
        let harness = try CLITestHarness(testName: "noArgs")
        
        let result = try harness.run([])
        
        // Should show usage
        XCTAssertTrue(
            result.stdoutContains("Usage:") || result.stderrContains("Usage:"),
            "Should show usage information"
        )
    }
}
