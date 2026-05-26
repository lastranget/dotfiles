return {
  "nmac427/guess-indent.nvim",
  ft = "xquery",
  opts = {
    auto_cmd = true,
    filetype_exclude = { "netrw", "tutor" },
    buftype_exclude = { "help", "nofile", "terminal", "prompt" },
  },
  config = function(_, opts)
    require("guess-indent").setup(opts)

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "xquery",
      callback = function()
        vim.opt_local.foldmethod = "indent"
        vim.opt_local.foldlevel = 0
        vim.cmd("GuessIndent")
      end,
    })
  end,
}
