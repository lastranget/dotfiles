return {
  "linux-cultist/venv-selector.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    { "nvim-telescope/telescope.nvim", branch = "0.1.x", dependencies = { "nvim-lua/plenary.nvim" } }, -- optional: you can also use fzf-lua, snacks, mini-pick instead.
  },
  ft = "python", -- Load when opening Python files
  keys = {
    { "<leader>e", "<cmd>VenvSelect<cr>", desc = "Open venv picker" }, -- Open picker on keymap
  },
  opts = {
      search = {},
      options = {
          -- On Ubuntu/Debian, fd is installed as fdfind
          fd_binary_name = vim.fn.executable("fd") == 1 and "fd" or "fdfind",
      },
  },
}
