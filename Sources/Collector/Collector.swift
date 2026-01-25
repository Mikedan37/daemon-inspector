import Foundation
import Model

/// Protocol for platform-specific collectors that observe daemons and background services.
public protocol Collector {
    /// Human-readable name of this collector (e.g., "launchd")
    var name: String { get }
    
    /// Collect a snapshot of currently observable daemons.
    /// This method must be read-only and never mutate system state.
    func collect() throws -> CollectorSnapshot
}
