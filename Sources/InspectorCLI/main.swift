import Foundation
import Model
import Collector
import Storage
import TerminalUI
import Inspector

@main
struct DaemonInspector {
    
    // MARK: - Version Constants (Phase 7: Scriptability)
    
    /// Tool version - single source of truth
    static let toolVersion = "1.2.0"
    
    /// JSON schema version - increment on breaking changes
    static let schemaVersion = "1"
    
    // MARK: - Command Options
    
    /// Parsed command-line options
    struct CommandOptions {
        var jsonOutput: Bool = false
        var tableView: Bool = false
        var detailedView: Bool = false
        var noPager: Bool = false
        var sinceInterval: TimeInterval? = nil
        var untilInterval: TimeInterval? = nil
        // Focus filters (triage for large systems) - legacy
        var onlyRunning: Bool = false
        var onlyChanged: Bool = false
        var onlyUnknown: Bool = false
        // Phase 2: Deterministic filters
        var domainFilter: String? = nil      // gui, system, unknown
        var runningFilter: Bool = false      // --running
        var stoppedFilter: Bool = false      // --stopped
        var hasBinaryFilter: Bool = false    // --has-binary
        var noBinaryFilter: Bool = false     // --no-binary
        var labelPrefixFilter: String? = nil // --label-prefix <string>
        // Expectation mode (quiet confirmation)
        var expectStable: Bool = false
        var remainingArgs: [String] = []
    }
    
    /// Check if this is the first run (no snapshots exist yet)
    private static var isFirstRun: Bool = {
        let baseDir: URL
        if let envPath = ProcessInfo.processInfo.environment["DAEMON_INSPECTOR_DB_PATH"] {
            baseDir = URL(fileURLWithPath: envPath, isDirectory: true)
        } else {
            baseDir = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".daemon-inspector", isDirectory: true)
        }
        return !FileManager.default.fileExists(atPath: baseDir.path)
    }()
    
    /// Storage location for user information
    private static var storagePath: String {
        if let envPath = ProcessInfo.processInfo.environment["DAEMON_INSPECTOR_DB_PATH"] {
            return envPath
        }
        return "~/.daemon-inspector"
    }
    
    /// Track if hints have been shown this session (no persistence)
    private static var hintsShownThisSession = false
    
    /// Show guided usage hints for interactive first-time users
    private static func showGuidedHint(afterCommand command: String) {
        // Only show in TTY, only once per session, only on first run
        guard !hintsShownThisSession, isFirstRun, TTYDetector.isInteractive else { return }
        hintsShownThisSession = true
        
        print("")
        print("Tip: Getting started with daemon-inspector")
        
        switch command {
        case "list":
            print("  - Run 'daemon-inspector list' again to capture another snapshot")
            print("  - Then 'daemon-inspector diff' to see what changed")
            print("  - Use --json for scripting")
        case "diff":
            print("  - Use 'daemon-inspector unstable' to find flapping services")
            print("  - Use 'daemon-inspector timeline <label>' for forensic history")
        case "sample":
            print("  - After sampling, try 'daemon-inspector unstable' to find churn")
            print("  - Use 'daemon-inspector timeline <label>' to investigate specific daemons")
        default:
            print("  - Use 'daemon-inspector list' to capture current state")
            print("  - Use 'daemon-inspector diff' to see changes over time")
            print("  - Use --help for all commands")
        }
        print("")
    }
    
    static func main() {
        let args = CommandLine.arguments
        
        // Global help handling - check anywhere in args, exit cleanly
        if args.contains("--help") || args.contains("-h") {
            printUsage()
            exit(0)
        }
        
        // Version handling
        if args.contains("--version") || args.contains("-V") {
            print("daemon-inspector \(toolVersion)")
            exit(0)
        }
        
        // No command provided - show help (exit 0 for usability)
        guard args.count >= 2 else {
            printUsage()
            exit(0)
        }
        
        let command = args[1]
        
        // "help" as a command is equivalent to --help
        if command == "help" {
            printUsage()
            exit(0)
        }
        
        let options: CommandOptions
        
        do {
            options = try parseOptions(Array(args.dropFirst(2)))
        } catch {
            printError("Invalid options: \(error)")
            exit(1)
        }
        
        do {
            switch command {
            // Primary commands
            case "list":
                try runList(options: options)
            case "diff", "what-changed":
                try runDiff(options: options)
            case "sample":
                try runSample(args: options.remainingArgs)
            case "timeline", "what-happened":
                guard !options.remainingArgs.isEmpty else {
                    printError("Usage: daemon-inspector timeline <daemon-label> [--json] [--since <duration>]")
                    exit(1)
                }
                try runTimeline(label: options.remainingArgs[0], options: options)
            case "unstable", "what-flaps":
                try runUnstable(options: options)
            // Change-first commands (Phase 1)
            case "changed":
                try runChanged(options: options)
            case "appeared":
                try runAppeared(options: options)
            case "disappeared":
                try runDisappeared(options: options)
            case "churn":
                try runChurn(options: options)
            case "compare":
                try runCompare(options: options)
            // Binary inspection (v1.2)
            case "inspect":
                try runInspect(args: options.remainingArgs, options: options)
            // Pro stub (v1.3)
            case "explain":
                runExplainStub(args: options.remainingArgs)
            // Help commands
            case "why-unknown":
                printWhyUnknown()
            // Internal commands
            case "test-derive":
                EventDeriverTests.runDemo()
            case "verify":
                try runVerify()
            default:
                printError("Unknown command: \(command)")
                printUsage()
                exit(1)
            }
            
            // Show guided hints for first-time interactive users
            showGuidedHint(afterCommand: command)
            
        } catch let error as InspectorError {
            printError(error.message)
            exit(1)
        } catch {
            printError("Unexpected error: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    // MARK: - Usage & Error Handling (Phase 4)
    
    private static func printUsage() {
        print("daemon-inspector \(toolVersion) — read-only daemon introspection")
        print("This tool never modifies system state.")
        print("")
        print("Common questions:")
        print("  What daemons exist right now?     daemon-inspector list")
        print("  What changed recently?            daemon-inspector changed")
        print("  What keeps flapping?              daemon-inspector churn")
        print("  What happened to one daemon?      daemon-inspector timeline <label>")
        print("")
        print("Observation commands:")
        print("  list                              Collect and display current daemon state")
        print("  sample --every <t> --for <d>      Collect snapshots at fixed cadence")
        print("")
        print("Binary inspection (read-only):")
        print("  inspect binary <label>            Inspect binary metadata")
        print("")
        print("Pro (planned):")
        print("  explain <label>                   Narrative summary (Pro)")
        print("")
        print("Help commands:")
        print("  why-unknown                       Explain why values may be unknown")
        print("")
        print("Change-first commands:")
        print("  changed                           Show all daemons with derived events")
        print("  appeared                          Show daemons that appeared")
        print("  disappeared                       Show daemons that disappeared")
        print("  churn                             Show daemons with multiple events (sorted)")
        print("  diff                              Show changes between snapshots")
        print("  compare                           Side-by-side snapshot comparison")
        print("  timeline <label>                  Forensic history for one daemon")
        print("  unstable                          Daemons with observed instability")
        print("")
        print("Global options:")
        print("  --version, -V            Show version and exit")
        print("  --help, -h               Show this help and exit")
        print("")
        print("Output options:")
        print("  --json                   Output in JSON format (disables pager)")
        print("  --table                  Display in tabular format")
        print("  --detailed               Display in detailed format")
        print("  --no-pager               Disable interactive pager")
        print("")
        print("Time filters:")
        print("  --since <duration>       Snapshots within duration (e.g., 30m, 1h)")
        print("  --until <duration>       Snapshots older than duration")
        print("")
        print("Focus filters:")
        print("  --domain <d>             Filter by domain (gui, system, unknown)")
        print("  --running                Show only running daemons")
        print("  --stopped                Show only stopped daemons")
        print("  --has-binary             Show daemons with known binary path")
        print("  --no-binary              Show daemons without binary path")
        print("  --label-prefix <s>       Filter by label prefix")
        print("")
        print("Expectation mode:")
        print("  --expect-stable          Quiet if stable, prints diff if not (exit 1)")
        print("")
        print("Examples:")
        print("  daemon-inspector changed --since 10m")
        print("  daemon-inspector churn --domain gui")
        print("  daemon-inspector list --running --domain system")
        print("  daemon-inspector compare --since 1h")
        print("  daemon-inspector diff --expect-stable")
        print("")
        print("Pager controls (when interactive):")
        print("  j/k scroll · space/b page · g/G jump · q quit")
    }
    
    private static func printError(_ message: String) {
        // Plain language errors, no stack traces
        print("Error: \(message)")
    }
    
    /// Inspector-specific errors with plain language messages.
    /// All errors provide: cause, context, and next step.
    enum InspectorError: Error {
        case noSnapshots
        case insufficientSnapshots(required: Int, found: Int)
        case daemonNotFound(label: String)
        case databaseError(String)
        case invalidTimeFilter(String)
        case permissionDenied(path: String)
        case binaryNotFound(path: String)
        
        var message: String {
            switch self {
            case .noSnapshots:
                return """
                    No snapshots available yet.
                    
                    Next step: Run 'daemon-inspector list' to capture current daemon state.
                    """
            case .insufficientSnapshots(let required, let found):
                return """
                    Need at least \(required) snapshots to compare, found \(found).
                    
                    Next step: Run 'daemon-inspector list' to capture another snapshot.
                    """
            case .daemonNotFound(let label):
                return """
                    No observations found for '\(label)'.
                    
                    This daemon may not exist, or may not have been observed yet.
                    Try 'daemon-inspector list' to see currently visible daemons.
                    """
            case .databaseError(let msg):
                return """
                    Storage error: \(msg)
                    
                    The database may be locked or corrupted.
                    Storage location: ~/.daemon-inspector/
                    """
            case .invalidTimeFilter(let msg):
                return """
                    Invalid time filter: \(msg)
                    
                    Valid formats: 30s, 5m, 2h, 1d
                    Example: --since 30m
                    """
            case .permissionDenied(let path):
                return """
                    Permission denied: \(path)
                    
                    daemon-inspector cannot read this path.
                    This is expected for some protected system binaries.
                    """
            case .binaryNotFound(let path):
                return """
                    Binary not found: \(path)
                    
                    The file may have been moved or deleted since observation.
                    This can happen after updates or uninstalls.
                    """
            }
        }
    }
    
    // MARK: - Option Parsing (Phase 2)
    
    private static func parseOptions(_ args: [String]) throws -> CommandOptions {
        var options = CommandOptions()
        var i = 0
        
        while i < args.count {
            let arg = args[i]
            
            if arg == "--json" {
                options.jsonOutput = true
                i += 1
            } else if arg == "--table" {
                options.tableView = true
                i += 1
            } else if arg == "--detailed" {
                options.detailedView = true
                i += 1
            } else if arg == "--no-pager" {
                options.noPager = true
                i += 1
            } else if arg == "--since" {
                guard i + 1 < args.count else {
                    throw InspectorError.invalidTimeFilter("--since requires a duration value")
                }
                options.sinceInterval = try parseTimeInterval(args[i + 1])
                i += 2
            } else if arg == "--until" {
                guard i + 1 < args.count else {
                    throw InspectorError.invalidTimeFilter("--until requires a duration value")
                }
                options.untilInterval = try parseTimeInterval(args[i + 1])
                i += 2
            // Focus filters (triage for large systems)
            } else if arg == "--only-running" {
                options.onlyRunning = true
                i += 1
            } else if arg == "--only-changed" {
                options.onlyChanged = true
                i += 1
            } else if arg == "--only-unknown" {
                options.onlyUnknown = true
                i += 1
            // Expectation mode
            } else if arg == "--expect-stable" {
                options.expectStable = true
                i += 1
            // Phase 2: Deterministic filters
            } else if arg == "--domain" {
                guard i + 1 < args.count else {
                    throw InspectorError.invalidTimeFilter("--domain requires a value (gui, system, unknown)")
                }
                options.domainFilter = args[i + 1]
                i += 2
            } else if arg == "--running" {
                options.runningFilter = true
                i += 1
            } else if arg == "--stopped" {
                options.stoppedFilter = true
                i += 1
            } else if arg == "--has-binary" {
                options.hasBinaryFilter = true
                i += 1
            } else if arg == "--no-binary" {
                options.noBinaryFilter = true
                i += 1
            } else if arg == "--label-prefix" {
                guard i + 1 < args.count else {
                    throw InspectorError.invalidTimeFilter("--label-prefix requires a value")
                }
                options.labelPrefixFilter = args[i + 1]
                i += 2
            } else if arg.hasPrefix("--") {
                // Unknown option for commands that don't use generic parsing
                options.remainingArgs.append(arg)
                i += 1
            } else {
                options.remainingArgs.append(arg)
                i += 1
            }
        }
        
        return options
    }
    
    /// Determine output mode based on options and terminal state
    private static func getOutputMode(options: CommandOptions) -> TTYDetector.OutputMode {
        if options.jsonOutput {
            return .json
        }
        if options.noPager {
            return .piped
        }
        return TTYDetector.detectMode(jsonRequested: false)
    }
    
    /// Output content using appropriate mode (pager, plain, or JSON)
    private static func output(lines: [String], options: CommandOptions) {
        let mode = getOutputMode(options: options)
        
        switch mode {
        case .interactive:
            let pager = TerminalPager(lines: lines)
            pager.run()
        case .piped, .json:
            for line in lines {
                print(line)
            }
        }
    }
    
    /// Output content with orientation header (pager mode only)
    private static func outputWithHeader(
        lines: [String],
        options: CommandOptions,
        snapshotCount: Int,
        observationWindow: TimeInterval?
    ) {
        let mode = getOutputMode(options: options)
        
        switch mode {
        case .interactive:
            // Prepend orientation header in pager mode
            var allLines = OrientationHeader.build(
                snapshotCount: snapshotCount,
                observationWindow: observationWindow,
                commandContext: ""
            )
            allLines.append(contentsOf: lines)
            
            let pager = TerminalPager(lines: allLines)
            pager.run()
        case .piped, .json:
            // No header for piped/JSON output
            for line in lines {
                print(line)
            }
        }
    }
    
    /// Output content with minimal header for list command
    private static func outputListWithHeader(lines: [String], options: CommandOptions) {
        let mode = getOutputMode(options: options)
        
        switch mode {
        case .interactive:
            var allLines = OrientationHeader.buildForList(daemonCount: 0)
            allLines.append(contentsOf: lines)
            
            let pager = TerminalPager(lines: allLines)
            pager.run()
        case .piped, .json:
            for line in lines {
                print(line)
            }
        }
    }
    
    /// Filter snapshots by time window (Phase 2)
    private static func filterSnapshotsByTime(
        _ snapshots: [CollectorSnapshot],
        since: TimeInterval?,
        until: TimeInterval?
    ) -> [CollectorSnapshot] {
        let now = Date()
        
        var filtered = snapshots
        
        if let sinceInterval = since {
            let sinceDate = now.addingTimeInterval(-sinceInterval)
            filtered = filtered.filter { $0.timestamp >= sinceDate }
        }
        
        if let untilInterval = until {
            let untilDate = now.addingTimeInterval(-untilInterval)
            filtered = filtered.filter { $0.timestamp <= untilDate }
        }
        
        return filtered
    }
    
    /// Get labels of daemons that had events in recent snapshots
    private static func getRecentlyChangedLabels(since: TimeInterval?) throws -> Set<String> {
        let loader = try SnapshotLoader()
        var snapshots = try loader.loadAllSnapshots()
        
        if let sinceInterval = since {
            snapshots = filterSnapshotsByTime(snapshots, since: sinceInterval, until: nil)
        }
        
        guard snapshots.count >= 2 else {
            return []
        }
        
        let events = EventDeriver().deriveEvents(from: snapshots)
        return Set(events.map { $0.label })
    }
    
    /// Apply deterministic filters to daemons (Phase 2)
    private static func applyFilters(_ daemons: [ObservedDaemon], options: CommandOptions) -> ([ObservedDaemon], [String]) {
        var filtered = daemons
        var appliedFilters: [String] = []
        
        // Domain filter
        if let domain = options.domainFilter {
            if domain == "gui" {
                filtered = filtered.filter { $0.domain.hasPrefix("gui") }
            } else if domain == "system" {
                filtered = filtered.filter { $0.domain == "system" }
            } else if domain == "unknown" {
                filtered = filtered.filter { $0.domain == "unknown" }
            }
            appliedFilters.append("domain=\(domain)")
        }
        
        // Running/stopped filters
        if options.runningFilter || options.onlyRunning {
            filtered = filtered.filter { $0.isRunning }
            appliedFilters.append("running")
        }
        if options.stoppedFilter {
            filtered = filtered.filter { !$0.isRunning }
            appliedFilters.append("stopped")
        }
        
        // Binary filters
        if options.hasBinaryFilter {
            filtered = filtered.filter { $0.binaryPath != nil }
            appliedFilters.append("has-binary")
        }
        if options.noBinaryFilter || options.onlyUnknown {
            filtered = filtered.filter { $0.binaryPath == nil }
            appliedFilters.append("no-binary")
        }
        
        // Label prefix filter
        if let prefix = options.labelPrefixFilter {
            filtered = filtered.filter { $0.label.hasPrefix(prefix) }
            appliedFilters.append("prefix=\(prefix)")
        }
        
        return (filtered, appliedFilters)
    }
    
    /// Apply filters to events by label lookup
    private static func applyEventFilters(_ events: [DerivedDaemonEvent], daemons: [ObservedDaemon], options: CommandOptions) -> [DerivedDaemonEvent] {
        let (filteredDaemons, _) = applyFilters(daemons, options: options)
        let allowedLabels = Set(filteredDaemons.map { $0.label })
        return events.filter { allowedLabels.contains($0.label) }
    }
    
    private static func runList(options: CommandOptions) throws {
        let collector = LaunchdCollector()
        let snapshot = try collector.collect()
        
        // Apply all filters (Phase 2 unified filtering)
        let (daemons, appliedFilters) = applyFilters(snapshot.daemons, options: options)
        
        // Handle --only-changed specially (requires historical data)
        var finalDaemons = daemons
        var allFilters = appliedFilters
        if options.onlyChanged {
            if let changedLabels = try? getRecentlyChangedLabels(since: options.sinceInterval) {
                finalDaemons = finalDaemons.filter { changedLabels.contains($0.label) }
                allFilters.append("recently-changed")
            }
        }
        
        let filterDescription: String? = allFilters.isEmpty ? nil : allFilters.joined(separator: ", ")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // Determine view mode:
        // - JSON: exact JSON output
        // - --detailed: explicit detailed view
        // - --table: explicit table view
        // - TTY + no explicit flag: default to table (more scannable)
        // - Piped + no explicit flag: default to detailed (more scriptable)
        let useTableView = options.tableView || 
            (!options.jsonOutput && !options.detailedView && TTYDetector.isInteractive)
        
        // Build count description
        let countDesc: String
        if let filter = filterDescription {
            countDesc = "\(finalDaemons.count) daemon(s) (\(filter)) at \(formatter.string(from: snapshot.timestamp))"
        } else {
            countDesc = "\(finalDaemons.count) daemon(s) at \(formatter.string(from: snapshot.timestamp))"
        }
        
        if options.jsonOutput {
            // JSON output - no pager, exact JSON
            let json: [String: Any] = [
                "command": "list",
                "timestamp": formatter.string(from: snapshot.timestamp),
                "daemon_count": finalDaemons.count,
                "filter": filterDescription as Any,
                "daemons": finalDaemons.sorted(by: { $0.label < $1.label }).map { daemon -> [String: Any?] in
                    [
                        "label": daemon.label,
                        "pid": daemon.pid,
                        "is_running": daemon.isRunning,
                        "domain": daemon.domain,
                        "binary_path": daemon.binaryPath
                    ]
                }
            ]
            printJSON(json)
        } else if useTableView {
            // Table view (default in TTY)
            var lines: [String] = []
            lines.append("Observed \(countDesc)")
            lines.append("")
            lines.append(contentsOf: TableRenderer.render(daemons: finalDaemons))
            
            outputListWithHeader(lines: lines, options: options)
        } else {
            // Detailed view
            var lines: [String] = []
            lines.append("Observed \(countDesc)")
            lines.append("")
            
            for daemon in finalDaemons.sorted(by: { $0.label < $1.label }) {
                let pidStr = daemon.pid.map { String($0) } ?? "-"
                let status = daemon.isRunning ? "running" : "not running"
                lines.append(daemon.label)
                lines.append("  PID: \(pidStr)")
                lines.append("  Status: \(status)")
                lines.append("  Domain: \(daemon.domain)")
                if let path = daemon.binaryPath {
                    lines.append("  Binary: \(path)")
                }
                lines.append("")
            }
            
            outputListWithHeader(lines: lines, options: options)
        }
        
        // First-run message (shown once, before first persist)
        let showFirstRunMessage = isFirstRun && !options.jsonOutput
        
        // Persist (after display so user sees output first)
        do {
            let store = try BlazeStore()
            try persist(snapshot: snapshot, collectorName: collector.name, store: store)
            
            // Show storage location on first run only
            if showFirstRunMessage {
                print("")
                print("Snapshots stored at: \(storagePath)")
            }
        } catch {
            // Plain language error, don't crash
            printError("Failed to persist snapshot: \(error.localizedDescription)")
        }
    }
    
    private static func persist(snapshot: CollectorSnapshot, collectorName: String, store: BlazeStore) throws {
        
        let dbSnapshot = DBSnapshot(
            id: snapshot.id,
            collector: collectorName,
            timestamp: snapshot.timestamp
        )
        
        try store.snapshots.insert(dbSnapshot)
        
        for daemon in snapshot.daemons {
            let record = DBObservedDaemon(
                snapshotID: snapshot.id,
                label: daemon.label,
                domain: daemon.domain,
                pid: daemon.pid,
                isRunning: daemon.isRunning,
                binaryPath: daemon.binaryPath,
                observedAt: daemon.observedAt
            )
            
            try store.daemons.insert(record)
        }
    }
    
    private static func runDiff(options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        
        // Load snapshots based on time filter or latest 2
        var snapshots: [CollectorSnapshot]
        
        if options.sinceInterval != nil || options.untilInterval != nil {
            // Phase 2: Time-filtered comparison
            let allSnapshots = try loader.loadAllSnapshots()
            snapshots = filterSnapshotsByTime(allSnapshots, since: options.sinceInterval, until: options.untilInterval)
            
            if snapshots.count < 2 {
                throw InspectorError.invalidTimeFilter(
                    "Time filter returned \(snapshots.count) snapshot(s). Need at least 2 for comparison."
                )
            }
        } else {
            snapshots = try loader.loadLatestSnapshots(limit: 2)
        }
        
        guard snapshots.count >= 2 else {
            if snapshots.count == 0 {
                throw InspectorError.noSnapshots
            } else {
                throw InspectorError.insufficientSnapshots(required: 2, found: snapshots.count)
            }
        }
        
        let events = EventDeriver().deriveEvents(from: snapshots)
        
        let firstSnapshot = snapshots.first!
        let lastSnapshot = snapshots.last!
        
        // --expect-stable: quiet confirmation mode
        if options.expectStable {
            if events.isEmpty {
                // Stable - quiet confirmation
                print("Stable. No changes observed.")
                return
            } else {
                // Not stable - show diff and exit non-zero
                print("Changes detected:")
                print("")
                let lines = formatDiffLines(events, from: firstSnapshot, to: lastSnapshot)
                for line in lines {
                    print(line)
                }
                exit(1)
            }
        }
        
        if options.jsonOutput {
            // JSON output
            printDiffJSON(events, from: firstSnapshot, to: lastSnapshot)
        } else {
            let lines = formatDiffLines(events, from: firstSnapshot, to: lastSnapshot)
            let observationWindow = lastSnapshot.timestamp.timeIntervalSince(firstSnapshot.timestamp)
            outputWithHeader(
                lines: lines,
                options: options,
                snapshotCount: snapshots.count,
                observationWindow: observationWindow
            )
        }
    }
    
    // MARK: - JSON Output (Phase 3 + Phase 7)
    
    /// Print JSON with version metadata.
    ///
    /// OUTPUT CONTRACT (see docs/OUTPUT_CONTRACTS.md):
    /// - All JSON includes _meta.toolVersion and _meta.schemaVersion
    /// - schemaVersion increments on breaking changes
    /// - New fields may be added without version bump
    /// - Existing fields will not be removed or change type
    private static func printJSON(_ dict: [String: Any]) {
        // Add version metadata to all JSON outputs (Phase 7: Scriptability)
        var output = dict
        output["_meta"] = [
            "toolVersion": toolVersion,
            "schemaVersion": schemaVersion
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } catch {
            printError("Failed to serialize JSON: \(error.localizedDescription)")
        }
    }
    
    private static func eventToJSON(_ event: DerivedDaemonEvent) -> [String: Any?] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return [
            "label": event.label,
            "type": event.type.rawValue,
            "window_start": formatter.string(from: event.timeWindow.lowerBound),
            "window_end": formatter.string(from: event.timeWindow.upperBound),
            "details": event.details
        ]
    }
    
    /// Format diff output as lines
    private static func formatDiffLines(
        _ events: [DerivedDaemonEvent],
        from: CollectorSnapshot,
        to: CollectorSnapshot
    ) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var lines: [String] = []
        
        lines.append("Changes between \(formatter.string(from: from.timestamp)) and \(formatter.string(from: to.timestamp))")
        lines.append("")
        
        if events.isEmpty {
            lines.append("No observable changes between snapshots.")
            lines.append("")
            lines.append("All observed daemons maintained stable state during this window.")
            return lines
        }
        
        // Group events by type
        let grouped = Dictionary(grouping: events) { $0.type }
        
        // Sort by type order, then by label
        let sortedGroups = grouped.sorted { $0.key.sortOrder < $1.key.sortOrder }
        
        for (type, group) in sortedGroups {
            lines.append("\(type.displayName):")
            
            for event in group.sorted(by: { $0.label < $1.label }) {
                lines.append("  \(type.symbol) \(event.label)")
                lines.append("    window: [\(formatter.string(from: event.timeWindow.lowerBound)) → \(formatter.string(from: event.timeWindow.upperBound))]")
                
                if let details = event.details {
                    lines.append("    details: \(details)")
                }
            }
            
            lines.append("")
        }
        
        return lines
    }
    
    private static func printDiffJSON(
        _ events: [DerivedDaemonEvent],
        from: CollectorSnapshot,
        to: CollectorSnapshot
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let json: [String: Any] = [
            "command": "diff",
            "from_timestamp": formatter.string(from: from.timestamp),
            "to_timestamp": formatter.string(from: to.timestamp),
            "event_count": events.count,
            "has_changes": !events.isEmpty,
            "events": events.map { eventToJSON($0) }
        ]
        
        printJSON(json)
    }
    
    // MARK: - Timeline Command
    
    private static func runTimeline(label: String, options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        
        // Load all snapshots containing the daemon label
        var snapshots = try loader.loadSnapshotsContaining(daemonLabel: label)
        
        // Apply time filter (Phase 2)
        if options.sinceInterval != nil || options.untilInterval != nil {
            snapshots = filterSnapshotsByTime(snapshots, since: options.sinceInterval, until: options.untilInterval)
        }
        
        // Handle no snapshots case
        if snapshots.isEmpty {
            let allSnapshots = try loader.loadLatestSnapshots(limit: 1)
            if allSnapshots.isEmpty {
                throw InspectorError.noSnapshots
            } else {
                throw InspectorError.daemonNotFound(label: label)
            }
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // Derive events from snapshots
        let allEvents = EventDeriver().deriveEvents(from: snapshots)
        
        // Filter events to only this daemon label
        let events = allEvents.filter { $0.label == label }
        
        // Compute summary
        let firstObserved = snapshots.first!.timestamp
        let lastObserved = snapshots.last!.timestamp
        let duration = lastObserved.timeIntervalSince(firstObserved)
        
        // Count restarts
        let restartCount = countRestarts(events: events)
        
        // Count PID changes
        let pidChangeCount = events.filter { $0.type == .pidChanged }.count
        
        // Phase 1: Get domain from most recent observation
        let latestSnapshot = snapshots.last!
        let daemonInLatest = latestSnapshot.daemons.first { $0.label == label }
        let domain = daemonInLatest?.domain ?? "unknown"
        
        if options.jsonOutput {
            // JSON output
            let json: [String: Any] = [
                "command": "timeline",
                "label": label,
                "domain": domain,
                "snapshot_count": snapshots.count,
                "duration": formatDuration(duration),
                "first_observed": formatter.string(from: firstObserved),
                "last_observed": formatter.string(from: lastObserved),
                "restart_count": restartCount,
                "pid_change_count": pidChangeCount,
                "event_count": events.count,
                "events": events.sorted { $0.timeWindow.lowerBound < $1.timeWindow.lowerBound }.map { eventToJSON($0) }
            ]
            printJSON(json)
        } else {
            // Build lines for pager
            var lines: [String] = []
            
            // Contextual header with domain
            lines.append(label)
            lines.append("Domain: \(domain)")
            lines.append("Observed across \(snapshots.count) snapshot(s) (\(formatDuration(duration)))")
            lines.append("")
            
            // Events section
            if !events.isEmpty {
                lines.append("Events:")
                lines.append("(Times shown as windows, not exact timestamps)")
                lines.append("")
                
                let sortedEvents = events.sorted { $0.timeWindow.lowerBound < $1.timeWindow.lowerBound }
                
                for event in sortedEvents {
                    lines.append("  \(event.type.rawValue)")
                    lines.append("    window: [\(formatter.string(from: event.timeWindow.lowerBound)) → \(formatter.string(from: event.timeWindow.upperBound))]")
                    
                    if let details = event.details {
                        lines.append("    \(details)")
                    }
                    lines.append("")
                }
            } else {
                // Empty state - no events but daemon was observed
                lines.append("No state changes observed.")
                lines.append("The daemon maintained stable state during this window.")
                lines.append("")
            }
            
            // Summary
            lines.append("Summary:")
            lines.append("  First observed: \(formatter.string(from: firstObserved))")
            lines.append("  Last observed: \(formatter.string(from: lastObserved))")
            lines.append("  Restart count: \(restartCount)")
            lines.append("  PID changes: \(pidChangeCount)")
            
            outputWithHeader(
                lines: lines,
                options: options,
                snapshotCount: snapshots.count,
                observationWindow: duration
            )
        }
    }
    
    /// Count restarts: a restart is a started event where there was a prior stopped event
    private static func countRestarts(events: [DerivedDaemonEvent]) -> Int {
        // Sort events chronologically
        let sorted = events.sorted { $0.timeWindow.lowerBound < $1.timeWindow.lowerBound }
        
        var restartCount = 0
        var sawStopped = false
        
        for event in sorted {
            if event.type == .stopped {
                sawStopped = true
            } else if event.type == .started && sawStopped {
                restartCount += 1
                sawStopped = false
            }
        }
        
        // pidChanged also implies restart
        restartCount += events.filter { $0.type == .pidChanged }.count
        
        return restartCount
    }
    
    /// Format duration for display
    private static func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return "<1s"
        } else if interval < 60 {
            return String(format: "%.0fs", interval)
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            if seconds == 0 {
                return "\(minutes)m"
            }
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(minutes)m"
        }
    }
    
    // MARK: - Unstable Command
    
    /// Instability counts for a single daemon
    private struct DaemonInstability {
        let label: String
        let domain: String
        let startedCount: Int
        let stoppedCount: Int
        let pidChangedCount: Int
        let appearedCount: Int
        let disappearedCount: Int
        let firstObserved: Date
        let lastObserved: Date
        
        /// Total churn: sum of all instability indicators
        var totalChurn: Int {
            startedCount + stoppedCount + pidChangedCount + appearedCount + disappearedCount
        }
        
        /// Restart count: stopped->started pairs + pidChanged
        var restartCount: Int {
            min(startedCount, stoppedCount) + pidChangedCount
        }
        
        /// Observation duration
        var observationDuration: TimeInterval {
            lastObserved.timeIntervalSince(firstObserved)
        }
    }
    
    private static func runUnstable(options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        
        // Load all snapshots
        var snapshots = try loader.loadAllSnapshots()
        
        // Apply time filter (Phase 2)
        if options.sinceInterval != nil || options.untilInterval != nil {
            snapshots = filterSnapshotsByTime(snapshots, since: options.sinceInterval, until: options.untilInterval)
        }
        
        // Handle edge cases (Phase 4)
        if snapshots.isEmpty {
            throw InspectorError.noSnapshots
        }
        
        if snapshots.count < 2 {
            throw InspectorError.insufficientSnapshots(required: 2, found: snapshots.count)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let firstSnapshot = snapshots.first!
        let lastSnapshot = snapshots.last!
        let duration = lastSnapshot.timestamp.timeIntervalSince(firstSnapshot.timestamp)
        
        // Build domain lookup from latest snapshot
        var domainByLabel: [String: String] = [:]
        for daemon in lastSnapshot.daemons {
            domainByLabel[daemon.label] = daemon.domain
        }
        
        // Derive all events
        let allEvents = EventDeriver().deriveEvents(from: snapshots)
        
        if allEvents.isEmpty {
            if options.jsonOutput {
                let json: [String: Any] = [
                    "command": "unstable",
                    "snapshot_count": snapshots.count,
                    "duration": formatDuration(duration),
                    "from_timestamp": formatter.string(from: firstSnapshot.timestamp),
                    "to_timestamp": formatter.string(from: lastSnapshot.timestamp),
                    "daemon_count": 0,
                    "daemons": []
                ]
                printJSON(json)
            } else {
                // Improved empty state
                let lines = EmptyStateMessage.noInstability(
                    snapshotsExamined: snapshots.count,
                    window: formatDuration(duration)
                )
                outputWithHeader(
                    lines: lines,
                    options: options,
                    snapshotCount: snapshots.count,
                    observationWindow: duration
                )
            }
            return
        }
        
        // Group events by daemon label
        let eventsByLabel = Dictionary(grouping: allEvents) { $0.label }
        
        // Compute instability for each daemon
        var instabilities: [DaemonInstability] = []
        
        for (label, events) in eventsByLabel {
            let startedCount = events.filter { $0.type == .started }.count
            let stoppedCount = events.filter { $0.type == .stopped }.count
            let pidChangedCount = events.filter { $0.type == .pidChanged }.count
            let appearedCount = events.filter { $0.type == .appeared }.count
            let disappearedCount = events.filter { $0.type == .disappeared }.count
            
            let sortedEvents = events.sorted { $0.timeWindow.lowerBound < $1.timeWindow.lowerBound }
            let firstObserved = sortedEvents.first!.timeWindow.lowerBound
            let lastObserved = sortedEvents.last!.timeWindow.upperBound
            
            // Phase 1: Include domain
            let domain = domainByLabel[label] ?? "unknown"
            
            let instability = DaemonInstability(
                label: label,
                domain: domain,
                startedCount: startedCount,
                stoppedCount: stoppedCount,
                pidChangedCount: pidChangedCount,
                appearedCount: appearedCount,
                disappearedCount: disappearedCount,
                firstObserved: firstObserved,
                lastObserved: lastObserved
            )
            
            instabilities.append(instability)
        }
        
        // Sort by total churn (most unstable first)
        let sorted = instabilities.sorted { $0.totalChurn > $1.totalChurn }
        
        if options.jsonOutput {
            // JSON output
            let json: [String: Any] = [
                "command": "unstable",
                "snapshot_count": snapshots.count,
                "duration": formatDuration(duration),
                "from_timestamp": formatter.string(from: firstSnapshot.timestamp),
                "to_timestamp": formatter.string(from: lastSnapshot.timestamp),
                "daemon_count": sorted.count,
                "daemons": sorted.map { inst -> [String: Any] in
                    [
                        "label": inst.label,
                        "domain": inst.domain,
                        "total_events": inst.totalChurn,
                        "restart_count": inst.restartCount,
                        "started": inst.startedCount,
                        "stopped": inst.stoppedCount,
                        "pid_changed": inst.pidChangedCount,
                        "appeared": inst.appearedCount,
                        "disappeared": inst.disappearedCount,
                        "observation_window": formatDuration(inst.observationDuration)
                    ]
                }
            ]
            printJSON(json)
        } else {
            // Build lines for pager
            var lines: [String] = []
            
            // Report header
            lines.append("Instability Report")
            lines.append("Analyzed \(snapshots.count) snapshots over \(formatDuration(duration))")
            lines.append("Window: [\(formatter.string(from: firstSnapshot.timestamp)) → \(formatter.string(from: lastSnapshot.timestamp))]")
            lines.append("")
            lines.append("Daemons with observed instability: \(sorted.count)")
            lines.append("(Sorted by total state changes, most unstable first)")
            lines.append("")
            
            // Group by domain
            let byDomain = Dictionary(grouping: sorted) { $0.domain }
            let domainOrder = ["system", "gui", "user", "unknown"]
            let sortedDomains = byDomain.keys.sorted { 
                (domainOrder.firstIndex(of: $0) ?? 99) < (domainOrder.firstIndex(of: $1) ?? 99) 
            }
            
            for domain in sortedDomains {
                guard let domainInstabilities = byDomain[domain] else { continue }
                
                lines.append("[\(domain)] (\(domainInstabilities.count) daemons)")
                lines.append("")
                
                for instability in domainInstabilities {
                    // Show churn relative to observation window
                    let churnContext = "\(instability.totalChurn) events over \(formatDuration(instability.observationDuration))"
                    
                    lines.append("  \(instability.label)")
                    lines.append("    Churn: \(churnContext)")
                    
                    var details: [String] = []
                    if instability.restartCount > 0 {
                        details.append("restarts: \(instability.restartCount)")
                    }
                    if instability.pidChangedCount > 0 {
                        details.append("PID changes: \(instability.pidChangedCount)")
                    }
                    if instability.startedCount > 0 {
                        details.append("started: \(instability.startedCount)")
                    }
                    if instability.stoppedCount > 0 {
                        details.append("stopped: \(instability.stoppedCount)")
                    }
                    if instability.appearedCount > 0 {
                        details.append("appeared: \(instability.appearedCount)")
                    }
                    if instability.disappearedCount > 0 {
                        details.append("disappeared: \(instability.disappearedCount)")
                    }
                    
                    if !details.isEmpty {
                        lines.append("    Breakdown: \(details.joined(separator: ", "))")
                    }
                    lines.append("")
                }
            }
            
            outputWithHeader(
                lines: lines,
                options: options,
                snapshotCount: snapshots.count,
                observationWindow: duration
            )
        }
    }
    
    // MARK: - Phase 1: Change-First Commands
    
    /// Show all daemons with derived events (grouped by event type)
    private static func runChanged(options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        var snapshots = try loader.loadAllSnapshots()
        
        if options.sinceInterval != nil || options.untilInterval != nil {
            snapshots = filterSnapshotsByTime(snapshots, since: options.sinceInterval, until: options.untilInterval)
        }
        
        guard snapshots.count >= 2 else {
            if snapshots.isEmpty {
                throw InspectorError.noSnapshots
            }
            throw InspectorError.insufficientSnapshots(required: 2, found: snapshots.count)
        }
        
        let allEvents = EventDeriver().deriveEvents(from: snapshots)
        
        // Get current daemon state for filtering
        let currentDaemons = snapshots.last?.daemons ?? []
        let events = applyEventFilters(allEvents, daemons: currentDaemons, options: options)
        
        let firstSnapshot = snapshots.first!
        let lastSnapshot = snapshots.last!
        let duration = lastSnapshot.timestamp.timeIntervalSince(firstSnapshot.timestamp)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if options.jsonOutput {
            let json: [String: Any] = [
                "command": "changed",
                "snapshot_count": snapshots.count,
                "duration": formatDuration(duration),
                "event_count": events.count,
                "events": events.map { eventToJSON($0) }
            ]
            printJSON(json)
        } else {
            var lines: [String] = []
            
            if events.isEmpty {
                lines.append("No changes observed.")
                lines.append("")
                lines.append("All daemons maintained stable state during this window.")
                lines.append("(\(snapshots.count) snapshots examined over \(formatDuration(duration)))")
            } else {
                lines.append("Changed daemons: \(Set(events.map { $0.label }).count)")
                lines.append("Total events: \(events.count)")
                lines.append("Window: \(formatDuration(duration))")
                lines.append("")
                
                // Group by event type
                let byType = Dictionary(grouping: events) { $0.type }
                let typeOrder: [DaemonEventType] = [.appeared, .disappeared, .started, .stopped, .pidChanged, .binaryPathChanged]
                
                for eventType in typeOrder {
                    guard let typeEvents = byType[eventType], !typeEvents.isEmpty else { continue }
                    
                    lines.append("\(eventType.rawValue.uppercased()) (\(typeEvents.count)):")
                    for event in typeEvents.sorted(by: { $0.label < $1.label }) {
                        lines.append("  \(event.label)")
                        lines.append("    window: [\(formatter.string(from: event.timeWindow.lowerBound)) → \(formatter.string(from: event.timeWindow.upperBound))]")
                        if let details = event.details {
                            lines.append("    \(details)")
                        }
                    }
                    lines.append("")
                }
            }
            
            outputWithHeader(
                lines: lines,
                options: options,
                snapshotCount: snapshots.count,
                observationWindow: duration
            )
        }
    }
    
    /// Show daemons that appeared (present later but not earlier)
    private static func runAppeared(options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        var snapshots = try loader.loadAllSnapshots()
        
        if options.sinceInterval != nil || options.untilInterval != nil {
            snapshots = filterSnapshotsByTime(snapshots, since: options.sinceInterval, until: options.untilInterval)
        }
        
        guard snapshots.count >= 2 else {
            if snapshots.isEmpty { throw InspectorError.noSnapshots }
            throw InspectorError.insufficientSnapshots(required: 2, found: snapshots.count)
        }
        
        let allEvents = EventDeriver().deriveEvents(from: snapshots)
        let appearedEvents = allEvents.filter { $0.type == .appeared }
        
        let currentDaemons = snapshots.last?.daemons ?? []
        let events = applyEventFilters(appearedEvents, daemons: currentDaemons, options: options)
        
        let duration = snapshots.last!.timestamp.timeIntervalSince(snapshots.first!.timestamp)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if options.jsonOutput {
            let json: [String: Any] = [
                "command": "appeared",
                "snapshot_count": snapshots.count,
                "duration": formatDuration(duration),
                "count": events.count,
                "daemons": events.map { eventToJSON($0) }
            ]
            printJSON(json)
        } else {
            var lines: [String] = []
            
            if events.isEmpty {
                lines.append("No daemons appeared during this window.")
                lines.append("(\(snapshots.count) snapshots examined over \(formatDuration(duration)))")
            } else {
                lines.append("Appeared: \(events.count) daemon(s)")
                lines.append("Window: \(formatDuration(duration))")
                lines.append("")
                
                for event in events.sorted(by: { $0.label < $1.label }) {
                    lines.append("  \(event.label)")
                    lines.append("    window: [\(formatter.string(from: event.timeWindow.lowerBound)) → \(formatter.string(from: event.timeWindow.upperBound))]")
                }
            }
            
            outputWithHeader(lines: lines, options: options, snapshotCount: snapshots.count, observationWindow: duration)
        }
    }
    
    /// Show daemons that disappeared (present earlier but missing later)
    private static func runDisappeared(options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        var snapshots = try loader.loadAllSnapshots()
        
        if options.sinceInterval != nil || options.untilInterval != nil {
            snapshots = filterSnapshotsByTime(snapshots, since: options.sinceInterval, until: options.untilInterval)
        }
        
        guard snapshots.count >= 2 else {
            if snapshots.isEmpty { throw InspectorError.noSnapshots }
            throw InspectorError.insufficientSnapshots(required: 2, found: snapshots.count)
        }
        
        let allEvents = EventDeriver().deriveEvents(from: snapshots)
        let disappearedEvents = allEvents.filter { $0.type == .disappeared }
        
        // Use first snapshot for filtering disappeared daemons
        let earlierDaemons = snapshots.first?.daemons ?? []
        let events = applyEventFilters(disappearedEvents, daemons: earlierDaemons, options: options)
        
        let duration = snapshots.last!.timestamp.timeIntervalSince(snapshots.first!.timestamp)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if options.jsonOutput {
            let json: [String: Any] = [
                "command": "disappeared",
                "snapshot_count": snapshots.count,
                "duration": formatDuration(duration),
                "count": events.count,
                "daemons": events.map { eventToJSON($0) }
            ]
            printJSON(json)
        } else {
            var lines: [String] = []
            
            if events.isEmpty {
                lines.append("No daemons disappeared during this window.")
                lines.append("(\(snapshots.count) snapshots examined over \(formatDuration(duration)))")
            } else {
                lines.append("Disappeared: \(events.count) daemon(s)")
                lines.append("Window: \(formatDuration(duration))")
                lines.append("")
                
                for event in events.sorted(by: { $0.label < $1.label }) {
                    lines.append("  \(event.label)")
                    lines.append("    window: [\(formatter.string(from: event.timeWindow.lowerBound)) → \(formatter.string(from: event.timeWindow.upperBound))]")
                }
            }
            
            outputWithHeader(lines: lines, options: options, snapshotCount: snapshots.count, observationWindow: duration)
        }
    }
    
    /// Show daemons with more than one event (sorted by count)
    private static func runChurn(options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        var snapshots = try loader.loadAllSnapshots()
        
        if options.sinceInterval != nil || options.untilInterval != nil {
            snapshots = filterSnapshotsByTime(snapshots, since: options.sinceInterval, until: options.untilInterval)
        }
        
        guard snapshots.count >= 2 else {
            if snapshots.isEmpty { throw InspectorError.noSnapshots }
            throw InspectorError.insufficientSnapshots(required: 2, found: snapshots.count)
        }
        
        let allEvents = EventDeriver().deriveEvents(from: snapshots)
        let currentDaemons = snapshots.last?.daemons ?? []
        let events = applyEventFilters(allEvents, daemons: currentDaemons, options: options)
        
        // Group by label and count
        let byLabel = Dictionary(grouping: events) { $0.label }
        let churning = byLabel.filter { $0.value.count > 1 }
            .map { (label: $0.key, events: $0.value, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        
        let duration = snapshots.last!.timestamp.timeIntervalSince(snapshots.first!.timestamp)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if options.jsonOutput {
            let json: [String: Any] = [
                "command": "churn",
                "snapshot_count": snapshots.count,
                "duration": formatDuration(duration),
                "count": churning.count,
                "daemons": churning.map { entry -> [String: Any] in
                    [
                        "label": entry.label,
                        "event_count": entry.count,
                        "events": entry.events.map { eventToJSON($0) }
                    ]
                }
            ]
            printJSON(json)
        } else {
            var lines: [String] = []
            
            if churning.isEmpty {
                lines.append("No churning daemons detected.")
                lines.append("")
                lines.append("All daemons had at most one state change.")
                lines.append("(\(snapshots.count) snapshots examined over \(formatDuration(duration)))")
            } else {
                lines.append("Churning daemons: \(churning.count)")
                lines.append("(Daemons with multiple events, sorted by count)")
                lines.append("Window: \(formatDuration(duration))")
                lines.append("")
                
                // Phase 6: Micro-orientation note
                lines.append("Note: Frequent events indicate repeated lifecycle transitions.")
                lines.append("Times shown as observation windows, not exact timestamps.")
                lines.append("")
                
                for entry in churning {
                    lines.append("  \(entry.label)")
                    lines.append("    Events: \(entry.count)")
                    
                    // Summarize event types
                    let typeCounts = Dictionary(grouping: entry.events) { $0.type }
                        .mapValues { $0.count }
                        .sorted { $0.value > $1.value }
                    let summary = typeCounts.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")
                    lines.append("    Breakdown: \(summary)")
                    lines.append("")
                }
            }
            
            outputWithHeader(lines: lines, options: options, snapshotCount: snapshots.count, observationWindow: duration)
        }
    }
    
    // MARK: - Phase 5: Compare Command
    
    /// Side-by-side snapshot comparison
    private static func runCompare(options: CommandOptions) throws {
        let loader = try SnapshotLoader()
        var snapshots = try loader.loadAllSnapshots()
        
        if options.sinceInterval != nil || options.untilInterval != nil {
            snapshots = filterSnapshotsByTime(snapshots, since: options.sinceInterval, until: options.untilInterval)
        }
        
        guard snapshots.count >= 2 else {
            if snapshots.isEmpty { throw InspectorError.noSnapshots }
            throw InspectorError.insufficientSnapshots(required: 2, found: snapshots.count)
        }
        
        let firstSnapshot = snapshots.first!
        let lastSnapshot = snapshots.last!
        let allEvents = EventDeriver().deriveEvents(from: snapshots)
        
        let duration = lastSnapshot.timestamp.timeIntervalSince(firstSnapshot.timestamp)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // Categorize events
        let appeared = allEvents.filter { $0.type == .appeared }
        let disappeared = allEvents.filter { $0.type == .disappeared }
        let changed = allEvents.filter { $0.type != .appeared && $0.type != .disappeared }
        
        // Find unchanged daemons
        let changedLabels = Set(allEvents.map { $0.label })
        let allLabels = Set(firstSnapshot.daemons.map { $0.label }).union(Set(lastSnapshot.daemons.map { $0.label }))
        let unchangedLabels = allLabels.subtracting(changedLabels)
        
        if options.jsonOutput {
            let json: [String: Any] = [
                "command": "compare",
                "from": formatter.string(from: firstSnapshot.timestamp),
                "to": formatter.string(from: lastSnapshot.timestamp),
                "duration": formatDuration(duration),
                "appeared": appeared.map { eventToJSON($0) },
                "disappeared": disappeared.map { eventToJSON($0) },
                "changed": changed.map { eventToJSON($0) },
                "unchanged_count": unchangedLabels.count
            ]
            printJSON(json)
        } else {
            var lines: [String] = []
            
            lines.append("Comparison")
            lines.append("From: \(formatter.string(from: firstSnapshot.timestamp))")
            lines.append("To:   \(formatter.string(from: lastSnapshot.timestamp))")
            lines.append("Duration: \(formatDuration(duration))")
            lines.append("")
            
            // Appeared section
            lines.append("APPEARED (\(appeared.count)):")
            if appeared.isEmpty {
                lines.append("  (none)")
            } else {
                for event in appeared.sorted(by: { $0.label < $1.label }) {
                    lines.append("  + \(event.label)")
                }
            }
            lines.append("")
            
            // Disappeared section
            lines.append("DISAPPEARED (\(disappeared.count)):")
            if disappeared.isEmpty {
                lines.append("  (none)")
            } else {
                for event in disappeared.sorted(by: { $0.label < $1.label }) {
                    lines.append("  - \(event.label)")
                }
            }
            lines.append("")
            
            // Changed section
            lines.append("CHANGED (\(changed.count)):")
            if changed.isEmpty {
                lines.append("  (none)")
            } else {
                for event in changed.sorted(by: { $0.label < $1.label }) {
                    let details = event.details ?? event.type.rawValue
                    lines.append("  ~ \(event.label) (\(details))")
                }
            }
            lines.append("")
            
            // Unchanged summary (collapsed)
            lines.append("UNCHANGED: \(unchangedLabels.count) daemon(s)")
            lines.append("")
            
            outputWithHeader(lines: lines, options: options, snapshotCount: snapshots.count, observationWindow: duration)
        }
    }
    
    // MARK: - Why Unknown Helper
    
    private static func printWhyUnknown() {
        print("Why values may be unknown in daemon-inspector")
        print(String(repeating: "=", count: 50))
        print("")
        print("PID: - (nil)")
        print("  The service is loaded but not currently running.")
        print("  This is normal for:")
        print("    - On-demand services (activated by socket, timer, or event)")
        print("    - Crashed services awaiting restart")
        print("    - Services with KeepAlive = false")
        print("  This is not an error. The service may run later.")
        print("")
        print("Binary Path: - (nil)")
        print("  launchd does not expose the binary path for this service.")
        print("  Common reasons:")
        print("    - XPC services (bundled within apps)")
        print("    - App-embedded launch agents")
        print("    - System internals with private configurations")
        print("    - Services defined inline rather than via plist")
        print("  Use 'inspect binary <label>' to investigate if a path becomes available.")
        print("")
        print("Domain: unknown")
        print("  The execution domain could not be determined from launchctl print.")
        print("  Possible reasons:")
        print("    - Service visible in 'launchctl list' but not in 'launchctl print'")
        print("    - Cross-domain services")
        print("    - Transient or ephemeral jobs")
        print("  The service exists; its context is simply opaque to observation.")
        print("")
        print("Time Windows (not exact timestamps)")
        print("  Events are derived by comparing snapshots.")
        print("  We can only say 'something changed between T1 and T2'.")
        print("  Exact timestamps would be fabricated.")
        print("  Wider snapshot gaps produce wider time windows.")
        print("")
        print("Unknown is a valid, stable state.")
        print("It may resolve in future observations.")
        print("Do not assume unknown means broken.")
        exit(0)
    }
    
    // MARK: - Pro Stub (v1.3)
    
    /// Pro activation UX: Clear distinction between Free and Pro.
    /// - Pro is additive, never degrades Free functionality
    /// - No nagging, no DRM, just information
    /// - Pro feels like a private agreement, not enforcement
    private static func runExplainStub(args: [String]) {
        print("daemon-inspector explain")
        print(String(repeating: "=", count: 30))
        print("")
        print("This command is part of daemon-inspector Pro.")
        print("")
        print("What it does:")
        print("  Provides human-readable narrative summaries")
        print("  derived from your existing snapshots and events.")
        print("  No additional data collection. No system modification.")
        print("")
        print("What you have now (Free):")
        print("  - All observation, storage, and derivation features")
        print("  - Binary inspection")
        print("  - JSON output for scripting")
        print("  - Full event derivation")
        print("")
        print("What Pro adds:")
        print("  - Narrative explanations of daemon behavior")
        print("  - Plain-language summaries")
        print("  - No changes to Free functionality")
        print("")
        print("Free remains complete and useful indefinitely.")
        print("")
        print("Learn more: https://mikedan37.github.io/daemon-inspector/")
        exit(0)
    }
    
    // MARK: - Binary Inspection (v1.2)
    
    private static func runInspect(args: [String], options: CommandOptions) throws {
        // Need at least one arg (the subcommand)
        guard !args.isEmpty else {
            printError("Usage: daemon-inspector inspect binary <label>")
            print("")
            print("Subcommands:")
            print("  binary <label>    Inspect binary metadata (read-only)")
            exit(1)
        }
        
        let subcommand = args[0]
        
        guard subcommand == "binary" else {
            printError("Unknown inspect subcommand: \(subcommand)")
            print("")
            print("Available subcommands:")
            print("  binary <label>    Inspect binary metadata (read-only)")
            exit(1)
        }
        
        // Need a label after "binary"
        guard args.count >= 2 else {
            printError("Usage: daemon-inspector inspect binary <label>")
            exit(1)
        }
        
        let label = args[1]
        
        // Look up the daemon to get its binary path
        let collector = LaunchdCollector()
        let snapshot = try collector.collect()
        
        guard let daemon = snapshot.daemons.first(where: { $0.label == label }) else {
            throw InspectorError.daemonNotFound(label: label)
        }
        
        guard let binaryPath = daemon.binaryPath else {
            // Binary path unknown
            let metadata = BinaryMetadata.unknownPath(label: label)
            if options.jsonOutput {
                printBinaryInspectionJSON(metadata)
            } else {
                printBinaryInspection(metadata, options: options)
            }
            return
        }
        
        // Perform inspection
        let inspector = BinaryInspector()
        let metadata = inspector.inspect(label: label, path: binaryPath)
        
        if options.jsonOutput {
            printBinaryInspectionJSON(metadata)
        } else {
            printBinaryInspection(metadata, options: options)
        }
    }
    
    private static func printBinaryInspection(_ metadata: BinaryMetadata, options: CommandOptions) {
        var lines: [String] = []
        
        // Header
        lines.append("Binary Inspection — read-only")
        lines.append("")
        lines.append("Daemon: \(metadata.daemonLabel)")
        lines.append("")
        
        // Check for error cases
        if let error = metadata.errorMessage {
            lines.append("Status: \(error)")
            lines.append("")
        } else {
            // File facts
            lines.append("Path: \(metadata.path)")
            lines.append("Exists: \(metadata.exists ? "yes" : "no")")
            
            if metadata.exists {
                if let fileType = metadata.fileType {
                    let typeDesc: String
                    switch fileType {
                    case .machO: typeDesc = "Mach-O executable"
                    case .script: typeDesc = "Script"
                    case .unknown: typeDesc = "Unknown"
                    }
                    lines.append("Type: \(typeDesc)")
                }
                
                if let arch = metadata.architecture, arch != .unknown {
                    lines.append("Architecture: \(arch.rawValue)")
                }
                
                if let size = metadata.sizeBytes {
                    lines.append("Size: \(formatFileSize(size))")
                }
                
                if let ownership = metadata.ownership {
                    let user = ownership.userName ?? String(ownership.uid)
                    let group = ownership.groupName ?? String(ownership.gid)
                    lines.append("Owner: \(user):\(group)")
                }
                
                if let perms = metadata.permissions {
                    lines.append("Permissions: \(perms)")
                }
                
                if let isSymlink = metadata.isSymlink {
                    if isSymlink {
                        lines.append("Symlink: yes")
                        if let resolved = metadata.resolvedPath {
                            lines.append("Resolved: \(resolved)")
                        }
                    } else {
                        lines.append("Symlink: no")
                    }
                }
                
                if let volume = metadata.volumeType {
                    let volDesc: String
                    switch volume {
                    case .system: volDesc = "system (sealed)"
                    case .data: volDesc = "data"
                    case .external: volDesc = "external"
                    case .unknown: volDesc = "unknown"
                    }
                    lines.append("Volume: \(volDesc)")
                }
                
                if let hasSig = metadata.hasCodeSignature {
                    lines.append("Code signature: \(hasSig ? "present" : "not detected")")
                }
            }
        }
        
        // Footer note
        lines.append("")
        lines.append("Note:")
        lines.append("This inspection is metadata-only.")
        lines.append("No code was executed.")
        lines.append("No trust or safety judgment is implied.")
        
        // Output with pager or plain
        let mode = getOutputMode(options: options)
        switch mode {
        case .interactive:
            let pager = TerminalPager(lines: lines)
            pager.run()
        case .piped, .json:
            for line in lines {
                print(line)
            }
        }
    }
    
    private static func printBinaryInspectionJSON(_ metadata: BinaryMetadata) {
        var binary: [String: Any?] = [
            "path": metadata.path,
            "exists": metadata.exists
        ]
        
        if metadata.exists {
            binary["type"] = metadata.fileType?.rawValue
            binary["architecture"] = metadata.architecture?.rawValue
            binary["sizeBytes"] = metadata.sizeBytes
            
            if let ownership = metadata.ownership {
                binary["owner"] = [
                    "user": ownership.userName ?? String(ownership.uid),
                    "group": ownership.groupName ?? String(ownership.gid),
                    "uid": ownership.uid,
                    "gid": ownership.gid
                ]
            } else {
                binary["owner"] = nil
            }
            
            binary["permissions"] = metadata.permissions
            binary["isSymlink"] = metadata.isSymlink
            binary["resolvedPath"] = metadata.resolvedPath
            binary["volume"] = metadata.volumeType?.rawValue
            binary["hasCodeSignature"] = metadata.hasCodeSignature
        }
        
        binary["error"] = metadata.errorMessage
        
        let json: [String: Any] = [
            "daemon": [
                "label": metadata.daemonLabel
            ],
            "binary": binary
        ]
        
        printJSON(json)
    }
    
    private static func formatFileSize(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return "\(bytes) B"
        } else {
            return String(format: "%.1f %@", size, units[unitIndex])
        }
    }
    
    private static func runSample(args: [String]) throws {
        // Parse arguments: --every <interval> --for <duration>
        var everyInterval: TimeInterval?
        var forDuration: TimeInterval?
        
        var i = 0
        while i < args.count {
            if args[i] == "--every" && i + 1 < args.count {
                everyInterval = try parseTimeInterval(args[i + 1])
                i += 2
            } else if args[i] == "--for" && i + 1 < args.count {
                forDuration = try parseTimeInterval(args[i + 1])
                i += 2
            } else {
                throw SampleError.invalidArgument(args[i])
            }
        }
        
        guard let interval = everyInterval else {
            throw SampleError.missingArgument("--every")
        }
        
        guard let duration = forDuration else {
            throw SampleError.missingArgument("--for")
        }
        
        guard interval > 0 else {
            throw SampleError.invalidInterval("Interval must be greater than 0")
        }
        
        guard duration > 0 else {
            throw SampleError.invalidInterval("Duration must be greater than 0")
        }
        
        // Run sampling loop
        try performSampling(interval: interval, duration: duration)
    }
    
    /// Parse time interval string (e.g., "2s", "5s", "2m", "30s")
    private static func parseTimeInterval(_ str: String) throws -> TimeInterval {
        let str = str.lowercased().trimmingCharacters(in: .whitespaces)
        
        guard let lastChar = str.last else {
            throw SampleError.invalidTimeFormat(str)
        }
        
        let numberPart = String(str.dropLast())
        guard let value = Double(numberPart) else {
            throw SampleError.invalidTimeFormat(str)
        }
        
        switch lastChar {
        case "s":
            return value
        case "m":
            return value * 60
        case "h":
            return value * 3600
        default:
            throw SampleError.invalidTimeFormat(str)
        }
    }
    
    /// Perform foreground sampling loop
    private static func performSampling(interval: TimeInterval, duration: TimeInterval) throws {
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(duration)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        print("Sampling started at \(formatter.string(from: startTime))")
        print("Cadence: \(formatInterval(interval))")
        print("Duration: \(formatInterval(duration))")
        print("")
        
        // Open BlazeStore once and reuse for all snapshots
        let store = try BlazeStore()
        let collector = LaunchdCollector()
        var snapshotCount = 0
        
        while true {
            let now = Date()
            
            // Check if duration has elapsed
            if now >= endTime {
                break
            }
            
            // Collect snapshot
            do {
                let snapshot = try collector.collect()
                try persist(snapshot: snapshot, collectorName: collector.name, store: store)
                snapshotCount += 1
            } catch {
                print("Error collecting snapshot: \(error)")
                // Continue to next iteration
            }
            
            // Calculate next sample time
            let nextSampleTime = now.addingTimeInterval(interval)
            
            // If next sample would exceed duration, exit
            if nextSampleTime >= endTime {
                break
            }
            
            // Sleep until next sample time
            let sleepDuration = nextSampleTime.timeIntervalSince(now)
            if sleepDuration > 0 {
                Thread.sleep(forTimeInterval: sleepDuration)
            }
        }
        
        print("Sampling completed")
        print("Snapshots written: \(snapshotCount)")
    }
    
    /// Format time interval for display
    private static func formatInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: "%.0fs", interval)
        } else if interval < 3600 {
            return String(format: "%.0fm", interval / 60)
        } else {
            return String(format: "%.1fh", interval / 3600)
        }
    }
    
    enum SampleError: Error, CustomStringConvertible {
        case missingArgument(String)
        case invalidArgument(String)
        case invalidTimeFormat(String)
        case invalidInterval(String)
        
        var description: String {
            switch self {
            case .missingArgument(let arg):
                return "Missing required argument: \(arg)"
            case .invalidArgument(let arg):
                return "Invalid argument: \(arg)"
            case .invalidTimeFormat(let str):
                return "Invalid time format: \(str). Expected format: <number><s|m|h> (e.g., 2s, 5m, 1h)"
            case .invalidInterval(let msg):
                return msg
            }
        }
    }
    
    // MARK: - Verification Hook (Phase 5)
    
    /// Internal verification helper for tests and debugging.
    /// Validates:
    /// - Snapshots are append-only
    /// - No snapshot mutation occurs
    /// - Event derivation is deterministic
    /// 
    /// This is not a user command - it's for internal validation.
    private static func runVerify() throws {
        print("Verification Hook")
        print("=================")
        print("")
        
        let loader = try SnapshotLoader()
        let snapshots = try loader.loadAllSnapshots()
        
        print("Snapshot Integrity:")
        print("  Total snapshots: \(snapshots.count)")
        
        if snapshots.isEmpty {
            print("  Status: No snapshots to verify")
            return
        }
        
        // Verify chronological ordering (append-only property)
        var orderValid = true
        var previousTimestamp: Date? = nil
        for snapshot in snapshots {
            if let prev = previousTimestamp, snapshot.timestamp < prev {
                orderValid = false
                break
            }
            previousTimestamp = snapshot.timestamp
        }
        print("  Chronological order: \(orderValid ? "PASS" : "FAIL")")
        
        // Track determinism result
        var deterministicResult = true
        
        // Verify determinism: derive events twice, compare
        if snapshots.count >= 2 {
            let events1 = EventDeriver().deriveEvents(from: snapshots)
            let events2 = EventDeriver().deriveEvents(from: snapshots)
            
            // Events should be identical in content and order
            // Compare as sets first (content), then as arrays (order)
            let events1Set = Set(events1.map { "\($0.label)|\($0.type)|\($0.timeWindow)" })
            let events2Set = Set(events2.map { "\($0.label)|\($0.type)|\($0.timeWindow)" })
            let contentMatch = events1Set == events2Set
            
            let orderMatch = events1.count == events2.count && 
                zip(events1, events2).allSatisfy { e1, e2 in
                    e1.label == e2.label && 
                    e1.type == e2.type &&
                    e1.timeWindow == e2.timeWindow
                }
            
            deterministicResult = orderMatch
            
            print("")
            print("Event Derivation:")
            print("  Derived events: \(events1.count)")
            print("  Content match: \(contentMatch ? "PASS" : "FAIL")")
            print("  Order deterministic: \(orderMatch ? "PASS" : "FAIL")")
        }
        
        // Verify no duplicate snapshot IDs
        let ids = snapshots.map { $0.id }
        let uniqueIds = Set(ids)
        let noDuplicates = ids.count == uniqueIds.count
        
        print("")
        print("Snapshot IDs:")
        print("  Unique IDs: \(noDuplicates ? "PASS" : "FAIL")")
        
        // Summary
        print("")
        let allPassed = orderValid && noDuplicates && deterministicResult
        print("Overall: \(allPassed ? "PASS" : "FAIL")")
    }
}
