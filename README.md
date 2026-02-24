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

## Repo Layout (planned)

```

terminaut/
apps/
macos/
Terminaut/                 # SwiftUI app
Terminaut.xcodeproj
crates/
term-core/                   # Rust core library
term-adapters/               # Terminal/iTerm/Ghostty adapters
term-index/                  # Folder index + fuzzy search
assets/
icon/
docs/
scripts/
LICENSE
README.md

```

---

## Build (coming soon)

Terminaut is in early development. Build instructions will land once the first native shell is committed.

Planned:
- Rust stable
- Xcode / Swift toolchain
- `cargo build -p term-core`
- Xcode build for `apps/macos`

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
