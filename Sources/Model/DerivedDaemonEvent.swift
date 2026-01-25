import Foundation

/// An event derived from comparing snapshots.
/// Events have time windows, never point-in-time.
public struct DerivedDaemonEvent: Hashable, Sendable {
    public let label: String
    public let type: DaemonEventType
    
    /// Snapshot ID where the event was first observable (may be nil for initial state)
    public let fromSnapshotID: UUID?
    
    /// Snapshot ID where the event was confirmed (may be nil for ongoing state)
    public let toSnapshotID: UUID?
    
    /// Time window when this event occurred (between snapshots, never at a snapshot)
    public let timeWindow: ClosedRange<Date>
    
    /// Optional human-readable details about the event
    public let details: String?
    
    public init(
        label: String,
        type: DaemonEventType,
        fromSnapshotID: UUID?,
        toSnapshotID: UUID?,
        timeWindow: ClosedRange<Date>,
        details: String? = nil
    ) {
        self.label = label
        self.type = type
        self.fromSnapshotID = fromSnapshotID
        self.toSnapshotID = toSnapshotID
        self.timeWindow = timeWindow
        self.details = details
    }
}
