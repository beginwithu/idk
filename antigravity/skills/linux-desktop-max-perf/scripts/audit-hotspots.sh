#!/bin/bash
# Scans a Linux desktop / shell / dotfiles repository for common performance hotspots.
# Usage: audit-hotspots.sh [target_dir]

set -euo pipefail

TARGET_DIR=${1:-.}
if [[ ! -d $TARGET_DIR ]]; then
  printf 'Error: directory not found: %s\n' "$TARGET_DIR" >&2
  exit 1
fi
TARGET_DIR=$(cd -- "$TARGET_DIR" && pwd)

section() {
  printf '\n==> %s\n' "$1"
}

report_matches() {
  local label=$1
  local output=$2
  if [[ -n $output ]]; then
    printf '  [FOUND] %s:\n' "$label"
    printf '%s\n' "$output" | sed -n '1,20p' | sed 's/^/    /'
    local total=0
    while IFS= read -r _; do total=$((total + 1)); done <<<"$output"
    if (( total > 20 )); then
      printf '    ... (%d more matches)\n' "$((total - 20))"
    fi
  else
    printf '  [CLEAN] %s\n' "$label"
  fi
}

printf 'Auditing performance hotspots in: %s\n' "$TARGET_DIR"

section "1. Python Bytecode Hygiene (__pycache__ & missing -B)"
pyc_hits=$(find "$TARGET_DIR" -path '*/.git' -prune -o \( -name '__pycache__' -o -name '*.pyc' \) -print 2>/dev/null || true)
report_matches "Stray __pycache__ or .pyc files" "$pyc_hits"

py_no_b=$(grep -rnI --exclude-dir=.git -E '^#!.*python' "$TARGET_DIR" 2>/dev/null | grep -vE ' -[A-Za-z]*B\b' || true)
report_matches "Python shebangs without -B flag" "$py_no_b"

section "2. Bash Subshell & Coreutils Fork Hotspots"
fork_hits=$(grep -rnI --exclude-dir=.git --include='*.sh' \
  -E '\$\((dirname|basename|cat|date|wc|tr|cut)\b|`(dirname|basename|cat|date|wc|tr|cut)\b' \
  "$TARGET_DIR" 2>/dev/null || true)
if [[ -d $TARGET_DIR/bin ]]; then
  bin_forks=$(grep -rnI -E '\$\((dirname|basename|cat|date|wc|tr|cut)\b' "$TARGET_DIR/bin" 2>/dev/null || true)
  [[ -n $bin_forks ]] && fork_hits=${fork_hits:+$fork_hits$'\n'}$bin_forks
fi
report_matches "Subshell forks for dirname/basename/cat/date/wc/tr/cut" "$fork_hits"

fc_force=$(grep -rnI --exclude-dir=.git -E '\bfc-cache[[:space:]]+-[a-zA-Z]*f' "$TARGET_DIR" 2>/dev/null || true)
report_matches "Forced full font-cache rebuilds (fc-cache -f)" "$fc_force"

section "3. Unbatched Compositor / Package Queries"
hypr_seq=$(grep -rnI --exclude-dir=.git -E '^[[:space:]]*hyprctl[[:space:]]+dispatch\b' "$TARGET_DIR" 2>/dev/null || true)
report_matches "Individual hyprctl dispatch calls (check if consecutive calls can use --batch)" "$hypr_seq"

pacman_loop=$(grep -rnI --exclude-dir=.git -B1 -E 'pacman[[:space:]]+-Q' "$TARGET_DIR" 2>/dev/null | grep -E 'for |while ' || true)
report_matches "Potential pacman -Q inside loops" "$pacman_loop"

section "4. Lua & C++ Compositor Checks"
lua_find=$(grep -rnI --exclude-dir=.git --include='*.lua' -E 'io\.popen.*find ' "$TARGET_DIR" 2>/dev/null || true)
report_matches "Lua io.popen('find ...') spawns" "$lua_find"

lua_pkgpath=$(grep -rnI --exclude-dir=.git --include='*.lua' -E '^[[:space:]]*package\.path[[:space:]]*=' "$TARGET_DIR" 2>/dev/null || true)
report_matches "Lua package.path assignments (verify reload idempotence)" "$lua_pkgpath"

cpp_o1=$(grep -rnI --exclude-dir=.git -E '(OPT_FLAG|CXXFLAGS).*(-O0|-O1)\b' "$TARGET_DIR" 2>/dev/null || true)
report_matches "Sub-optimal C++ optimization flags (-O0/-O1)" "$cpp_o1"

section "5. Quickshell QML / JS Hotspots"
qml_json=$(grep -rnI --exclude-dir=.git --include='*.qml' -E 'path:.*\.json"' "$TARGET_DIR" 2>/dev/null || true)
report_matches "QML FileView JSON paths (verify large catalogs in keepLoaded plugins load lazily)" "$qml_json"

js_hot=$(grep -rnI --exclude-dir=.git --include='*.js' -E '\.(toLowerCase|split)\(' "$TARGET_DIR" 2>/dev/null || true)
report_matches "JS .toLowerCase() / .split() sites (verify search loops pre-stamp or hoist outside loops)" "$js_hot"

printf '\nAudit complete.\n'
