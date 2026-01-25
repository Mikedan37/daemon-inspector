import Foundation

/// Test harness for invoking daemon-inspector CLI as an external process.
/// 
/// This harness:
/// - Builds the binary if needed
/// - Creates isolated temporary database directories per test
/// - Captures stdout/stderr
/// - Provides assertion helpers for output validation
/// 
/// Design principle: Tests invoke the CLI as a black box.
/// No mocking of internals, no injection of fake data.
final class CLITestHarness {
    
    /// Path to the built binary
    private let binaryPath: URL
    
    /// Temporary database directory for this test
    let dbDirectory: URL
    
    /// Whether to clean up the database directory on deinit
    private let cleanupOnDeinit: Bool
    
    /// Result of a CLI invocation
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        
        var succeeded: Bool { exitCode == 0 }
        
        /// Check if stdout contains a substring (case-sensitive)
        func stdoutContains(_ substring: String) -> Bool {
            stdout.contains(substring)
        }
        
        /// Check if stderr contains a substring (case-sensitive)
        func stderrContains(_ substring: String) -> Bool {
            stderr.contains(substring)
        }
        
        /// Count occurrences of a pattern in stdout
        func countOccurrences(of pattern: String) -> Int {
            var count = 0
            var searchRange = stdout.startIndex..<stdout.endIndex
            while let range = stdout.range(of: pattern, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<stdout.endIndex
            }
            return count
        }
    }
    
    /// Initialize the test harness with an isolated database directory.
    /// 
    /// - Parameters:
    ///   - testName: Name of the test (used for directory naming)
    ///   - cleanupOnDeinit: Whether to remove the database directory when harness is deallocated
    init(testName: String, cleanupOnDeinit: Bool = true) throws {
        // Locate the binary (assume it's built)
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // DaemonInspectorTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // project root
        
        // Try release first, then debug
        var binaryURL = projectRoot
            .appendingPathComponent(".build/release/daemon-inspector")
        
        if !FileManager.default.fileExists(atPath: binaryURL.path) {
            binaryURL = projectRoot
                .appendingPathComponent(".build/debug/daemon-inspector")
        }
        
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw TestHarnessError.binaryNotFound(
                "daemon-inspector binary not found. Run 'swift build' first."
            )
        }
        
        self.binaryPath = binaryURL
        self.cleanupOnDeinit = cleanupOnDeinit
        
        // Create unique temporary directory for this test
        // Use home directory instead of /tmp to avoid macOS sandbox restrictions
        let tempBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".daemon-inspector-tests", isDirectory: true)
        let uniqueDir = tempBase.appendingPathComponent("test-\(testName)-\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(
            at: uniqueDir,
            withIntermediateDirectories: true
        )
        
        self.dbDirectory = uniqueDir
    }
    
    deinit {
        if cleanupOnDeinit {
            try? FileManager.default.removeItem(at: dbDirectory)
        }
    }
    
    /// Run a daemon-inspector command.
    /// 
    /// - Parameters:
    ///   - arguments: Command line arguments (e.g., ["list"], ["sample", "--every", "1s", "--for", "5s"])
    ///   - timeout: Maximum time to wait for command completion
    /// - Returns: Result containing exit code and captured output
    /// 
    /// Note: The list command can take 60-120 seconds on systems with 500+ daemons
    /// because each daemon is persisted individually (append-only, one-at-a-time).
    /// This is by design - correctness over speed.
    func run(_ arguments: [String], timeout: TimeInterval = 300) throws -> Result {
        // Use shell wrapper to properly redirect output
        let stdoutFile = dbDirectory.appendingPathComponent("stdout_\(UUID().uuidString).txt")
        let stderrFile = dbDirectory.appendingPathComponent("stderr_\(UUID().uuidString).txt")
        
        defer {
            try? FileManager.default.removeItem(at: stdoutFile)
            try? FileManager.default.removeItem(at: stderrFile)
        }
        
        // Build command string with proper escaping
        let escapedArgs = arguments.map { arg in
            "'\(arg.replacingOccurrences(of: "'", with: "'\\''"))'"
        }.joined(separator: " ")
        
        let exitCodeFile = dbDirectory.appendingPathComponent("exitcode_\(UUID().uuidString).txt")
        
        defer {
            try? FileManager.default.removeItem(at: exitCodeFile)
        }
        
        let shellCommand = """
        export DAEMON_INSPECTOR_DB_PATH='\(dbDirectory.path)'; \
        '\(binaryPath.path)' \(escapedArgs) \
        > '\(stdoutFile.path)' 2> '\(stderrFile.path)'; \
        echo $? > '\(exitCodeFile.path)'
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", shellCommand]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        // Read exit code from file
        let exitCodeStr = (try? String(contentsOf: exitCodeFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1"
        let exitCode = Int32(exitCodeStr) ?? 1
        
        // Read output from files
        let stdout = (try? String(contentsOf: stdoutFile, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrFile, encoding: .utf8)) ?? ""
        
        return Result(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )
    }
    
    /// Run the list command
    func runList() throws -> Result {
        try run(["list"])
    }
    
    /// Run the diff command
    func runDiff() throws -> Result {
        try run(["diff"])
    }
    
    /// Run the sample command
    func runSample(every interval: String, forDuration duration: String) throws -> Result {
        try run(["sample", "--every", interval, "--for", duration], timeout: 120)
    }
    
    /// Run the timeline command
    func runTimeline(label: String) throws -> Result {
        try run(["timeline", label])
    }
    
    /// Run the unstable command
    func runUnstable() throws -> Result {
        try run(["unstable"])
    }
    
    /// Count files in the database directory (proxy for snapshot count)
    func databaseFileCount() throws -> Int {
        let contents = try FileManager.default.contentsOfDirectory(
            at: dbDirectory,
            includingPropertiesForKeys: nil
        )
        return contents.count
    }
    
    /// Check if database directory has any files
    func hasDatabaseFiles() throws -> Bool {
        try databaseFileCount() > 0
    }
    
    enum TestHarnessError: Error, CustomStringConvertible {
        case binaryNotFound(String)
        case timeout(String)
        
        var description: String {
            switch self {
            case .binaryNotFound(let msg): return msg
            case .timeout(let msg): return msg
            }
        }
    }
}
