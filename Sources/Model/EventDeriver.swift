import Foundation

/// Derives events from a sequence of snapshots.
/// Pure, deterministic, read-only computation.
public struct EventDeriver {
    /// Threshold for considering a snapshot "partial" (percentage of previous snapshot's daemon count)
    /// If a snapshot has fewer than this percentage, disappeared events are suppressed.
    public let partialSnapshotThreshold: Double
    
    public init(partialSnapshotThreshold: Double = 0.5) {
        self.partialSnapshotThreshold = partialSnapshotThreshold
    }
    
    /// Derive events from a sequence of snapshots.
    /// Snapshots must be ordered by time ascending.
    public func deriveEvents(from snapshots: [CollectorSnapshot]) -> [DerivedDaemonEvent] {
        guard snapshots.count >= 2 else {
            return []
        }
        
        var events: [DerivedDaemonEvent] = []
        var pendingDisappearances: Set<String> = []
        
        // Step 1 & 2: Normalize and pairwise comparison
        for i in 1..<snapshots.count {
            let prev = snapshots[i - 1]
            let curr = snapshots[i]
            
            // Normalize to maps
            let prevMap = normalizeSnapshot(prev)
            let currMap = normalizeSnapshot(curr)
            
            // Check if current snapshot is partial
            let isPartial = isPartialSnapshot(prevMap: prevMap, currMap: currMap)
            
            // Step 3: Label set comparison
            let prevLabels = Set(prevMap.keys)
            let currLabels = Set(currMap.keys)
            
            let appearedCandidates = currLabels.subtracting(prevLabels)
            let disappearedCandidates = prevLabels.subtracting(currLabels)
            let commonLabels = prevLabels.intersection(currLabels)
            
            // Step 4: Appeared events (sorted for determinism)
            for label in appearedCandidates.sorted() {
                events.append(DerivedDaemonEvent(
                    label: label,
                    type: .appeared,
                    fromSnapshotID: prev.id,
                    toSnapshotID: curr.id,
                    timeWindow: prev.timestamp...curr.timestamp
                ))
            }
            
            // Step 5: Disappeared events (careful, sorted for determinism)
            if !isPartial {
                for label in disappearedCandidates.sorted() {
                    if pendingDisappearances.contains(label) {
                        // Absent in two consecutive snapshots - emit disappeared
                        events.append(DerivedDaemonEvent(
                            label: label,
                            type: .disappeared,
                            fromSnapshotID: prev.id,
                            toSnapshotID: curr.id,
                            timeWindow: prev.timestamp...curr.timestamp
                        ))
                        pendingDisappearances.remove(label)
                    } else {
                        // First absence - mark as pending
                        pendingDisappearances.insert(label)
                    }
                }
                
                // Clear pending disappearances that reappeared
                pendingDisappearances = pendingDisappearances.subtracting(currLabels)
            } else {
                // Partial snapshot - suppress disappeared derivation
                // Clear pending disappearances since we can't trust this snapshot
                pendingDisappearances.removeAll()
            }
            
            // Step 6: Compare common labels (sorted for determinism)
            for label in commonLabels.sorted() {
                guard let prevDaemon = prevMap[label],
                      let currDaemon = currMap[label] else {
                    continue
                }
                
                // 6.1 PID transitions
                if let prevPID = prevDaemon.pid, let currPID = currDaemon.pid {
                    if prevPID != currPID {
                        // PID changed - implies restart
                        events.append(DerivedDaemonEvent(
                            label: label,
                            type: .pidChanged,
                            fromSnapshotID: prev.id,
                            toSnapshotID: curr.id,
                            timeWindow: prev.timestamp...curr.timestamp,
                            details: "PID \(prevPID) → \(currPID)"
                        ))
                    }
                } else if prevDaemon.pid == nil && currDaemon.pid != nil {
                    // Started
                    events.append(DerivedDaemonEvent(
                        label: label,
                        type: .started,
                        fromSnapshotID: prev.id,
                        toSnapshotID: curr.id,
                        timeWindow: prev.timestamp...curr.timestamp
                    ))
                } else if prevDaemon.pid != nil && currDaemon.pid == nil {
                    // Stopped
                    events.append(DerivedDaemonEvent(
                        label: label,
                        type: .stopped,
                        fromSnapshotID: prev.id,
                        toSnapshotID: curr.id,
                        timeWindow: prev.timestamp...curr.timestamp
                    ))
                }
                
                // 6.2 Binary path changes
                if let prevPath = prevDaemon.binaryPath,
                   let currPath = currDaemon.binaryPath,
                   prevPath != currPath {
                    events.append(DerivedDaemonEvent(
                        label: label,
                        type: .binaryPathChanged,
                        fromSnapshotID: prev.id,
                        toSnapshotID: curr.id,
                        timeWindow: prev.timestamp...curr.timestamp,
                        details: "\(prevPath) → \(currPath)"
                    ))
                }
            }
        }
        
        return events
    }
    
    /// Normalize snapshot to a map: label -> daemon
    /// Last occurrence wins (handles duplicates in partial snapshots)
    private func normalizeSnapshot(_ snapshot: CollectorSnapshot) -> [String: ObservedDaemon] {
        var map: [String: ObservedDaemon] = [:]
        for daemon in snapshot.daemons {
            map[daemon.label] = daemon
        }
        return map
    }
    
    /// Determine if current snapshot is partial (too few daemons compared to previous)
    private func isPartialSnapshot(prevMap: [String: ObservedDaemon], currMap: [String: ObservedDaemon]) -> Bool {
        guard !prevMap.isEmpty else {
            return false
        }
        
        let prevCount = prevMap.count
        let currCount = currMap.count
        let ratio = Double(currCount) / Double(prevCount)
        
        return ratio < partialSnapshotThreshold
    }
}
