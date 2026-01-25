import Foundation

struct LaunchctlPrintParser {

    /// Parse a single job's detailed output from `launchctl print <domain>/<label>`
    func parseJob(stdout: String, domain: String, label: String) -> RawLaunchdPrintEntry? {
        // Reject error messages - launchctl may return error text even with exit code 0
        if stdout.contains("Bad request") || stdout.contains("Could not find service") {
            return nil
        }

        // Must start with expected format: <domain>/<label> = {
        let expectedPrefix = "\(domain)/\(label) = {"
        if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(expectedPrefix) {
            return nil
        }

        var programPath: String? = nil

        for line in stdout.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)

            if l.hasPrefix("program =") {
                programPath = l
                    .replacingOccurrences(of: "program =", with: "")
                    .trimmingCharacters(in: .whitespaces)
                break
            }

            if l.hasPrefix("programarguments =") {
                // Look for the first argument on the next non-empty line
                continue
            }

            // If we see programarguments, the next line with a path might be argv[0]
            if programPath == nil, l.hasPrefix("/") && !l.contains("=") {
                programPath = l
                break
            }
        }

        return RawLaunchdPrintEntry(
            label: label,
            domain: domain,
            programPath: programPath
        )
    }
}
