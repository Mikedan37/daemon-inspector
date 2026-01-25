# daemon-inspector

A forensic, read-only daemon and background task introspection tool for macOS.

## What It Does

This tool answers questions macOS doesn't answer clearly:

- What background processes exist on my machine?
- How do they change over time?
- Which ones are unstable?
- What binary backs a given daemon?

It does this by **taking snapshots of system state**, **storing them durably**, and **deriving events by comparing snapshots**. No heuristics. No health scores. No guessing.

## What It Doesn't Do

- Monitor, manage, or control daemons
- Start, stop, or restart anything
- Send telemetry or connect to the network
- Invent meaning or assign severity
- Pretend to know things it can't verify

## Installation

### Homebrew (recommended)

```bash
# Install from local formula
brew install --build-from-source Formula/daemon-inspector.rb

# Or tap and install (when published)
# brew tap <user>/daemon-inspector
# brew install daemon-inspector
```

### Build from Source

```bash
git clone https://github.com/Mikedan37/daemon-background-task-introspection.git
cd daemon-background-task-introspection
swift build -c release

# Create symlink
ln -sf $(pwd)/.build/release/daemon-inspector ~/bin/daemon-inspector
```

### Swift Package Manager (as library)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/Mikedan37/daemon-background-task-introspection.git",
        from: "1.2.0"
    )
]
```

Available products:
- `DaemonInspectorCore` — Model, Collector, Inspector (no storage dependency)
- `DaemonInspectorStorage` — BlazeDB-backed persistence

```swift
import Model
import Collector
import Inspector

// Collect current daemon state
let collector = LaunchdCollector()
let snapshot = try collector.collect()

// Inspect a binary
let inspector = BinaryInspector()
let metadata = inspector.inspect(label: "com.apple.Finder", path: "/path/to/binary")
```

## Usage

### Collect Current State

```bash
daemon-inspector list
```

Shows all observable daemons with their PIDs, domains, and binary paths. Persists a snapshot to storage.

### See What Changed

```bash
daemon-inspector diff
```

Compares the latest two snapshots and shows what appeared, disappeared, started, stopped, or changed PID.

### Sample Over Time

```bash
daemon-inspector sample --every 2s --for 2m
```

Collects snapshots at fixed cadence. Useful for catching transient behavior.

### Investigate One Daemon

```bash
daemon-inspector timeline com.apple.Finder
```

Shows the forensic history of a single daemon: every observed state change, restarts, PID changes.

### Find Unstable Daemons

```bash
daemon-inspector unstable
```

Shows daemons sorted by "churn" - how many times they started, stopped, or changed PID.

### Inspect a Binary (v1.2)

```bash
daemon-inspector inspect binary com.apple.Finder
```

Shows metadata about the on-disk binary backing a daemon:
- File type (Mach-O, script, unknown)
- Architecture (arm64, x86_64, universal)
- Size, ownership, permissions
- Symlink status
- Volume type (system/sealed, data, external)
- Code signature presence (not trust validation)

**Read-only. No code execution. No trust judgment.**

### Change-First Commands (v1.1)

```bash
daemon-inspector changed      # All daemons with events
daemon-inspector appeared     # Daemons that appeared
daemon-inspector disappeared  # Daemons that disappeared
daemon-inspector churn        # Daemons with multiple events
daemon-inspector compare      # Side-by-side snapshot comparison
```

## Options

| Option | Effect |
|--------|--------|
| `--json` | Output JSON instead of text (disables pager) |
| `--table` | Show list as a compact table |
| `--detailed` | Show detailed format |
| `--no-pager` | Disable scrolling, print plain text |
| `--since <duration>` | Filter to snapshots within duration (e.g., `30m`, `1h`) |
| `--until <duration>` | Filter to snapshots older than duration |
| `--expect-stable` | Quiet mode for diff (exit 0 if no changes) |

### Filters (v1.1)

| Filter | Effect |
|--------|--------|
| `--domain <d>` | Filter by domain (gui, system, unknown) |
| `--running` | Show only running daemons |
| `--stopped` | Show only stopped daemons |
| `--has-binary` | Show only daemons with known binary path |
| `--no-binary` | Show only daemons without binary path |
| `--label-prefix <p>` | Filter by label prefix |

## Pager Controls

When running in a terminal, output is scrollable:

| Key | Action |
|-----|--------|
| `j` / Down | Scroll down |
| `k` / Up | Scroll up |
| `Space` | Page down |
| `b` | Page up |
| `g` | Jump to top |
| `G` | Jump to bottom |
| `q` | Quit |

When piped or with `--json`, pager is disabled automatically.

## Storage

Snapshots are stored in `~/.daemon-inspector/` using BlazeDB (append-only, encrypted).

- Snapshots survive restarts and reboots
- History cannot be rewritten
- Each snapshot is immutable once written

Override location with `DAEMON_INSPECTOR_DB_PATH` environment variable.

## Design Principles

1. **Read-only**: Never modifies system state
2. **Honest**: Unknown stays unknown, time windows not fabricated timestamps
3. **Append-only**: History cannot be rewritten
4. **No invented meaning**: Events are derived, not guessed
5. **Local-only**: No network, no telemetry

## Requirements

- macOS 14.0+
- Swift 5.9+

## Examples

```bash
# Basic workflow
daemon-inspector list          # Take snapshot
# ... do something ...
daemon-inspector list          # Take another
daemon-inspector diff          # See changes

# Sampling workflow
daemon-inspector sample --every 5s --for 1m
daemon-inspector unstable --since 10m

# Binary inspection
daemon-inspector inspect binary com.apple.Finder
daemon-inspector inspect binary com.apple.keyboardservicesd --json

# Filtering
daemon-inspector list --running --domain system
daemon-inspector churn --has-binary

# Scripting
daemon-inspector list --json | jq '.daemons[] | select(.is_running)'
daemon-inspector inspect binary com.apple.Finder --json | jq '.binary'
```

## Why This Tool Exists

Most observability tools collapse uncertainty into convenient lies. They sample too aggressively, invent metrics, and optimize for dashboards.

This tool preserves uncertainty. It records what the OS admits exists, marks unknowns explicitly, and lets you reason about time as intervals, not fabricated points.

It's designed to be boring, honest, and trustworthy.

## Future: daemon-inspector Pro

**Pro is additive, not required.**

The free version remains fully functional indefinitely. Pro adds:

- Narrative explanations derived from existing events
- Human-readable summaries of daemon behavior
- No changes to existing command semantics

Pro never overrides Free behavior. Free remains fully scriptable and complete.

Try the stub:
```bash
daemon-inspector explain com.apple.Finder
```

## Project Stewardship

This project is developed and maintained by **Danylchuk Studios LLC**.

The goal is to produce durable, low-level tools that prioritize correctness, transparency, and developer trust over dashboards or automation.

## Links

- [Documentation](https://mikedan37.github.io/daemon-inspector/)
- [GitHub](https://github.com/Mikedan37/daemon-inspector1)
- [Homebrew Tap](https://github.com/Mikedan37/homebrew-daemon-inspector)

---

Developed and maintained by Danylchuk Studios LLC (Michael Danylchuk).
