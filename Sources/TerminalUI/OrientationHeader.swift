//
//  OrientationHeader.swift
//  daemon-inspector
//
//  Contextual orientation headers for pager output
//  Provides calm, non-interpreting context to users
//

import Foundation

/// Builds orientation headers for pager-based output
/// Headers provide context without adding interpretation
public struct OrientationHeader {
    
    /// Build an orientation header for commands that display data
    /// - Parameters:
    ///   - snapshotCount: Number of snapshots available
    ///   - observationWindow: Duration of observation window (nil if not applicable)
    ///   - commandContext: Brief description of what this command shows
    /// - Returns: Array of header lines to prepend to output
    public static func build(
        snapshotCount: Int,
        observationWindow: TimeInterval?,
        commandContext: String
    ) -> [String] {
        var lines: [String] = []
        
        // Tool identity and safety
        lines.append("Daemon Inspector — read-only")
        lines.append("This tool never modifies system state.")
        lines.append("")
        
        // Context
        lines.append("Snapshots available: \(snapshotCount)")
        
        if let window = observationWindow, window > 0 {
            lines.append("Observation window: \(formatDuration(window))")
        }
        
        lines.append("")
        
        // Semantic reminders
        lines.append("Events derived at read time. Unknowns preserved.")
        lines.append("Time windows shown, not exact timestamps.")
        lines.append("")
        
        // Separator
        lines.append(String(repeating: "─", count: 60))
        lines.append("")
        
        return lines
    }
    
    /// Build a minimal header for list command (snapshot-centric)
    public static func buildForList(daemonCount: Int) -> [String] {
        var lines: [String] = []
        
        lines.append("Daemon Inspector — read-only")
        lines.append("This tool never modifies system state.")
        lines.append("")
        lines.append(String(repeating: "─", count: 60))
        lines.append("")
        
        return lines
    }
    
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
}

/// Empty state messages for various scenarios
/// Calm, informational, non-prescriptive
public struct EmptyStateMessage {
    
    /// No snapshots exist at all
    public static func noSnapshots() -> [String] {
        return [
            "No snapshots available.",
            "",
            "Collect data using:",
            "  daemon-inspector list",
            "  daemon-inspector sample --every 2s --for 1m"
        ]
    }
    
    /// Not enough snapshots for diff
    public static func insufficientSnapshotsForDiff(found: Int) -> [String] {
        return [
            "Not enough snapshots to compute diff.",
            "(\(found) snapshot\(found == 1 ? "" : "s") found, need at least 2)",
            "",
            "Collect more data using:",
            "  daemon-inspector list"
        ]
    }
    
    /// No instability detected
    public static func noInstability(snapshotsExamined: Int, window: String) -> [String] {
        return [
            "No instability detected in this window.",
            "(\(snapshotsExamined) snapshots examined over \(window))",
            "",
            "All observed daemons maintained stable state."
        ]
    }
    
    /// Timeline exists but no events in filtered window
    public static func noEventsInWindow(label: String, snapshotCount: Int) -> [String] {
        return [
            "No events found for '\(label)' in this window.",
            "(\(snapshotCount) snapshot\(snapshotCount == 1 ? "" : "s") examined)",
            "",
            "The daemon was observed but showed no state changes."
        ]
    }
    
    /// Daemon not found in any snapshot
    public static func daemonNotFound(label: String) -> [String] {
        return [
            "No observations found for '\(label)'.",
            "",
            "This daemon may not exist, may have a different label,",
            "or was not running during any observed snapshot."
        ]
    }
}
