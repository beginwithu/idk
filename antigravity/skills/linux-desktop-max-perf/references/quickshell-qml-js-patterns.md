# Quickshell QML, JS Search Models & Shell Helper Optimization

## 1. QML V4 Engine Rules & Memory Hygiene

### Never Mutate `QObject` Wrappers or Live `property var` Maps In-Place
1. **C++ `QObject` entries** (such as `DesktopEntries.applications.values` items or `WifiNetwork` objects):
   - Do **not** assign cache properties onto them (`entry._lower = ...` will fail or throw in QML's V4 engine).
   - Do **not** store live `QObject` references inside `ListModel` rows if backend scans can destroy them mid-incubation (causes dangling-wrapper crashes); copy primitive strings/booleans/numbers instead.
2. **Objects stored in QML `property var`**:
   - V4 occasionally drops in-place property writes on nested objects living inside a `property var`.
   - Always construct fresh plain JS objects, stamp any cached fields (`_nameSearch`, `_labelLower`, `_descWords`) **before** returning from the JS module, and assign the top-level `property var` in one go.

### Lazy-Load Large Static Assets in `keepLoaded` Plugins
- Plugins with `"keepLoaded": true` in `manifest.json` instantiate at Quickshell startup.
- If a plugin loads a large JSON catalog (e.g., 100+ KB `emojis.json`) via `FileView`, bind `path` lazily so startup pays zero disk/parse/RAM cost until first open:
  ```qml
  FileView {
    path: (root.opened || root.emojis.length > 0) ? root.catalogPath : ""
    onLoaded: root.loadEmojis(text())
  }
  ```
- Guard empty-state placeholders with `visible: displayModel.count === 0 && root.emojis.length > 0` so the first asynchronous load never flashes "No matches" for one frame.

### Avoid Redundant `bash -c` Process Wrappers in `Process`
- When invoking an executable or bash script without shell pipelines, pass `command: ["bash", scriptPath, arg1]` (or `[scriptPath, arg1]`) instead of `["bash", "-c", Util.shellQuote(scriptPath) + " " + Util.shellQuote(arg1)]` to save an extra shell fork.

---

## 2. Per-Keystroke JS Search & Filter Models

Search handlers run synchronously on the UI thread on every keystroke. Eliminating redundant `.toLowerCase()`, `.split(/\s+/)`, regex `.replace()`, and $O(N^2)$ tree scans keeps 60–240 Hz input lag-free.

### App Launcher (`AppSearch.js` Pattern)
- Pre-split and lowercase `query` **once** before iterating entries (`splitTerms(q)`).
- Compute `nameLower = entryName(entry).toLowerCase()` once per entry (reusing it for `scoreEntry`, `key`, and `name`).
- Lazily compute `idLower`, `haystack`, and `acronym` in local variables **only when earlier checks miss**:
  1. Check `nameLower.indexOf(term) >= 0` first (catches most matches immediately).
  2. Only if needed, compute `idLower`, then `haystack`, then (when `term.length <= 5`) `acronym`.
  3. Reuse those exact local variables in the ranking phase instead of recomputing them.

### Hierarchical Menu (`MenuModel.js` + `Menu.qml` Pattern)
- **Pre-stamp search fields** (`_labelLower`, `_labelWords`, `_nameSearch`, `_descLower`, `_descWords`) when normalizing/merging items, guarded by fast reference checks (`entry._stampedLabel === entry.label && ...`) so even mutated test objects stay 100% coherent.
- **Replace $O(N^2)$ parent scans with `childrenByParent` ($O(1)$)**:
  - Build `var childrenMap = MenuModel.childrenByParent(root.items, root.itemOrder)` once per `rebuildDisplay()` in a single $O(N)$ pass using `Object.create(null)`.
  - Use `childrenMap[target]` for submenu listing, `childCount`, and recursive `isVisibleWithChildren(..., visibilityMemo)` (memoizing top-level `guard === 0` results to stay cycle-safe on `link` items).

### Emoji & Clipboard Pickers
- **Emoji picker**: Pre-compute `item._k = String(item.k || "").toLowerCase()` once inside `parseEmojis(raw)` rather than lowercasing 1,800 keyword strings on every keystroke.
- **Clipboard picker**: Cap scanned/rendered text prefix (`displayTextLimit = 8192` cut on newline so `file://` URIs stay intact), and compute `paths = filePaths(entry)` **once** per row, passing `paths` into search, preview, and fullText helpers instead of decoding `file://` URIs 3 times per row.

---

## 3. Quickshell Shell Helpers (`.sh`)

- **Clipboard capture (`capture.sh`)**: Match MIME types against `wl-paste --list-types` with Bash string matching (`[[ $'\n'"$types"$'\n' == *$'\n'"$mime"$'\n'* ]]`) and format image JSON with `printf` + pure-Bash `json_escape` instead of spawning 5 `grep` processes + `jq` + `awk`.
- **Hidden `.desktop` scanner (`hidden-entries.sh`)**: Parse `XDG_CURRENT_DESKTOP` once at script startup, match section headers with glob `[[ $line == \[*\] ]]` instead of regex `=~`, and `break` out of the file loop immediately when the next `[Section]` starts after `[Desktop Entry]`.
- **Wallpaper / image picker (`list.sh`)**: Preload `index.tsv` into an associative array, batch `stat -Lc '%s:%Y'` across all discovered images in one call, and cache resolved thumbnail paths per image so video and output loops never stat/hash twice.
