-- https://github.com/folke/sidekick.nvim/blob/main/README.md

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
          cmd = { "claude" },
          env = { SIDEKICK_TOOL = "claude" },
          is_proc = function(_, p)
            local marker = (p.env or {}).SIDEKICK_TOOL
            if marker == "claudeB" or marker == "claudeC" or marker == "claude_env" then
              return false
            end
            -- still match plain claude (incl. sessions started before this env existed)
            return vim.regex("\\<claude\\>"):match_str(p.cmd) ~= nil
          end,
        },
        claudeB = {
          cmd = { "claude" },
          env = { SIDEKICK_TOOL = "claudeB" },
          is_proc = function(_, p) return (p.env or {}).SIDEKICK_TOOL == "claudeB" end,
          url = "https://github.com/anthropics/claude-code",
        },
        claudeC = {
          cmd = { "claude" },
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

    vim.api.nvim_create_autocmd({ "WinLeave", "FocusLost" }, {
      group = grp,
      desc = "Sidekick: tell claude its pane is unfocused (arms the away recap)",
      callback = function() send_focus("O") end,
    })
    vim.api.nvim_create_autocmd({ "WinEnter", "FocusGained" }, {
      group = grp,
      desc = "Sidekick: tell claude its pane is focused again",
      callback = function() send_focus("I") end,
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
