return {
  {
    "FabijanZulj/blame.nvim",
    lazy = true,
    opts = {
      blame_options = { '-w' },
    },
    keys= {
      {
        "<leader>tB",
        function()
          vim.cmd('BlameToggle window')
        end,
        desc = "Toggle blame sidebar",
      },
    }
  },
}
