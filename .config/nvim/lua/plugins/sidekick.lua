-- https://github.com/folke/sidekick.nvim/blob/main/README.md
return {
 "folke/sidekick.nvim",
  opts = {
    nes = { enabled = false },
    cli = {
      win = {
        layout = "right",
      },
      mux = {
        backend = "tmux",
        enabled = true,
      },
      tools = {
        claude = { cmd = { "claude", "--dangerously-skip-permissions"} },
        cascade = {
          cmd = { "nvim" },
          -- Pass outer tmux info so inner nvim can send OSC 52 to the real terminal
          env = {
            CASCADE_OUTER_TMUX = vim.env.TMUX or "",
            CASCADE_OUTER_TMUX_PANE = vim.env.TMUX_PANE or "",
          },
          format = function(text, str)
            -- Prepend Escape + 'i' to switch to insert mode before inserting text
            return "\027i" .. str
          end,
        },
      },
      prompts = {
        server = "Read and follow the instructions in ~/.claude/dynamic-prompts/nvim-integration.md"
      }
    },
  },
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
      "<c-.>",
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
    -- Example of a keybinding to open Claude directly
    {
      "<leader>sc",
      function() require("sidekick.cli").toggle({ name = "claude", focus = true }) end,
      desc = "Sidekick Toggle Claude",
    },
    -- Toggle Windsurf Cascade bridge
    {
      "<leader>sw",
      function() require("sidekick.cli").toggle({ name = "cascade", focus = true }) end,
      desc = "Sidekick Toggle Cascade",
    },
  },
}
