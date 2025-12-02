return {
  'sainnhe/everforest',
  lazy = false,
  priority = 1000,
  init = function()
    -- Set options BEFORE plugin loads
    vim.g.everforest_enable_italic = true
    vim.g.everforest_background = 'medium'
    vim.o.background = 'light'
  end,
  config = function()
    -- Load colorscheme AFTER options are set
    vim.cmd.colorscheme('everforest')
  end
}
