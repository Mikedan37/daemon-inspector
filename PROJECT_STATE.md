# daemon-inspector: Project State (v1.2)

## Purpose

**daemon-inspector** is a forensic, read-only daemon and background task introspection tool for macOS, written in Swift. It answers questions that macOS does not answer clearly:

- What background processes exist on my machine?
- How do they change over time?
- Which ones are unstable?
- What is the backing binary for a given daemon?

It does this by **observing, not guessing**.

---

## What This Tool Is

- A forensic recorder that preserves observable facts
- A read-only introspection instrument
- A durable memory organ for system state
- A tool that preserves uncertainty rather than inventing certainty

## What This Tool Is Not

- A monitoring platform
- A management tool or controller
- An agent framework
- A UI product or dashboard
- A policy engine
- A health scoring system

---

## v1.2 Capabilities

### Core Commands

| Command | Purpose |
|---------|---------|
| `list` | Collect and display current daemon state, persist snapshot |
| `sample --every <t> --for <d>` | Collect snapshots at fixed cadence |

### Binary Inspection (v1.2)

| Command | Purpose |
|---------|---------|
| `inspect binary <label>` | Inspect binary metadata for a daemon |

Collects: path, exists, type (mach-o/script/unknown), architecture, size, owner, permissions, symlink status, volume type, code signature presence.

**Facts only. No trust judgment. No code execution.**

### Change-First Commands (v1.1)

| Command | Purpose |
|---------|---------|
| `changed` | Show all daemons with derived events |
| `appeared` | Show daemons that appeared |
| `disappeared` | Show daemons that disappeared |
| `churn` | Show daemons with multiple events (sorted) |
| `diff` | Show changes between latest snapshots |
| `compare` | Side-by-side snapshot comparison |
| `timeline <label>` | Forensic history for one daemon |
| `unstable` | Daemons with observed instability |

### Internal Commands

| Command | Purpose |
|---------|---------|
| `verify` | Internal validation (determinism, append-only) |

### Output Options

| Option | Purpose |
|--------|---------|
| `--json` | Output in JSON format (disables pager) |
| `--table` | Display list in tabular format |
| `--detailed` | Display in detailed format |
| `--no-pager` | Disable interactive pager, print plain text |
| `--since <duration>` | Filter to snapshots within duration |
| `--until <duration>` | Filter to snapshots older than duration |
| `--expect-stable` | Quiet mode for diff (exit 0 if no changes) |

### Deterministic Filters (v1.1)

| Filter | Purpose |
|--------|---------|
| `--domain <d>` | Filter by domain (gui/system/unknown) |
| `--running` | Show only running daemons |
| `--stopped` | Show only stopped daemons |
| `--has-binary` | Show only daemons with known binary path |
| `--no-binary` | Show only daemons without binary path |
| `--label-prefix <p>` | Filter by label prefix |

### Terminal UI

- Built-in scrollable pager (no external dependencies)
- TTY-aware: uses pager in terminal, plain text when piped
- Keyboard controls: j/k scroll, g/G jump, q quit
- Table view for compact daemon lists
- JSON mode bypasses pager completely

---

## Architecture

### Module Design

```
Sources/
├── Collector/       # Platform-specific observation (macOS launchd)
├── Model/           # Domain models and event derivation
├── Storage/         # BlazeDB persistence layer
├── Inspector/       # Binary inspection (v1.2)
├── TerminalUI/      # Pager and table rendering
└── InspectorCLI/    # CLI interface
```

### Layer Responsibilities

1. **Collector Layer**
   - Observes macOS launchd daemons
   - Phase 1: Fast discovery via `launchctl list`
   - Phase 2: Enrichment via `launchctl print`
   - No state, no decisions, no mutations
   - Marks unknown fields explicitly

2. **Storage Layer (BlazeDB)**
   - Append-only, encrypted, durable storage
   - Location: `~/.daemon-inspector/`
   - Stores snapshots and daemon records
   - No derived state at rest
   - Survives restarts, reboots, long gaps

3. **Event Derivation (in-memory)**
   - Derives events by comparing snapshots
   - Event types: appeared, disappeared, started, stopped, pidChanged, binaryPathChanged
   - Time windows, not point-in-time
   - Deterministic and idempotent
   - Never invents causality

4. **Inspector Layer (v1.2)**
   - Read-only binary inspection
   - Collects: file type, architecture, size, ownership, permissions
   - Detects: symlinks, volume type, code signature presence
   - Never executes code
   - No trust judgment

5. **CLI Layer**
   - Queries stored observations
   - Derives events in-memory
   - Produces human-readable or JSON output
   - Never mutates state

---

## What It Observes

For each daemon (snapshot):
- **Label**: e.g., "com.apple.some.daemon"
- **Domain**: system, gui/<uid>, or unknown
- **Running state**: PID if running, nil otherwise
- **Binary path**: if discoverable
- **Observation timestamp**: when this was observed

For each event (derived):
- **Time window**: when the change occurred (between two snapshots)
- **Type**: what kind of state transition
- **Details**: PID values, paths, etc.

For binary inspection (on-demand):
- **Path**: resolved absolute path
- **Exists**: whether the file is present on disk
- **Type**: mach-o, script, or unknown
- **Architecture**: arm64, x86_64, universal, or unknown
- **Size**: file size in bytes
- **Ownership**: uid/gid and user/group names
- **Permissions**: POSIX permissions (rwx format)
- **Symlink**: whether it's a symbolic link, resolved path if so
- **Volume**: system (sealed), data, external, or unknown
- **Code signature**: present or not (no trust validation)

---

## Design Invariants (Non-Negotiable)

### 1. Read-Only
- Never start, stop, restart, signal, or modify daemons
- Never write to system configuration
- Never influence scheduling or execution

### 2. Honest Output
- Every output maps to an observable fact
- Unknown stays unknown
- Time windows, not fabricated timestamps
- Absence is ambiguous unless proven

### 3. Append-Only Storage
- Snapshots are immutable once written
- History cannot be rewritten
- Partial writes are allowed (reality is messy)
- No derived state at rest

### 4. No Invented Meaning
- No health scores
- No severity levels
- No "likely cause"
- No recommended actions
- Events are derived, not stored

### 5. CLI-Only, Local-Only
- No GUI, no dashboards
- No networking, no cloud, no telemetry
- No background agents

---

## What Still Needs Work

### Testing Environment
- macOS TCC/sandbox blocks BlazeDB in test subprocesses
- Need: containerized Linux runner, mock adapter, or single-process tests

### Resilience
- Validate behavior on interruption mid-sampling
- Validate behavior on locked/partial DB
- Graceful failure in all commands

### Documentation
- README for external users
- Explain what it does and what it refuses to do

### Future Features (not v1)
- Linux systemd collector
- Trigger mechanism detection
- Start time extraction
- Performance optimization for enrichment (currently limited)

---

## Usage Examples

### Basic Workflow
```bash
# Collect current state
daemon-inspector list

# Wait, do something, collect again
daemon-inspector list

# See what changed
daemon-inspector diff
```

### Sampling Over Time
```bash
# Collect snapshots every 2 seconds for 2 minutes
daemon-inspector sample --every 2s --for 2m

# See what was unstable
daemon-inspector unstable --since 30m
```

### Forensic Investigation
```bash
# What happened to Finder?
daemon-inspector timeline com.apple.Finder

# What is this daemon backed by?
daemon-inspector inspect binary com.apple.Finder

# Show as table
daemon-inspector list --table

# Export for scripting
daemon-inspector list --json | jq '.daemons[] | select(.is_running)'
```

### Binary Inspection (v1.2)
```bash
# Inspect a daemon's binary
daemon-inspector inspect binary com.apple.keyboardservicesd

# JSON output for scripting
daemon-inspector inspect binary com.apple.Finder --json
```

---

## Why This Tool Exists

Most observability tools:
- Sample too aggressively
- Invent metrics
- Collapse uncertainty
- Optimize for dashboards
- Require kernel access or special privileges

This tool:
- Preserves uncertainty
- Compounds truth over time
- Works on locked-down systems
- Doesn't need entitlements
- Doesn't need kernel access
- Refuses to lie

**This is ground truth, not a toy.**

---

## Technical Details

### Dependencies
- Swift 5.9+
- macOS 14.0+
- BlazeDB (embedded, encrypted storage)

### Storage Location
- `~/.daemon-inspector/` (or `DAEMON_INSPECTOR_DB_PATH` env var)

### Build
```bash
swift build -c release
ln -sf $(pwd)/.build/release/daemon-inspector ~/bin/daemon-inspector
```

---

## Conclusion

**daemon-inspector v1.2** is a complete forensic introspection tool that:

- Observes background execution over time
- Stores immutable snapshots in append-only storage
- Derives events without inventing causality
- Preserves uncertainty explicitly
- Inspects backing binaries on-demand (v1.2)
- Provides change-first views (v1.1)
- Provides a usable terminal UI

It is designed to be boring, honest, and trustworthy.

---

## What v1.2 Closed

The loop between:
- "What exists" (list)
- "What changed" (diff, changed, churn, timeline)
- "What backs it" (inspect binary)

Most tools answer one. This tool answers all three without lying.

---

## What's Next (Not v1.2)

### Potential v1.3: Narrative Commands
- `explain <label>` - Compose facts into sentences
- `summary` - System-wide narrative
- `unknowns` - Explain why unknowns exist

### Potential v1.3: Cross-Cutting Views
- Combine filters with change detection
- "Show me changed daemons that are not system binaries"

### Longer Term
- Linux systemd collector
- Library extraction (not just CLI)
- Trigger mechanism detection

---

## Philosophical Position

This tool is closer to:
- `fs_usage`
- `ktrace`
- launchd debugging tools Apple never shipped

Than to:
- EDR vendors
- Activity Monitor
- Dashboard products

It is an instrument for understanding, not a product for selling.

**This is ground truth, not a toy.**
