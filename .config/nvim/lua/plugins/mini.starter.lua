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
        { name = "Harpoon",       action = "lua local h = require('harpoon'); h.ui:toggle_quick_menu(h:list())", section = "Navigate" },

        { name = "Markdown",      action = "enew | setfiletype markdown", section = "Scratch" },

        { name = "Switch Worktree", action = "lua require('worktree').pick()",   section = "Worktree" },
        { name = "Create Worktree", action = "lua require('worktree').create()", section = "Worktree" },

        { name = "Open Vault",    action = "lua pcall(require, 'obsidian'); vim.cmd('edit ~/vaults/Main/views/home.md'); vim.cmd('Obsidian quick_switch')", section = "Obsidian" },
        { name = "Tasks MOC",     action = "edit ~/vaults/Main/views/tasks\\ moc.md", section = "Obsidian" },
        { name = "Work Tasks MOC", action = "edit ~/vaults/Main/views/work\\ tasks\\ moc.md", section = "Obsidian" },
        { name = "Search Notes",  action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian search')", section = "Obsidian" },
        { name = "New Note",      action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian new_from_template')", section = "Obsidian" },
        { name = "Today's Note",  action = "lua pcall(require, 'obsidian'); vim.cmd('Obsidian today')", section = "Obsidian" },

        { name = "Claude",        action = "lua require('sidekick.cli').toggle({ name = 'claude', focus = true })",  section = "AI Sidekick" },
        { name = "Gemini",        action = "lua require('sidekick.cli').toggle({ name = 'gemini', focus = true })",  section = "AI Sidekick" },
        { name = "Neovim",        action = "lua require('sidekick.cli').toggle({ name = 'neovim', focus = true })", section = "AI Sidekick" },

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
