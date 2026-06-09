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
local function biofinder_wrap(args)
  local quoted = {}
  for _, a in ipairs(args) do
    quoted[#quoted + 1] = vim.fn.shellescape(a)
  end
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
-- The plain Claude tools (everything except the env.sh-based claude_env /
-- claude_env_resume, which are left alone) launch inside an `srt` sandbox. The
-- active srt config is chosen with <leader>sr, which lists every *.json under
-- ~/.sandbox/srt plus a "no sandbox" entry; the default is bypass.json.
-- Switching only affects tools started afterwards: sidekick reattaches to an
-- already-running session and ignores its cmd, so close a session first if you
-- want to relaunch it under a different sandbox.
local SRT_DIR = vim.fn.expand("~/.sandbox/srt")

-- Active sandbox: an srt config path, or `false` for "no sandbox".
local sandbox = SRT_DIR .. "/bypass.json"

-- Full argv for a plain `claude` launch under the active sandbox. `args` are
-- claude arguments after the binary name (empty for a fresh session).
--   sandbox: srt --settings <cfg> claude <args> --dangerously-skip-permissions
--   none:    claude <args> --permission-mode default
local function claude_argv(args)
  local argv = {}
  if sandbox then
    vim.list_extend(argv, { "srt", "--settings", sandbox })
  end
  argv[#argv + 1] = "claude"
  vim.list_extend(argv, args or {})
  if sandbox then
    argv[#argv + 1] = "--dangerously-skip-permissions"
  else
    vim.list_extend(argv, { "--permission-mode", "default" })
  end
  return argv
end

-- Build a tool command that resumes a Claude session whose ID is on the
-- clipboard. The ID is read at launch time: the tmux paste-buffer first (that's
-- what the sidekick summary TUI's `y` writes via `tmux set-buffer -w`), then the
-- system clipboard (wl-paste / xclip / pbpaste). When use_env is true it runs
-- inside the biofinder build environment exactly like the claude_env tool
-- (mirrors biofinder_wrap's env.sh search). When use_env is false the resume is
-- wrapped in the active srt sandbox, matching claude_argv. The tool names start
-- with "claude" so the summary tool classifies these as claude sessions
-- (transcript-backed).
local function claude_resume_wrap(use_env)
  local lines = {
    [[sid="$(tmux show-buffer 2>/dev/null | head -n1)"]],
    [[[ -z "$sid" ] && sid="$(wl-paste 2>/dev/null || xclip -o -selection clipboard 2>/dev/null || pbpaste 2>/dev/null)"]],
    [[sid="$(printf '%s' "$sid" | tr -d '[:space:]')"]],
    [[if [ -z "$sid" ]; then]],
    [[  echo "claude_resume: no session id on the clipboard."]],
    [[  echo "Copy one with 'y' in the sidekick summary TUI, then relaunch."]],
    [[  printf 'Press enter to close.'; read _; exit 1]],
    [[fi]],
    [[set -- "claude" --resume "$sid"]],
  }
  if use_env then
    -- biofinder env.sh path: left exactly as before (no srt, no extra flags).
    vim.list_extend(lines, {
      [[bf="$HOME/repos/biofinder"]],
      [[case "$PWD/" in]],
      [[  "$bf"/*) set -- "$bf/env.sh" env -u CLAUDE_CODE_USE_BEDROCK COLORTERM=truecolor "$@" ;;]],
      [[esac]],
    })
  elseif sandbox then
    lines[#lines + 1] = [[set -- "$@" --dangerously-skip-permissions]]
    lines[#lines + 1] = ([[set -- srt --settings %s "$@"]]):format(vim.fn.shellescape(sandbox))
  else
    lines[#lines + 1] = [[set -- "$@" --permission-mode default]]
  end
  lines[#lines + 1] = [[exec "$@"]]
  return { "sh", "-c", table.concat(lines, "\n") }
end

-- Rebuild the launch command of every sandbox-affected Claude tool from the
-- current `sandbox` selection. claude_env / claude_env_resume are untouched.
local function apply_sandbox()
  local tools = require("sidekick.config").cli.tools
  for _, name in ipairs({ "claude", "claudeB", "claudeC" }) do
    if tools[name] then
      tools[name].cmd = claude_argv({})
    end
  end
  if tools.claude_resume then
    tools.claude_resume.cmd = claude_resume_wrap(false)
  end
  if tools.claude_continue then
    tools.claude_continue.cmd = claude_argv({ "--continue" })
  end
  if tools.claude_agents then
    tools.claude_agents.cmd = claude_argv({ "agents" })
  end
end

-- <leader>sr picker: choose an srt config (or "no sandbox") for the Claude
-- tools. Lists every *.json under ~/.sandbox/srt by basename, marks the active
-- one, and rebuilds the affected tool commands on selection.
local function pick_sandbox()
  local items = {} ---@type { label: string, value: string|false }[]
  local files = vim.fn.glob(SRT_DIR .. "/*.json", false, true)
  table.sort(files)
  for _, f in ipairs(files) do
    items[#items + 1] = { label = vim.fn.fnamemodify(f, ":t:r"), value = f }
  end
  items[#items + 1] = { label = "no sandbox", value = false }
  vim.ui.select(items, {
    prompt = "srt sandbox for Claude tools",
    format_item = function(item)
      return item.label .. (item.value == sandbox and "  (current)" or "")
    end,
  }, function(choice)
    if not choice then
      return
    end
    sandbox = choice.value
    apply_sandbox()
    vim.notify("Claude sandbox → " .. choice.label, vim.log.levels.INFO)
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
-- first (what claude_resume reads back via `tmux show-buffer`, and which rides
-- the set-clipboard → terminal passthrough), plus nvim's `+` register.
local function clipboard_copy(text)
  local ok = false
  if vim.fn.executable("tmux") == 1 then
    vim.fn.system({ "tmux", "set-buffer", "-w", text })
    ok = vim.v.shell_error == 0
  end
  pcall(vim.fn.setreg, "+", text)
  return ok or vim.fn.has("clipboard") == 1
end

local function copy_claude_session_id()
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
  local sid = vim.fn.fnamemodify(newest, ":t:r")

  if clipboard_copy(sid) then
    vim.notify("Claude session id copied: " .. sid)
  else
    vim.notify("Claude session id (clipboard copy failed): " .. sid, vim.log.levels.WARN)
  end
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
        }
      },
      mux = {
        backend = "tmux",
        enabled = true,
      },
      tools = {
        -- All three variants run the same `claude` binary, so the default
        -- `\<claude\>` command-line match can't tell a reattached session
        -- apart. Instead we stamp each launch with a unique SIDEKICK_TOOL env
        -- var (sidekick passes `tool.env` to the tmux session) and match on it.
        claude = {
          cmd = claude_argv({}),
          env = { SIDEKICK_TOOL = "claude" },
          is_proc = function(_, p)
            local marker = (p.env or {}).SIDEKICK_TOOL
            if marker == "claudeB" or marker == "claudeC" or marker == "claude_env"
              or marker == "claude_resume" or marker == "claude_env_resume"
              or marker == "claude_continue" or marker == "claude_agents" then
              return false
            end
            -- still match plain claude (incl. sessions started before this env existed)
            return vim.regex("\\<claude\\>"):match_str(p.cmd) ~= nil
          end,
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
        -- Runs claude inside the biofinder docker build environment when nvim's
        -- cwd is under ~/repos/biofinder (otherwise behaves like plain claude).
        claude_env = {
          cmd = biofinder_wrap({ "claude" }),
          env = { SIDEKICK_TOOL = "claude_env" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claude_env" end,
          url = "https://github.com/anthropics/claude-code",
        },
        -- Resume the Claude session whose ID is on the clipboard (copy it with
        -- `y` in the sidekick summary TUI). claude_env_resume does so inside the
        -- biofinder build environment, like claude_env.
        claude_resume = {
          cmd = claude_resume_wrap(false),
          env = { SIDEKICK_TOOL = "claude_resume" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claude_resume" end,
          url = "https://github.com/anthropics/claude-code",
        },
        -- Like claude_resume, but continues the most recent Claude session in
        -- the cwd (claude --continue) instead of resuming a clipboard id. Runs
        -- under the active srt sandbox, just like the plain claude tools.
        claude_continue = {
          cmd = claude_argv({ "--continue" }),
          env = { SIDEKICK_TOOL = "claude_continue" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claude_continue" end,
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
        claude_env_resume = {
          cmd = claude_resume_wrap(true),
          env = { SIDEKICK_TOOL = "claude_env_resume" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claude_env_resume" end,
          url = "https://github.com/anthropics/claude-code",
        },
        gemini = { cmd = { "gemini", "--yolo" } },
        neovim = {
          cmd = { "nvim" },
        },
      },
      prompts = {
        server = "Read and follow the instructions in ~/.claude/dynamic-prompts/nvim-integration.md",
        vault_note = "Make a markdown document and put it in ~/vaults/Main/work/fleeting/",
        improve = "Are there any obvious ways to do what I'm intending to better than how I pitched the implementation?"
      }
    },
  },
  config = function(_, opts)
    require("sidekick").setup(opts)

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
    -- Toggle a specific Claude session directly
    {
      "<leader>sca",
      function() require("sidekick.cli").toggle({ name = "claude", focus = true }) end,
      desc = "Sidekick Toggle Claude",
    },
    {
      "<leader>scb",
      function() require("sidekick.cli").toggle({ name = "claudeB", focus = true }) end,
      desc = "Sidekick Toggle ClaudeB",
    },
    {
      "<leader>scc",
      function() require("sidekick.cli").toggle({ name = "claudeC", focus = true }) end,
      desc = "Sidekick Toggle ClaudeC",
    },
    {
      "<leader>sce",
      function() require("sidekick.cli").toggle({ name = "claude_env", focus = true }) end,
      desc = "Sidekick Toggle Claude (biofinder env)",
    },
    {
      "<leader>scg",
      function() require("sidekick.cli").toggle({ name = "claude_agents", focus = true }) end,
      desc = "Sidekick Toggle Claude Agents",
    },
    {
      "<leader>sr",
      function() pick_sandbox() end,
      desc = "Sidekick: pick srt sandbox for Claude",
    },
    {
      "<leader>sy",
      function() copy_claude_session_id() end,
      mode = { "n", "t" },
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
      mode = { "n", "t" },
      desc = "Switch to Sidekick tmux session",
    },
  },
}
