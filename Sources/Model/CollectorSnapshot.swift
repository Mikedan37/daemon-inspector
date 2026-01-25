import Foundation

/// A snapshot of observed daemons at a specific point in time.
public struct CollectorSnapshot: Hashable, Sendable {
    /// Unique identifier for this snapshot
    public let id: UUID
    
    /// When this snapshot was taken
    public let timestamp: Date
    
    /// The daemons observed at this time
    public let daemons: [ObservedDaemon]
    
    public init(id: UUID = UUID(), timestamp: Date, daemons: [ObservedDaemon]) {
        self.id = id
        self.timestamp = timestamp
        self.daemons = daemons
    }
}
