return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  opts = {
    ensure_installed = {
      "java",
      "lua",
      "python",
      "html",
      "json",
      "markdown",
      "typescript",
      "yaml",
    },
  },
}
