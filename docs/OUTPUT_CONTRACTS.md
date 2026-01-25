# Output Contracts

This document describes the stability guarantees for daemon-inspector output.
Use this when embedding daemon-inspector into scripts or workflows.

---

## JSON Output Stability

### Guaranteed Stable (will not change without major version bump)

**All JSON outputs include:**
```json
{
  "_meta": {
    "toolVersion": "1.2.0",
    "schemaVersion": "1"
  }
}
```

- `schemaVersion` increments on breaking changes
- `toolVersion` is informational only

### Field Guarantees

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `label` | string | no | Daemon identifier, always present |
| `domain` | string | no | May be "unknown" |
| `pid` | integer | yes | null when not running |
| `is_running` | boolean | no | Derived from PID presence |
| `binary_path` | string | yes | null when unknown |
| `observed_at` | ISO8601 | no | Observation timestamp |

### Event Fields

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `type` | string | no | One of: appeared, disappeared, started, stopped, pidChanged, binaryPathChanged |
| `label` | string | no | Daemon identifier |
| `time_window.start` | ISO8601 | no | Window start |
| `time_window.end` | ISO8601 | no | Window end |

---

## Unknown Values

### Why values may be unknown

| Field | Reason |
|-------|--------|
| `domain: "unknown"` | launchd does not expose domain for all services |
| `binary_path: null` | Service may be XPC, app-embedded, or metadata unavailable |
| `pid: null` | Service is loaded but not currently running |

### Handling unknowns

- Unknown is a valid, stable state
- Do not assume unknown means broken
- Unknown today may become known in future snapshots
- Unknown does not trigger events (discovery is not change)

---

## Ordering Guarantees

### Deterministic Output

| Command | Ordering |
|---------|----------|
| `list` | Sorted by label (alphabetical) |
| `diff` | Events grouped by type, then sorted by label |
| `timeline` | Events sorted by time window start (chronological) |
| `unstable` | Sorted by event count (descending), then by label |
| `churn` | Sorted by event count (descending), then by label |

### Determinism Guarantee

Given the same snapshot data:
- Event derivation produces identical results
- Output ordering is stable
- `verify` command validates this

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (invalid command, missing data, permission failure) |

### Special Cases

- `--expect-stable` with `diff`: exits 0 if no changes, 1 if changes detected
- `--help`, `--version`: always exit 0

---

## Time Semantics

### Time Windows, Not Timestamps

Events are never point-in-time. They are windows:

```
Event occurred between 12:40:00 and 12:42:00
```

This is honest. We cannot know the exact moment something changed, only that it was different between two observations.

### Snapshot Cadence

- Snapshots may be irregular
- Event derivation tolerates gaps
- Longer gaps produce wider time windows

---

## Binary Inspection (v1.2)

### Guaranteed Fields

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `path` | string | no | Resolved path or "(unknown)" |
| `exists` | boolean | no | Whether file is on disk |
| `type` | string | yes | mach-o, script, unknown |
| `architecture` | string | yes | arm64, x86_64, universal, unknown |
| `sizeBytes` | integer | yes | File size |
| `permissions` | string | yes | POSIX format (rwxr-xr-x) |
| `isSymlink` | boolean | yes | Whether path is symbolic link |
| `volume` | string | yes | system, data, external, unknown |
| `hasCodeSignature` | boolean | yes | Presence only, not trust |

### What is NOT guaranteed

- Code signature validity (we detect presence, not trust)
- Execution behavior
- Entitlements
- Dynamic library dependencies

---

## Stability Promise

- Breaking changes require `schemaVersion` increment
- New fields may be added without version bump
- Existing fields will not be removed or change type
- Ordering guarantees will be maintained

---

## Embedding Recommendations

```bash
# Safe scripting pattern
daemon-inspector list --json | jq '.daemons[] | select(.is_running)'

# Check schema version
daemon-inspector list --json | jq '._meta.schemaVersion'

# Handle unknowns explicitly
daemon-inspector list --json | jq '.daemons[] | select(.binary_path != null)'
```

---

Developed and maintained by Danylchuk Studios LLC.
