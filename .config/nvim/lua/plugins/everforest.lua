return {
  'sainnhe/everforest',
  lazy = false,
  priority = 1000,
  init = function()
    -- Set options BEFORE plugin loads
    vim.g.everforest_enable_italic = true
    vim.g.everforest_background = 'medium'
    vim.g.everforest_transparent_background = 0
    vim.o.background = 'light'
    vim.o.termguicolors = true

  end,
  config = function()
    -- Load colorscheme AFTER options are set
    vim.cmd.colorscheme('everforest')
  end
}
