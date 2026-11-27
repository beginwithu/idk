# Bash Startup, CLI Hot Paths & Process-Fork Elimination

Every external command (`dirname`, `basename`, `cat`, `head`, `cut`, `tr`, `awk`, `sed`, `date`, `jq`, `grep`) in Bash costs ~0.8–3 ms in `fork()` + `execve()`, and `$(...)` command substitutions fork a subshell even for builtins. On hotkey paths (volume, brightness, OSD, window actions) or loops over 50–200 files, removing forks yields 3x–15x speedups.

## 1. Return Values Without Subshells (`REPLY` Convention)

Replace `val=$(helper "$arg")` with functions that write to `REPLY` (or named globals):

```bash
# BEFORE (forks a subshell on every call)
join_by() { local IFS="$1"; shift; printf '%s' "$*"; }
out=$(join_by '|' "${items[@]}")

# AFTER (zero forks)
join_by_into() { local IFS="$1"; shift; REPLY="$*"; }
join_by_into '|' "${items[@]}"
out=$REPLY
```

## 2. Pure-Bash Replacements for Coreutils

| Slow Fork Pattern | Zero-Fork Bash Builtin |
| :--- | :--- |
| `$(dirname -- "$p")` | `dir=${p%/*}; [[ $dir == "$p" ]] && dir="."` (or `${p:-/}` when root) |
| `$(basename -- "$p" .ext)` | `base=${p##*/}; base=${base%.ext}` |
| `$(cat "$file")` | `content=$(<"$file")` or `IFS= read -r line <"$file"` (zero fork for single line!) |
| `head -n1 "$f" \| grep -q bash` | `IFS= read -r shebang <"$f" \|\| true; [[ $shebang == *bash* ]]` |
| `$(date +%s)` | `printf -v now '%(%s)T' -1` |
| `$(date +%s%3N)` (ms timestamp) | `ts=${EPOCHREALTIME/./}; ms=${ts:0:13}` |
| `sha256sum "$f" \| awk '{print $1}'` | `read -r hash _ < <(sha256sum "$f")` |
| `wc -l <"$f"` | Count lines while reading, or `mapfile -t lines <"$f"; count=${#lines[@]}` |
| `grep -qx "$mime" <<<"$types"` | `[[ $'\n'"$types"$'\n' == *$'\n'"$mime"$'\n'* ]]` |

## 3. Pure-Bash Hex Color Mixing & Luminance

Avoid spawning `awk` + `printf` per color token in theme generators:

```bash
# Mix hex color $1 into $2 with weight $3 (0..100 integer percent), rounded half-up:
mix_into() {
  local c1=${1#\#} c2=${2#\#} w=$3 inv=$(( 100 - $3 ))
  local r=$(( (16#${c1:0:2} * w + 16#${c2:0:2} * inv + 50) / 100 ))
  local g=$(( (16#${c1:2:2} * w + 16#${c2:2:2} * inv + 50) / 100 ))
  local b=$(( (16#${c1:4:2} * w + 16#${c2:4:2} * inv + 50) / 100 ))
  printf -v REPLY '#%02x%02x%02x' "$r" "$g" "$b"
}
```

## 4. Safe Pure-Bash JSON Escaping & Fast Paths

For simple flat payloads (OSD messages, notifications, clipboard image metadata, English `i18n` catalogs), avoid spawning `jq` (~12 ms startup):

```bash
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  REPLY=$s
}
```

- **Catalog lookup fast path (`quattro-i18n` pattern)**: When language is `en`, scan `en/cli.json` with `while IFS= read -r line` in Bash (~0.4–4 ms total script time). If any matched value contains a backslash escape (`[[ $val == *\\* ]]`) or language is non-English, fall back cleanly to `jq`.

## 5. Batching IPC, Package Manager, and Filesystem Queries

- **Hyprland IPC**:
  - Combine multiple queries: `hyprctl --batch -j "monitors;clients"` and parse once.
  - Combine dispatches: `hyprctl --batch "dispatch focuswindow ...; dispatch moveactive ..."` instead of sequential `hyprctl` invocations.
  - Merge multi-field `jq` extractions into one `@tsv` call:
    `IFS=$'\t' read -r width height scale < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | [.width, .height, .scale] | @tsv')`
- **Pacman**:
  - Never loop `for pkg in "${pkgs[@]}"; do pacman -Qq "$pkg"; done` (100 spawns). Run `mapfile -t installed < <(pacman -Qq "${pkgs[@]}" 2>/dev/null || true)` once!
- **`stat` & TSV Cache Indexes**:
  - Preload `index.tsv` into `declare -A idx_map=()` once before loops instead of running `awk` per file.
  - Batch `stat -Lc '%s:%Y' -- "${files[@]}"` once and map back by array index (with per-file fallback if counts differ).
- **`/sys` and `/proc` Polling**:
  - Read `/sys/class/power_supply/*` or `/sys/class/leds/*` single-value files with `read -r val <"$path"` directly in Bash; combine multi-file `/proc/stat` + `/proc/meminfo` calculations into a single `awk` invocation.

## 6. Interactive Shell Startup (`.bashrc`)

1. **Idempotent Environment Bootstrap**: Guard session/PATH setup with an unexported shell variable (`_env_bootstrapped=1`) so `.bashrc` sourcing `envs` + `env-bootstrap` never runs PATH deduplication twice in one shell.
2. **Guard Missing Wrapper Directories**: Check `[[ -d $wrapper_dir ]]` before splitting and rebuilding `$PATH`.
3. **Cache Tool Init Scripts (`starship`, `zoxide`, `mise`)**:
   - Store generated init code under `${XDG_CACHE_HOME:-$HOME/.cache}/<app>/bash-init/`.
   - Invalidate automatically by comparing `[[ $cache_file -nt $binary_path ]]` (e.g., `/usr/bin/starship`), regenerating atomically via `tmp` + `mv -f`.

## 7. Python CLI Hygiene

- Use `#!/usr/bin/env -S python3 -B` on standalone scripts in `bin/` (and `python3 -B` when invoking helper modules) so Python never writes `__pycache__/*.pyc` into runtime directories or dirty git trees.
- Batch `ast.parse` syntax checks across all Python files in a single `python3 -B - "${py_files[@]}"` process during CI/verification.
