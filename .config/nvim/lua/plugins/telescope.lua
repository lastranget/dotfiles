-- plugins/telescope.lua
return {
  'nvim-telescope/telescope.nvim',
  tag = '0.1.8',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local telescope = require("telescope")

    telescope.setup({
      defaults = {},
      pickers = {
        find_files = {
          attach_mappings = function(prompt_bufnr, map)
            map("i", "<C-p>", function()
              local entry = action_state.get_selected_entry()
              local path = entry.path or entry.filename
              actions.close(prompt_bufnr) -- Close Telescope first
              vim.schedule(function()
                if path then
                  vim.api.nvim_put({ path }, "c", true, true)
                end
              end)
            end)
            return true
          end,
        },
      },
    })
  end,
  keys = {
    {
      "<leader>fr",
      function()
        require("telescope.builtin").lsp_references()
      end,
      desc = "Telescope find lsp references",
      noremap = true,
      silent = true
    },
    {
      "<leader>ff",
      function()
        require("telescope.builtin").find_files()
      end,
      desc = "Telescope find files",
    },
    {
      "<leader>fg",
      function()
        require("telescope.builtin").live_grep()
      end,
      desc = "Telescope live grep",
    },
    {
      "<leader>fb",
      function()
        require("telescope.builtin").buffers()
      end,
      desc = "Telescope buffers",
    },
    {
      "<leader>fa",
      function()
        require("telescope.builtin").help_tags()
      end,
      desc = "Telescope help_tags",
    },
  },
}
