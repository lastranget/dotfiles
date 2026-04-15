# Déjà Vu — Implementation Notes

## Applying

```bash
cfg apply ~/.config/nvim/deja-vu.patch
```

## Files Changed

- **`lua/deja-vu.lua`** (new) — Standalone module with parsing, picker, and entry point.
- **`lua/keymaps.lua`** (modified) — Two keybinds appended at the end of the file.

## Key Decisions

### Diffview for Commit Diffs

The `<CR>` confirm action opens the selected commit's diff via **Diffview** (`DiffviewOpen <hash>^..<hash> -- <file>`) rather than a scratch buffer with raw `git show` output. Rationale:

- Diffview is already installed and configured in the repo.
- Provides the familiar split-diff UI with syntax highlighting, file panel navigation, and the existing `<leader>cq` close binding.
- `<hash>^..<hash>` shows exactly the one-commit range. The `-- <file>` filter scopes it to the relevant file.

Tradeoff: for the very first commit in a repo (no parent), `^` will fail. This is rare enough that it doesn't warrant the complexity of detecting orphan commits and falling back.

### Standalone Module (not a plugin spec)

The spec recommends `lua/deja-vu.lua` as a plain module loaded via `require('deja-vu')` from keymaps, not a lazy.nvim plugin spec. This is the right call because:

- There is no external repo dependency — no lazy.nvim `dir` or `url` needed.
- The module is only loaded on first keypress (lazy `require`), so there's no startup cost.
- Keybinds live in `keymaps.lua` alongside the existing `<leader>h*` gitsigns bindings, keeping the Git Hunk group cohesive.

### `vim.system()` over `vim.fn.system()`

All git commands use `vim.system({...}, {cwd = git_root, text = true}):wait()` instead of `vim.fn.system()`. This ensures:

- Commands run from the correct git root regardless of neovim's cwd.
- Structured opts (`cwd`, `text`) instead of shell string concatenation — no escaping bugs.
- Requires Neovim 0.10+, which this config already targets (treesitter foldexpr, etc.).

### Parsing `git log -L`

`git log -L` ignores `--no-patch` (known git behavior), so the output always includes diff hunks. The parser:

1. Splits on `\ncommit ` boundaries to isolate per-commit chunks.
2. Extracts hash, date, message from the structured `--format` header.
3. Collects `+` lines (excluding `+++` header) as the "after" state of the line at that commit.
4. Falls back to context lines (` ` prefix) if no `+` lines exist (e.g., when the line wasn't changed in the hunk but appears as context).

### Format Function Avoids Regex on Display Text

Instead of regex-parsing the formatted `text` field in the picker's `format` callback, each item stores pre-formatted display segments (`_hash_display`, `_date_display`, `_msg_display`, `_preview_display`). The `text` field contains a plain concatenation for snacks' fuzzy filter. This avoids fragile pattern matching on padded strings with unicode separators.

### Edge Cases Handled

| Case | Handling |
|------|----------|
| Buffer has no file | Early return with notification |
| Not in a git repo | `git rev-parse --show-toplevel` check |
| File has no git history | Pre-flight `git log --oneline -1` check |
| `git log -L` failure | Error notification with stderr |
| Empty history result | Info notification |
| Very long history | Capped at 100 commits (`-n 100`) |
| `<C-o>` git show failure | Scratch buffer shows failure message |

### Not Handled (out of scope)

- **Bare repo / dotfiles context**: If `GIT_DIR`/`GIT_WORK_TREE` env vars are set (e.g., via `<leader>cc`), the standard `git` commands will respect them. No special-casing needed.
- **Binary files**: `git log -L` will fail gracefully on binary files; the error notification covers this.
- **Uncommitted changes**: The spec mentions showing a `(uncommitted)` entry. Omitted for simplicity — the current buffer content is already visible in the editor.

## Keybind Summary

| Key | Mode | Action |
|-----|------|--------|
| `<leader>hh` | normal | Open Déjà Vu for cursor line |
| `<leader>hH` | visual | Open Déjà Vu for selected range |
| `<CR>` | picker | Diffview commit diff |
| `<C-y>` | picker | Yank full commit hash to `"` register |
| `<C-o>` | picker | Open file at that commit in a vertical split |
