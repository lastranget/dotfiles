return {
  "linux-cultist/venv-selector.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    "folke/snacks.nvim",
  },
  ft = "python", -- Load when opening Python files
  keys = {
    { "<leader>e", "<cmd>VenvSelect<cr>", desc = "Open venv picker" }, -- Open picker on keymap
  },
  opts = {
      picker = "snacks",
      search = {},
      options = {
          -- On Ubuntu/Debian, fd is installed as fdfind
          fd_binary_name = vim.fn.executable("fd") == 1 and "fd" or "fdfind",
      },
  },
}
