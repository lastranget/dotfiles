return {
  'stevearc/aerial.nvim',
  branch = "nvim-0.11", -- current default branch requires Neovim >= 0.12
  opts = {},
  -- Optional dependencies
  dependencies = {
     "nvim-treesitter/nvim-treesitter",
     "nvim-tree/nvim-web-devicons"
  },
  cmd = { "AerialToggle", "AerialOpen", "AerialClose", "AerialNavToggle" },
  keys = {
    { "<leader>ta", "<cmd>AerialToggle<cr>", desc = "Toggle Aerial" },
  },
}
