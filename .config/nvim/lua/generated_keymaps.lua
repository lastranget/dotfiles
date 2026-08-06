-- generated_keymaps.lua
-- The <leader>g "Generated" which-key group, plus <leader>gr which refreshes
-- which-key (clears its cached mapping tree, then re-opens it on the <leader>g
-- prefix) so keymaps added to the group at runtime -- e.g. annotation toggles
-- injected over the RPC socket by an AI session -- are discovered and shown.
--
-- Registration is deferred to the VeryLazy event because which-key is a lazy
-- plugin and is not yet loaded when this file is required (right after
-- `require("keymaps")` in lua/config/lazy.lua, before lazy.setup()).
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    local ok, wk = pcall(require, "which-key")
    if not ok then
      return
    end
    wk.add({
      { "<leader>g", group = "Generated" },
      {
        "<leader>gr",
        function()
          pcall(function()
            require("which-key.buf").clear()
          end)
          require("which-key").show({ keys = (vim.g.mapleader or "\\") .. "g", mode = "n" })
        end,
        desc = "Refresh + show Generated keymaps",
      },
    })
  end,
})
