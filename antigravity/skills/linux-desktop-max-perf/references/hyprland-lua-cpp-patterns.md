# Hyprland Lua Modules & C++ Compositor Plugin Optimization

## 1. Hyprland Lua Config & Reload Performance

Hyprland evaluates Lua config files synchronously during startup and `hyprctl reload`. Keep reloads allocation-light, fork-free, and side-effect-free when state is unchanged.

### Avoid `find | sort` in `io.popen`
- Replace `io.popen("find ... -name '*.lua' | sort")` with a lightweight shell glob loop (`for f in "$dir"/*.lua; do [ -f "$f" ] && printf '%s\n' "$f"; done`), which Bash/sh expands sorted in-process without forking `find` or `sort`.

### Idempotent `package.path` Setup
- Unguarded `package.path = entry .. ";" .. package.path` grows `package.path` on every `hyprctl reload`, slowing down every subsequent `require()`.
- Use a plain-substring guard and **preserve prepend order** (last prepended entry sits at the front of `package.path`):
  ```lua
  local function ensure_package_path(entry)
    if not (";" .. package.path .. ";"):find(";" .. entry .. ";", 1, true) then
      package.path = entry .. ";" .. package.path
    end
  end

  -- Results in: state_home; config_home; quattro_path; <default>
  ensure_package_path(quattro_path .. "/?.lua")
  ensure_package_path(config_home .. "/?.lua")
  ensure_package_path(state_home .. "/?.lua")
  ```

### Skip No-Op State File Writes
- Modules that persist state files watched by Quickshell `FileView` (e.g., `monitors`, `workspaces`) must initialize `last_written = raw_loaded_on_disk` when loading.
- Only open/write the state file when `serialized ~= last_written`. Unnecessary writes wake up `inotify` / `FileView` watchers and trigger redundant UI rebuilds on every `hyprctl reload`.

### Cache `$PATH` Binary Probes & Short-Circuit IPC Loops
- Split `os.getenv("PATH")` once per module load and memoize `cmd_present(name)` in a local Lua table.
- When checking special workspaces (e.g., `special:qconsole`), verify the workspace exists before fetching the full `clients` list, and `break` out of client loops as soon as the threshold count (e.g., `tiled > 1`) is reached.

---

## 2. Hyprland C++ Titlebar / Decoration Plugins

Compositor plugins run inside Hyprland's main render and input threads. Any heap allocation, linear scan, or redundant box calculation in `renderPass` or pointer-motion callbacks directly impacts frame pacing at high refresh rates (120–360 Hz).

### Compile Flags
- Build production compositor plugins with `-O2` (not `-O1` or `-O0`) alongside `-std=c++23`.

### `O(1)` `.desktop` App Name Indexing
- Never linearly scan a `std::vector` and call `std::transform(..., ::tolower)` on every lookup.
- When indexing XDG `.desktop` files:
  1. Stop reading each `.desktop` file as soon as a new `[Section]` header appears after `[Desktop Entry]` (avoids parsing `[Desktop Action ...]` blocks).
  2. Populate two `std::unordered_map<std::string, std::string>` tables at index time (`g_byWmClass[lower(startupWmClass)]` and `g_byLowerId[lower(desktopId)]`).
  3. Lookups lowercase only the query key once and perform `O(1)` hash lookups.

### Zero-Allocation Steady-State `renderPass`
- Cache `m_szLastAppID` and `m_szLastRawTitle` on the decoration instance.
- Recompute display title text and re-render the Cairo/Pango title texture **only** when `window->m_class != m_szLastAppID || window->m_title != m_szLastRawTitle` (plus a throttled timestamp check, e.g., every 2 seconds, if checking `.desktop` cache invalidation), rather than allocating `std::string` copies every frame.

### Early-Exit Pointer Hover Damage
- In `damageOnButtonHover()` (invoked on pointer movement):
  - Immediately return if the window has no active titlebar/buttons (`!m_bButtonsVisible` or hidden decoration).
  - Hoist `assignedBoxGlobal()` outside the button hit-test loop so geometry is computed once per event instead of once per button.
  - Issue compositor `damageBox` **only** when a button's hover boolean actually flips state.
