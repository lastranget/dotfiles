return {
  "rebelot/heirline.nvim",
  config = function(_, opts)
    local conditions = require("heirline.conditions")
    local utils = require("heirline.utils")

    -- TabLine: TabList Component
    local Tabpage = {
      init = function(self)
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

        -- Store for children to use
        self.icon = icon
        self.display = display
      end,
      hl = function(self)
        if not self.is_active then
          return "TabLine"
        else
          return "TabLineSel"
        end
      end,
      -- Tab number
      { provider = function(self) return " " .. self.tabnr .. " " end },
      -- Icon
      { provider = function(self) return self.icon end },
      -- Filename (italicized only when active)
      {
        provider = function(self) return self.display .. " " end,
        hl = function(self)
          if self.is_active then
            return { italic = true }
          end
        end,
      },
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

    -- StatusLine: Cool minimal design with everforest colors

    -- Setup colors from everforest
    local colors = {
      bg0 = utils.get_highlight("Normal").bg,
      fg = utils.get_highlight("Normal").fg,
      green = utils.get_highlight("String").fg,
      yellow = utils.get_highlight("Number").fg,
      red = utils.get_highlight("Error").fg,
      blue = utils.get_highlight("Function").fg,
      gray = utils.get_highlight("Comment").fg,
      orange = utils.get_highlight("Constant").fg,
    }

    -- Vim Mode component with color blocks
    local ViMode = {
      init = function(self)
        self.mode = vim.fn.mode(1)
      end,
      static = {
        mode_names = {
          n = "N",
          no = "N",
          nov = "N",
          noV = "N",
          ["no\22"] = "N",
          niI = "N",
          niR = "N",
          niV = "N",
          nt = "N",
          v = "V",
          vs = "V",
          V = "V",
          Vs = "V",
          ["\22"] = "V",
          ["\22s"] = "V",
          s = "S",
          S = "S",
          ["\19"] = "S",
          i = "I",
          ic = "I",
          ix = "I",
          R = "R",
          Rc = "R",
          Rx = "R",
          Rv = "R",
          Rvc = "R",
          Rvx = "R",
          c = "C",
          cv = "C",
          r = ".",
          rm = "M",
          ["r?"] = "?",
          ["!"] = "!",
          t = "T",
        },
        mode_colors = {
          n = "green",
          i = "yellow",
          v = "red",
          V = "red",
          ["\22"] = "red",
          c = "blue",
          s = "orange",
          S = "orange",
          ["\19"] = "orange",
          R = "orange",
          r = "orange",
          ["!"] = "red",
          t = "green",
        },
      },
      provider = function(self)
        return " " .. self.mode_names[self.mode] .. " "
      end,
      hl = function(self)
        local mode = self.mode:sub(1, 1)
        return { fg = "bg0", bg = self.mode_colors[mode], bold = true, italic = false }
      end,
      update = {
        "ModeChanged",
        pattern = "*:*",
        callback = vim.schedule_wrap(function()
          vim.cmd("redrawstatus")
        end),
      },
    }

    -- Git branch and changes
    local Git = {
      condition = conditions.is_git_repo,
      init = function(self)
        self.status_dict = vim.b.gitsigns_status_dict
      end,
      {
        provider = function(self)
          return "  " .. self.status_dict.head .. " "
        end,
        hl = { fg = "blue", bold = true },
      },
      {
        condition = function(self)
          return self.status_dict.added and self.status_dict.added > 0
        end,
        provider = function(self)
          return "+" .. self.status_dict.added .. " "
        end,
        hl = { fg = "green" },
      },
      {
        condition = function(self)
          return self.status_dict.changed and self.status_dict.changed > 0
        end,
        provider = function(self)
          return "~" .. self.status_dict.changed .. " "
        end,
        hl = { fg = "yellow" },
      },
      {
        condition = function(self)
          return self.status_dict.removed and self.status_dict.removed > 0
        end,
        provider = function(self)
          return "-" .. self.status_dict.removed .. " "
        end,
        hl = { fg = "red" },
      },
    }

    -- Filename with modified indicator
    local FileName = {
      init = function(self)
        self.filename = vim.api.nvim_buf_get_name(0)
      end,
      {
        provider = function(self)
          local filename = vim.fn.fnamemodify(self.filename, ":t")
          if filename == "" then
            return "[No Name] "
          end
          return filename .. " "
        end,
        hl = { fg = "fg", bold = true },
      },
      {
        condition = function()
          return vim.bo.modified
        end,
        provider = "[+] ",
        hl = { fg = "yellow", bold = true },
      },
    }

    -- LSP Active indicator
    local LSPActive = {
      condition = conditions.lsp_attached,
      update = { "LspAttach", "LspDetach" },
      provider = " LSP ",
      hl = { fg = "green", bold = true },
    }

    -- Diagnostics
    local Diagnostics = {
      condition = conditions.has_diagnostics,
      static = {
        error_icon = " ",
        warn_icon = " ",
        info_icon = " ",
        hint_icon = " ",
      },
      init = function(self)
        self.errors = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
        self.warnings = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
        self.hints = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.HINT })
        self.info = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.INFO })
      end,
      update = { "DiagnosticChanged", "BufEnter" },
      {
        condition = function(self)
          return self.errors > 0
        end,
        provider = function(self)
          return self.error_icon .. self.errors .. " "
        end,
        hl = { fg = "red" },
      },
      {
        condition = function(self)
          return self.warnings > 0
        end,
        provider = function(self)
          return self.warn_icon .. self.warnings .. " "
        end,
        hl = { fg = "yellow" },
      },
    }

    -- File position
    local FilePosition = {
      provider = " %l:%c ",
      hl = { fg = "fg" },
    }

    -- File progress
    local FileProgress = {
      provider = " %P ",
      hl = { fg = "gray" },
    }

    -- Spacer to push right-aligned content
    local Spacer = { provider = "%=" }

    -- Small spacer
    local Space = { provider = " " }

    -- Assemble statusline
    local StatusLine = {
      ViMode,
      Space,
      Git,
      FileName,
      Spacer,
      LSPActive,
      Diagnostics,
      FilePosition,
      FileProgress,
    }

    require("heirline").setup({
      statusline = StatusLine,
      tabline = TabLine,
      opts = {
        colors = colors,
      },
    })

    vim.o.showtabline = 1  -- Only show tabline when there are 2+ tabs
  end
}
