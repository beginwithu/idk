# `quattro-hypr` Architecture & Verification Reference

Quick-reference map and invariants when maintaining or further optimizing the `quattro-hypr` repository.

## Repository Layout

- `bin/quattro` & `bin/quattro-*`: Modular Bash/Python CLI commands. `bin/quattro` parses `# quattro:summary=...` / `# quattro:args=...` headers for routing and `--help`.
- `default/bash/`: Interactive shell chain (`bashrc` -> `envs` -> `env-bootstrap`, `init`, `completions`, `lib-common.sh`, `lib-shell-config.sh`, `fns/*`).
- `default/hypr/`: Hyprland Lua config (`bootstrap.lua`, `require_all.lua`, `helpers.lua`, `monitor-workspaces.lua`, `qconsole.lua`, `toggles.lua`, `workspace-layouts.lua`) and `default/hypr/titlebars/` C++ plugin (`main.cpp`, `barDeco.hpp`, `barDeco.cpp`, `appName.cpp`).
- `shell/`: Quickshell desktop shell (`shell.qml`, `Commons/`, `Ui/`, `services/`, `plugins/`).
- `themes/<theme>/`: 10 curated themes (`colors.toml`, `backgrounds/`, optional overrides), rendered into `~/.local/state/quattro/current/theme/` by `bin/quattro-theme-set*`.
- `install.sh`, `uninstall.sh`, `verify.sh`: Installer, uninstaller, and comprehensive verification suite.

## Strict Repository Invariants (Enforced by `./verify.sh`)

1. **Every file directly in `bin/` (`-maxdepth 1 -type f`)**:
   - Must have executable bit set (`chmod +x`).
   - If a Bash script, must contain `set -eo pipefail` or `set -euo pipefail`.
   - Must not be deleted or renamed without checking git-history callers (`verify.sh` scans git history of `bin/quattro-*` to catch stale references to removed commands, and runs `bin/quattro commands --check`).
2. **Menu command integrity**:
   - Every `quattro-*` command referenced in `action`, `when`, `checked`, or `disabled` inside `default/quattro/quattro-menu.jsonc` must exist in `bin/`.
3. **Repository hygiene**:
   - Keep `.agents/` directories out of the repo tree (store skills globally in `~/.gemini/config/skills/`); contributor conventions live in root `AGENTS.md`.
   - Never leave `__pycache__` or `*.pyc` files in `bin/` or `default/`.
   - Ensure all packages in `packages/arch-core.packages` exist in official Arch repos.

## Standard Verification Command Sequence

Run this single chained check after making changes in `quattro-hypr`:

```bash
./verify.sh && \
  g++ -std=c++23 -O2 -Wall -Wextra -c default/hypr/titlebars/appName.cpp -o /tmp/appName.o && \
  rm -f /tmp/appName.o && \
  test -z "$(find . -path './.git' -prune -o \( -name '__pycache__' -o -name '*.pyc' \) -print)"
```
