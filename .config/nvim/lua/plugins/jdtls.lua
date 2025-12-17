-- plugins/lua/jdtls.lua
-- nvim-jdtls plugin configuration with DAP dependencies
return {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = {
        "mfussenegger/nvim-dap",
        "rcarriga/nvim-dap-ui",
    },
}
