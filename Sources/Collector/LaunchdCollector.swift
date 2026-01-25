import Foundation
import Model

public struct LaunchdCollector: Collector {
    public let name = "launchd"

    private let runner = CommandRunner()
    private let listParser = LaunchctlListParser()
    private let printParser = LaunchctlPrintParser()

    public init() {}

    private func currentUID() throws -> String {
        let result = try runner.run("/usr/bin/id", ["-u"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func collect() throws -> CollectorSnapshot {
        let now = Date()

        // Phase 1: Discovery via launchctl list
        let result = try runner.run("/bin/launchctl", ["list"])
        let rawEntries = try listParser.parse(result.stdout)

        // Phase 2: Best-effort enrichment via launchctl print (individual jobs)
        var enrichment: [RawLaunchdPrintEntry] = []
        let uid = try? currentUID()

        // Try to enrich a sample of jobs (best-effort, failures are ignored)
        // We limit to avoid excessive slowness, and we try both system and gui domains
        for entry in rawEntries.prefix(100) { // Limit to first 100 for performance
            // Try system domain first
            do {
                let printResult = try runner.run("/bin/launchctl", ["print", "system/\(entry.label)"])
                if let enriched = printParser.parseJob(stdout: printResult.stdout, domain: "system", label: entry.label) {
                    enrichment.append(enriched)
                    continue // Found in system, skip gui check
                }
            } catch {
                // Not in system domain or failed, try gui
            }

            // Try GUI domain if we have a UID
            if let uid = uid {
                do {
                    let printResult = try runner.run("/bin/launchctl", ["print", "gui/\(uid)/\(entry.label)"])
                    if let enriched = printParser.parseJob(stdout: printResult.stdout, domain: "gui/\(uid)", label: entry.label) {
                        enrichment.append(enriched)
                    }
                } catch {
                    // Not in gui domain or failed, continue
                }
            }
        }

        // Build lookup: label -> enrichment
        let enrichmentByLabel = Dictionary(
            enrichment.map { ($0.label, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Merge enrichment into observed daemons
        let daemons: [ObservedDaemon] = rawEntries.map { entry in
            let enrich = enrichmentByLabel[entry.label]

            return ObservedDaemon(
                label: entry.label,
                domain: enrich?.domain ?? "unknown",
                pid: entry.pid,
                isRunning: entry.pid != nil,
                binaryPath: enrich?.programPath,
                observedAt: now
            )
        }

        return CollectorSnapshot(timestamp: now, daemons: daemons)
    }
}
