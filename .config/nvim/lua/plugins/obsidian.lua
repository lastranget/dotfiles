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

    -- Disable backup files when editing vault files to prevent sync conflicts
    callbacks = {
      ---@param note obsidian.Note
      enter_note = function(note)
        vim.opt_local.backup = false
        vim.opt_local.writebackup = false
        vim.opt_local.swapfile = false

        -- Add fold settings
        vim.opt_local.foldmethod = "expr"
        vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.opt.foldlevelstart = 99
        vim.opt.foldtext = "" -- can look into nvim-ufo if we want more complicated rendering that preserves syntax highlighting
        vim.cmd('normal! zx')
      end,
    },

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
    notes_subdir="work/fleeting",
    new_notes_location = "notes_subdir",

    -- Optional, customize how note IDs are generated given an optional title.
    ---@param title string|?
    ---@return string
    note_id_func = function(title)
      return title or tostring(os.time())  -- fallback if nil
    end,

    -- Optional, customize how note file names are generated given the ID, target directory, and title.
    ---@param spec { id: string, dir: obsidian.Path, title: string|? }
    ---@return string|obsidian.Path The full path to the new note.
    note_path_func = function(spec)
      local path = spec.dir / tostring(spec.id)
      return path:with_suffix(".md")
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
