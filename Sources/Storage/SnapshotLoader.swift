import Foundation
import Model

public struct SnapshotLoader {
    let store: BlazeStore
    
    public init() throws {
        self.store = try BlazeStore()
    }
    
    public func loadLatestSnapshots(limit: Int) throws -> [CollectorSnapshot] {
        // BlazeDB owns query execution. We just construct the query.
        let snapshotQuery = store.snapshots
            .query()
            .order(by: \.timestamp, descending: true)
            .limit(limit)
        
        let metas = try snapshotQuery.all().reversed() // chronological
        
        return try metas.map { meta in
            // Query daemons for this snapshot. BlazeDB owns how this executes.
            let daemonQuery = store.daemons
                .query()
                .where { $0.snapshotID == meta.id }
            
            let daemons = try daemonQuery.all().map { db in
                ObservedDaemon(
                    label: db.label,
                    domain: db.domain,
                    pid: db.pid,
                    isRunning: db.isRunning,
                    binaryPath: db.binaryPath,
                    observedAt: db.observedAt
                )
            }
            
            return CollectorSnapshot(
                id: meta.id,
                timestamp: meta.timestamp,
                daemons: daemons
            )
        }
    }
    
    /// Load all snapshots that contain a specific daemon label.
    /// Returns snapshots ordered by timestamp ascending (chronological).
    /// Each snapshot contains all its daemons, not just the filtered one.
    public func loadSnapshotsContaining(daemonLabel: String) throws -> [CollectorSnapshot] {
        // Step 1: Find all snapshot IDs that contain the daemon label
        let daemonRecords = try store.daemons
            .query()
            .where { $0.label == daemonLabel }
            .all()
        
        // Collect unique snapshot IDs
        let snapshotIDs = Set(daemonRecords.map { $0.snapshotID })
        
        guard !snapshotIDs.isEmpty else {
            return []
        }
        
        // Step 2: Load all snapshots
        let allMetas = try store.snapshots
            .query()
            .order(by: \.timestamp, descending: false) // chronological ascending
            .all()
        
        // Filter to only those containing the daemon
        let filteredMetas = allMetas.filter { snapshotIDs.contains($0.id) }
        
        // Step 3: Load full snapshots with all daemons
        return try filteredMetas.map { meta in
            let daemonQuery = store.daemons
                .query()
                .where { $0.snapshotID == meta.id }
            
            let daemons = try daemonQuery.all().map { db in
                ObservedDaemon(
                    label: db.label,
                    domain: db.domain,
                    pid: db.pid,
                    isRunning: db.isRunning,
                    binaryPath: db.binaryPath,
                    observedAt: db.observedAt
                )
            }
            
            return CollectorSnapshot(
                id: meta.id,
                timestamp: meta.timestamp,
                daemons: daemons
            )
        }
    }
    
    /// Load all snapshots ordered by timestamp ascending (chronological).
    public func loadAllSnapshots() throws -> [CollectorSnapshot] {
        let metas = try store.snapshots
            .query()
            .order(by: \.timestamp, descending: false) // chronological ascending
            .all()
        
        return try metas.map { meta in
            let daemonQuery = store.daemons
                .query()
                .where { $0.snapshotID == meta.id }
            
            let daemons = try daemonQuery.all().map { db in
                ObservedDaemon(
                    label: db.label,
                    domain: db.domain,
                    pid: db.pid,
                    isRunning: db.isRunning,
                    binaryPath: db.binaryPath,
                    observedAt: db.observedAt
                )
            }
            
            return CollectorSnapshot(
                id: meta.id,
                timestamp: meta.timestamp,
                daemons: daemons
            )
        }
    }
}
