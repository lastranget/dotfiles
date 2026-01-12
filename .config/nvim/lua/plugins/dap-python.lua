-- plugins/dap-python.lua
-- nvim-dap-python for proper Python debugging with debugpy
return {
    "mfussenegger/nvim-dap-python",
    ft = "python",
    dependencies = {
        "mfussenegger/nvim-dap",
    },
    config = function()
        local debugpy_python = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
        require("dap-python").setup(debugpy_python)

        local dap = require("dap")

        -- Add remote attach configurations with pathMappings support
        table.insert(dap.configurations.python, {
            type = "python",
            request = "attach",
            name = "Attach to Remote (5678)",
            connect = {
                host = "127.0.0.1",
                port = 5678,
            },
            pathMappings = {
                {
                    localRoot = vim.fn.getcwd(),
                    remoteRoot = ".",
                },
            },
        })

        table.insert(dap.configurations.python, {
            type = "python",
            request = "attach",
            name = "Attach to Remote (Custom)",
            connect = function()
                local host = vim.fn.input("Host [127.0.0.1]: ", "127.0.0.1")
                local port = tonumber(vim.fn.input("Port [5678]: ", "5678"))
                return { host = host, port = port }
            end,
            pathMappings = {
                {
                    localRoot = vim.fn.getcwd(),
                    remoteRoot = function()
                        return vim.fn.input("Remote root [.]: ", ".")
                    end,
                },
            },
        })
    end,
}
