# daemon-inspector

A forensic, read-only tool for understanding what background services are doing on macOS.

---

## What this tool answers

- What daemons exist right now?
- What changed since the last observation?
- Which services keep restarting?
- What binary backs this daemon?
- Which daemons are unstable over time?

---

## What this tool never does

- Never modifies system state
- Never starts, stops, or restarts daemons
- Never executes inspected binaries
- Never invents meaning, scores, or severity levels
- Never sends data over the network
- Never requires root access for basic operation

---

## Who this is for

**macOS developers** debugging background behavior in their apps

**Platform and systems engineers** investigating daemon lifecycles

**Security and incident response** teams needing forensic evidence

**Power users** diagnosing battery drain, CPU spikes, or unexplained restarts

---

## How it works

1. **Observation**: Queries launchd for current daemon state
2. **Storage**: Persists snapshots in append-only, encrypted local storage
3. **Derivation**: Computes events (started, stopped, appeared, disappeared) by comparing snapshots
4. **Inspection**: Optionally examines binary metadata without execution

All conclusions are derived at read time. Raw observations are never modified.

---

## Installation

```bash
brew tap Mikedan37/daemon-inspector
brew install daemon-inspector
```

Or build from source:

```bash
git clone https://github.com/Mikedan37/daemon-inspector.git
cd daemon-inspector
swift build -c release
```

---

## Basic usage

```bash
# Take a snapshot of current state
daemon-inspector list

# See what changed
daemon-inspector diff

# Sample over time
daemon-inspector sample --every 2s --for 1m

# Find unstable daemons
daemon-inspector unstable

# Inspect a binary
daemon-inspector inspect binary com.apple.Finder
```

---

## Free vs Pro

**Free** (current release):
- All observation, storage, and derivation features
- Binary inspection
- JSON output for scripting
- Built-in pager and table views
- Fully functional, no limitations

**Pro** (planned):
- Narrative explanations derived from events
- Human-readable summaries
- No changes to Free functionality

Free remains complete and useful indefinitely. Pro is additive.

---

## Updates

If you want updates on daemon-inspector Pro, watch this repository or check back here.

For more information: [danylchukstudios.com](https://danylchukstudios.com)

---

## Design principles

1. **Read-only**: Cannot modify system state
2. **Append-only**: History cannot be rewritten
3. **Honest**: Unknown stays unknown
4. **Local-only**: No network, no telemetry
5. **Boring**: Correct over clever

---

## Stewardship

daemon-inspector is developed and maintained by **Danylchuk Studios LLC**.

Danylchuk Studios focuses on building low-level, developer-first tools for system introspection, debugging, and forensic analysis. All tools are designed to be honest, local-first, and respectful of system boundaries.

---

## Source

[GitHub: Mikedan37/daemon-inspector](https://github.com/Mikedan37/daemon-inspector)

Developed and maintained by Danylchuk Studios LLC (Michael Danylchuk).

MIT License
