# Etch — Implementation Decisions

## Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `lua/etch.lua` | **Created** | Core module: all logic for annotations, persistence, rendering, re-anchoring, and the snacks picker browser |
| `lua/config/lazy.lua` | **Modified** | Adds a `VeryLazy` autocmd to call `require("etch").setup()` after all plugins are loaded |
| `lua/keymaps.lua` | **Modified** | Adds the five etch keybinds (`<leader>he`, `<leader>hE`, `<leader>hx`, `<leader>hX`, visual `<leader>he`) |

## Applying the Patch

```bash
cfg apply ~/.config/nvim/etch.patch
```

To undo:

```bash
cfg apply --reverse ~/.config/nvim/etch.patch
```

## Architecture Decisions

### Single module, no plugin spec

Etch lives as `lua/etch.lua` on the runtimepath — no lazy.nvim plugin spec needed. The spec's "simpler alternative" was chosen over the `dir`-based plugin spec approach because:

- `lua/etch.lua` is already on nvim's runtimepath by default
- Using `dir = vim.fn.stdpath("config")` to register the entire nvim config as a "plugin" is semantically odd and can cause lazy.nvim to scan the whole config tree
- The `VeryLazy` autocmd pattern is simple, explicit, and matches how other non-plugin modules could be initialized

### Setup timing: VeryLazy autocmd

`require("etch").setup()` runs on the `User VeryLazy` event (fired by lazy.nvim after UI is ready). This ensures:

- snacks.nvim is loaded and `Snacks.picker` is available for the browse command
- Keybinds in `keymaps.lua` use lazy `function()` wrappers, so `require("etch")` only resolves on first keypress — well after setup

### Keybinds in keymaps.lua, not a separate file

The existing config places general keybinds in `keymaps.lua` and plugin-specific ones in their plugin specs. Since etch has no plugin spec, `keymaps.lua` is the natural home. All etch keybinds use the `<leader>h` prefix alongside the existing gitsigns hunk operations — this is intentional (etch annotations are conceptually adjacent to git hunks).

### Per-directory git root caching

The spec's `get_git_root()` uses a single global cache, which breaks when editing files from multiple repos in one session. The implementation caches per-directory instead (`state.git_roots[dir]`), using `git -C <dir> rev-parse --show-toplevel`. This correctly handles multi-repo sessions without meaningful performance cost.

### Snacks picker integration

The browse picker uses `Snacks.picker()` with:

- **`items`** — pre-built list of annotation items (the snacks `items` config field bypasses the finder and directly provides items to the matcher)
- **`format`** — custom formatter returning `snacks.picker.Highlight[]` with file path, separator, and annotation text in distinct highlight groups
- **`preview = "file"`** — leverages the built-in file previewer via `item.file` and `item.pos` fields
- **`confirm`** — jumps to the annotated line and centers the view
- **`etch_delete` action** bound to `<C-d>` — deletes the annotation, re-renders affected buffers, then reopens the picker to refresh the list

### Re-anchoring strategy

On `BufRead` and `BufWritePost`, annotations are re-anchored by comparing the stored `anchor.content` (trimmed line text) against the current file contents. If the line content doesn't match at the stored position, an expanding-radius search (±50 lines) looks for the original content. This handles:

- Lines shifted by edits above/below the annotation
- Formatter-induced reflows (via `BufWritePost` re-anchor)
- Git rebases and merges (next `BufRead` re-anchors)

Annotations whose anchor content can't be found anywhere are marked `orphaned = true` and rendered with a `[?]` prefix and `DiagnosticWarn` highlight to signal the user.

### Highlight groups

Three custom highlight groups are defined with `default = true` so they can be overridden:

| Group | Default link | Used for |
|-------|-------------|----------|
| `EtchAnnotation` | `DiagnosticHint` | Annotation text (subtle teal/green in everforest) |
| `EtchSeparator` | `Comment` | The `──` separator |
| `EtchOrphaned` | `DiagnosticWarn` | The `[?]` prefix on orphaned annotations |

### Debounced saving

Annotations are saved 2 seconds after the last mutation. This batches rapid edits (e.g., deleting several annotations in sequence) into a single disk write. A `VimLeavePre` autocmd flushes any pending dirty state on exit.

## Known Limitations

1. **Single-repo annotation store** — `load_annotations()` replaces `state.annotations` entirely, so switching between repos in one session reloads from disk. This is correct behavior but means annotations for repo A aren't in memory while editing repo B.

2. **No `.gitignore` auto-append** — The spec suggests auto-appending `.etch.json` to `.gitignore`. This was omitted to avoid surprising side effects. Add it manually:
   ```bash
   echo '.etch.json' >> .gitignore
   ```

3. **Concurrent sessions** — Two nvim instances on the same repo use last-write-wins. The `browse_annotations()` function reloads from disk before displaying to minimize stale data.

4. **No file rename tracking** — If a file is renamed via `git mv`, annotations keyed to the old path become orphaned at the storage level. A future enhancement could detect renames via `git log --follow`.
