-- https://github.com/Exafunction/windsurf.nvim
return {
  "Exafunction/windsurf.nvim",
  event = "BufEnter",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("codeium").setup({
      enable_cmp_source = false,
      virtual_text = {
        enabled = true,
        key_bindings = {
          accept = "<C-g>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
    })
  end,
}
