import Foundation

/// Type of event derived from comparing snapshots.
public enum DaemonEventType: String, Codable, Sendable {
    case appeared
    case disappeared
    case started
    case stopped
    case pidChanged
    case binaryPathChanged
    
    public var displayName: String {
        switch self {
        case .appeared: return "Appeared"
        case .disappeared: return "Disappeared"
        case .started, .stopped, .pidChanged, .binaryPathChanged:
            return "State changes"
        }
    }
    
    public var symbol: String {
        switch self {
        case .appeared: return "+"
        case .disappeared: return "-"
        default: return "~"
        }
    }
    
    public var sortOrder: Int {
        switch self {
        case .appeared: return 0
        case .disappeared: return 1
        default: return 2
        }
    }
}
