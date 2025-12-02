return {
  'nvim-telescope/telescope-symbols.nvim',
  keys = {
    {
      "<leader>fe",
      function()
        require("telescope.builtin").symbols{ sources = {'emoji'} }
      end,
      desc = "Telescope emoji"
    }
  }
}
