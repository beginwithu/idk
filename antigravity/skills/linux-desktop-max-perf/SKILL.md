---
name: linux-desktop-max-perf
description: >-
  Audits and optimizes Linux desktop environments, Wayland/Hyprland configs,
  Quickshell QML/JS shells, Bash CLI/startup scripts, Python helpers, Lua
  modules, and C++ compositor plugins for maximum performance, low latency, and
  minimal CPU/RAM overhead. Use this skill when the user asks to optimize,
  revise for speed/efficiency, reduce process forks or memory allocations, fix
  startup/hotkey latency, or tune repositories like quattro-hypr.
---

# Linux Desktop & Shell Max-Performance Skill

Systematic runbook for squeezing maximum speed, lowest latency, and minimal memory/process overhead out of Linux desktop stacks (Bash, Python, Hyprland Lua/C++, and Quickshell QML/JavaScript) **without breaking CLI contracts, IPC payloads, or visual behavior**.

## End-to-End Workflow

1. **Capture Baselines Before Editing**
   - Record deterministic outputs of hot CLI commands (e.g., color generators, i18n lookups, `--help` outputs) into a scratch directory so optimized implementations can be diffed bit-for-bit.
   - Time representative commands in-process using Bash `$EPOCHREALTIME` loops (works even when `/usr/bin/time` is absent).

2. **Run the Hotspot Scanner**
   - Execute [audit-hotspots.sh](./scripts/audit-hotspots.sh) against the target workspace:
     ```bash
     bash ~/.gemini/config/skills/linux-desktop-max-perf/scripts/audit-hotspots.sh /path/to/repo
     ```
   - Group findings by execution frequency:
     1. **Per-frame / pointer-move** (C++ compositor `renderPass` / hover damage, QML bindings)
     2. **Per-keystroke** (Quickshell JS launcher, menu, emoji, and clipboard search)
     3. **Per-hotkey / OSD** (volume, brightness, window/monitor management, screenshot, i18n)
     4. **Per-shell / reload** (`.bashrc` startup chain, `hyprctl reload` Lua modules, theme switchers)
     5. **Install / CI verification** (`install.sh`, `uninstall.sh`, `verify.sh`)

3. **Apply Subsystem Optimizations (Load Only Needed References)**
   - **Bash startup, CLI scripts, hex math, JSON/i18n fast paths, `hyprctl`/`pacman` batching**: read [bash-and-cli-patterns.md](./references/bash-and-cli-patterns.md).
   - **Hyprland Lua reload idempotence & C++ titlebar/plugin render loops**: read [hyprland-lua-cpp-patterns.md](./references/hyprland-lua-cpp-patterns.md).
   - **Quickshell QML lazy loading, V4 engine `QObject`/`var` safety, & `O(1)` JS search models**: read [quickshell-qml-js-patterns.md](./references/quickshell-qml-js-patterns.md).
   - **`quattro-hypr` repository map, strict invariants, & `verify.sh` rules**: read [quattro-hypr-architecture.md](./references/quattro-hypr-architecture.md).

4. **Verify Equivalence & Regressions in One Batched Pass**
   - Syntax-check every touched language (`bash -n`, `python3 -B` `ast.parse`, `luac -p`, `g++ -std=c++23 -O2 -Wall -Wextra -c`).
   - Diff outputs of pure-Bash fast paths (`theme-color`, `i18n`, `osd`, JSON builders) against reference Python/baseline outputs, including edge cases (`--number`, negative counts, missing keys, backslash escapes).
   - Confirm zero stray `__pycache__` / `*.pyc` files in the repository (`find . -name '__pycache__' -o -name '*.pyc'`).
   - Run the project's test/verification script (e.g., `./verify.sh`) and confirm `0` failures.

## Critical Anti-Traps (Never Violate)

- **Never pass NUL bytes (`$'\0'`) inside CLI `argv` strings**: `execve()` C-strings truncate or strip NULs silently. Pass NUL-delimited streams via `stdin` (`-print0 | python3 ...`) or pass separate `argv` arguments.
- **Never mutate QML C++ `QObject` instances or live QML `property var` maps in place**:
  - Attaching `_cache` fields onto `DesktopEntry` (`QObject`) fails in QML's V4 engine. Use local JS metadata objects or WeakMap/id maps.
  - Mutating objects already stored in QML `property var` can silently drop keys in V4. Stamp precomputed fields (`_nameSearch`, `_labelLower`, `_descWords`) on fresh plain JS objects *before* assigning the map to QML.
- **Watch `shift` offsets in Bash fast paths**: When adding an early exit after argument parsing (e.g., `--number` mode), verify positional indices (`$1` vs `$2`) under `set -u` (`set -euo pipefail`).
- **Preserve `package.path` priority when deduplicating prepends**: Prepending `A`, then `B`, then `C` puts `C` first (`C;B;A;...`). Keep call order identical while guarding with plain-substring `find(";" .. entry .. ";", 1, true)`.
- **Avoid `fc-cache -f` in installers**: Use incremental `fc-cache` so unchanged system font directories are not rescanned from scratch.
