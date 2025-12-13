-- required for obsidian
vim.opt_local.conceallevel = 2

-- Backup file configuration
-- Remove current directory (.) from backupdir to prevent backup files in vault
vim.fn.mkdir(vim.fn.stdpath('state') .. '/backup', 'p')
vim.opt.backupdir = vim.fn.stdpath('state') .. '/backup//'
vim.opt.backup = true
vim.opt.writebackup = true

require("config.lazy")
