import Foundation

/// Raw entry parsed from `launchctl list` output.
/// This represents what we can directly observe, before any enrichment.
struct RawLaunchctlListEntry: Hashable, Sendable {
    /// The PID column from `launchctl list`. `nil` means "-" or unknown.
    let pid: Int?

    /// The status column from `launchctl list` (often exit code / last status).
    /// We store it because it's observable, but we won't interpret it yet.
    let status: Int?

    /// The label column from `launchctl list`
    let label: String
}
