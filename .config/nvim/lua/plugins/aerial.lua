return {
  'stevearc/aerial.nvim',
  opts = {},
  -- Optional dependencies
  dependencies = {
     "nvim-treesitter/nvim-treesitter",
     "nvim-tree/nvim-web-devicons"
  },
  keys = {
    { "<leader>ta", "<cmd>AerialToggle<cr>", desc = "Toggle Aerial" },
  },
}
