return {
  "rebelot/heirline.nvim",
  config = function(_, opts)
    local conditions = require("heirline.conditions")
    local utils = require("heirline.utils")

    -- Helper function to parse JDT URIs (for Maven dependency files)
    local function parse_jdt_uri(uri)
      if not uri or not uri:match("^jdt://") then
        return nil
      end

      local result = {}

      -- Extract filename from the path portion (before the ?)
      -- Format: jdt://contents/jar-name.jar/package/ClassName.class?...
      local path_part = uri:match("^jdt://contents/[^/]+/[^/]+/([^?]+)")
      if path_part then
        result.filename = path_part
      end

      -- Extract maven coordinates from query string
      -- Format: ...=/maven.groupId=/org.cas.seti=/=/maven.artifactId=/models=/...
      local group_id = uri:match("maven%.groupId=/([^/=]+)")
      local artifact_id = uri:match("maven%.artifactId=/([^/=]+)")

      if group_id then
        result.group_id = group_id
      end
      if artifact_id then
        result.artifact_id = artifact_id
      end

      return result
    end

    -- Format a parsed JDT result for display
    local function format_jdt_display(parsed)
      if not parsed then
        return nil
      end

      local display = parsed.filename or "[Unknown]"

      if parsed.group_id and parsed.artifact_id then
        display = display .. " [" .. parsed.group_id .. ":" .. parsed.artifact_id .. "]"
      elseif parsed.artifact_id then
        display = display .. " [" .. parsed.artifact_id .. "]"
      end

      return display
    end

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
          -- Check if this is a JDT URI (Maven dependency)
          local jdt_parsed = parse_jdt_uri(bufname)
          if jdt_parsed then
            display = format_jdt_display(jdt_parsed)
            icon = " "  -- Java icon for dependency files
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

    -- Setup colors from everforest
    local colors = {
      bg0 = utils.get_highlight("Normal").bg or "#FDF6E3",
      fg = utils.get_highlight("Normal").fg,
      green = utils.get_highlight("String").fg,
      yellow = utils.get_highlight("Number").fg,
      red = utils.get_highlight("Error").fg,
      blue = utils.get_highlight("Function").fg,
      gray = utils.get_highlight("Comment").fg,
      orange = utils.get_highlight("Constant").fg,
      halfway_green = 12634221, 
      halfway_yellow = 15306129,
      halfway_red = 16163477,
      halfway_blue = 12634221,
      halfway_gray = 12826485,
      halfway_orange = 9751466
    }

    -- Vim Mode component with color blocks
    local ViMode = {
      init = function(self)
        self.mode = vim.fn.mode(1)
      end,
      static = {
        mode_names = {
          n = "NORMAL",
          no = "NORMAL",
          nov = "NORMAL",
          noV = "NORMAL",
          ["no\22"] = "NORMAL",
          niI = "NORMAL",
          niR = "NORMAL",
          niV = "NORMAL",
          nt = "NORMAL",
          v = "VISUAL",
          vs = "VISUAL",
          V = "VISUAL",
          Vs = "VISUAL",
          ["\22"] = "VISUAL",
          ["\22s"] = "VISUAL",
          s = "SELECT",
          S = "SELECT",
          ["\19"] = "SELECT",
          i = "INSERT",
          ic = "INSERT",
          ix = "INSERT",
          R = "REPLACE",
          Rc = "REPLACE",
          Rx = "REPLACE",
          Rv = "REPLACE",
          Rvc = "REPLACE",
          Rvx = "REPLACE",
          c = "COMMAND",
          cv = "COMMAND",
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
      -- the name of the mode
      {
        provider = function(self)
          return "  " .. self.mode_names[self.mode]
        end,
        hl = function(self)
          local mode = self.mode:sub(1, 1)
          return { fg = "bg0", bg = self.mode_colors[mode], bold = true, italic = false }
        end,
      },
      -- the first diaognal between full color and halfway color
      {
        provider = function(self)
          return ""
        end,
        hl = function(self)
          local mode = self.mode:sub(1, 1)
          return { fg = self.mode_colors[mode], bg = "halfway_" .. self.mode_colors[mode], bold = true, italic = false }
        end,
      },
      -- the second diaognal, between halfway color and full color
      {
        provider = function(self)
          return ""
        end,
        hl = function(self)
          local mode = self.mode:sub(1, 1)
          return { fg = "halfway_" .. self.mode_colors[mode], bold = true, italic = false }
        end,
      },
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
        -- Parse JDT URI if applicable
        self.jdt_parsed = parse_jdt_uri(self.filename)
      end,
      {
        provider = function(self)
          -- Handle JDT URIs (Maven dependencies)
          if self.jdt_parsed then
            return format_jdt_display(self.jdt_parsed) .. " "
          end

          -- Normal file handling
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
