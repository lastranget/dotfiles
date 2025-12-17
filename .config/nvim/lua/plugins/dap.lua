-- plugins/lua/dap.lua
-- nvim-dap configuration for debugging support
return {
    "mfussenegger/nvim-dap",
    lazy = true,
    dependencies = {
        -- Required for nvim-dap-ui
        "nvim-neotest/nvim-nio",
    },
    keys = {
        { "<leader>dl", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: ")) end, desc = "Log Point" },
        { "<leader>dr", function() require("dap").repl.open() end, desc = "Open REPL" },
        { "<leader>dR", function() require("dap").run_last() end, desc = "Run Last" },
    },
    config = function()
        local dap = require("dap")

        -- DAP signs for breakpoints
        vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint", linehl = "", numhl = "" })
        vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DapBreakpointCondition", linehl = "", numhl = "" })
        vim.fn.sign_define("DapLogPoint", { text = "◇", texthl = "DapLogPoint", linehl = "", numhl = "" })
        vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStopped", linehl = "DapStoppedLine", numhl = "" })
        vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DapBreakpointRejected", linehl = "", numhl = "" })

        -- Highlight groups for DAP signs (theme-aware)
        local function set_dap_highlights()
            local function get_hl_fg(name)
                local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
                return hl.fg and string.format("#%06x", hl.fg) or nil
            end

            local function get_hl_bg(name)
                local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
                return hl.bg and string.format("#%06x", hl.bg) or nil
            end

            vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = get_hl_fg("DiagnosticError") })
            vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = get_hl_fg("DiagnosticWarn") })
            vim.api.nvim_set_hl(0, "DapLogPoint", { fg = get_hl_fg("DiagnosticInfo") })
            vim.api.nvim_set_hl(0, "DapStopped", { fg = get_hl_fg("DiagnosticHint") })
            vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = get_hl_bg("DiffAdd") })
            vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = get_hl_fg("Comment") })
        end

        set_dap_highlights()

        vim.api.nvim_create_autocmd("ColorScheme", {
            callback = set_dap_highlights,
        })

        -- Note: Java adapter is automatically registered by nvim-jdtls when bundles are configured
        -- You can add a fallback attach configuration here if needed:
        dap.configurations.java = dap.configurations.java or {}

        -- Add a remote attach configuration (useful for debugging running applications)
        table.insert(dap.configurations.java, {
            type = "java",
            request = "attach",
            name = "Attach to Remote (5005)",
            hostName = "127.0.0.1",
            port = 5005,
        })

        table.insert(dap.configurations.java, {
            type = "java",
            request = "attach",
            name = "Attach to Remote (5006)",
            hostName = "127.0.0.1",
            port = 5006,
        })

        -- Enable DAP completion in REPL buffer
        vim.api.nvim_create_autocmd("FileType", {
            pattern = "dap-repl",
            callback = function()
                require("dap.ext.autocompl").attach()
                vim.b.completion = false -- disables blink for this buffer
            end,
        })
    end,
}
