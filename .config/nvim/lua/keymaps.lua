-- Set space as leader
--
local map = vim.api.nvim_set_keymap
local silent = { silent = true, noremap = true }
map("", "<Space>", "<Nop>", silent)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.softtabstop = 2

vim.wo.number = false
vim.wo.relativenumber = true
-- fold settings
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 1
vim.opt.foldnestmax = 9 -- this is subjective, so we might want to change it
vim.opt.foldcolumn = "4"

vim.g.markdown_folding = 1
vim.opt.foldtext = "" -- can look into nvim-ufo if we want more complicated rendering that preserves syntax highlighting

-- Python-specific fold settings
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.opt_local.foldlevelstart = 0
  end,
})

-- harpoon and mini.files relative line numbers
vim.api.nvim_create_autocmd("FileType", {
  pattern = "mini-files",
  callback = function()
    vim.wo.relativenumber = true
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "harpoon",
  callback = function()
    vim.wo.relativenumber = true
  end,
})
-- Add open obsidian anywhere command
vim.keymap.set('n', "<leader>oo", function()
  vim.cmd('edit ~/vaults/Main/views/home.md')
  vim.cmd('Obsidian quick_switch')
end, { desc = "Open obsidian home (from anywhere)" })

vim.keymap.set('n', "<leader>os", function()
  vim.cmd('split ~/vaults/Main/views/home.md')
  vim.cmd('Obsidian quick_switch')
end, { desc = "split obsidian home (from anywhere)" })

vim.keymap.set('n', "<leader>ov", function()
  vim.cmd('vsplit ~/vaults/Main/views/home.md')
  vim.cmd('Obsidian quick_switch')
end, { desc = "vsplit obsidian home (from anywhere)" })

-- Add yank filepath command
vim.keymap.set('n', '<leader>yp', function()
  -- Get the last used register (default to unnamed if none)
  local reg = vim.v.register
  local full_path = vim.fn.expand('%:p')
  vim.fn.setreg(reg, full_path)
  vim.fn.setreg("p", full_path)
  print('Full path copied to register "' .. reg .. '": ' .. full_path)
end, { desc = 'Copy full file path to last used register (and p)' })

-- Add tab split command

vim.keymap.set('n', '<leader>z', function()
  vim.cmd('tab split')
end, { desc = "tab split (pseudo full screen)" })

-- Add quick tabbing
local feedkeys = function(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'n', true)
end

vim.keymap.set('n', '<leader>1', function()
  feedkeys('1gt')
end, { desc = "Go to tab 1" })

vim.keymap.set('n', '<leader>2', function()
  feedkeys('2gt')
end, { desc = "Go to tab 2" })

vim.keymap.set('n', '<leader>3', function()
  feedkeys('3gt')
end, { desc = "Go to tab 3" })

vim.keymap.set('n', '<leader>4', function()
  feedkeys('4gt')
end, { desc = "Go to tab 4" })

vim.keymap.set('n', '<leader>5', function()
  feedkeys('5gt')
end, { desc = "Go to tab 5" })

vim.keymap.set('n', '<leader>6', function()
  feedkeys('6gt')
end, { desc = "Go to tab 6" })

vim.keymap.set('n', '<leader>7', function()
  feedkeys('7gt')
end, { desc = "Go to tab 7" })

vim.keymap.set('n', '<leader>8', function()
  feedkeys('8gt')
end, { desc = "Go to tab 8" })

vim.keymap.set('n', '<leader>9', function()
  feedkeys('9gt')
end, { desc = "Go to tab 9" })

vim.keymap.set('n', '<leader>0', function()
  vim.cmd('tablast')
end, { desc = "Go to last tab" })
-- Adding obsidian commands here for now to fix issue
vim.keymap.set("n", "<leader>tc", "<cmd>Obsidian toggle_checkbox<cr>", {
  desc = "Toggle checkbox",
})
vim.keymap.set("n", "<leader>oq", "<cmd>Obsidian quick_switch<cr>", {
  desc = "Obsidian quick switcher",
})
vim.keymap.set("n", "<leader>ob", "<cmd>Obsidian backlinks<cr>", {
  desc = "Obsidian backlinks",
})
vim.keymap.set("n", "<leader>og", "<cmd>Obsidian search<cr>", {
  desc = "Obsidian grep",
})
vim.keymap.set("n", "<leader>ot", "<cmd>Obsidian template<cr>", {
  desc = "Obsidian template",
})
vim.keymap.set("n", "<leader>ol", "<cmd>Obsidian links<cr>", {
  desc = "Obsidian links",
})
vim.keymap.set("n", "<leader>on", "<cmd>Obsidian new_from_template<cr>", {
  desc = "Obsidian new",
})
vim.keymap.set("n", "<leader>oh", "<cmd>Obsidian tags<cr>", {
  desc = "Obsidian new",
})
vim.keymap.set("n", "<Tab>", function () require("obsidian.api").nav_link("next") end, {
    desc = "Go to next link"
})
vim.keymap.set("n", "<S-Tab>", function () require("obsidian.api").nav_link("prev") end, {
    desc = "Go to previous link"
})

vim.keymap.set('n', '<leader>o#', function()
  local reg = vim.v.register
  local line = vim.api.nvim_get_current_line()

  -- Extract header text (strip leading #'s and whitespace)
  local header = line:match('^#+%s*(.+)$')

  if not header then
    vim.notify('Current line is not a markdown header', vim.log.levels.WARN)
    return
  end

  -- Get filename without extension
  local filename = vim.fn.expand('%:t:r')

  -- Build obsidian link
  local link = string.format('[[%s#%s|%s]]', filename, header, header)

  vim.fn.setreg(reg, link)
  vim.notify('Yanked: ' .. link)
end, { desc = 'Yank Obsidian header link' })

-- Adding an easy way to show diagnostic in a pop up window
vim.keymap.set("n", "<leader>tD", function () vim.diagnostic.open_float() end, {
  desc = "Toggle diagnostic pop-up window",
})

-- Add command to invoke repeatable functions
vim.keymap.set('n', '<C-q>', function()
  if _G.Repeatable.last_cmd then
    _G.Repeatable.last_cmd()
  else
    vim.notify('No command to repeat', vim.log.levels.WARN)
  end
end, { desc = 'Repeat last command' })

-- Send buffer to Windsurf Cascade via OSC 52
vim.keymap.set('n', '<leader>so', function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, "\n")
  if text == "" then
    vim.notify("Buffer is empty", vim.log.levels.WARN)
    return
  end
  local encoded = vim.base64.encode("::cascade::" .. text)
  
  -- Check if we're in a nested tmux (sidekick cascade tool sets these)
  local outer_tmux = vim.env.CASCADE_OUTER_TMUX
  local outer_pane = vim.env.CASCADE_OUTER_TMUX_PANE
  
  if outer_tmux and outer_tmux ~= '' then
    -- We're in nested tmux - use the outer tmux session to get the real TTY
    local socket = outer_tmux:match("^([^,]+)")  -- Extract socket path from TMUX var
    local pane_tty = vim.fn.system(
      string.format("tmux -S %s display-message -t %s -p '#{pane_tty}'", socket, outer_pane)
    ):gsub('%s+$', '')
    if pane_tty ~= '' then
      local osc = string.format('\027Ptmux;\027\027]52;c;%s\a\027\\', encoded)
      local cmd = string.format("printf '%%s' %s > %s", vim.fn.shellescape(osc), pane_tty)
      os.execute(cmd)
      vim.notify("Sent to Cascade (" .. #text .. " chars)", vim.log.levels.INFO)
    else
      vim.notify("Could not get outer tmux pane TTY", vim.log.levels.ERROR)
    end
  elseif vim.env.TMUX then
    -- Normal tmux (not nested) - get current pane's TTY
    local pane_tty = vim.fn.system("tmux display-message -p '#{pane_tty}'"):gsub('%s+$', '')
    if pane_tty ~= '' then
      local osc = string.format('\027Ptmux;\027\027]52;c;%s\a\027\\', encoded)
      local cmd = string.format("printf '%%s' %s > %s", vim.fn.shellescape(osc), pane_tty)
      os.execute(cmd)
      vim.notify("Sent to Cascade (" .. #text .. " chars)", vim.log.levels.INFO)
    else
      vim.notify("Could not get tmux pane TTY", vim.log.levels.ERROR)
    end
  else
    local osc = string.format('\027]52;c;%s\a', encoded)
    vim.fn.chansend(vim.v.stderr, osc)
    vim.notify("Sent to Cascade (" .. #text .. " chars)", vim.log.levels.INFO)
  end
end, { desc = 'Send buffer to Cascade' })
