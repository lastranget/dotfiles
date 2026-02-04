# Cascade + Sidekick.nvim Integration

This document describes the integration between Neovim (running on a remote server) and Windsurf Cascade (running on a Mac), using OSC 52 clipboard sequences to bridge the gap.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│ Mac                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ Kitty Terminal                                                  ││
│  │  ┌─────────────────────────────────────────────────────────────┐││
│  │  │ SSH to remote server                                        │││
│  │  │  ┌─────────────────────────────────────────────────────────┐│││
│  │  │  │ tmux                                                    ││││
│  │  │  │  ┌─────────────────────────────────────────────────────┐││││
│  │  │  │  │ Outer Neovim                                        │││││
│  │  │  │  │  ┌─────────────────────────────────────────────────┐│││││
│  │  │  │  │  │ Sidekick.nvim terminal buffer                   ││││││
│  │  │  │  │  │  ┌─────────────────────────────────────────────┐│││││││
│  │  │  │  │  │  │ Inner Neovim ("cascade" tool)               ││││││││
│  │  │  │  │  │  │ - User writes prompt here                   ││││││││
│  │  │  │  │  │  │ - <leader>so sends to Cascade               ││││││││
│  │  │  │  │  │  └─────────────────────────────────────────────┘│││││││
│  │  │  │  │  └─────────────────────────────────────────────────┘││││││
│  │  │  │  └─────────────────────────────────────────────────────┘│││││
│  │  │  └─────────────────────────────────────────────────────────┘││││
│  │  └─────────────────────────────────────────────────────────────┘│││
│  └─────────────────────────────────────────────────────────────────┘││
│                                                                     │
│  ┌──────────────────┐    ┌──────────────────────────────────────┐  │
│  │ Hammerspoon      │───▶│ Windsurf Cascade                     │  │
│  │ (clipboard watch)│    │ (receives prompt, AI responds)       │  │
│  └──────────────────┘    └──────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## How It Works

### 1. Neovim Keymap (`<leader>so`)

Located in `~/.config/nvim/lua/keymaps.lua`:

```lua
vim.keymap.set('n', '<leader>so', function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, "\n")
  local encoded = vim.base64.encode("::cascade::" .. text)
  
  if vim.env.TMUX then
    -- Get the tmux pane's TTY and write OSC 52 directly to it
    local pane_tty = vim.fn.system("tmux display-message -p '#{pane_tty}'"):gsub('%s+$', '')
    local osc = string.format('\027Ptmux;\027\027]52;c;%s\a\027\\', encoded)
    local cmd = string.format("printf '%%s' %s > %s", vim.fn.shellescape(osc), pane_tty)
    os.execute(cmd)
  else
    local osc = string.format('\027]52;c;%s\a', encoded)
    vim.fn.chansend(vim.v.stderr, osc)
  end
end, { desc = 'Send buffer to Cascade' })
```

### 2. Hammerspoon Clipboard Watcher (Mac side)

Located at `~/.hammerspoon/init.lua` on the Mac:

- Polls the clipboard every 0.5 seconds
- Looks for the `::cascade::` prefix
- When found, strips the prefix and:
  1. Activates Windsurf
  2. Presses `Cmd+1` (focus editor, ensures Cmd+L won't toggle-close)
  3. Presses `Cmd+L` (open Cascade chat input)
  4. Pastes the text

### 3. Sidekick.nvim Configuration

Located in `~/.config/nvim/lua/plugins/sidekick.lua`:

```lua
cli = {
  mux = {
    backend = "tmux",
    enabled = false,  -- IMPORTANT: Disabled to avoid nested tmux issues
  },
  tools = {
    cascade = {
      cmd = { "nvim" },
      format = function(text, str)
        return "\027i" .. str  -- Enter insert mode before text
      end,
    },
  },
}
```

**Key setting:** `mux.enabled = false` - This prevents sidekick from wrapping the inner Neovim in another tmux session, which would complicate the OSC 52 passthrough.

### 4. tmux Configuration

Required settings in `~/.tmux.conf`:

```bash
set -g allow-passthrough on
set -s set-clipboard external
set -as terminal-features ',xterm-kitty:clipboard'
```

### 5. Kitty Configuration (Mac)

Ensure clipboard control is enabled in `~/.config/kitty/kitty.conf`:

```
clipboard_control write-clipboard write-primary read-clipboard read-primary
```

## The OSC 52 Challenge: What Didn't Work

### Problem Statement

When running Neovim inside another Neovim's terminal buffer (via sidekick.nvim), OSC 52 sequences don't reach the actual terminal (Kitty). The inner Neovim's output goes to the outer Neovim's terminal emulator, which doesn't pass through escape sequences.

### Failed Approaches

#### 1. `vim.fn.chansend(vim.v.stderr, osc)`
- **Works from:** Outer Neovim only
- **Fails from:** Inner Neovim
- **Why:** Inner Neovim's stderr is the outer Neovim's terminal buffer, which interprets (and fails) the OSC 52 instead of passing it through

#### 2. `io.write(osc)` / `io.flush()`
- **Works from:** Neither
- **Why:** Lua's io writes to Neovim's internal stdout, not the terminal

#### 3. Writing to `/dev/tty`
```lua
local tty = io.open('/dev/tty', 'w')
tty:write(osc)
```
- **Error:** "Failed to open /dev/tty"
- **Why:** The inner Neovim process doesn't have a controlling TTY

#### 4. Shell out to `/dev/tty`
```bash
printf '%s' "$osc" > /dev/tty
```
- **Error:** "cannot create /dev/tty: No such device or address"
- **Why:** Same reason - no controlling TTY for the nested process

#### 5. Walking the process tree to find parent TTY
```lua
-- Walk /proc/<pid>/stat to find parent with TTY
local fd0 = vim.fn.resolve('/proc/' .. ppid .. '/fd/0')
```
- **Result:** "Could not find parent TTY"
- **Why:** The resolution logic didn't properly traverse the process hierarchy

#### 6. `tmux load-buffer` + `tmux refresh-client -l`
- **Result:** No clipboard change
- **Why:** `refresh-client -l` doesn't trigger OSC 52 output as expected

#### 7. `tmux run-shell` with printf
- **Result:** Output went to tmux log, not terminal
- **Why:** `run-shell` captures output rather than sending to terminal

### What Actually Works

#### Solution: `tmux display-message -p '#{pane_tty}'` + direct write

```lua
local pane_tty = vim.fn.system("tmux display-message -p '#{pane_tty}'"):gsub('%s+$', '')
local osc = string.format('\027Ptmux;\027\027]52;c;%s\a\027\\', encoded)
local cmd = string.format("printf '%%s' %s > %s", vim.fn.shellescape(osc), pane_tty)
os.execute(cmd)
```

**Why this works:**

1. `tmux display-message -p '#{pane_tty}'` returns the actual PTY device (e.g., `/dev/pts/5`) that the tmux pane is connected to
2. This PTY is the real terminal connection that goes through SSH to Kitty
3. Writing directly to this device bypasses all the nested terminal emulators (outer Neovim's terminal buffer)
4. The OSC 52 sequence reaches tmux, which (with `allow-passthrough on`) forwards it to Kitty
5. Kitty receives the OSC 52 and updates the Mac's system clipboard

**Key insight:** The tmux pane's TTY is always accessible from any process running within that pane, regardless of nesting level. By asking tmux for the pane's TTY path and writing directly to it, we bypass the entire Neovim terminal emulator stack.

## Workflow

1. User opens outer Neovim in tmux
2. User presses `<leader>sw` to open sidekick's "cascade" tool (inner Neovim)
3. User writes their prompt in the inner Neovim buffer
4. User presses `<Esc>` to enter normal mode, then `<leader>so`
5. The buffer content is base64-encoded with `::cascade::` prefix
6. OSC 52 sequence is written directly to the tmux pane's TTY
7. tmux passes it through to Kitty (via SSH)
8. Kitty updates the Mac's clipboard
9. Hammerspoon detects the `::cascade::` prefix
10. Hammerspoon activates Windsurf and pastes into Cascade

## Files Involved

| File | Location | Purpose |
|------|----------|---------|
| `keymaps.lua` | `~/.config/nvim/lua/keymaps.lua` | `<leader>so` keymap |
| `sidekick.lua` | `~/.config/nvim/lua/plugins/sidekick.lua` | Sidekick config with cascade tool |
| `cascade-hammerspoon-for-mac.lua` | `~/.config/nvim/lua/cascade-hammerspoon-for-mac.lua` | Reference for Mac's Hammerspoon config |
| `tmux.conf` | `~/.tmux.conf` | tmux passthrough settings |
| `init.lua` | `~/.hammerspoon/init.lua` (Mac) | Clipboard watcher |

## Troubleshooting

### OSC 52 not working from command line in tmux
Ensure `~/.tmux.conf` has:
```bash
set -g allow-passthrough on
```
Then reload: `tmux source-file ~/.tmux.conf`

### Test OSC 52 manually
```bash
printf '\ePtmux;\e\033]52;c;%s\a\e\\' "$(echo -n 'test' | base64)"
```
Check if "test" appears in your Mac clipboard.

### Hammerspoon not triggering
- Check Hammerspoon console for errors
- Verify the clipboard contains the `::cascade::` prefix
- Reload Hammerspoon config (menu bar → Reload Config)

### Inner Neovim showing garbage characters
This means OSC 52 is being interpreted by Neovim's terminal emulator instead of passing through. Ensure you're using the `pane_tty` approach, not `chansend`.
