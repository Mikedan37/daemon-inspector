import Foundation

enum LaunchctlListParseError: Error, CustomStringConvertible {
    case emptyOutput

    var description: String {
        switch self {
        case .emptyOutput:
            return "launchctl list returned empty output"
        }
    }
}

struct LaunchctlListParser {
    func parse(_ stdout: String) throws -> [RawLaunchctlListEntry] {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.isEmpty { throw LaunchctlListParseError.emptyOutput }

        var entries: [RawLaunchctlListEntry] = []
        entries.reserveCapacity(lines.count)

        for lineSub in lines {
            let line = String(lineSub)

            // Header varies; safest skip: if it contains "Label" and "PID"
            if line.localizedCaseInsensitiveContains("label"),
               line.localizedCaseInsensitiveContains("pid") {
                continue
            }

            // Split by whitespace; expected: PID STATUS LABEL
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count < 3 { continue }

            let pidStr = parts[0]
            let statusStr = parts[1]
            let label = parts[2]

            let pid: Int? = (pidStr == "-") ? nil : Int(pidStr)
            let status: Int? = Int(statusStr)

            entries.append(.init(pid: pid, status: status, label: label))
        }

        return entries
    }
}
