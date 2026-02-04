return {
  "sindrets/diffview.nvim",
  lazy = false,
  opts = {
    file_panel = {
      win_config = {
        position = "left",
        width = 65,
        win_opts = {}
      }
    },
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
      "<leader>co",
      function()
        require("diffview").open({})
      end,
      desc = "Diffview Open"
    },
    {
      "<leader>cq",
      function()
        require("diffview").close()
        vim.env.GIT_DIR = nil
        vim.env.GIT_WORK_TREE = nil
      end,
      desc = "Diffview Close (clear git env)"
    },
    {
      "<leader>cf",
      function()
        vim.cmd('DiffviewFileHistory %')
      end,
      desc = "Diffview file history"
    },
    {
      "<leader>cb",
      function()
        vim.cmd('DiffviewFileHistory')
      end,
      desc = "Diffview branch history"
    },
    {
      "<leader>cc",
      function()
        local git_dir = vim.fn.expand('$HOME') .. '/.cfg'
        local work_tree = vim.fn.expand('$HOME')
        vim.env.GIT_DIR = git_dir
        vim.env.GIT_WORK_TREE = work_tree
        require("diffview").open({})
      end,
      desc = "Diffview Open Dotfiles"
    },
  }
}
