return {
  "nvim-mini/mini.starter",
  version = "*",
  lazy = false,
  priority = 900, -- load after colorscheme (1000) but before most plugins
  config = function()
    local starter = require("mini.starter")

    local function greeting()
      local hour = tonumber(os.date("%H"))
      if hour >= 5 and hour < 12 then
        return "Good morning, Tom"
      elseif hour >= 12 and hour < 17 then
        return "Good afternoon, Tom"
      elseif hour >= 17 and hour < 21 then
        return "Good evening, Tom"
      else
        return "Good night, Tom"
      end
    end

    starter.setup({
      header = greeting,
      items = {
        { name = "Find File",     action = "lua require('snacks').picker.files()",   section = "Search" },
        { name = "Live Grep",     action = "lua require('snacks').picker.grep()",    section = "Search" },
        { name = "Buffers",       action = "lua require('snacks').picker.buffers()", section = "Search" },
        { name = "Help Tags",     action = "lua require('snacks').picker.help()",    section = "Search" },
        { name = "Resume Last",   action = "lua require('snacks').picker.resume()",  section = "Search" },

        { name = "Harpoon",       action = "lua local h = require('harpoon'); h.ui:toggle_quick_menu(h:list())", section = "Navigate" },
        { name = "File Explorer", action = "lua require('mini.files').open()",       section = "Navigate" },

        { name = "Markdown",      action = "enew | setfiletype markdown", section = "Scratch" },
        { name = "Python",        action = "enew | setfiletype python",   section = "Scratch" },
        { name = "TypeScript",    action = "enew | setfiletype typescript", section = "Scratch" },

        { name = "Open Vault",    action = "lua pcall(require, 'obsidian'); vim.cmd('edit ~/vaults/Main/views/home.md'); vim.cmd('Obsidian quick_switch')", section = "Obsidian" },
        { name = "Search Notes",  action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian search')", section = "Obsidian" },
        { name = "New Note",      action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian new_from_template')", section = "Obsidian" },
        { name = "Today's Note",  action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian today')", section = "Obsidian" },

        { name = "Claude",        action = "lua require('sidekick.cli').toggle({ name = 'claude', focus = true })",  section = "AI Sidekick" },
        { name = "Gemini",        action = "lua require('sidekick.cli').toggle({ name = 'gemini', focus = true })",  section = "AI Sidekick" },
        { name = "Cascade",       action = "lua require('sidekick.cli').toggle({ name = 'cascade', focus = true })", section = "AI Sidekick" },

        { name = "Diffview",       action = "lua require('diffview').open({})",      section = "Git" },
        { name = "Branch History",  action = "DiffviewFileHistory",                  section = "Git" },

        starter.sections.recent_files(5, false),

        { name = "Lazy",          action = "Lazy",                                   section = "Config" },
        { name = "Mason",         action = "Mason",                                  section = "Config" },
        { name = "Quit",          action = "qa",                                     section = "Config" },
      },
      footer = "",
      content_hooks = {
        starter.gen_hook.adding_bullet("  ▸ "),
        starter.gen_hook.aligning("center", "center"),
      },
    })
  end,
}
