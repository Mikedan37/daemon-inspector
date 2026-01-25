import Foundation

/// Simple test/demo of event derivation.
/// This is not a full test suite, just verification the algorithm works.
public struct EventDeriverTests {
    public static func runDemo() {
        let deriver = EventDeriver()
        
        // Create test snapshots
        let t0 = Date()
        let t1 = t0.addingTimeInterval(60)
        let t2 = t1.addingTimeInterval(60)
        let t3 = t2.addingTimeInterval(60)
        
        // Snapshot 0: Two daemons running
        let snapshot0 = CollectorSnapshot(
            timestamp: t0,
            daemons: [
                ObservedDaemon(
                    label: "com.apple.foo",
                    domain: "system",
                    pid: 123,
                    isRunning: true,
                    binaryPath: "/usr/bin/foo",
                    observedAt: t0
                ),
                ObservedDaemon(
                    label: "com.apple.bar",
                    domain: "system",
                    pid: 456,
                    isRunning: true,
                    binaryPath: "/usr/bin/bar",
                    observedAt: t0
                )
            ]
        )
        
        // Snapshot 1: foo stopped, bar still running, baz appeared
        let snapshot1 = CollectorSnapshot(
            timestamp: t1,
            daemons: [
                ObservedDaemon(
                    label: "com.apple.foo",
                    domain: "system",
                    pid: nil,
                    isRunning: false,
                    binaryPath: "/usr/bin/foo",
                    observedAt: t1
                ),
                ObservedDaemon(
                    label: "com.apple.bar",
                    domain: "system",
                    pid: 456,
                    isRunning: true,
                    binaryPath: "/usr/bin/bar",
                    observedAt: t1
                ),
                ObservedDaemon(
                    label: "com.apple.baz",
                    domain: "gui/501",
                    pid: 789,
                    isRunning: true,
                    binaryPath: "/usr/bin/baz",
                    observedAt: t1
                )
            ]
        )
        
        // Snapshot 2: foo restarted (new PID), bar disappeared, baz still running
        let snapshot2 = CollectorSnapshot(
            timestamp: t2,
            daemons: [
                ObservedDaemon(
                    label: "com.apple.foo",
                    domain: "system",
                    pid: 999,
                    isRunning: true,
                    binaryPath: "/usr/bin/foo",
                    observedAt: t2
                ),
                ObservedDaemon(
                    label: "com.apple.baz",
                    domain: "gui/501",
                    pid: 789,
                    isRunning: true,
                    binaryPath: "/usr/bin/baz",
                    observedAt: t2
                )
            ]
        )
        
        // Snapshot 3: foo binary path changed
        let snapshot3 = CollectorSnapshot(
            timestamp: t3,
            daemons: [
                ObservedDaemon(
                    label: "com.apple.foo",
                    domain: "system",
                    pid: 999,
                    isRunning: true,
                    binaryPath: "/usr/local/bin/foo",
                    observedAt: t3
                ),
                ObservedDaemon(
                    label: "com.apple.baz",
                    domain: "gui/501",
                    pid: 789,
                    isRunning: true,
                    binaryPath: "/usr/bin/baz",
                    observedAt: t3
                )
            ]
        )
        
        let snapshots = [snapshot0, snapshot1, snapshot2, snapshot3]
        let events = deriver.deriveEvents(from: snapshots)
        
        print("Event Derivation Demo")
        print("====================")
        print("Snapshots: \(snapshots.count)")
        print("Derived Events: \(events.count)")
        print("")
        
        for event in events {
            let timeStr = formatTimeWindow(event.timeWindow)
            print("\(event.type.rawValue): \(event.label)")
            print("  Time: \(timeStr)")
            if let details = event.details {
                print("  Details: \(details)")
            }
            print("")
        }
    }
    
    private static func formatTimeWindow(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: range.lowerBound)) ... \(formatter.string(from: range.upperBound))"
    }
}
