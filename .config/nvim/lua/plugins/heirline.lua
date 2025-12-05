return {
  "rebelot/heirline.nvim",
  config = function(_, opts)
    local conditions = require("heirline.conditions")
    local utils = require("heirline.utils")

    -- TabLine: TabList Component
    local Tabpage = {
      provider = function(self)
        -- Get all windows in this tabpage
        local wins = vim.api.nvim_tabpage_list_wins(self.tabpage)

        -- Get unique buffers from those windows (excluding floating windows)
        local buffers = {}
        local buf_set = {}
        for _, win in ipairs(wins) do
          -- Skip floating windows
          local win_config = vim.api.nvim_win_get_config(win)
          if win_config.relative == "" then
            local buf = vim.api.nvim_win_get_buf(win)
            if not buf_set[buf] then
              buf_set[buf] = true
              table.insert(buffers, buf)
            end
          end
        end

        -- Get icon and display text
        local icon = ""
        local display
        local has_devicons, devicons = pcall(require, "nvim-web-devicons")

        -- Get the active buffer in this tabpage
        local active_win = vim.api.nvim_tabpage_get_win(self.tabpage)
        local active_buf = vim.api.nvim_win_get_buf(active_win)
        local bufname = vim.api.nvim_buf_get_name(active_buf)

        if bufname == "" then
          display = "[No Name]"
          icon = "󰈤 "
        else
          local filename = vim.fn.fnamemodify(bufname, ":t")
          local extension = vim.fn.fnamemodify(bufname, ":e")
          display = filename

          -- Get file icon
          if has_devicons then
            local file_icon = devicons.get_icon(filename, extension, { default = true })
            if file_icon then
              icon = file_icon .. " "
            end
          end
        end

        -- Use multi-buffer icon if there are multiple buffers
        if #buffers > 1 then
          icon = "󰓩 "
        end

        return " " .. self.tabnr .. " " .. icon .. display .. " "
      end,
      hl = function(self)
        if not self.is_active then
          return "TabLine"
        else
          return "TabLineSel"
        end
      end,
    }

    -- Separator between tabs (not after the last tab)
    local TabSeparator = {
      condition = function(self)
        return self.tabnr ~= #vim.api.nvim_list_tabpages()
      end,
      provider = "│",
      hl = "TabLine",
    }

    local TabPages = {
      condition = function()
        return #vim.api.nvim_list_tabpages() >= 2
      end,
      utils.make_tablist({ Tabpage, TabSeparator }),
    }

    local TabLine = { TabPages }

    require("heirline").setup({
      tabline = TabLine,
    })

    vim.o.showtabline = 2
  end
}
