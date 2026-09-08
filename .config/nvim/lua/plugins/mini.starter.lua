return {
  "nvim-mini/mini.starter",
  version = "*",
  lazy = false,
  priority = 900, -- load after colorscheme (1000) but before most plugins
  keys = {
    { "<leader>l", function() require("mini.starter").open() end, desc = "Open starter dashboard" },
  },
  config = function()
    local starter = require("mini.starter")

    local logo = table.concat({
      [[███▄▄▄▄      ▄████████  ▄██████▄   ▄█    █▄   ▄█    ▄▄▄▄███▄▄▄▄   ]],
      [[███▀▀▀██▄   ███    ███ ███    ███ ███    ███ ███  ▄██▀▀▀███▀▀▀██▄ ]],
      [[███   ███   ███    ▀█  ███    ███ ███    ███ ███▌ ███   ███   ███ ]],
      [[███   ███  ▄███▄▄▄     ███    ███ ███    ███ ███▌ ███   ███   ███ ]],
      [[███   ███ ▀▀███▀▀▀     ███    ███ ███    ███ ███▌ ███   ███   ███ ]],
      [[███   ███   ███    █▄  ███    ███ ███    ███ ███  ███   ███   ███ ]],
      [[███   ███   ███    ███ ███    ███ ███    ███ ███  ███   ███   ███ ]],
      [[ ▀█   █▀    ██████████  ▀██████▀   ▀██████▀  █▀    ▀█   ███   █▀  ]],
    }, "\n")

    local function greeting()
      local hour = tonumber(os.date("%H"))
      local msg
      if hour >= 5 and hour < 12 then
        msg = "Good morning, Tom"
      elseif hour >= 12 and hour < 17 then
        msg = "Good afternoon, Tom"
      elseif hour >= 17 and hour < 21 then
        msg = "Good evening, Tom"
      else
        msg = "Good night, Tom"
      end
      return logo .. "\n\n" .. msg
    end

    -- Like gen_hook.aligning("center", "center"), but keeps a left margin
    -- proportional to the window width even when the content is too wide to
    -- center (e.g. in a narrow/split pane), so it never jams against the edge.
    local function aligning_with_margin(min_coef)
      return function(content, buf_id)
        local win_id = vim.fn.bufwinid(buf_id)
        if win_id < 0 then return end

        local win_width = vim.api.nvim_win_get_width(win_id)
        local win_height = vim.api.nvim_win_get_height(win_id)

        local line_strings = starter.content_to_lines(content)
        local lines_width = vim.tbl_map(function(l) return vim.fn.strdisplaywidth(l) end, line_strings)
        local content_width = math.max(unpack(lines_width))

        local center_pad = math.floor(0.5 * (win_width - content_width))
        local min_pad = math.floor(min_coef * win_width)
        local left_pad = math.max(center_pad, min_pad, 0)

        local top_pad = math.max(math.floor(0.5 * (win_height - #line_strings)), 0)

        return starter.gen_hook.padding(left_pad, top_pad)(content)
      end
    end

    starter.setup({
      header = greeting,
      items = {
        { name = "Markdown",      action = "enew | setfiletype markdown", section = "Scratch" },

        { name = "Open Vault",    action = "lua pcall(require, 'obsidian'); vim.cmd.edit(vim.fn.fnameescape(vim.fn.expand('~/vaults/Main/mocs/home moc.md'))); vim.cmd('Obsidian quick_switch')", section = "Obsidian" },
        { name = "Tasks MOC",     action = "edit ~/vaults/Main/mocs/tasks\\ moc.md", section = "Obsidian" },
        { name = "Work Tasks",    action = "edit ~/vaults/Main/mocs/work\\ tasks.md", section = "Obsidian" },
        { name = "Search Notes",  action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian search')", section = "Obsidian" },
        { name = "New Note",      action = "lua pcall(require, 'obsidian'); vim.cmd('ObsNew')", section = "Obsidian" },
        { name = "Today's Note",  action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian today')", section = "Obsidian" },

        starter.sections.recent_files(5, false),

        { name = "Lazy",          action = "Lazy",                                   section = "Config" },
        { name = "Mason",         action = "Mason",                                  section = "Config" },
        { name = "Quit",          action = "qa",                                     section = "Config" },
      },
      footer = "",
      content_hooks = {
        starter.gen_hook.adding_bullet("  ▸ "),
        aligning_with_margin(0.15),
      },
    })
  end,
}
