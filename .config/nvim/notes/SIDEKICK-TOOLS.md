# Sidekick.nvim: Tools, Sessions & How to Add More

Notes on how [`folke/sidekick.nvim`](https://github.com/folke/sidekick.nvim) manages CLI
tools and sessions, and a recipe for adding new tools or duplicating existing ones
(e.g. running several independent Claude sessions in the same repo).

Config lives in [`lua/plugins/sidekick.lua`](../lua/plugins/sidekick.lua).

---

## How sessions are identified (the key insight)

Every CLI session gets a **deterministic id derived from the tool name + a hash of the
working directory**:

```lua
-- lua/sidekick/cli/session/init.lua
function M.sid(opts)
  local cwd = M.cwd(opts)
  return ("%s %s"):format(tool, vim.fn.sha256(cwd):sub(1, 16 - #tool))
end
```

Consequences:

- There is **exactly one session slot per `(tool, cwd)` pair**. When sidekick starts a
  tmux session it runs `tmux new -A -s <sid>` — the `-A` means "attach if it already
  exists", so re-launching a tool in the same repo just re-attaches to the one session.
- The picker (`<leader>ss`) **hides the "start new" entry** whenever a live session
  already occupies that `sid`:

  ```lua
  -- lua/sidekick/cli/state.lua
  for name, tool in pairs(Config.tools()) do
    local sid = Session.sid({ tool = name })
    if not sids[sid] then           -- only offer "start" if no live session has this sid
      all[#all + 1] = { tool = tool, installed = ... }
    end
  end
  ```

  That's why a session from a **different** directory shows up as a separate, choosable
  item (different cwd → different `sid`), but you never get a second same-repo session for
  the same tool.

**To get more than one session of the same tool in one repo, you must vary the tool
name.** That's the whole trick behind the `claude` / `claudeB` / `claudeC` setup below.

There is an open, unimplemented upstream request for native multi-session support:
[folke/sidekick.nvim Discussion #161](https://github.com/folke/sidekick.nvim/discussions/161).

---

## How a running process is matched back to a tool (`is_proc`)

When sidekick scans for existing sessions, it walks the tmux pane process trees and asks
each configured tool "is this your process?" via `is_proc`. The first tool that matches a
process wins (`lua/sidekick/cli/session/tmux.lua`).

`is_proc` can be:

- a **string** — treated as a Vim regex matched against the process command line
  (`proc.cmd`, the full `ps -o args` string). The built-in default for Claude is
  `"\\<claude\\>"`.
- a **function** `function(self, proc) -> boolean`. The `proc` table exposes:
  - `proc.cmd`  — full command line
  - `proc.env`  — lazily read from `/proc/<pid>/environ` (Linux) or `ps eww` (macOS)
  - `proc.cwd`, `proc.pid`, `proc.ppid`

This matters for **duplicate tools**: if two tools both run the `claude` binary, the plain
`\<claude\>` regex can't tell them apart, and a reattached session may be labelled as the
wrong one. The fix is to give each duplicate a unique signature and match on it. The
cleanest signature is an **environment variable** (sidekick passes `tool.env` straight to
the tmux session via `tmux new ... -e KEY=VAL ...`), because it leaves the command line as
a plain `claude` invocation.

---

## Recipe 1: Add a brand-new tool

Add an entry under `opts.cli.tools` keyed by the tool name. Minimum is a `cmd`:

```lua
tools = {
  -- ...
  mytool = {
    cmd = { "mytool", "--some-flag" },
    -- optional:
    is_proc = "\\<mytool\\>",                 -- regex to recognise a running instance
    url = "https://example.com/mytool",       -- shown when the binary isn't installed
    env = { FOO = "bar" },                     -- extra env for the launched process
  },
}
```

Then add keybindings (see "Keybindings" below). Built-in tools (`claude`, `gemini`,
`codex`, etc.) ship sensible `is_proc`/`url`/`format` defaults from the plugin's
`sk/cli/<name>.lua` files; **a tool name with no built-in file inherits no defaults**, so
set `is_proc`/`url` yourself if you want them.

---

## Recipe 2: Duplicate an existing tool (multiple sessions per repo)

This is how `claudeB` and `claudeC` are set up so you can run three independent Claude
sessions in the same directory. The trick is a unique `SIDEKICK_TOOL` env var plus an
`is_proc` that matches on it:

```lua
tools = {
  claude = {
    cmd = { "claude", "--dangerously-skip-permissions" },
    env = { SIDEKICK_TOOL = "claude" },
    is_proc = function(_, p)
      local marker = (p.env or {}).SIDEKICK_TOOL
      if marker == "claudeB" or marker == "claudeC" then
        return false                          -- don't claim the duplicates' processes
      end
      -- still match plain claude (incl. sessions started before this env existed)
      return vim.regex("\\<claude\\>"):match_str(p.cmd) ~= nil
    end,
  },
  claudeB = {
    cmd = { "claude", "--dangerously-skip-permissions" },
    env = { SIDEKICK_TOOL = "claudeB" },
    is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeB" end,
    url = "https://github.com/anthropics/claude-code",
  },
  claudeC = {
    cmd = { "claude", "--dangerously-skip-permissions" },
    env = { SIDEKICK_TOOL = "claudeC" },
    is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeC" end,
    url = "https://github.com/anthropics/claude-code",
  },
}
```

Why each piece matters:

- **`env = { SIDEKICK_TOOL = ... }`** — stamps every launch with a unique marker that ends
  up in the process environment.
- **Exact-match `is_proc` for the duplicates** — each one only claims its own marked
  process, regardless of tool iteration order.
- **The base tool excludes the duplicate markers** — otherwise its broad `\<claude\>`
  regex would also match the duplicates' processes and the labelling would be
  order-dependent. The fallback to the plain regex keeps pre-existing (unmarked) sessions
  working.

Notes / caveats:

- Each named tool is a **separate session slot per cwd**, so the picker shows `claude`,
  `claudeB`, `claudeC` as distinct choices and each remembers its own session per repo.
- The env-marker approach reads `proc.env`, which on Linux comes from `/proc` (works on
  this setup). On macOS it falls back to `ps eww`.
- Sessions started *before* the env var existed won't carry the marker; the base tool's
  regex fallback keeps them matching `claude`.

---

## Keybindings

Direct-toggle bindings open/focus/hide a specific tool's session in the float, bypassing
the picker:

```lua
{ "<leader>sca", function() require("sidekick.cli").toggle({ name = "claude",  focus = true }) end, desc = "Sidekick Toggle Claude"  },
{ "<leader>scb", function() require("sidekick.cli").toggle({ name = "claudeB", focus = true }) end, desc = "Sidekick Toggle ClaudeB" },
{ "<leader>scc", function() require("sidekick.cli").toggle({ name = "claudeC", focus = true }) end, desc = "Sidekick Toggle ClaudeC" },
```

Other useful ones already configured:

- `<leader>ss` — the picker (start or attach to any tool/session)
- `<leader>sd` — detach a session
- `<leader>sz` — switch the tmux client to the attached session's tmux session

**Prefix gotcha:** don't keep a bare `<leader>sc` *and* `<leader>sca/scb/scc` — the bare
mapping would only fire after a which-key timeout. Use the explicit leaf bindings instead.

---

## Source-file map (for spelunking the installed plugin)

Under `~/.local/share/nvim/lazy/sidekick.nvim/lua/sidekick/cli/`:

| File | What it does |
|------|--------------|
| `session/init.lua` | `sid()` generation, attach/detach, backend dispatch |
| `session/tmux.lua`  | tmux session create (`tmux new -A -s <sid>`) and discovery |
| `state.lua`         | builds the picker list, dedups by `sid`, sorts/filters |
| `tool.lua`          | tool config merge, `is_proc` resolution |
| `procs.lua`         | process tree walking, `proc.cmd` / `proc.env` / `proc.cwd` |
| `ui/select.lua`     | how each picker row is formatted/labelled |
