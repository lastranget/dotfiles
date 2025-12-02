return {
  "nvim-zh/colorful-winsep.nvim",
  config = true,
  event = { "WinLeave" },
  opts = {
    highlight = "#1D94C2",
    animate = {
      enabled = false
    },
    indicator_for_2wins = {
      position = false
    }
  },
  config = function(_, opts)
    require("colorful-winsep").setup(opts)

    -- Create autocommands to toggle based on focus
    local group = vim.api.nvim_create_augroup("ColorfulWinsepToggle", { clear = true })

    vim.api.nvim_create_autocmd("FocusLost", {
      group = group,
      callback = function()
        -- Disable colorful-winsep when losing focus
        vim.cmd('Winsep disable')
      end,
    })

    vim.api.nvim_create_autocmd("FocusGained", {
      group = group,
      callback = function()
        -- Re-enable colorful-winsep when gaining focus
        vim.cmd('Winsep enable')
      end,
    })

  end
}
