return {
  "rebelot/heirline.nvim",
  config = function(_, opts)
    local conditions = require("heirline.conditions")
    local utils = require("heirline.utils")

    require("heirline").setup(opts)
  end
}
