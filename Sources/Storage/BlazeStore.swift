import Foundation
import Model
import BlazeDBCore

/// Configure BlazeDB logging based on environment
/// BLAZEDB_DEBUG=1 enables verbose logging
/// Default: silent (errors only)
private func configureBlazeLogging() {
    if ProcessInfo.processInfo.environment["BLAZEDB_DEBUG"] == "1" {
        BlazeLogger.enableDebugMode()
    } else {
        // Keep BlazeDB quiet by default
        BlazeLogger.enableSilentMode()
    }
}

/// Storage interface for snapshots and daemon records.
/// 
/// This struct provides the application's view of storage. It does NOT
/// own persistence mechanics - BlazeDB does.
/// 
/// Responsibilities of this struct:
/// - Open BlazeDB connection
/// - Provide typed access to tables
/// - Never rewrite history
/// 
/// Responsibilities of BlazeDB:
/// - Encoding (may use Codable internally)
/// - Durability
/// - Append-only storage
/// - Query execution
public struct BlazeStore {
    let db: any BlazeDatabase
    public let snapshots: any BlazeTable<DBSnapshot>
    public let daemons: any BlazeTable<DBObservedDaemon>
    
    /// Initialize BlazeDB storage.
    /// 
    /// Database location: ~/.daemon-inspector/state.blazedb
    /// Or override via DAEMON_INSPECTOR_DB_PATH environment variable (for testing)
    /// 
    /// Logging: Set BLAZEDB_DEBUG=1 for verbose BlazeDB logging (default: silent)
    /// 
    /// This opens BlazeDB and provides access to tables. BlazeDB owns
    /// all persistence mechanics from this point forward.
    public init() throws {
        // Configure logging before any BlazeDB operations
        configureBlazeLogging()
        
        let baseDir: URL
        
        // Allow environment variable override for testing
        if let envPath = ProcessInfo.processInfo.environment["DAEMON_INSPECTOR_DB_PATH"] {
            baseDir = URL(fileURLWithPath: envPath, isDirectory: true)
        } else {
            baseDir = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".daemon-inspector", isDirectory: true)
        }
        
        try FileManager.default.createDirectory(
            at: baseDir,
            withIntermediateDirectories: true
        )
        
        let dbURL = baseDir.appendingPathComponent("state.blazedb")
        
        // Initialize BlazeDB client
        // Using a fixed password for local-only, single-user tool
        // In production, this could be derived from keychain or user input
        let client = try BlazeDBClient(
            name: "daemon-inspector",
            fileURL: dbURL,
            password: "DaemonInspector2024LocalOnly"
        )
        
        // Create adapter that implements our storage protocols
        let adapter = BlazeDBAdapter(client: client)
        self.db = adapter
        
        // Get table interfaces (BlazeDB owns the actual storage)
        self.snapshots = try db.table(name: "snapshots", of: DBSnapshot.self)
        self.daemons = try db.table(name: "observed_daemons", of: DBObservedDaemon.self)
    }
}
