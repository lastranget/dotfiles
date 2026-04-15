# Etch — Persistent Local Code Review Annotations

## Overview

Press `<leader>he` on any line to attach a note to it — a thought, a concern, a reminder. The annotation appears as dim virtual text next to the line and **persists across sessions**. It tracks with the line through git changes. Browse all annotations with `<leader>hE` in a snacks picker.

Think of it as TODO comments that don't pollute your code, persist locally, and survive git rebases.

## User-Facing Behavior

### Keybinds

| Key | Mode | Where | Description |
|-----|------|-------|-------------|
| `<leader>he` | n | Any buffer | Add/edit annotation on current line |
| `<leader>he` | v | Any buffer | Add annotation on selected range (anchored to first line) |
| `<leader>hE` | n | Any buffer | Browse all annotations in snacks picker |
| `<leader>hx` | n | Any buffer | Delete annotation on current line |
| `<leader>hX` | n | Any buffer | Delete ALL annotations in current file |

### Adding an Annotation

Press `<leader>he`. A small `vim.ui.input` prompt appears:

```
Etch: ▌
```

Type your note ("this retry logic doesn't handle timeouts") and press `<CR>`. The annotation appears immediately as virtual text:

```
  42 │   if retries > MAX_RETRIES:          ── this retry logic doesn't handle timeouts
```

The virtual text uses a dim/comment-like highlight so it doesn't visually compete with code.

If an annotation already exists on that line, `<leader>he` opens the input pre-filled with the existing text so you can edit it.

### Viewing Annotations

Annotations are always visible as virtual text in any file that has them. They load automatically when you open a buffer (via `BufRead` autocmd).

### Browsing All Annotations

Press `<leader>hE` to open the snacks picker. Each entry shows:

```
  src/main/java/org/cas/seti/qas/engine/QASEngine.java:142   ── ask Sarah about this merge logic
  backend/app/services/agent_service.py:87                     ── refactor after SETI-2200
  backend/app/hooks.py:23                                      ── this retry logic doesn't handle timeouts
```

Format: `<relative file path>:<line>  ──  <annotation text>`

| Key | Action |
|-----|--------|
| `<CR>` | Jump to the annotated line |
| `<C-d>` | Delete the selected annotation |

### Deleting Annotations

- `<leader>hx` on an annotated line removes it
- `<leader>hX` removes all annotations in the current file (with a confirmation prompt)
- `<C-d>` in the picker removes the selected annotation

## Persistence Format

### Storage Location

Annotations are stored per git repo in a `.etch.json` file at the repo root. The file is **gitignored by default** (Etch appends to `.gitignore` on first write, or the user can do it manually).

Alternatively, for repos where you don't want to touch `.gitignore`, store in:
```
~/.local/share/nvim/etch/<repo-name-hash>.json
```

**Recommended:** Support both. Default to repo-local `.etch.json` (easier to find, can be committed if desired), with a config option to use the global location.

### JSON Schema

```json
{
  "version": 1,
  "annotations": {
    "src/main/java/org/cas/seti/qas/engine/QASEngine.java": [
      {
        "line": 142,
        "text": "ask Sarah about this merge logic",
        "created": "2026-02-27T15:30:00",
        "anchor": {
          "content": "    private Result mergeResults(List<Result> results) {",
          "hash": "abc1234"
        }
      }
    ],
    "backend/app/services/agent_service.py": [
      {
        "line": 87,
        "text": "refactor after SETI-2200",
        "created": "2026-02-26T10:15:00",
        "anchor": {
          "content": "        response = await self.chain.ainvoke(prompt)",
          "hash": "def5678"
        }
      }
    ]
  }
}
```

Key fields:
- **line** — 1-indexed line number (current position)
- **text** — the annotation content
- **created** — ISO timestamp for sorting/filtering
- **anchor.content** — the line's content when the annotation was created (used for re-anchoring after edits)
- **anchor.hash** — the git commit hash when the annotation was created (used for drift detection)

## Implementation

### Module File

Create `~/.config/nvim/lua/etch.lua`.

### Data Structures

```lua
-- In-memory state
local state = {
  -- Annotations indexed by absolute file path
  -- Each entry: { line = int, text = string, created = string, anchor = { content = string, hash = string } }
  annotations = {},  -- { [abs_path] = { [line_number] = annotation } }

  -- Namespace for virtual text
  ns = vim.api.nvim_create_namespace("etch"),

  -- Git root of the current project (cached)
  git_root = nil,

  -- Dirty flag for debounced saving
  dirty = false,
}
```

### Step 1: Git Root Detection

```lua
local function get_git_root()
  if state.git_root then return state.git_root end
  local root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error == 0 and root then
    state.git_root = root
    return root
  end
  return nil
end

local function get_rel_path(abs_path)
  local root = get_git_root()
  if root and abs_path:sub(1, #root) == root then
    return abs_path:sub(#root + 2)  -- strip root + "/"
  end
  return abs_path
end

local function get_abs_path(rel_path)
  local root = get_git_root()
  if root then
    return root .. "/" .. rel_path
  end
  return rel_path
end
```

### Step 2: Load and Save

```lua
local function get_etch_path()
  local root = get_git_root()
  if not root then return nil end
  return root .. "/.etch.json"
end

local function load_annotations()
  local path = get_etch_path()
  if not path then return end

  local fp = io.open(path, "r")
  if not fp then return end

  local content = fp:read("*a")
  fp:close()

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or not data or not data.annotations then return end

  -- Convert to internal format: indexed by absolute path, then by line number
  state.annotations = {}
  for rel_path, file_annotations in pairs(data.annotations) do
    local abs_path = get_abs_path(rel_path)
    state.annotations[abs_path] = {}
    for _, ann in ipairs(file_annotations) do
      state.annotations[abs_path][ann.line] = ann
    end
  end
end

local function save_annotations()
  local path = get_etch_path()
  if not path then return end

  -- Convert internal format back to JSON-friendly structure
  local data = { version = 1, annotations = {} }

  for abs_path, file_anns in pairs(state.annotations) do
    local rel_path = get_rel_path(abs_path)
    local ann_list = {}
    for _, ann in pairs(file_anns) do
      table.insert(ann_list, ann)
    end
    -- Sort by line number for stable output
    table.sort(ann_list, function(a, b) return a.line < b.line end)
    if #ann_list > 0 then
      data.annotations[rel_path] = ann_list
    end
  end

  local fp = io.open(path, "w")
  if not fp then
    vim.notify("Etch: Failed to save to " .. path, vim.log.levels.ERROR)
    return
  end
  fp:write(vim.fn.json_encode(data))
  fp:close()
  state.dirty = false
end

-- Debounced save: don't write on every edit, batch them
local save_timer = nil
local function save_debounced()
  state.dirty = true
  if save_timer then
    save_timer:stop()
  end
  save_timer = vim.defer_fn(function()
    if state.dirty then
      save_annotations()
    end
  end, 2000)  -- Save 2 seconds after last change
end
```

### Step 3: Render Virtual Text

```lua
local function render_file(bufnr)
  local abs_path = vim.api.nvim_buf_get_name(bufnr)
  local file_anns = state.annotations[abs_path]

  -- Clear existing virtual text for this buffer
  vim.api.nvim_buf_clear_namespace(bufnr, state.ns, 0, -1)

  if not file_anns then return end

  for line, ann in pairs(file_anns) do
    -- line is 1-indexed, extmark is 0-indexed
    local row = line - 1
    -- Make sure line exists in buffer
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if row >= 0 and row < line_count then
      vim.api.nvim_buf_set_extmark(bufnr, state.ns, row, 0, {
        virt_text = {
          { "  ── ", "Comment" },
          { ann.text, "DiagnosticHint" },
        },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end
  end
end

-- Render for the current buffer
local function render_current()
  render_file(vim.api.nvim_get_current_buf())
end
```

**Highlight choice:** `DiagnosticHint` gives a subtle, non-alarming color (typically muted teal/green in everforest). The `── ` prefix visually separates annotations from code. Alternative: define a custom `EtchAnnotation` highlight group:

```lua
vim.api.nvim_set_hl(0, "EtchAnnotation", { fg = "#859289", italic = true })  -- everforest comment-like
vim.api.nvim_set_hl(0, "EtchSeparator", { fg = "#9DA9A0" })
```

Then use `{ "  ── ", "EtchSeparator" }, { ann.text, "EtchAnnotation" }`.

### Step 4: Add / Edit Annotation

```lua
local function add_annotation(line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.fn.line(".")
  local abs_path = vim.api.nvim_buf_get_name(bufnr)

  if abs_path == "" then
    vim.notify("Etch: Buffer has no file", vim.log.levels.WARN)
    return
  end

  -- Check for existing annotation (pre-fill input)
  local existing = state.annotations[abs_path] and state.annotations[abs_path][line]
  local default_text = existing and existing.text or ""

  vim.ui.input({
    prompt = "Etch: ",
    default = default_text,
  }, function(input)
    if not input or input == "" then
      if existing then
        -- Empty input on existing = treat as "keep it", don't delete
        -- Use <leader>hx for explicit delete
      end
      return
    end

    -- Get current line content for anchoring
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""

    -- Get current git hash
    local hash = vim.fn.systemlist("git rev-parse --short HEAD")[1] or "unknown"

    -- Create or update annotation
    if not state.annotations[abs_path] then
      state.annotations[abs_path] = {}
    end

    state.annotations[abs_path][line] = {
      line = line,
      text = input,
      created = os.date("!%Y-%m-%dT%H:%M:%S"),
      anchor = {
        content = vim.trim(line_content),
        hash = hash,
      },
    }

    render_current()
    save_debounced()
    vim.notify("Etch: Annotation added", vim.log.levels.INFO)
  end)
end
```

### Step 5: Delete Annotation

```lua
local function delete_annotation(line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.fn.line(".")
  local abs_path = vim.api.nvim_buf_get_name(bufnr)

  if state.annotations[abs_path] and state.annotations[abs_path][line] then
    state.annotations[abs_path][line] = nil

    -- Clean up empty file entries
    if next(state.annotations[abs_path]) == nil then
      state.annotations[abs_path] = nil
    end

    render_current()
    save_debounced()
    vim.notify("Etch: Annotation removed", vim.log.levels.INFO)
  else
    vim.notify("Etch: No annotation on this line", vim.log.levels.WARN)
  end
end

local function delete_file_annotations(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local abs_path = vim.api.nvim_buf_get_name(bufnr)

  if not state.annotations[abs_path] then
    vim.notify("Etch: No annotations in this file", vim.log.levels.WARN)
    return
  end

  local count = 0
  for _ in pairs(state.annotations[abs_path]) do count = count + 1 end

  vim.ui.input({
    prompt = string.format("Delete all %d annotations in this file? (y/N): ", count),
  }, function(input)
    if input and input:lower() == "y" then
      state.annotations[abs_path] = nil
      render_current()
      save_debounced()
      vim.notify("Etch: Removed " .. count .. " annotations", vim.log.levels.INFO)
    end
  end)
end
```

### Step 6: Browse Annotations (Snacks Picker)

```lua
local function browse_annotations()
  load_annotations()  -- Refresh from disk in case of external changes

  local items = {}

  for abs_path, file_anns in pairs(state.annotations) do
    local rel_path = get_rel_path(abs_path)
    for line, ann in pairs(file_anns) do
      table.insert(items, {
        text = string.format("%-60s  ──  %s", rel_path .. ":" .. line, ann.text),
        file = abs_path,
        line = line,
        annotation = ann,
        -- For sorting
        sort_key = rel_path .. string.format(":%05d", line),
      })
    end
  end

  -- Sort by file:line
  table.sort(items, function(a, b) return a.sort_key < b.sort_key end)

  if #items == 0 then
    vim.notify("Etch: No annotations found", vim.log.levels.INFO)
    return
  end

  require("snacks").picker.pick({
    title = "Etch — Annotations",
    items = items,
    format = function(item)
      -- Split into path:line and annotation text
      local path_part = get_rel_path(item.file) .. ":" .. item.line
      local text_part = item.annotation.text
      return {
        { path_part, "String" },
        { "  ── ", "Comment" },
        { text_part, "DiagnosticHint" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        vim.api.nvim_win_set_cursor(0, { item.line, 0 })
        vim.cmd("normal! zz")  -- Center the line
      end
    end,
    actions = {
      delete_annotation = function(picker, item)
        if item then
          -- Remove from state
          if state.annotations[item.file] then
            state.annotations[item.file][item.line] = nil
            if next(state.annotations[item.file]) == nil then
              state.annotations[item.file] = nil
            end
          end
          save_debounced()

          -- Re-render the affected buffer if it's open
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(buf) == item.file then
              render_file(buf)
            end
          end

          vim.notify("Etch: Deleted annotation", vim.log.levels.INFO)

          -- Refresh the picker by closing and reopening
          picker:close()
          vim.defer_fn(browse_annotations, 100)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-d>"] = { "delete_annotation", mode = { "n", "i" } },
        },
      },
    },
  })
end
```

### Step 7: Line Drift Tracking (Re-anchoring)

This is the hardest part. When the file changes (edits, rebases), line numbers shift. Etch needs to move its annotations to follow the lines they're attached to.

**Strategy: Anchor content matching**

Each annotation stores `anchor.content` — the trimmed content of the line when the annotation was created. On buffer load, if the annotation's line no longer matches, search nearby lines for the anchor content.

```lua
local function reanchor_file(bufnr)
  local abs_path = vim.api.nvim_buf_get_name(bufnr)
  local file_anns = state.annotations[abs_path]
  if not file_anns then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local updated = {}
  local changed = false

  for old_line, ann in pairs(file_anns) do
    local target_content = ann.anchor and ann.anchor.content
    if not target_content then
      -- No anchor, keep as-is
      updated[old_line] = ann
    else
      -- Check if current line matches
      local current = lines[old_line] and vim.trim(lines[old_line]) or ""
      if current == target_content then
        -- Line hasn't moved
        updated[old_line] = ann
      else
        -- Search nearby (expanding radius) for the anchor content
        local found = false
        local max_search = 50  -- search up to 50 lines away
        for offset = 1, max_search do
          -- Check above
          local above = old_line - offset
          if above >= 1 and vim.trim(lines[above] or "") == target_content then
            ann.line = above
            updated[above] = ann
            found = true
            changed = true
            break
          end
          -- Check below
          local below = old_line + offset
          if below <= #lines and vim.trim(lines[below] or "") == target_content then
            ann.line = below
            updated[below] = ann
            found = true
            changed = true
            break
          end
        end

        if not found then
          -- Line was deleted or changed beyond recognition
          -- Keep annotation at original line but mark it as orphaned
          ann.orphaned = true
          updated[old_line] = ann
          changed = true
        end
      end
    end
  end

  if changed then
    state.annotations[abs_path] = updated
    save_debounced()
  end
end
```

**When to run re-anchoring:**
- On `BufRead` / `BufEnter` (when opening a file)
- NOT on every keystroke (too expensive)
- Optionally on `BufWritePost` (after saving, the line positions are "settled")

**Orphaned annotations:** If a line was deleted entirely, the annotation becomes "orphaned." Render these with a different highlight (e.g., strikethrough or dimmer) and a `[?]` prefix:

```lua
if ann.orphaned then
  virt_text = {
    { "  ── [?] ", "DiagnosticWarn" },
    { ann.text, "Comment" },
  }
end
```

This signals to the user: "I tried to find this line but couldn't — you might want to delete or re-anchor this annotation."

### Step 8: Autocmds

```lua
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("etch", { clear = true })

  -- Load and render annotations when opening a buffer
  vim.api.nvim_create_autocmd("BufRead", {
    group = group,
    callback = function(ev)
      -- Only process files in a git repo
      if not get_git_root() then return end

      -- Ensure annotations are loaded
      if next(state.annotations) == nil then
        load_annotations()
      end

      -- Re-anchor and render
      reanchor_file(ev.buf)
      render_file(ev.buf)
    end,
  })

  -- Re-render after saving (positions may have been updated by formatters etc.)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      reanchor_file(ev.buf)
      render_file(ev.buf)
    end,
  })

  -- Save on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if state.dirty then
        save_annotations()
      end
    end,
  })

  -- Re-render when switching to a buffer (in case annotations were updated elsewhere)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      render_file(ev.buf)
    end,
  })
end
```

### Step 9: Public API

```lua
local M = {}

function M.setup(opts)
  opts = opts or {}
  -- Merge user config

  -- Set up highlight groups
  vim.api.nvim_set_hl(0, "EtchAnnotation", { link = "DiagnosticHint", default = true })
  vim.api.nvim_set_hl(0, "EtchSeparator", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "EtchOrphaned", { link = "DiagnosticWarn", default = true })

  -- Load annotations for current repo
  load_annotations()

  -- Set up autocmds
  setup_autocmds()

  -- Render for any already-open buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
      render_file(buf)
    end
  end
end

function M.add(line, bufnr)
  add_annotation(line, bufnr)
end

function M.delete(line, bufnr)
  delete_annotation(line, bufnr)
end

function M.delete_file(bufnr)
  delete_file_annotations(bufnr)
end

function M.browse()
  browse_annotations()
end

-- Force reload from disk (useful after git operations)
function M.reload()
  state.annotations = {}
  state.git_root = nil
  load_annotations()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      render_file(buf)
    end
  end
  vim.notify("Etch: Reloaded", vim.log.levels.INFO)
end

return M
```

### Step 10: Plugin Spec (Lazy Loading)

Create `~/.config/nvim/lua/plugins/etch.lua`:

```lua
return {
  dir = "~/.config/nvim",  -- local plugin, no git repo
  name = "etch",
  lazy = false,
  config = function()
    require("etch").setup()
  end,
  keys = {
    { "<leader>he", function() require("etch").add() end, desc = "Etch: Add annotation" },
    {
      "<leader>he",
      function()
        local start = vim.fn.line("v")
        require("etch").add(start)
      end,
      mode = "v",
      desc = "Etch: Add annotation on selection start"
    },
    { "<leader>hE", function() require("etch").browse() end, desc = "Etch: Browse annotations" },
    { "<leader>hx", function() require("etch").delete() end, desc = "Etch: Delete annotation" },
    { "<leader>hX", function() require("etch").delete_file() end, desc = "Etch: Delete file annotations" },
  },
}
```

**Note on lazy.nvim `dir` usage:** Using `dir` with lazy.nvim for a local module requires that the directory has a `lua/` subdirectory or plugin structure. Since `etch.lua` lives at `~/.config/nvim/lua/etch.lua`, it's already on the runtimepath. A simpler approach is to skip the plugin spec entirely and just call `require("etch").setup()` from `config/lazy.lua` (after lazy setup) or from an autocmd. The keybinds can go in `keymaps.lua`.

**Simpler alternative — no plugin spec:**

In `~/.config/nvim/lua/config/lazy.lua`, after `require("lazy").setup(...)`:

```lua
-- Initialize Etch after plugins are loaded
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    require("etch").setup()
  end,
})
```

And in `keymaps.lua`, add the keybinds listed above.

### Edge Cases to Handle

1. **No git repo:** All functions check `get_git_root()` first and silently skip if not in a git repo. Etch only works in git repos (needed for relative paths and anchoring).

2. **Multiple git repos in one session:** `state.git_root` is cached, which breaks if you switch repos. Fix: compute git root per-buffer, not globally. Change `get_git_root()` to accept an optional `abs_path` argument and use `git -C <dir> rev-parse --show-toplevel`.

3. **File renames:** If a file is renamed via git, annotations keyed to the old path are lost. Mitigation: on `load_annotations()`, check each path exists. If not, try `git log --follow --diff-filter=R -- <old_path>` to detect renames and auto-migrate.

4. **Merge conflicts on `.etch.json`:** If multiple people use Etch (unlikely for a local tool, but possible), the JSON file could conflict. The JSON structure is designed to be merge-friendly (keyed by filepath, sorted by line). But for safety, `.etch.json` should stay in `.gitignore`.

5. **Large repos with many annotations:** For repos with 500+ annotations, `load_annotations()` should be fast (it's just JSON parsing). But `browse_annotations()` should support filtering by current file first, then "all." Add a `<C-a>` toggle in the picker for "current file only" vs "all files."

6. **Concurrent neovim sessions:** Two neovim instances on the same repo could overwrite each other's `.etch.json`. Mitigation: reload from disk before saving (merge strategy). Or use file locking (`vim.uv.fs_open` with exclusive mode). Simple approach: always reload before browse/save, and accept last-write-wins for the rare conflict.

7. **Performance of re-anchoring:** For files with many annotations, scanning 50 lines per annotation on every `BufRead` could be slow. Optimization: skip re-anchoring if the file's git hash hasn't changed since the last anchor check. Store a `last_checked_hash` per file.

8. **Virtual text overlap with other plugins:** gitsigns and other plugins use virtual text too. Etch uses its own namespace, so there's no conflict — they'll stack at EOL. However, if the line is long and the window is narrow, multiple virtual texts may be truncated. This is acceptable.

### Dependencies

- **snacks.nvim** — already installed, used for the browse picker
- **git** — already available
- No other dependencies

### File Structure

```
~/.config/nvim/
  lua/
    etch.lua               -- Module with all logic
  lua/keymaps.lua          -- Add keybinds
  lua/keymap-groups.lua    -- <leader>h group already exists ("Git Hunk")
```

### Future Enhancements

1. **Annotation categories:** Add a prefix syntax like `[bug]`, `[question]`, `[todo]`, `[refactor]` and color-code them differently. The picker could filter by category.

2. **Export to markdown:** `<leader>hEM` exports all annotations as a markdown checklist — ready to paste into an Obsidian note or a PR description:
   ```markdown
   ## Code Review Notes
   - [ ] `QASEngine.java:142` — ask Sarah about this merge logic
   - [ ] `agent_service.py:87` — refactor after SETI-2200
   ```

3. **Git hook integration:** A pre-commit hook that warns if you have unresolved annotations in staged files. Prevents "fix later" annotations from being forgotten.

4. **Annotation aging:** Annotations older than N days get a progressively dimmer highlight, or a `[stale]` marker. Encourages cleaning up old notes.

5. **Integration with Obsidian (Nexus-like):** If an annotation mentions a ticket pattern like `SETI-\d+`, make it a clickable link that opens the matching Obsidian note. This bridges Etch and your knowledge base.

6. **Diffview integration:** When in diffview, show Etch annotations overlaid on the diff. If an annotated line changed, highlight the annotation more prominently ("you noted something about this line and now it changed").
