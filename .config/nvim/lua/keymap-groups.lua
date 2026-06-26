-- Keymap group definitions for which-key.nvim
-- Provides descriptive labels for leader-key prefixes so which-key popup
-- shows meaningful group names instead of raw key sequences.
--
-- See keymap-groups-notes.md for the full audit of leader keymaps by file.

local wk = require("which-key")

wk.add({
  { "<leader>c", group = "Diffview" },
  { "<leader>d", group = "Debug" },
  { "<leader>dt", group = "Debug Test" },
  { "<leader>f", group = "Find" },
  { "<leader>h", group = "Git Hunk" },
  { "<leader>j", group = "Java" },
  { "<leader>m", group = "Mini.files / Metals" },
  { "<leader>o", group = "Obsidian" },
  { "<leader>or", group = "Obsidian lint" },
  { "<leader>s", group = "Sidekick/Send" },
  { "<leader>sn", group = "Send New" },
  { "<leader>t", group = "Toggle" },
  { "<leader>y", group = "Yank" },
})
