# Déjà Vu — Line-Level Git Time Machine

## Overview

Place your cursor on any line and press `<leader>hh`. A snacks picker opens showing **every historical version of that line** — not just who last touched it (that's blame), but every commit that ever modified it, with the line's content at each point in time.

Select an entry to see the full commit diff in a split.

## User-Facing Behavior

### Keybinds

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>hh` | n | Open Déjà Vu for current line |
| `<leader>hH` | v | Open Déjà Vu for selected line range |

### Picker UI

Each entry in the snacks picker shows:

```
 abc1234  2026-01-15  Fix retry timeout logic          │  if retries > MAX_RETRIES:
 def5678  2025-12-03  Add retry mechanism               │  if retries > 3:
 9ab0123  2025-11-20  Initial implementation            │  if should_retry():
```

Format: `<short hash>  <date>  <commit message (truncated)>  │  <the line's content at that commit>`

### Actions from Picker

| Key | Action |
|-----|--------|
| `<CR>` | Open full commit diff in a vertical split (using diffview or a scratch buffer with `git show`) |
| `<C-y>` | Yank the commit hash to the `"` register |
| `<C-o>` | Open the entire file as it existed at that commit (`:Git show <hash>:<file>`) in a split |

## Implementation

### Single Plugin File

Create `~/.config/nvim/lua/plugins/deja-vu.lua`. It should be a standalone local plugin — no repo dependency. Use a lazy.nvim spec with `dir` pointing nowhere; just define it inline or as a simple `return {}` with a `config` function, or more cleanly: put the logic in a module at `~/.config/nvim/lua/deja-vu.lua` and load it from `keymaps.lua`.

**Recommended approach:** Create `~/.config/nvim/lua/deja-vu.lua` as a module, and add the keybinds in `keymaps.lua`.

### Core Function: `get_line_history(file, line_start, line_end)`

This is the heart of the feature. It wraps `git log -L`.

```lua
--- Runs git log -L to get the history of a specific line range.
--- @param file string Absolute path to the file
--- @param line_start integer 1-indexed start line
--- @param line_end integer 1-indexed end line
--- @return table[] List of { hash, date, author, message, line_content }
local function get_line_history(file, line_start, line_end)
```

**Step 1: Build the git command**

```bash
git log -L <start>,<end>:<relative_path> --no-patch --format="%H%x00%ad%x00%an%x00%s" --date=short
```

Key flags:
- `-L <start>,<end>:<path>` — trace the evolution of a line range
- `--no-patch` — we don't want the full diff in this initial query (we fetch it on selection)
- `--format="%H%x00%ad%x00%an%x00%s"` — null-separated fields for reliable parsing
- `--date=short` — `YYYY-MM-DD` format

**Problem:** `git log -L` ignores `--no-patch`. It always outputs the diff. This is a known git behavior.

**Workaround:** Use `--format` and parse the output, stripping diff lines (those starting with `+`, `-`, `@@`, `diff`, `index`, etc.). OR use a two-pass approach:

1. First pass: `git log -L <start>,<end>:<path> --format="%H %ad %s" --date=short` — parse to get commit hashes and metadata.
2. For each commit hash, extract the line content with: `git show <hash>:<path>` and read the relevant line(s). But line numbers shift across commits.

**Better workaround:** Parse the `-L` output directly. The output format is:

```
commit abc1234...
Author: ...
Date:   ...

    Commit message

diff --git ...
--- a/file
+++ b/file
@@ -10,3 +10,3 @@
-old line
+new line
 context line
```

Parse this by:
1. Splitting on `^commit [a-f0-9]{40}` to get chunks per commit
2. From each chunk, extract: hash, date, message, and the `+` lines from the diff (which represent what the line looked like AFTER that commit)

**Step 2: Parse the output**

```lua
local function parse_git_log_L(raw_output)
  local entries = {}
  -- Split by "commit " at start of line
  local chunks = vim.split(raw_output, "\ncommit ", { plain = true })

  for i, chunk in ipairs(chunks) do
    -- First chunk may start with "commit " (no leading newline)
    if i == 1 then
      chunk = chunk:gsub("^commit ", "")
    end

    local hash = chunk:match("^(%x+)")
    local date = chunk:match("Date:%s+(.-)%s*\n")
    local message = chunk:match("\n\n%s+(.-)%s*\n")

    -- Extract the "after" state: lines starting with "+" (but not "+++")
    local plus_lines = {}
    for line in chunk:gmatch("\n%+([^\n]*)") do
      if not line:match("^%+%+ ") then
        table.insert(plus_lines, line)
      end
    end

    -- If no plus lines, this commit might be the initial addition
    -- Try lines starting with " " (context) as fallback
    local content = table.concat(plus_lines, "\n")
    if content == "" then
      -- Grab context lines from the diff
      local ctx = {}
      for line in chunk:gmatch("\n ([^\n]+)") do
        table.insert(ctx, line)
      end
      content = table.concat(ctx, "\n")
    end

    if hash then
      table.insert(entries, {
        hash = hash,
        short_hash = hash:sub(1, 7),
        date = date or "unknown",
        message = message or "",
        line_content = content,
      })
    end
  end

  return entries
end
```

**Step 3: Open the snacks picker**

```lua
local function open_picker(entries, original_file)
  local items = {}
  for _, entry in ipairs(entries) do
    -- Truncate message and line content for display
    local msg = entry.message:sub(1, 40)
    local line_preview = entry.line_content:gsub("\n", " "):sub(1, 60)

    table.insert(items, {
      text = string.format("%-7s  %-10s  %-40s  │  %s",
        entry.short_hash, entry.date, msg, line_preview),
      hash = entry.hash,
      short_hash = entry.short_hash,
      date = entry.date,
      message = entry.message,
      file = original_file,
    })
  end

  require("snacks").picker.pick({
    title = "Déjà Vu — Line History",
    items = items,
    format = function(item)
      return {
        { item.text:match("^(.-  )"), "Comment" },       -- hash
        { item.text:match("^.-  (.-  )"), "Number" },     -- date
        { item.text:match("^.-  .-  (.-  │)"), "String" }, -- message
        { item.text:match("│(.*)$"), "Normal" },           -- line content
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.hash then
        -- Open the full commit diff in a vertical split
        vim.cmd("vnew")
        vim.bo.buftype = "nofile"
        vim.bo.bufhidden = "wipe"
        vim.bo.filetype = "diff"
        local diff = vim.fn.systemlist({ "git", "show", item.hash, "--", item.file })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, diff)
        vim.bo.modifiable = false
        vim.api.nvim_buf_set_name(0, "dejavu://" .. item.short_hash)
      end
    end,
    -- Additional actions
    actions = {
      yank_hash = function(picker, item)
        if item then
          vim.fn.setreg('"', item.hash)
          vim.notify("Yanked: " .. item.hash)
        end
      end,
      open_file_at_commit = function(picker, item)
        picker:close()
        if item then
          vim.cmd("vnew")
          local content = vim.fn.systemlist({ "git", "show", item.hash .. ":" .. item.file })
          vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
          vim.bo.buftype = "nofile"
          vim.bo.bufhidden = "wipe"
          vim.bo.modifiable = false
          -- Try to set filetype from extension
          local ext = vim.fn.fnamemodify(item.file, ":e")
          if ext ~= "" then
            vim.bo.filetype = ext
          end
          vim.api.nvim_buf_set_name(0, item.file .. "@" .. item.short_hash)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-y>"] = { "yank_hash", mode = { "n", "i" } },
          ["<C-o>"] = { "open_file_at_commit", mode = { "n", "i" } },
        },
      },
    },
  })
end
```

**Step 4: The main entry point**

```lua
local M = {}

function M.show(line_start, line_end)
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("Déjà Vu: Buffer has no file", vim.log.levels.WARN)
    return
  end

  -- Get git-relative path
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error ~= 0 then
    vim.notify("Déjà Vu: Not in a git repo", vim.log.levels.WARN)
    return
  end

  local rel_path = file:sub(#git_root + 2) -- strip git root + "/"

  line_start = line_start or vim.fn.line(".")
  line_end = line_end or line_start

  local cmd = string.format(
    "git log -L %d,%d:%s --format='commit %%H%%nDate: %%ad%%n%%n    %%s' --date=short",
    line_start, line_end, rel_path
  )

  local raw = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Déjà Vu: git log -L failed:\n" .. raw, vim.log.levels.ERROR)
    return
  end

  local entries = parse_git_log_L(raw)
  if #entries == 0 then
    vim.notify("Déjà Vu: No history found for this line", vim.log.levels.INFO)
    return
  end

  open_picker(entries, rel_path)
end

return M
```

**Step 5: Keybinds in `keymaps.lua`**

```lua
vim.keymap.set('n', '<leader>hh', function()
  require('deja-vu').show()
end, { desc = 'Déjà Vu: Line history' })

vim.keymap.set('v', '<leader>hH', function()
  local start = vim.fn.line("v")
  local finish = vim.fn.line(".")
  if start > finish then start, finish = finish, start end
  require('deja-vu').show(start, finish)
end, { desc = 'Déjà Vu: Range history' })
```

### Edge Cases to Handle

1. **File not yet committed:** `git log -L` will fail. Check `git log --oneline -1 -- <file>` first; if empty, notify "File has no git history."

2. **Binary files:** Check `git diff --numstat` or file extension before running.

3. **Renamed files:** Add `--follow` to the git log command to track across renames: `git log --follow -L <start>,<end>:<path>`.

4. **Very long history:** Cap at 100 entries by default. Add `--max-count=100` to the git command. Could make this configurable.

5. **Uncommitted changes:** The current line content may differ from the latest commit. Consider showing "(uncommitted)" as the first entry with the current buffer content, to give context.

6. **CWD vs git root:** Run the git command with `cwd` set to the git root to ensure relative paths resolve correctly. Use `vim.fn.system()` with a `cd <root> &&` prefix, or use `vim.system()` with `cwd` option.

### Dependencies

- **snacks.nvim** — already installed, used for the picker
- **git** — already available (gitsigns, diffview depend on it)
- No other dependencies

### File Structure

```
~/.config/nvim/
  lua/
    deja-vu.lua          -- Module with show(), parse, picker logic
  lua/keymaps.lua        -- Add <leader>hh and <leader>hH keybinds
  lua/keymap-groups.lua  -- Already has <leader>h = "Git Hunk" group
```

### Snacks Picker Format Notes

The snacks picker `format` function should return a list of `{ text, highlight_group }` tuples. Verify the exact API by checking:
```lua
:lua print(vim.inspect(require("snacks").picker))
```

If the snacks picker format API differs from what's shown above, adapt accordingly. The key requirement is that hash, date, message, and line content should be visually distinct via different highlight groups.

### Alternative: Use Diffview Instead of Scratch Buffer

For the `confirm` action (viewing the full commit), instead of a scratch buffer, you could invoke diffview:

```lua
vim.cmd("DiffviewOpen " .. item.hash .. "~1.." .. item.hash .. " -- " .. item.file)
```

This would show the commit's changes in your familiar diffview UI. This is a better experience but adds a dependency on the diffview command API staying stable.
