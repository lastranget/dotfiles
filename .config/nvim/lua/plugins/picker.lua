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
        sidekick_send_context = function(picker)
          require("sidekick.cli.picker.snacks").action(
            require("sidekick.cli.picker")._send_cb({ kind = "position" })
          )(picker)
        end,
        -- Delete items from lists (harpoon, buffers, marks)
        list_delete = function(picker)
          local selected = picker:selected({ fallback = true })
          if #selected == 0 then return end

          local source = picker.opts.source or ""

          if source == "harpoon" then
            local harpoon = require("harpoon")
            local list = harpoon:list()
            local to_remove = {}
            for _, item in ipairs(selected) do
              to_remove[item.file] = true
            end
            for i = list._length, 1, -1 do
              if list.items[i] and to_remove[list.items[i].value] then
                list:remove_at(i)
              end
            end
            picker:refresh()
          elseif source == "buffers" then
            picker.preview:reset()
            for _, item in ipairs(selected) do
              if item.buf then
                Snacks.bufdelete.delete(item.buf)
              end
            end
            picker:refresh()
          elseif source == "marks" then
            for _, item in ipairs(selected) do
              if item.label then
                if item.buf then
                  vim.api.nvim_buf_del_mark(item.buf, item.label)
                else
                  vim.api.nvim_del_mark(item.label)
                end
              end
            end
            picker:refresh()
          else
            Snacks.notify.warn("Delete not supported for this picker", { title = "Snacks Picker" })
          end
        end,
      },
      -- Add sidekick keybinding to picker input
      win = {
        input = {
          keys = {
            ["?"] = { "toggle_help_input", desc = "Help" },
            ["<C-x>"] = {
              "sidekick_send",
              mode = { "n", "i" },
            },
            ["<C-y>"] = {
              "sidekick_send_context",
              mode = { "n", "i" },
              desc = "Sidekick",
            },
            ["<Tab>"] = { "select_and_next", mode = { "i", "n" }, desc = "Select" },
            ["<C-a>"] = { "select_all", mode = { "n", "i" }, desc = "All" },
            ["<C-d>"] = { "list_delete", mode = { "n", "i" }, desc = "Del" },
            ["<C-v>"] = { "edit_vsplit", mode = { "i", "n" }, desc = "VS" },
          },
          footer = {
            { " ", "SnacksFooter" },
            { "?", "SnacksFooterKey" },
            { " Help ", "SnacksFooterDesc" },
            { "<C-y>", "SnacksFooterKey" },
            { " Sidekick ", "SnacksFooterDesc" },
            { "<Tab>", "SnacksFooterKey" },
            { " Sel ", "SnacksFooterDesc" },
            { "<C-a>", "SnacksFooterKey" },
            { " All ", "SnacksFooterDesc" },
            { "<C-d>", "SnacksFooterKey" },
            { " Del ", "SnacksFooterDesc" },
            { "<C-v>", "SnacksFooterKey" },
            { " VS ", "SnacksFooterDesc" },
            { " ", "SnacksFooter" },
          },
        },
        list = {
          keys = {
            ["?"] = { "toggle_help_list", desc = "Help" },
            ["<C-y>"] = {
              "sidekick_send_context",
              mode = { "n" },
              desc = "Sidekick",
            },
            ["<Tab>"] = { "select_and_next", mode = { "n", "x" }, desc = "Select" },
            ["<C-a>"] = { "select_all", desc = "All" },
            ["<C-d>"] = { "list_delete", desc = "Del" },
            ["<C-v>"] = { "edit_vsplit", desc = "VS" },
          },
          footer = {
            { " ", "SnacksFooter" },
            { "?", "SnacksFooterKey" },
            { " Help ", "SnacksFooterDesc" },
            { "<C-y>", "SnacksFooterKey" },
            { " Sidekick ", "SnacksFooterDesc" },
            { "<Tab>", "SnacksFooterKey" },
            { " Sel ", "SnacksFooterDesc" },
            { "<C-a>", "SnacksFooterKey" },
            { " All ", "SnacksFooterDesc" },
            { "<C-d>", "SnacksFooterKey" },
            { " Del ", "SnacksFooterDesc" },
            { "<C-v>", "SnacksFooterKey" },
            { " VS ", "SnacksFooterDesc" },
            { " ", "SnacksFooter" },
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
