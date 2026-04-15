# Periscope — Live-Tail Any Tmux Pane in a Floating Window

## Overview

Press `<leader>tp` to pick any tmux pane from a list. A floating window opens inside neovim that **live-streams** that pane's output — with full ANSI color rendering via baleia.nvim. It's picture-in-picture for your terminal processes.

Watch server logs while debugging. Watch test output while fixing code. Watch a build while coding the next change. All without leaving your editor or switching tmux panes.

## User-Facing Behavior

### Keybinds

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>tp` | n | Open Periscope (pick a tmux pane to watch) |
| `<leader>tP` | n | Toggle the last Periscope window (hide/show without destroying) |
| `q` | n (inside periscope) | Close the Periscope window |
| `<C-f>` | n (inside periscope) | Freeze/unfreeze auto-scroll (pause to read, resume to follow) |
| `<C-r>` | n (inside periscope) | Switch to a different tmux pane |

### Pane Picker UI

When `<leader>tp` is pressed, a `vim.ui.select` menu (or snacks picker) shows available tmux panes:

```
  0: main:0.0  bash         "~/repos/sf-agent"         80x24
  1: main:0.1  python       "backend server running"   80x24
  2: main:0.2  gradle       "building qas-text..."     120x40
  3: main:1.0  nvim         "(current)"                200x50
```

Each entry shows: pane ID, running command, pane title/current path, and dimensions. The current neovim pane is marked and excluded from selection.

### Floating Window

- Opens as a floating window (configurable size, default 0.4 width × 0.35 height, anchored bottom-right)
- Content auto-scrolls to follow new output (like `tail -f`)
- ANSI escape codes are rendered as colors via baleia.nvim
- The buffer is read-only (`buftype = "nofile"`)
- Window title shows the pane being watched: `Periscope: main:0.1 (python)`
- A subtle footer line shows: `[Frozen]` when scrolling is paused, `[Live]` when following

## Implementation

### Module File

Create `~/.config/nvim/lua/periscope.lua`.

### Architecture

```
┌──────────────────────────┐
│ periscope.lua            │
│                          │
│  pick_pane()             │  ← vim.ui.select with tmux list-panes
│       │                  │
│       ▼                  │
│  open(pane_id)           │  ← Creates float + buffer + timer
│       │                  │
│       ▼                  │
│  vim.uv.new_timer()      │  ← Fires every N ms
│       │                  │
│       ▼                  │
│  capture_pane(pane_id)   │  ← tmux capture-pane -p -t <id>
│       │                  │
│       ▼                  │
│  update_buffer(lines)    │  ← Diff against current content,
│       │                  │     append new lines, apply baleia
│       ▼                  │
│  auto_scroll()           │  ← Scroll to bottom if not frozen
└──────────────────────────┘
```

### Step 1: List Available Tmux Panes

```lua
local function list_panes()
  -- Get current pane to exclude it
  local current_pane = vim.env.TMUX_PANE

  -- List all panes with useful metadata
  local fmt = "#{pane_id}\t#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_width}x#{pane_height}"
  local raw = vim.fn.systemlist("tmux list-panes -a -F '" .. fmt .. "'")

  local panes = {}
  for _, line in ipairs(raw) do
    local id, name, cmd, path, size = line:match("^(%%[%d]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
    if id and id ~= current_pane then
      table.insert(panes, {
        id = id,
        name = name,
        cmd = cmd,
        path = vim.fn.fnamemodify(path, ":~"), -- shorten home dir
        size = size,
        display = string.format("%-12s  %-12s  %-30s  %s", name, cmd, path, size),
      })
    end
  end

  return panes
end
```

**Note on nested tmux:** If the user is inside sidekick's nested tmux, `vim.env.TMUX` points to the inner session. To list panes from the *outer* tmux (where the servers run), check for `CASCADE_OUTER_TMUX`:

```lua
local function get_tmux_socket()
  local outer = vim.env.CASCADE_OUTER_TMUX
  if outer and outer ~= "" then
    return "-S " .. outer:match("^([^,]+)")
  end
  return ""
end
```

Then prefix all tmux commands with the socket flag.

### Step 2: Pane Picker

```lua
local function pick_pane(callback)
  local panes = list_panes()

  if #panes == 0 then
    vim.notify("Periscope: No other tmux panes found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(panes, {
    prompt = "Periscope — Select pane to watch:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      callback(choice.id, choice.name)
    end
  end)
end
```

### Step 3: Create the Floating Window

```lua
local state = {
  buf = nil,
  win = nil,
  timer = nil,
  pane_id = nil,
  pane_name = nil,
  frozen = false,
  last_line_count = 0,
  baleia = nil,
}

local config = {
  width_ratio = 0.4,
  height_ratio = 0.35,
  anchor = "SE",         -- bottom-right
  border = "rounded",
  refresh_ms = 500,       -- capture interval
  max_lines = 1000,       -- max buffer lines before trimming
}

local function create_float(title)
  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "periscope"

  -- Calculate dimensions
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * config.width_ratio)
  local height = math.floor(ui.height * config.height_ratio)

  -- Position: bottom-right with a small margin
  local row = ui.height - height - 3
  local col = ui.width - width - 2

  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = config.border,
    title = " Periscope: " .. title .. " ",
    title_pos = "center",
    footer = " [Live] ",
    footer_pos = "right",
  })

  -- Window-local options
  vim.wo[state.win].wrap = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].cursorline = false
  -- Slight transparency so code is still partially visible behind it
  vim.wo[state.win].winblend = 10

  -- Buffer-local keymaps
  local buf_opts = { buffer = state.buf, silent = true }
  vim.keymap.set("n", "q", function() require("periscope").close() end, buf_opts)
  vim.keymap.set("n", "<C-f>", function() require("periscope").toggle_freeze() end, buf_opts)
  vim.keymap.set("n", "<C-r>", function()
    require("periscope").close()
    require("periscope").pick()
  end, buf_opts)
end
```

### Step 4: Capture and Stream Pane Output

```lua
local function capture_pane()
  if not state.pane_id then return end

  local socket = get_tmux_socket()
  -- Capture the visible content of the target pane
  -- -p prints to stdout, -t targets the pane
  -- -e includes escape sequences (for ANSI color)
  local cmd = string.format("tmux %s capture-pane -p -e -t %s", socket, state.pane_id)
  local lines = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 then
    -- Pane may have been closed
    vim.notify("Periscope: Pane " .. state.pane_id .. " is no longer available", vim.log.levels.WARN)
    require("periscope").close()
    return
  end

  return lines
end
```

**Streaming strategy — two modes:**

**Mode A: Viewport capture (simpler, recommended starting point)**

Capture the pane's current visible content on each tick and replace the buffer entirely. This is simple and always shows exactly what the pane shows.

```lua
local function update_buffer(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Apply ANSI coloring via baleia
  if state.baleia then
    state.baleia.once(state.buf)
  end

  -- Auto-scroll to bottom
  if not state.frozen and state.win and vim.api.nvim_win_is_valid(state.win) then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
  end
end
```

**Mode B: History capture (advanced, captures scrollback)**

Use `tmux capture-pane -p -e -t <pane> -S -<N>` where `-S -<N>` captures N lines of scrollback history. This lets you see output that has scrolled off the visible area. Append new lines to the buffer:

```lua
local function update_buffer_streaming(new_lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  -- Simple diff: compare with what we had last time
  -- If new_lines ends differently, append the delta
  local current = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local current_last = current[#current] or ""

  -- Find where new content diverges
  -- (Simple approach: if last line changed, replace everything)
  -- (Better approach: hash-based diffing of trailing lines)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, new_lines)
  vim.bo[state.buf].modifiable = false

  -- Trim if too long
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  if line_count > config.max_lines then
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, line_count - config.max_lines, false, {})
    vim.bo[state.buf].modifiable = false
  end

  -- Colorize and scroll
  if state.baleia then
    state.baleia.once(state.buf)
  end

  if not state.frozen and state.win and vim.api.nvim_win_is_valid(state.win) then
    line_count = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
  end
end
```

**Recommendation:** Start with Mode A (viewport capture). It's reliable and simple. Mode B can be added later as an option.

### Step 5: Timer Loop

```lua
local function start_polling(pane_id)
  state.timer = vim.uv.new_timer()
  state.timer:start(0, config.refresh_ms, vim.schedule_wrap(function()
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then
      require("periscope").close()
      return
    end

    local lines = capture_pane()
    if lines then
      update_buffer(lines)
    end
  end))
end
```

### Step 6: Freeze/Unfreeze

```lua
local function toggle_freeze()
  state.frozen = not state.frozen

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local footer = state.frozen and " [Frozen] " or " [Live] "
    vim.api.nvim_win_set_config(state.win, { footer = footer, footer_pos = "right" })
  end

  vim.notify("Periscope: " .. (state.frozen and "Frozen" or "Live"), vim.log.levels.INFO)
end
```

### Step 7: Public API

```lua
local M = {}

function M.pick()
  pick_pane(function(pane_id, pane_name)
    M.open(pane_id, pane_name)
  end)
end

function M.open(pane_id, pane_name)
  -- Close existing periscope if open
  M.close()

  state.pane_id = pane_id
  state.pane_name = pane_name or pane_id

  -- Initialize baleia for this buffer
  state.baleia = require("baleia").setup({})

  create_float(state.pane_name)
  start_polling(pane_id)
end

function M.close()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.pane_id = nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    -- Hide: close window but keep buffer and timer
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  elseif state.pane_id then
    -- Show: reopen float with existing state
    create_float(state.pane_name or state.pane_id)
  else
    -- Nothing to toggle, open picker
    M.pick()
  end
end

function M.toggle_freeze()
  toggle_freeze()
end

return M
```

### Step 8: Keybinds in `keymaps.lua`

```lua
vim.keymap.set('n', '<leader>tp', function()
  require('periscope').pick()
end, { desc = 'Periscope: Watch tmux pane' })

vim.keymap.set('n', '<leader>tP', function()
  require('periscope').toggle()
end, { desc = 'Periscope: Toggle visibility' })
```

### Edge Cases to Handle

1. **No tmux session:** Check `vim.env.TMUX` first. If not in tmux, notify and return.

2. **Pane closes while watching:** The `capture_pane` function checks `vim.v.shell_error` and auto-closes Periscope with a notification.

3. **Multiple Periscope instances:** The current design is singleton (one at a time). To support multiple, change `state` to a table of states keyed by pane_id, and create multiple floats.

4. **Performance — refresh rate:** 500ms is a good default. For log-heavy processes, the user may want 250ms. For low-activity panes, 1000ms saves CPU. Consider making this configurable or adaptive (slow down if content hasn't changed).

5. **Performance — baleia on every tick:** `baleia.once()` re-processes the entire buffer every tick. For Mode A (full replace), this is necessary. Optimization: only run baleia if the content actually changed (compare a hash of the line content).

6. **Floating window overlap with other floats:** If sidekick or another float is open, Periscope's bottom-right anchor may overlap. Consider making the anchor configurable, or add a `position` config option: `"SE"`, `"SW"`, `"NE"`, `"NW"`.

7. **Terminal resize:** Add an autocmd for `VimResized` that recalculates and repositions the float:

```lua
vim.api.nvim_create_autocmd("VimResized", {
  callback = function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local ui = vim.api.nvim_list_uis()[1]
      local width = math.floor(ui.width * config.width_ratio)
      local height = math.floor(ui.height * config.height_ratio)
      local row = ui.height - height - 3
      local col = ui.width - width - 2
      vim.api.nvim_win_set_config(state.win, {
        width = width, height = height, row = row, col = col,
      })
    end
  end,
})
```

8. **Nested tmux (sidekick):** The `get_tmux_socket()` function handles this, but test both cases: direct tmux and nested tmux via sidekick.

### Dependencies

- **baleia.nvim** — already installed, used for ANSI color rendering
- **tmux** — already the user's multiplexer
- No other dependencies

### File Structure

```
~/.config/nvim/
  lua/
    periscope.lua          -- Module with all logic
  lua/keymaps.lua          -- Add <leader>tp and <leader>tP keybinds
  lua/keymap-groups.lua    -- Already has <leader>t = "Toggle" group
```

### Future Enhancements

1. **Multi-pane dashboard:** Open 2-3 Periscopes tiled vertically on the right side — watch server + tests + build simultaneously.

2. **Search in Periscope:** `/` in the Periscope window to search through captured output (useful for finding errors in log streams).

3. **Snapshot to buffer:** A keybind inside Periscope that copies the current content to a new regular buffer (for reading, searching, or sending to Cascade).

4. **Alert on pattern:** Configure a regex (e.g., `ERROR`, `FAILED`, `Exception`). When the pattern appears in the captured output, flash the Periscope border red and/or send a notification. This turns Periscope into a passive watchdog.
