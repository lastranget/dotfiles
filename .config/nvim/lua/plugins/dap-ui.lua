-- plugins/lua/dap-ui.lua
-- nvim-dap-ui configuration for debugging UI
return {
    "rcarriga/nvim-dap-ui",
    lazy = true,
    dependencies = {
        "mfussenegger/nvim-dap",
        "nvim-neotest/nvim-nio",
    },
    keys = {
        { "<leader>du", function() require("dapui").toggle() end, desc = "Toggle DAP UI" },
        { "<leader>de", function() require("dapui").eval() end, desc = "Evaluate Expression", mode = { "n", "v" } },
        { "<leader>dE", function() require("dapui").eval(vim.fn.input("Expression: ")) end, desc = "Evaluate Input Expression" },
        { "<leader>df", function() require("dapui").float_element() end, desc = "Float Element" },
    },
    config = function()
        local dap, dapui = require("dap"), require("dapui")

        dapui.setup({
            -- Icon configuration
            icons = { expanded = "▾", collapsed = "▸", current_frame = "→" },

            -- Mappings within DAP UI windows
            mappings = {
                -- Use a table to apply multiple mappings
                expand = { "<CR>", "<2-LeftMouse>" },
                open = "o",
                remove = "d",
                edit = "e",
                repl = "r",
                toggle = "t",
            },

            -- Element arrangement in sidebars
            element_mappings = {},

            -- Expand lines larger than the window
            expand_lines = vim.fn.has("nvim-0.7") == 1,

            -- Layouts define sections of the screen for UI elements
            layouts = {
                {
                    -- Left sidebar
                    elements = {
                        { id = "console", size = 0.25 },
                        { id = "breakpoints", size = 0.25 },
                        { id = "stacks", size = 0.25 },
                        { id = "watches", size = 0.25 },
                    },
                    size = 40, -- Width in columns
                    position = "left",
                },
                {
                    -- Bottom panel
                    elements = {
                        { id = "repl", size = 0.5 },
                        { id = "scopes", size = 0.5 },
                    },
                    size = 10, -- Height in rows
                    position = "bottom",
                },
            },

            -- Floating window configuration
            floating = {
                max_height = nil,
                max_width = nil,
                border = "rounded",
                mappings = {
                    close = { "q", "<Esc>" },
                },
            },

            -- Window controls
            controls = {
                enabled = true,
                element = "repl",
                icons = {
                    pause = "⏸",
                    play = "▶",
                    step_into = "↓",
                    step_over = "→",
                    step_out = "↑",
                    step_back = "←",
                    run_last = "↺",
                    terminate = "■",
                },
            },

            -- Render settings
            render = {
                max_type_length = nil,
                max_value_lines = 100,
            },
        })

        -- Automatically open/close DAP UI when debugging starts/ends
        dap.listeners.before.attach.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.launch.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.event_terminated.dapui_config = function()
            dapui.close()
        end
        dap.listeners.before.event_exited.dapui_config = function()
            dapui.close()
        end
    end,
}
