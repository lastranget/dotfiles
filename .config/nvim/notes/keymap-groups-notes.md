# Keymap Groups Analysis

## Leader-key bindings by file

### keymaps.lua
- `<leader>oo` Open obsidian home
- `<leader>os` Split obsidian home
- `<leader>ov` Vsplit obsidian home
- `<leader>oq` Obsidian quick switcher
- `<leader>ob` Obsidian backlinks
- `<leader>og` Obsidian grep
- `<leader>od` Obsidian template
- `<leader>ol` Obsidian links
- `<leader>on` Obsidian new
- `<leader>oh` Obsidian tags
- `<leader>o#` Yank Obsidian header link
- `<leader>yp` Copy full file path
- `<leader>z`  Tab split (pseudo full screen)
- `<leader>1-9,0` Go to tab N
- `<leader>tc` Toggle checkbox (Obsidian)
- `<leader>tD` Toggle diagnostic pop-up
- `<leader>so` Send buffer to Cascade
- `<leader>sno` Send buffer to new Cascade chat

### aerial.lua
- `<leader>ta` AerialToggle

### blame.lua
- `<leader>tB` Toggle blame sidebar

### buffer_walker.lua
- `<leader>,` MoveBack
- `<leader>.` MoveForward

### dap-ui.lua
- `<leader>du` Toggle DAP UI
- `<leader>de` Evaluate Expression
- `<leader>dE` Evaluate Input Expression
- `<leader>df` Float Element

### dap.lua
- `<leader>dc` Debug Continue/Start
- `<leader>do` Debug Step Over
- `<leader>di` Debug Step Into
- `<leader>dO` Debug Step Out
- `<leader>dt` Debug Terminate
- `<leader>dg` Go to Debug Cursor
- `<leader>db` Toggle Breakpoint
- `<leader>dB` Conditional Breakpoint
- `<leader>dl` Log Point
- `<leader>dr` Open REPL
- `<leader>dR` Run Last
- `<leader>dD` Disconnect
- `<leader>dC` Clear Breakpoints
- `<leader>dx` Break on raised exceptions
- `<leader>dX` Unset raised exceptions
- `<leader>dS` Save Breakpoints
- `<leader>dL` Load Breakpoints
- `<leader>dU` Unload Breakpoint Set
- `<leader>dY` Delete Breakpoint Set

### diffview.lua
- `<leader>co` Diffview Open
- `<leader>cq` Diffview Close
- `<leader>cf` Diffview file history
- `<leader>cb` Diffview branch history
- `<leader>cc` Diffview Open Dotfiles

### gitsigns.lua
- `<leader>hs` Git stage hunk
- `<leader>hr` Git reset hunk
- `<leader>hS` Git stage buffer
- `<leader>hR` Git reset buffer
- `<leader>hp` Git preview hunk
- `<leader>hi` Git preview hunk inline
- `<leader>hb` Git blame line
- `<leader>hd` Git diff this
- `<leader>hD` Diff this ~
- `<leader>hQ` Git setqflist all
- `<leader>hq` Git setqflist
- `<leader>tb` Git toggle current line blame
- `<leader>tw` Git toggle word diff

### harpoon.lua
- `<leader>fh` Open harpoon window
- `<leader>a`  Add to harpoon list

### lsp.lua
- `<leader>td` Toggle Diagnostics
- `<leader>th` Toggle Inlay Hints

### mini.files.lua
- `<leader>mm` Mini.files open here
- `<leader>mo` Mini.files open Obsidian
- `<leader>mr` Mini.files open root

### nvim-metals.lua (buffer-local, scala ft)
- `<leader>mc` Metals Commands
- `<leader>mw` Metals Worksheet Hover
- `<leader>mi` Metals Import Build
- `<leader>md` Metals Doctor
- `<leader>da` Attach to Remote Debugger

### picker.lua
- `<leader>fl` Picker resume last search
- `<leader>fr` Picker find lsp references
- `<leader>ff` Picker find files
- `<leader>fg` Picker live grep
- `<leader>fb` Picker buffers
- `<leader>fa` Picker help tags

### sidekick.lua
- `<leader>sa` Sidekick Toggle CLI
- `<leader>ss` Select CLI
- `<leader>sd` Detach a CLI Session
- `<leader>st` Send This
- `<leader>sf` Send File
- `<leader>sv` Send Visual Selection
- `<leader>sp` Sidekick Select Prompt
- `<leader>sc` Sidekick Toggle Claude
- `<leader>sw` Sidekick Toggle Cascade

### treesitter-context.lua
- `<leader>tc` TSContext toggle (NOTE: conflicts with obsidian toggle checkbox)

### venv-selector.lua
- `<leader>e` Open venv picker

### after/ftplugin/java.lua (buffer-local, java ft)
- `<leader>jo` Organize Imports
- `<leader>jv` Extract Variable
- `<leader>jc` Extract Constant
- `<leader>jm` Extract Method
- `<leader>dtc` Test Class
- `<leader>dtm` Test Nearest Method
- `<leader>da` Attach to Remote Debugger

## Files with NO leader keymaps
- baleia.lua, blink.lua, bullets.lua, dap-python.lua, everforest.lua,
  hardtime.lua, heirline.lua, jdtls.lua, marks.lua, obsidian.lua,
  render-markdown.lua, vim-tmux-navigator.lua, autocommands.lua, utils.lua

## Identified Groups (by prefix)
- `<leader>o`  → Obsidian
- `<leader>t`  → Toggle
- `<leader>d`  → Debug
- `<leader>dt` → Debug Test (sub-group)
- `<leader>c`  → Diffview
- `<leader>h`  → Git Hunk
- `<leader>f`  → Find
- `<leader>s`  → Sidekick/Send
- `<leader>sn` → Send New (sub-group)
- `<leader>m`  → Mini.files / Metals
- `<leader>j`  → Java
- `<leader>y`  → Yank
