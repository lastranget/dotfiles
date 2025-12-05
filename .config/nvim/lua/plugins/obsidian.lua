return {
  "obsidian-nvim/obsidian.nvim",
  version = "*", -- recommended, use latest release instead of latest commit
  ft = "markdown",
  -- event = {
--    -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
--    -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
--    -- refer to `:h file-pattern` for more examples
--    "BufReadPre ~/vaults/Main/*.md",
--    "BufNewFile ~/vaults/Main/*.md",
--  },
  ---@module 'obsidian'
  ---@type obsidian.config

  dependencies = {
    'nvim-telescope/telescope.nvim',
    'nvim-treesitter/nvim-treesitter',
    'saghen/blink.cmp',
  },

  opts = {
    ui = { enable = false }, -- use render-markdown instead
    workspaces = {
      {
        name = "Main",
        path = "~/vaults/Main",
      },
    },
    completion = { blink = true },
    legacy_commands = false,
    templates = {
      folder = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
      -- A map for custom variables, the key should be the variable and the value a function
      substitutions = {},
    },
    notes_subdir="fleeting",
    new_notes_location = "notes_subdir",

    -- Optional, customize how note IDs are generated given an optional title.
    ---@param title string|?
    ---@return string
    note_id_func = function(title)
      -- Create note IDs in a Zettelkasten format with a timestamp and a suffix.
      -- In this case a note with the title 'My new note' will be given an ID that looks
      -- like '1657296016-my-new-note', and therefore the file name '1657296016-my-new-note.md'.
      -- You may have as many periods in the note ID as you'd like—the ".md" will be added automatically
      return title
    end,

    -- Optional, customize how note file names are generated given the ID, target directory, and title.
    ---@param spec { id: string, dir: obsidian.Path, title: string|? }
    ---@return string|obsidian.Path The full path to the new note.
    note_path_func = function(spec)
      -- This is equivalent to the default behavior.
      local path = spec.dir / tostring(spec.title)
      return path:with_suffix ".md"
    end,

    ---This was set to allow obsidian to be open in the background for obsidian sync.
    ---It likely makes not_id_func do nothing
    frontmatter = {
      enabled = false
    },

  ---Order of checkbox state chars, e.g. { " ", "x" }
  ---@field order? string[]
  checkbox = {
    order = { " ", "x" },
  },

    -- see below for full list of options 👇
  },

}
