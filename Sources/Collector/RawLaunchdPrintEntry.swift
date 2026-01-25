import Foundation

/// Raw enrichment data from `launchctl print` output.
/// This represents what launchd claimed, if anything.
struct RawLaunchdPrintEntry {
    let label: String
    let domain: String
    let programPath: String?
}
