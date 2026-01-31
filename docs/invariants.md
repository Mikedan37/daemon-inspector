# daemon-inspector Invariants

These are non-negotiable constraints that must never be violated.

## Read-Only

The tool is strictly read-only. No command may modify system state.

- Never start, stop, restart, or signal daemons
- Never write to system configuration
- Never influence scheduling or execution
- Never execute inspected binaries

## Observation Semantics

All observations are derived from snapshots. No inferred timestamps.

- Events are derived by comparing snapshots, never stored
- Time is represented as intervals, not fabricated point-in-time certainty
- Snapshots are facts, not opinions
- Derivation happens at read time, not write time

## Unknown Preservation

Unknown data must remain unknown. Never fabricate defaults.

- `nil` / `"unknown"` is a valid, stable state
- Unknown today may become known tomorrow (that's discovery, not change)
- Unknown does not trigger events
- Do not assume unknown means broken

## Storage Semantics

Storage is append-only. History cannot be rewritten.

- Snapshots are immutable once written
- No updates, no deletions, no compaction
- Each snapshot is a complete fact
- Partial writes are acceptable (reality is messy)

## No Invented Meaning

Events are derived, not guessed.

- No health scores
- No severity levels
- No "likely cause" inference
- No stability judgments beyond counts

## Local-Only

No network, no telemetry, no background agents.

- All operations are local
- No cloud, no sync, no replication
- No phone-home, no analytics
- BlazeDB is a local store, not a distributed system

---

## Why These Matter

These invariants ensure:
- The tool remains trustworthy under audit
- Output can be explained without hand-waving
- Future changes don't accidentally corrupt semantics
- Cursor respects boundaries instead of inventing features

If a change would violate any invariant, it is architecturally incorrect.
