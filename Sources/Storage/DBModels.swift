import Foundation

/// Storage record for a snapshot (not a domain model)
public struct DBSnapshot: Codable, Sendable {
    public let id: UUID
    public let collector: String
    public let timestamp: Date
    
    public init(id: UUID, collector: String, timestamp: Date) {
        self.id = id
        self.collector = collector
        self.timestamp = timestamp
    }
}

/// Storage record for observed daemon (not a domain model)
public struct DBObservedDaemon: Codable, Sendable {
    public let snapshotID: UUID
    
    public let label: String
    public let domain: String
    public let pid: Int?
    public let isRunning: Bool
    public let binaryPath: String?
    public let observedAt: Date
    
    public init(
        snapshotID: UUID,
        label: String,
        domain: String,
        pid: Int?,
        isRunning: Bool,
        binaryPath: String?,
        observedAt: Date
    ) {
        self.snapshotID = snapshotID
        self.label = label
        self.domain = domain
        self.pid = pid
        self.isRunning = isRunning
        self.binaryPath = binaryPath
        self.observedAt = observedAt
    }
}
