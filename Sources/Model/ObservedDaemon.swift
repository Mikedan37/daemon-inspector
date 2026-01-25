import Foundation

/// A daemon or background service observed at a specific point in time.
public struct ObservedDaemon: Hashable, Sendable {
    /// Service label (e.g., "com.apple.some.daemon")
    public let label: String
    
    /// Domain: "system", "user", "gui", or "unknown"
    public let domain: String
    
    /// Process ID if running, nil otherwise
    public let pid: Int?
    
    /// Whether the daemon appears to be running (pid != nil)
    public let isRunning: Bool
    
    /// Binary path if discoverable, nil otherwise
    public let binaryPath: String?
    
    /// When this observation was made
    public let observedAt: Date
    
    public init(
        label: String,
        domain: String,
        pid: Int?,
        isRunning: Bool,
        binaryPath: String?,
        observedAt: Date
    ) {
        self.label = label
        self.domain = domain
        self.pid = pid
        self.isRunning = isRunning
        self.binaryPath = binaryPath
        self.observedAt = observedAt
    }
}
