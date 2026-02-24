# Terminaut

[![License: MIT](https://img.shields.io/badge/License-MIT-informational.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-111111.svg)](#)
[![Language](https://img.shields.io/badge/language-Rust-dea584.svg)](#)
[![UI](https://img.shields.io/badge/ui-native%20macOS-0a84ff.svg)](#)

**A native macOS multi-window terminal launcher with a Finder-style path bar, instant folder jumps, and one-click terminal spawning.**

---

## Why Terminaut?

Finder gets you to folders. Terminals get you work done.  
**Terminaut** makes the jump *instant*:

- Path input at the top (paste, type, autocomplete)
- Quick folder selection (favorites / recents / pinned)
- Spawn **multiple terminal windows/tabs** in the same location
- Fast movement: parent / back-forward / breadcrumb clicks
- Designed for speed, not ceremony

---

## Features

### Core
- **Path Bar**: editable path + breadcrumb navigation
- **Finder Location Input**: paste any Finder path, POSIX path, or `~`
- **Quick Jump**:
  - Favorites (pinned folders)
  - Recent locations
  - Project roots (auto-detected via `.git`, `package.json`, `Cargo.toml`, etc.)
- **Multi-launch**:
  - Spawn N windows at once
  - Spawn as tabs (if configured)
  - Choose terminal: Terminal.app / iTerm2 / Ghostty (via adapters)

### Power-user
- **Hotkeys** (global / in-app)
- **Profiles** (per-project command presets: `bun dev`, `cargo watch`, etc.)
- **Workspace layouts** (2x2, 3-column, etc.)
- **Clipboard actions** (copy path, copy `cd` command, copy project env)

---

## Roadmap

- [ ] Native macOS UI (SwiftUI shell) + Rust core
- [ ] Finder integration: “Open in Terminaut”
- [ ] iTerm2 and Ghostty adapters
- [ ] Spotlight-like fuzzy folder picker
- [ ] Workspace layouts + saved sessions
- [ ] File watcher triggers (optional)
- [ ] Minimal permissions, no telemetry

---

## Architecture

Terminaut is a **native macOS app** with a **Rust core**.

- **UI:** SwiftUI (macOS)
- **Core:** Rust (path resolution, indexing, launching, config)
- **Bridge:** UniFFI (Rust <-> Swift) or FFI via C ABI
- **Launch adapters:** small modules per terminal app (Terminal/iTerm/Ghostty)

```

Terminaut.app (SwiftUI)
|
|  (UniFFI / FFI)
v
Rust Core (term-core)
|
+-- path resolver / normalization
+-- recents + favorites store
+-- project detection
+-- terminal launch adapters

```

---

## Repo Layout

```
terminaut/
├── Cargo.toml                 # Rust workspace manifest
├── crates/
│   ├── term-core/             # Rust core library + FFI/JSON surface
│   └── term-core-cli/         # CLI bridge consumed by the SwiftUI shell
└── apps/
    └── macos/
        └── Terminaut/        # SwiftUI app (Swift Package)
            ├── Package.swift
            └── Sources/     # AppState, views, services
```

---

## Quick Start (local build)

Prereqs:
- macOS 13+
- Rust toolchain (`rustup` + stable target)
- Xcode command line tools (for SwiftUI + `swift run`)

Steps:
1. **Build the Rust core + CLI bridge**
   ```bash
   cargo build -p term-core-cli
   ```
   This produces `target/debug/term-core-cli` which stores favorites/recents in `~/Library/Application Support/Terminaut/state.json`.

2. **(Optional) expose the CLI location** – the Swift app will auto-discover `../../target/{debug,release}/term-core-cli` relative to its working directory. If you relocate it, point to it manually:
   ```bash
   export TERMINAUT_CORE_BIN=/absolute/path/to/term-core-cli
   ```

3. **Run the SwiftUI shell**
   ```bash
   cd apps/macos/Terminaut
   swift run TerminautApp
   ```
   The window should launch with your home folder loaded. Favorites, recents, and detected project roots flow through the Rust core via the CLI.

4. **Launch terminals** – pick Terminal/iTerm2/Ghostty in the control panel, choose how many windows to spawn, and click *Open Terminal Here*. AppleScript bridges create the requested windows/tabs and sync recents back into the Rust store.

### Verifying the core library without the UI

```
cargo run -p term-core-cli -- list ~
cargo run -p term-core-cli -- favorites add ~/Projects
cargo run -p term-core-cli -- recents list | jq
```
These commands return JSON payloads that match what the SwiftUI app expects.

---

## Contributing

PRs welcome:
- Terminal adapters
- Folder picker UX patterns
- Workspace/layout ideas
- Performance + indexing strategies

Open an issue with:
- Your terminal app (Terminal/iTerm/Ghostty)
- Your preferred workflow (tabs vs windows, layouts, hotkeys)
- Any must-have Finder behavior

---

## License

MIT — see [LICENSE](LICENSE).
