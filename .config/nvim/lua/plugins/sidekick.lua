-- https://github.com/folke/sidekick.nvim/blob/main/README.md

-- Toggle for the `ps eww` runtime patch applied in config() below. When true,
-- the redundant/erroring `ps eww -p <pid>` env probe is skipped on Linux (faster
-- picker, no "Command failed: ps eww" errors). Flip to false to restore stock
-- sidekick behavior. See the comment at the patch site for the full rationale.
local SKIP_PS_EWW_PROBE = true

-- When nvim's working directory is ~/repos/biofinder (or a subdirectory), run
-- the CLI inside the biofinder docker build environment by prepending
-- ~/repos/biofinder/env.sh to the command. The decision is made at launch time
-- inside the shell (against the spawned session's $PWD, which sidekick sets to
-- the nvim cwd) rather than at config-load time, so it tracks `:cd` changes.
--
-- The dev-environment image sets CLAUDE_CODE_USE_BEDROCK=1, which forces claude
-- onto AWS Bedrock. We strip it with `env -u` so claude inside the container
-- uses the default Anthropic subscription credentials (host ~/.claude and
-- ~/.claude.json are bind-mounted in, so they're available).
--
-- The container also doesn't advertise truecolor support, so claude renders in
-- greyscale ("Try setting environment variable COLORTERM=truecolor..."). The
-- same in-container `env` invocation sets COLORTERM=truecolor to restore rich
-- colors. Both tweaks live here in the wrapper so they travel with any future
-- env.sh-based build environments.
--
-- Like the plain claude tools, this launches with bypass permissions
-- (--dangerously-skip-permissions appended to every claude invocation).
local function biofinder_wrap(args)
  local quoted = {}
  for _, a in ipairs(args) do
    quoted[#quoted + 1] = vim.fn.shellescape(a)
  end
  quoted[#quoted + 1] = "--dangerously-skip-permissions"
  local joined = table.concat(quoted, " ")
  local script = ([[
bf="$HOME/repos/biofinder"
case "$PWD/" in
  "$bf"/*) exec "$bf/env.sh" env -u CLAUDE_CODE_USE_BEDROCK COLORTERM=truecolor %s ;;
  *) exec %s ;;
esac
]]):format(joined, joined)
  return { "sh", "-c", script }
end

-- ── srt sandbox selection ─────────────────────────────────────────────────
-- The plain Claude tools (everything except the env.sh-based claude_env, which
-- is left alone) launch inside an `srt` sandbox. The default srt config is
-- chosen with <leader>sc, which lists every *.json under ~/.sandbox/srt plus a
-- "no sandbox" entry; the default is bypass.json. Switching only affects tools
-- started afterwards: sidekick reattaches to an already-running session and
-- ignores its cmd, so close a session first if you want to relaunch it under a
-- different sandbox (or use <leader>se, which kills + relaunches for you).
local SRT_DIR = vim.fn.expand("~/.sandbox/srt")

-- Sentinel sandbox value meaning "run the clipboard contents as the launch
-- command" (see override_wrap). A unique table so it can't collide with an srt
-- config path or `false`.
local OVERRIDE = setmetatable({}, { __tostring = function() return "override" end })

-- Sentinel sandbox value meaning "no srt sandbox, but still pass
-- --dangerously-skip-permissions" — i.e. the unsandboxed-yet-unprompted launch.
-- This is the deliberately dangerous combination plain `false` ("no sandbox")
-- avoids: false keeps permission prompts because nothing contains the session,
-- whereas this drops both nets. A unique table (truthy, like OVERRIDE) so it
-- can't collide with an srt config path or `false`.
local NOSANDBOX_SKIP = setmetatable({}, { __tostring = function() return "no sandbox (skip perms)" end })

-- Active (default) sandbox: an srt config path, `false` for "no sandbox",
-- NOSANDBOX_SKIP, or OVERRIDE. Only <leader>sc changes this; the <leader>se
-- "exchange" picker takes a one-shot sandbox override without touching it.
local sandbox = SRT_DIR .. "/bypass.json"

-- Build a tool command that runs whatever is on the clipboard as the launch
-- command, read at launch time. Intended for a hand-crafted `srt … claude …`
-- line copied from elsewhere, but it will run any shell command. Reads the
-- system clipboard first (wl-paste / xclip / pbpaste), then the tmux
-- paste-buffer. SIDEKICK_TOOL still rides the tmux session env, so is_proc
-- classification keeps working regardless of what the clipboard command is.
local function override_wrap()
  local lines = {
    [[cmd="$(wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || pbpaste 2>/dev/null)"]],
    [[[ -z "$cmd" ] && cmd="$(tmux show-buffer 2>/dev/null)"]],
    [[if [ -z "$cmd" ]; then]],
    [[  echo "claude override: clipboard is empty."]],
    [[  echo "Copy a full launch command (e.g. srt --settings … claude …) first."]],
    [[  printf 'Press enter to close.'; read _; exit 1]],
    [[fi]],
    [[exec sh -c "$cmd"]],
  }
  return { "sh", "-c", table.concat(lines, "\n") }
end

-- Full argv for a plain `claude` launch. `args` are claude arguments after the
-- binary name (empty for a fresh session). `sb` is the sandbox to use: pass nil
-- to use the active default, an srt config path, `false` for no sandbox, or
-- NOSANDBOX_SKIP for no sandbox with skip-permissions.
--   sandbox:        srt --settings <cfg> claude <args> --dangerously-skip-permissions
--   none:           claude <args> --permission-mode default
--   none+skip-perms: claude <args> --dangerously-skip-permissions   (NOSANDBOX_SKIP)
local function claude_argv(args, sb)
  if sb == nil then
    sb = sandbox
  end
  if sb == OVERRIDE then
    return override_wrap()
  end
  local argv = {}
  -- Only a real srt config path (a string) gets the srt prefix; NOSANDBOX_SKIP
  -- is truthy but means "no sandbox", so it skips it.
  if sb and sb ~= NOSANDBOX_SKIP then
    vim.list_extend(argv, { "srt", "--settings", sb })
  end
  argv[#argv + 1] = "claude"
  vim.list_extend(argv, args or {})
  -- Both srt-sandboxed and NOSANDBOX_SKIP launches skip permission prompts
  -- (both are truthy); only plain `false` keeps the default permission mode.
  if sb then
    argv[#argv + 1] = "--dangerously-skip-permissions"
  else
    vim.list_extend(argv, { "--permission-mode", "default" })
  end
  return argv
end

-- Build a tool command that resumes a Claude session with `claude --resume`.
-- `sid` is the session id: pass an explicit string to bake it in (the
-- <leader>se exchange flow, which already knows the id), or nil to read it at
-- launch time from the tmux paste-buffer (what the sidekick summary TUI's `y`
-- writes via `tmux set-buffer -w`) and then the system clipboard
-- (wl-paste / xclip / pbpaste) — the <leader>sr resume picker. When use_env is
-- true it runs inside the biofinder build environment exactly like the
-- claude_env tool (mirrors biofinder_wrap's env.sh search). Otherwise the
-- resume is wrapped in `sb` (nil → active default, a path, or false for none),
-- matching claude_argv.
local function claude_resume_wrap(use_env, sb, sid)
  if sb == nil then
    sb = sandbox
  end
  if sb == OVERRIDE then
    return override_wrap()
  end
  local lines = {}
  if sid then
    -- explicit id: skip the clipboard read entirely
    lines[#lines + 1] = ([[set -- "claude" --resume %s]]):format(vim.fn.shellescape(sid))
  else
    vim.list_extend(lines, {
      [[sid="$(tmux show-buffer 2>/dev/null | head -n1)"]],
      [[[ -z "$sid" ] && sid="$(wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || pbpaste 2>/dev/null)"]],
      [[sid="$(printf '%s' "$sid" | tr -d '[:space:]')"]],
      [[if [ -z "$sid" ]; then]],
      [[  echo "claude resume: no session id on the clipboard."]],
      [[  echo "Copy one with 'y' in the sidekick summary TUI, then relaunch."]],
      [[  printf 'Press enter to close.'; read _; exit 1]],
      [[fi]],
      [[set -- "claude" --resume "$sid"]],
    })
  end
  if use_env then
    -- biofinder env.sh path: left exactly as before (no srt, no extra flags).
    vim.list_extend(lines, {
      [[bf="$HOME/repos/biofinder"]],
      [[case "$PWD/" in]],
      [[  "$bf"/*) set -- "$bf/env.sh" env -u CLAUDE_CODE_USE_BEDROCK COLORTERM=truecolor "$@" ;;]],
      [[esac]],
    })
  elseif sb == NOSANDBOX_SKIP then
    -- no srt, but still skip permission prompts (the dangerous combination).
    lines[#lines + 1] = [[set -- "$@" --dangerously-skip-permissions]]
  elseif sb then
    lines[#lines + 1] = [[set -- "$@" --dangerously-skip-permissions]]
    lines[#lines + 1] = ([[set -- srt --settings %s "$@"]]):format(vim.fn.shellescape(sb))
  else
    lines[#lines + 1] = [[set -- "$@" --permission-mode default]]
  end
  lines[#lines + 1] = [[exec "$@"]]
  return { "sh", "-c", table.concat(lines, "\n") }
end

-- Human-readable label for a sandbox value: the srt config basename, "no
-- sandbox" for false, or the active default when nil. Shown in the terminal
-- float title (see terminal_title) and stamped into the session env below.
local function sandbox_label(sb)
  if sb == nil then
    sb = sandbox
  end
  if sb == OVERRIDE then
    return "override"
  end
  if sb == NOSANDBOX_SKIP then
    return "no sandbox (skip perms)"
  end
  if sb == false then
    return "no sandbox"
  end
  return vim.fn.fnamemodify(sb, ":t:r")
end

-- Point a tool at a launch command, stamping `label` into its env as
-- SIDEKICK_SANDBOX. sidekick passes tool.env to the spawned tmux session
-- (`tmux new -e …`), so the label both rides the launch argv (for fresh
-- launches) and persists in the session environment (readable on reattach via
-- `tmux show-environment`) — see terminal_title.
local function set_tool_launch(name, cmd, label)
  local tools = require("sidekick.config").cli.tools
  local t = tools[name]
  if not t then
    return
  end
  t.cmd = cmd
  t.env = t.env or {}
  t.env.SIDEKICK_SANDBOX = label
end

-- Reset every Claude tool's launch command to its default (fresh-session) form
-- under the current `sandbox` selection. Called when the default sandbox
-- changes (<leader>sc) and to restore a tool after a one-shot resume/continue
-- launch (<leader>sr / <leader>sb / <leader>se) temporarily overrode its cmd.
local function apply_sandbox()
  local label = sandbox_label(sandbox)
  for _, name in ipairs({ "claudeA", "claudeB", "claudeC", "claudeD", "claudeE" }) do
    set_tool_launch(name, claude_argv({}), label)
  end
  set_tool_launch("claude_env", biofinder_wrap({ "claude" }), "biofinder env")
  set_tool_launch("claude_agents", claude_argv({ "agents" }), label)
end

-- Resolve the sandbox label to show in a terminal float's title, or nil if
-- unknown. Fresh launches carry it as a `SIDEKICK_SANDBOX=<label>` arg in the
-- `tmux new -e …` command; reattaches (`tmux attach-session …`) don't, so fall
-- back to reading it from the live tmux session environment.
local function terminal_title(terminal)
  local cmd = (terminal.tool or {}).cmd or {}
  for _, a in ipairs(cmd) do
    local v = type(a) == "string" and a:match("^SIDEKICK_SANDBOX=(.+)$")
    if v then
      return v
    end
  end
  local sid = terminal.sid
  if sid and vim.fn.executable("tmux") == 1 then
    local out = vim.fn.systemlist({ "tmux", "show-environment", "-t", sid, "SIDEKICK_SANDBOX" })
    if vim.v.shell_error == 0 then
      for _, line in ipairs(out) do
        local v = line:match("^SIDEKICK_SANDBOX=(.+)$")
        if v then
          return v
        end
      end
    end
  end
end

-- srt config chooser. Lists every *.json under ~/.sandbox/srt by basename, plus
-- "no sandbox", "no sandbox (skip perms)" and "override" entries, marks the
-- active default, and calls `cb(value, label)` with the chosen srt config path,
-- `false` (no sandbox), NOSANDBOX_SKIP (no sandbox + skip permissions), or
-- OVERRIDE (run the clipboard as the command). Not called if the picker is
-- cancelled. The picker itself never mutates `sandbox`.
local function select_sandbox(prompt, cb)
  local items = {} ---@type { label: string, value: string|false|table }[]
  local files = vim.fn.glob(SRT_DIR .. "/*.json", false, true)
  table.sort(files)
  for _, f in ipairs(files) do
    items[#items + 1] = { label = vim.fn.fnamemodify(f, ":t:r"), value = f }
  end
  items[#items + 1] = { label = "no sandbox", value = false }
  items[#items + 1] = { label = "no sandbox (skip perms)", value = NOSANDBOX_SKIP }
  items[#items + 1] = { label = "override (clipboard command)", value = OVERRIDE }
  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(item)
      return item.label .. (item.value == sandbox and "  (current)" or "")
    end,
  }, function(choice)
    if not choice then
      return
    end
    cb(choice.value, choice.label)
  end)
end

-- <leader>sc picker: choose the default srt config (or "no sandbox") for the
-- Claude tools and rebuild their launch commands. This is the only thing that
-- changes the active default sandbox.
local function pick_sandbox()
  select_sandbox("default srt sandbox for Claude tools", function(value, label)
    sandbox = value
    apply_sandbox()
    vim.notify("Claude sandbox → " .. label, vim.log.levels.INFO)
  end)
end

-- ── copy attached Claude session id ───────────────────────────────────────
-- Mirrors how ~/repos/summary resolves a sidekick claude session's id: the
-- Claude Code transcript lives at ~/.claude/projects/<encoded-cwd>/<uuid>.jsonl
-- (cwd with '/' and '.' replaced by '-'), and the id is that filename stem. The
-- newest *.jsonl by mtime is the active session (the cheap single-pane case the
-- summary tool uses; it only content-matches when several claude panes share a
-- cwd, which we don't try to disambiguate here).

-- Copy text the same way the summary TUI's `y` does: the tmux paste-buffer
-- first (what the resume command reads back via `tmux show-buffer`, and which
-- rides the set-clipboard → terminal passthrough), plus nvim's `+` register.
local function clipboard_copy(text)
  local ok = false
  if vim.fn.executable("tmux") == 1 then
    vim.fn.system({ "tmux", "set-buffer", "-w", text })
    ok = vim.v.shell_error == 0
  end
  pcall(vim.fn.setreg, "+", text)
  return ok or vim.fn.has("clipboard") == 1
end

-- Resolve the attached Claude session to operate on, and its transcript id.
-- Returns (state, sid) or (nil) with a warning notified. `state.tool.name` is
-- the tool slot (claude / claudeB / …); `sid` is the Claude Code transcript
-- uuid.
local function resolve_claude_session()
  local State = require("sidekick.cli.state")
  -- claude-kind sessions only (tool name starts with "claude")
  local claude = {}
  for _, st in ipairs(State.get({ attached = true })) do
    if st.session and ((st.tool or {}).name or ""):match("^claude") then
      claude[#claude + 1] = st
    end
  end
  if #claude == 0 then
    vim.notify("sidekick: no attached Claude session", vim.log.levels.WARN)
    return
  end

  -- if several are attached, prefer the one shown in the current window
  local chosen = claude[1]
  if #claude > 1 then
    local ok, winsid = pcall(vim.api.nvim_win_get_var, 0, "sidekick_session_id")
    if ok and type(winsid) == "string" then
      winsid = winsid:gsub("^terminal:%s*", "")
      for _, st in ipairs(claude) do
        if st.session.sid == winsid then
          chosen = st
          break
        end
      end
    end
  end

  local cwd = (chosen.session.cwd or ""):gsub("/+$", "")
  local enc = cwd:gsub("[/.]", "-")
  local proj = vim.fn.expand("~/.claude/projects/") .. enc
  local files = vim.fn.glob(proj .. "/*.jsonl", false, true)
  if #files == 0 then
    vim.notify("sidekick: no Claude transcript under " .. proj, vim.log.levels.WARN)
    return
  end
  local newest, newest_t
  for _, f in ipairs(files) do
    local t = vim.fn.getftime(f)
    if not newest_t or t > newest_t then
      newest, newest_t = f, t
    end
  end
  return chosen, vim.fn.fnamemodify(newest, ":t:r")
end

-- <leader>sy: copy the attached Claude session id to the clipboard.
local function copy_claude_session_id()
  local _, sid = resolve_claude_session()
  if not sid then
    return
  end
  if clipboard_copy(sid) then
    vim.notify("Claude session id copied: " .. sid)
  else
    vim.notify("Claude session id (clipboard copy failed): " .. sid, vim.log.levels.WARN)
  end
end

-- ── resume / continue / exchange launchers ────────────────────────────────
-- Claude tool slots that can host a resumed/continued session. claude_agents
-- is excluded (it runs the `claude agents` subcommand, not a chat session).
local RESUMABLE = { "claudeA", "claudeB", "claudeC", "claudeD", "claudeE", "claude_env" }

-- Launch `name` with a one-shot `cmd` (titled `label`), then restore every
-- tool's default cmd.
--
-- We attach a tool-only state directly instead of `cli.toggle({ name })`. toggle
-- routes through State.with, whose attach path falls back to a *tool-name*
-- filtered picker whenever no session of that name is currently attached — and
-- that filter ignores cwd, so same-named sessions running in other directories
-- show up too (the exact bug here: <leader>se kills this cwd's session, leaving
-- 0 attached, then the relaunch prompts with claudeA sessions from elsewhere).
-- State.attach on a `{ tool = … }` state with no session always spawns a fresh
-- session, pinned to the current cwd (Session.new → M.cwd), with no picker.
--
-- Config.get_tool() deep-copies the tool config — including the cmd/env we just
-- baked via set_tool_launch — into the session's own `tool`, so the one-shot cmd
-- is captured immutably at attach time. The deferred apply_sandbox() then resets
-- the shared config for future launches without ever touching this session.
local function launch_with_cmd(name, cmd, label)
  local Config = require("sidekick.config")
  if not Config.cli.tools[name] then
    return
  end
  set_tool_launch(name, cmd, label)
  require("sidekick.cli.state").attach(
    { tool = Config.get_tool(name) },
    { show = true, focus = true }
  )
  vim.schedule(apply_sandbox)
end

-- Pick a Claude tool slot (like <leader>ss, but scoped to RESUMABLE) and launch
-- it with the command (and title label) returned by `build_cmd(name)`.
local function pick_resumable(prompt, build_cmd)
  local tools = require("sidekick.config").cli.tools
  local items = {}
  for _, name in ipairs(RESUMABLE) do
    if tools[name] then
      items[#items + 1] = name
    end
  end
  vim.ui.select(items, { prompt = prompt }, function(name)
    if name then
      launch_with_cmd(name, build_cmd(name))
    end
  end)
end

-- Default sandbox label for a slot picked in the resume/continue pickers:
-- claude_env runs the biofinder env, everything else the active default.
local function slot_label(name)
  return name == "claude_env" and "biofinder env" or sandbox_label(sandbox)
end

-- <leader>sr: resume picker. Choose any Claude slot; it launches
-- `claude --resume <id>` reading the id from the clipboard.
local function pick_resume()
  pick_resumable("resume Claude session (from clipboard) into…", function(name)
    return claude_resume_wrap(name == "claude_env"), slot_label(name)
  end)
end

-- <leader>sb: continue picker. Choose any Claude slot; it launches
-- `claude --continue` (most recent session in the cwd).
local function pick_continue()
  pick_resumable("continue most recent Claude session into…", function(name)
    if name == "claude_env" then
      return biofinder_wrap({ "claude", "--continue" }), slot_label(name)
    end
    return claude_argv({ "--continue" }), slot_label(name)
  end)
end

-- <leader>se: exchange. Pick an srt sandbox (without changing the default),
-- then capture the attached Claude session's id, kill that session, and
-- relaunch the *same* tool slot resuming that id under the chosen sandbox.
local function exchange_sandbox()
  local chosen, sid = resolve_claude_session()
  if not sid then
    return
  end
  local name = chosen.tool.name
  select_sandbox("reload " .. name .. " (--resume) into sandbox…", function(sb)
    -- "override" runs the clipboard verbatim, so don't clobber it with the sid;
    -- otherwise copy the sid (matching <leader>sy) for the --resume relaunch.
    if sb ~= OVERRIDE then
      clipboard_copy(sid)
    end
    local s = chosen.session
    local mux = s.mux_session or (s.parent and s.parent.mux_session)
    -- tear down the running session: close the nvim terminal, then destroy the
    -- tmux session so the slot is free for a fresh launch with the new cmd
    if chosen.terminal then
      pcall(function()
        chosen.terminal:close()
      end)
    end
    if mux then
      vim.fn.system({ "tmux", "kill-session", "-t", mux })
    end
    local use_env = name == "claude_env"
    local cmd = claude_resume_wrap(use_env, sb, sid)
    local label = use_env and "biofinder env" or sandbox_label(sb)
    -- defer so the old terminal/session has fully torn down before relaunch
    vim.defer_fn(function()
      launch_with_cmd(name, cmd, label)
    end, 150)
  end)
end

return {
 "folke/sidekick.nvim",
  opts = {
    nes = { enabled = false },
    cli = {
      win = {
        layout = "float",
        float = {
          width = 0.8,
          height = 0.8,
          border = "solid"
        },
        -- Show the launch sandbox in the float title (e.g. " Sidekick — bypass ").
        -- terminal_title reads it from the launch argv or the live tmux session
        -- env; falls back to the plain title when it can't tell.
        config = function(terminal)
          local name = (terminal.tool or {}).name
          local label = terminal_title(terminal)
          if name and label then
            terminal.opts.float.title = (" Sidekick — %s · %s "):format(name, label)
          elseif name then
            terminal.opts.float.title = (" Sidekick — %s "):format(name)
          elseif label then
            terminal.opts.float.title = (" Sidekick — %s "):format(label)
          end
        end,
      },
      mux = {
        backend = "tmux",
        enabled = true,
      },
      tools = {
        -- Every slot runs the same `claude` binary, so a command-line match
        -- (`\<claude\>`) can't tell reattached sessions apart. Instead each
        -- launch is stamped with a unique SIDEKICK_TOOL env var (sidekick passes
        -- `tool.env` to the tmux session) and is_proc matches on that exactly.
        --
        -- The primary slot is named `claudeA` (not `claude`) on purpose: a slot
        -- literally named `claude` is tempting to match with the broad
        -- `\<claude\>` regex "to also catch untagged sessions", but that regex
        -- matches *any* claude process — external tmux sessions, legacy/manual
        -- launches, other slots' resume wrappers — so `<leader>se`'s kill +
        -- relaunch would resolve the empty slot ambiguously against those live
        -- sessions and pop a picker. An exact SIDEKICK_TOOL match, like every
        -- other slot, keeps `claudeA` unambiguous.
        claudeA = {
          cmd = claude_argv({}),
          env = { SIDEKICK_TOOL = "claudeA" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeA" end,
        },
        claudeB = {
          cmd = claude_argv({}),
          env = { SIDEKICK_TOOL = "claudeB" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeB" end,
          url = "https://github.com/anthropics/claude-code",
        },
        claudeC = {
          cmd = claude_argv({}),
          env = { SIDEKICK_TOOL = "claudeC" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeC" end,
          url = "https://github.com/anthropics/claude-code",
        },
        claudeD = {
          cmd = claude_argv({}),
          env = { SIDEKICK_TOOL = "claudeD" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeD" end,
          url = "https://github.com/anthropics/claude-code",
        },
        claudeE = {
          cmd = claude_argv({}),
          env = { SIDEKICK_TOOL = "claudeE" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeE" end,
          url = "https://github.com/anthropics/claude-code",
        },
        -- Runs claude inside the biofinder docker build environment when nvim's
        -- cwd is under ~/repos/biofinder (otherwise behaves like plain claude).
        -- Resume/continue into this slot via <leader>sr / <leader>sb.
        claude_env = {
          cmd = biofinder_wrap({ "claude" }),
          env = { SIDEKICK_TOOL = "claude_env" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claude_env" end,
          url = "https://github.com/anthropics/claude-code",
        },
        -- Runs `claude agents` (just an extra argument before the permission
        -- flags) under the active srt sandbox, exactly like the plain claude
        -- tools — same sandbox selection, same skip-permissions behavior.
        claude_agents = {
          cmd = claude_argv({ "agents" }),
          env = { SIDEKICK_TOOL = "claude_agents" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claude_agents" end,
          url = "https://github.com/anthropics/claude-code",
        },
        gemini = { cmd = { "gemini", "--yolo" } },
        neovim = {
          cmd = { "nvim" },
        },
      },
      prompts = {
        work_note = "Make a markdown document and put it in ~/vaults/Main/work/fleeting/",
        nosync_note = "Make a markdown document and put it in ~/vaults/Main/work/fleeting/",
        improve = "Are there any obvious ways to do what I'm intending to better than how I pitched the implementation?",
        jira_links = "Enhance any Jira epic or story IDs (e.g. BFV2-4241, SETI-2037) into full markdown links pointing to https://acs-cas.atlassian.net/browse/<ID>, then use the Atlassian MCP to fetch each issue and append a 1-2 sentence description (summary, type, and status) after the link.",
        add_prompt = "Add a prompt to the prompt list in ~/.config/nvim/lua/plugins/sidekick.lua that (in a sentence (or two, max)) explains to: ",
        line_by_line = "Explain {selection}. Teach me what it does with a line by line visual with explanation to the right of each line.",
        explain_marklogic_note = "Add {selection} to \"Explaned Marklogic functions.md\" in ~/vaults/Main per the instructions in the document",
      }
    },
  },
  config = function(_, opts)
    require("sidekick").setup(opts)

    -- Drop sidekick's stock `claude` tool. There's no built-in disable flag:
    -- the default `tools` table hardcodes `claude = {}` and setup() deep-merges
    -- opts on top (keys are never removed), and setting `claude = false` doesn't
    -- help because tool.get() coerces it back via `Config.cli.tools[name] or {}`.
    -- We run our own slot as `claudeA` (exact SIDEKICK_TOOL match), so the stock
    -- `claude` is just a redundant, broad-matching duplicate in the picker.
    -- Deleting the key after setup is what removes it from pairs() iteration.
    require("sidekick.config").cli.tools.claude = nil

    -- Stamp the active sandbox label into every Claude tool's cmd/env up front,
    -- so even a first launch (before any <leader>sc pick) carries SIDEKICK_SANDBOX
    -- for the float title.
    apply_sandbox()

    -- ── kill the redundant `ps eww` env probe on Linux ───────────────────────
    -- sidekick's process scanner (cli/procs.lua M.env) reads a pid's env from
    -- /proc/<pid>/environ — which on Linux always succeeds — and then *also*
    -- runs a blocking `ps eww -p <pid>` "fallback" (BSD/macOS syntax) even
    -- though the env is already populated. session/tmux.lua walks the process
    -- subtree of every sidekick pane and probes env for each pid, so opening the
    -- picker spawns one synchronous `ps eww` per process (visible lag), and any
    -- pid that exits mid-scan makes `ps eww` exit non-zero → sidekick's
    -- Util.exec pops "Command failed: ps eww -p <pid>". Both go away if we just
    -- don't run the fallback: /proc is authoritative here.
    --
    -- M.env captures itself into a local `proc_fields` table at load, so it
    -- can't be monkeypatched directly; but it reaches the subprocess through
    -- Util.exec, looked up dynamically on the module table, so wrapping that
    -- short-circuits exactly the `ps eww -p` calls and nothing else (the main
    -- scan uses `ps -u`/`ps -ww`, lsof, curl, tmux … which all pass through).
    -- Gated on SKIP_PS_EWW_PROBE (top of file) so it's easy to flip off.
    if SKIP_PS_EWW_PROBE then
      local Util = require("sidekick.util")
      local orig_exec = Util.exec
      function Util.exec(cmd, exec_opts)
        if cmd[1] == "ps" and cmd[2] == "eww" then
          return nil
        end
        return orig_exec(cmd, exec_opts)
      end
    end

    -- ── Sidekick focus bridge ────────────────────────────────────────────────
    -- Sidekick shows the CLI's tmux session inside a neovim terminal float.
    -- Toggling the float away only *hides* the window — the nested tmux client
    -- stays attached, so claude never learns it's unfocused. But Claude Code's
    -- "away" recap (the `※ recap:` / away_summary) only generates while the pane
    -- is unfocused. This forwards a focus-out/in to the claude pane based on
    -- whether you're actually looking at the sidekick window, so the recap fires
    -- when you toggle/tab away — letting the sidekick summary tool surface it
    -- before you switch back. Free; uses Claude's native recap (no model calls).
    local grp = vim.api.nvim_create_augroup("sidekick_focus_bridge", { clear = true })
    local pane_of = {} ---@type table<string, string|false> session name -> pane id

    -- tmux session name of the *current* window, if it's a sidekick CLI window
    local function current_session()
      local ok, sid = pcall(vim.api.nvim_win_get_var, 0, "sidekick_session_id")
      if not ok or type(sid) ~= "string" then
        return nil
      end
      return (sid:gsub("^terminal:%s*", "")) -- "claude 176d2ddf2d"
    end

    local function exec(cmd)
      if vim.system then
        vim.system(cmd) -- async, fire-and-forget
      else
        vim.fn.jobstart(cmd)
      end
    end

    -- send a focus event ("I" = focus-in, "O" = focus-out) to the session's pane
    local function send_focus(kind)
      local session = current_session()
      if not session then
        return
      end
      local pane = pane_of[session]
      if pane == nil then
        local out = vim.fn.systemlist({ "tmux", "list-panes", "-t", session, "-F", "#{pane_id}" })
        pane = (vim.v.shell_error == 0 and out[1]) or false
        pane_of[session] = pane
      end
      if pane then
        -- mirrors how sidekick itself sends focus before pasting (tmux.lua)
        exec({ "tmux", "send-keys", "-t", pane, "Escape", "[", kind })
      end
    end

    -- ── resize nudge for sandboxed claude (float-toggle case) ────────────────
    -- srt runs claude under `bwrap --new-session`, detaching it from the tty so
    -- the kernel never delivers SIGWINCH on resize. Three things resize the pane
    -- and only some fire a tmux hook: dragging the terminal (client-resized) and
    -- switching *directly* to the session (client-session-changed) are covered by
    -- ~/.tmux.conf; tmux's *automatic* size recalculation (window-size=latest /
    -- aggressive-resize reflowing the session when its constraining client changes
    -- or detaches) fires NO hook on tmux 3.6 and is instead caught by the summary
    -- TUI's size poll (sk_tui.py _winch_poller). This autocmd covers a fourth case
    -- neither reaches: toggling the sidekick float away and back. The nested
    -- `tmux attach-session` client stays attached at the same size, so tmux fires
    -- no resize event; by the time the float is shown the claude pane is already
    -- at the right (float) size, it just never got told. So on focus-in of a
    -- sidekick window, re-send SIGWINCH (host helper). It only signals
    -- comm=="claude", so it's a no-op for other tools.
    local winch = vim.fn.expand("~/.local/bin/srt-send-winch")
    local function nudge_winch()
      local session = current_session()
      if not session or vim.fn.executable(winch) ~= 1 then
        return
      end
      -- fire twice to cover tmux propagating the size into the pty before claude
      -- is told to re-read it
      for _, ms in ipairs({ 80, 250 }) do
        vim.defer_fn(function() exec({ winch, "-s", session }) end, ms)
      end
    end

    vim.api.nvim_create_autocmd({ "WinLeave", "FocusLost" }, {
      group = grp,
      desc = "Sidekick: tell claude its pane is unfocused (arms the away recap)",
      callback = function() send_focus("O") end,
    })
    vim.api.nvim_create_autocmd({ "WinEnter", "FocusGained" }, {
      group = grp,
      desc = "Sidekick: tell claude its pane is focused again",
      callback = function()
        send_focus("I")
        nudge_winch()
      end,
    })
    -- session set changed → drop stale pane ids
    vim.api.nvim_create_autocmd("User", {
      group = grp,
      pattern = { "SidekickCliAttach", "SidekickCliDetach" },
      callback = function() pane_of = {} end,
    })
  end,
  keys = {
    -- No next line edit without copilot subscription
    -- {
    --   "<tab>",
    --   function()
    --     -- if there is a next edit, jump to it, otherwise apply it if any
    --     if not require("sidekick").nes_jump_or_apply() then
    --       return "<Tab>" -- fallback to normal tab
    --     end
    --   end,
    --   expr = true,
    --   desc = "Goto/Apply Next Edit Suggestion",
    -- },
    {
      "<c-space>",
      function() require("sidekick.cli").toggle() end,
      desc = "Sidekick Toggle",
      mode = { "n", "t", "i", "x" },
    },
  {
      "<leader>sa",
      function() require("sidekick.cli").toggle() end,
      desc = "Sidekick Toggle CLI",
    },
    {
      "<leader>ss",
      function() require("sidekick.cli").select() end,
      -- Or to select only installed tools:
      -- require("sidekick.cli").select({ filter = { installed = true } })
      -- Normal-mode only: a "t"-mode <leader> mapping intercepts the space bar
      -- while you're typing in the claude terminal, so leave it off here.
      desc = "Select CLI",
    },
    {
      "<leader>sd",
      function() require("sidekick.cli").close() end,
      desc = "Detach a CLI Session",
    },
    {
      "<leader>st",
      function() require("sidekick.cli").send({ msg = "{this}" }) end,
      mode = { "x", "n" },
      desc = "Send This",
    },
    {
      "<leader>sf",
      function() require("sidekick.cli").send({ msg = "{file}" }) end,
      desc = "Send File",
    },
    {
      "<leader>sv",
      function() require("sidekick.cli").send({ msg = "{selection}" }) end,
      mode = { "x" },
      desc = "Send Visual Selection",
    },
    {
      "<leader>sp",
      function() require("sidekick.cli").prompt() end,
      mode = { "n", "x" },
      desc = "Sidekick Select Prompt",
    },
    {
      "<leader>sc",
      function() pick_sandbox() end,
      desc = "Sidekick: pick default srt sandbox for Claude",
    },
    {
      "<leader>sr",
      function() pick_resume() end,
      desc = "Sidekick: resume Claude session (from clipboard) into a slot",
    },
    {
      "<leader>sb",
      function() pick_continue() end,
      desc = "Sidekick: continue most recent Claude session into a slot",
    },
    -- NOTE: these stay normal-mode only (no "t"). A "t"-mode <leader> mapping
    -- intercepts the space bar while you're typing in the claude terminal, so
    -- e.g. "<space>se" fires the chord instead of reaching claude. Only
    -- <c-space> is bound in terminal mode (above) so the toggle still works
    -- while typing; switch to normal mode (<c-q>) to use these in a session.
    {
      "<leader>se",
      function() exchange_sandbox() end,
      desc = "Sidekick: reload attached Claude session into another sandbox",
    },
    {
      "<leader>sy",
      function() copy_claude_session_id() end,
      desc = "Copy attached Claude session id",
    },
    {
      "<leader>sg",
      function() require("sidekick.cli").toggle({ name = "gemini", focus = true }) end,
      desc = "Sidekick Toggle Gemini",
    },
    -- Toggle a Neovim instance as a sidekick
    {
      "<leader>sn",
      function() require("sidekick.cli").toggle({ name = "neovim", focus = true }) end,
      desc = "Sidekick Toggle Neovim",
    },
    {
      "<leader>sz",
      function()
        require("sidekick.cli.state").with(function(state)
          local s = state.session
          local mux = s.mux_session or (s.parent and s.parent.mux_session)
          if mux then
            -- sidekick spawns its sessions with a session-local `status off` so
            -- the bar doesn't clutter the nvim float. We're leaving nvim to look
            -- at the session directly, so turn the bar back on first.
            vim.fn.system({ "tmux", "set-option", "-t", mux, "status", "on" })
            vim.fn.system({ "tmux", "switch-client", "-t", mux })
          else
            vim.notify("No tmux session for " .. state.tool.name, vim.log.levels.WARN)
          end
        end, { filter = { attached = true } })
      end,
      -- Bound in terminal mode too (unlike the other <leader>s* session
      -- commands): the whole point is to jump from the claude float into the
      -- tmux session, which you do while typing in the terminal.
      mode = { "n", "t" },
      desc = "Switch to Sidekick tmux session",
    },
  },
}
