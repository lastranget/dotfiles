-- plugins/picker.lua
return {
  "folke/snacks.nvim",
  lazy = false, -- Load immediately so sidekick can use picker for its menus
  opts = {
    picker = {
      -- Sidekick integration actions
      actions = {
        sidekick_send = function(...)
          return require("sidekick.cli.picker.snacks").send(...)
        end,
      },
      -- Add sidekick keybinding to picker input
      win = {
        input = {
          keys = {
            ["<C-x>"] = {
              "sidekick_send",
              mode = { "n", "i" },
            },
          },
        },
      },
    },
  },
  keys = {
    {
      "<leader>fl",
      function()
        require("snacks").picker.resume()
      end,
      desc = "Picker resume last search",
    },
    {
      "<leader>fr",
      function()
        require("snacks").picker.lsp_references()
      end,
      desc = "Picker find lsp references",
      noremap = true,
      silent = true
    },
    {
      "<leader>ff",
      function()
        require("snacks").picker.files()
      end,
      desc = "Picker find files",
    },
    {
      "<leader>fg",
      function()
        require("snacks").picker.grep()
      end,
      desc = "Picker live grep",
    },
    {
      "<leader>ft",
      function()
        require("snacks").picker.grep({ search = vim.fn.expand("<cword>") })
      end,
      desc = "Picker grep word under cursor",
    },
    {
      "<leader>fb",
      function()
        require("snacks").picker.buffers()
      end,
      desc = "Picker buffers",
    },
    {
      "<leader>fa",
      function()
        require("snacks").picker.help()
      end,
      desc = "Picker help tags",
    },
  },
}
