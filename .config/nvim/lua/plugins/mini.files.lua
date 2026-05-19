return {
  'nvim-mini/mini.files',
  version = '*',
  opts = {
    windows = {
      preview = true
    },
    -- this is llm output that didn't quite work
    -- hooks = {
    --   post_open = function(buf_id, win_id, path)
    --     vim.api.nvim_set_option_value('number', true, { win = win_id })
    --     vim.api.nvim_set_option_value('relativenumber', true, { win = win_id })
    --   end,
    -- },

  },
  keys = {
    { -- from https://www.reddit.com/r/neovim/comments/1fzfiex/open_minifiles_on_current_directory_focused_on/
      "<leader>mm",
      function()
        local MiniFiles = require("mini.files")
        local buf_name = vim.api.nvim_buf_get_name(0)
        local stat = vim.uv.fs_stat(buf_name)
        local is_valid = buf_name ~= "" and stat ~= nil
        if not MiniFiles.close() then
          if is_valid then
            MiniFiles.open(buf_name, false)
          else
            MiniFiles.open()
            vim.schedule(function() MiniFiles.reveal_cwd() end)
          end
        end
      end,
      desc = "Mini.files open here"
    },
    {
      "<leader>mo",
      function()
        require("mini.files").open("/home/txl25/vaults/Main")
      end,
      desc = "Mini.files open Obsidian"
    },
    {
      "<leader>mr",
      function()
        require("mini.files").open()
      end,
      desc = "Mini.files open root"
    }
  },
  config = function(_, opts)
        require('mini.files').setup(opts)
  end,
}
