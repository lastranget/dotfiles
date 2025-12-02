return {
   "m4xshen/hardtime.nvim",
   lazy = false,
   dependencies = { "MunifTanjim/nui.nvim" },
   opts = {
      disabled_keys = {
        ["<Left>"] = { "n", "x" },
        ["<Right>"] = { "n", "x" }
      }
   },
}
