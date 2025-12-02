return {
  "sindrets/diffview.nvim",
  opts = {
    view = {
      merge_tool = {
        layout = "diff3_mixed"
      }
    },
    hooks = {
      diff_buf_read = function(bufnr, ctx)
        -- Change local options in diff buffers

        -- print("symbol:", ctx.symbol)
        -- print("layout_name:", ctx.layout_name)

        -- Here, I'm targeting the editing window for git diffs
        if ctx.symbol == "b" and ctx.layout_name == "diff3_mixed" then
          vim.opt_local.wrap = true
        else
          vim.opt_local.wrap = false
        end
          end,
    }
  },
  keys = {
    {
      "<leader>do",
      function()
        require("diffview").open({})
      end,
      desc = "Diffview Open"
    },
    {
      "<leader>dq",
      function()
        require("diffview").close()
      end,
      desc = "Diffview Close"
    },
    {
      "<leader>df",
      function()
        vim.cmd('DiffviewFileHistory %')
      end,
      desc = "Diffview file history"
    },
    {
      "<leader>db",
      function()
        vim.cmd('DiffviewFileHistory')
      end,
      desc = "Diffview branch history"
    },
  }
}
