-- plugins/lua/dap.lua
-- nvim-dap configuration for debugging support
return {
    "mfussenegger/nvim-dap",
    lazy = true,
    dependencies = {
        "nvim-neotest/nvim-nio",
    },
    keys = {
        { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
        { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Conditional Breakpoint" },
        { "<leader>dl", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: ")) end, desc = "Log Point" },
        { "<leader>dr", function() require("dap").repl.open() end, desc = "Open REPL" },
        { "<leader>dR", function() require("dap").run_last() end, desc = "Run Last" },
        { "<leader>dC", function() require("dap").clear_breakpoints() end, desc = "Clear Breakpoints" }
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

        -- ============================================================================
        -- Breakpoint Sets: Save, Load, Unload, Delete
        -- ============================================================================

        local function get_breakpoints_dir()
            local root = vim.fn.getcwd()
            return root .. "/.dap-breakpoints"
        end

        local function ensure_breakpoints_dir()
            local dir = get_breakpoints_dir()
            if vim.fn.isdirectory(dir) == 0 then
                vim.fn.mkdir(dir, "p")
            end
            return dir
        end

        local function save_breakpoints()
            local bps = {}
            local breakpoints = require("dap.breakpoints").get()

            local has_breakpoints = false
            for bufnr, buf_bps in pairs(breakpoints) do
                local file = vim.api.nvim_buf_get_name(bufnr)
                if file ~= "" and #buf_bps > 0 then
                    bps[file] = buf_bps
                    has_breakpoints = true
                end
            end

            if not has_breakpoints then
                vim.notify("No breakpoints to save", vim.log.levels.WARN)
                return
            end

            vim.ui.input({ prompt = "Breakpoint set name: " }, function(name)
                if not name or name == "" then
                    vim.notify("Save cancelled", vim.log.levels.INFO)
                    return
                end

                local filename = name:gsub("[^%w%-_]", "_") .. ".json"
                local dir = ensure_breakpoints_dir()
                local filepath = dir .. "/" .. filename

                local fp = io.open(filepath, "w")
                if fp then
                    fp:write(vim.fn.json_encode(bps))
                    fp:close()
                    vim.notify("Saved breakpoints to: " .. name, vim.log.levels.INFO)
                else
                    vim.notify("Failed to save breakpoints", vim.log.levels.ERROR)
                end
            end)
        end

        local function load_breakpoints()
            local dir = get_breakpoints_dir()

            if vim.fn.isdirectory(dir) == 0 then
                vim.notify("No saved breakpoint sets found", vim.log.levels.WARN)
                return
            end

            local files = vim.fn.globpath(dir, "*.json", false, true)

            if #files == 0 then
                vim.notify("No saved breakpoint sets found", vim.log.levels.WARN)
                return
            end

            local items = {}
            for _, filepath in ipairs(files) do
                local name = vim.fn.fnamemodify(filepath, ":t:r")
                table.insert(items, name)
            end

            vim.ui.select(items, {
                prompt = "Select breakpoint set to load:",
            }, function(choice, idx)
                if not choice then
                    return
                end

                local filepath = files[idx]
                local fp = io.open(filepath, "r")
                if not fp then
                    vim.notify("Failed to read breakpoint file", vim.log.levels.ERROR)
                    return
                end

                local content = fp:read("*a")
                fp:close()

                local ok, bps = pcall(vim.fn.json_decode, content)
                if not ok or not bps then
                    vim.notify("Failed to parse breakpoint file", vim.log.levels.ERROR)
                    return
                end

                local loaded_count = 0
                for file, file_bps in pairs(bps) do
                    for _, bp in ipairs(file_bps) do
                        local bufnr = vim.fn.bufnr(file, true)
                        vim.fn.bufload(bufnr)
                        require("dap.breakpoints").set(bp, bufnr, bp.line)
                        loaded_count = loaded_count + 1
                    end
                end

                vim.notify("Loaded " .. loaded_count .. " breakpoints from: " .. choice, vim.log.levels.INFO)
            end)
        end

        local function unload_breakpoints()
            local dir = get_breakpoints_dir()

            if vim.fn.isdirectory(dir) == 0 then
                vim.notify("No saved breakpoint sets found", vim.log.levels.WARN)
                return
            end

            local files = vim.fn.globpath(dir, "*.json", false, true)

            if #files == 0 then
                vim.notify("No saved breakpoint sets found", vim.log.levels.WARN)
                return
            end

            local items = {}
            for _, filepath in ipairs(files) do
                local name = vim.fn.fnamemodify(filepath, ":t:r")
                table.insert(items, name)
            end

            vim.ui.select(items, {
                prompt = "Select breakpoint set to unload:",
            }, function(choice, idx)
                if not choice then
                    return
                end

                local filepath = files[idx]
                local fp = io.open(filepath, "r")
                if not fp then
                    vim.notify("Failed to read breakpoint file", vim.log.levels.ERROR)
                    return
                end

                local content = fp:read("*a")
                fp:close()

                local ok, bps = pcall(vim.fn.json_decode, content)
                if not ok or not bps then
                    vim.notify("Failed to parse breakpoint file", vim.log.levels.ERROR)
                    return
                end

                local removed_count = 0
                for file, file_bps in pairs(bps) do
                    local bufnr = vim.fn.bufnr(file)
                    if bufnr ~= -1 then
                        for _, bp in ipairs(file_bps) do
                            require("dap.breakpoints").remove(bufnr, bp.line)
                            removed_count = removed_count + 1
                        end
                    end
                end

                vim.notify("Removed " .. removed_count .. " breakpoints from: " .. choice, vim.log.levels.INFO)
            end)
        end

        local function delete_breakpoint_set()
            local dir = get_breakpoints_dir()

            if vim.fn.isdirectory(dir) == 0 then
                vim.notify("No saved breakpoint sets found", vim.log.levels.WARN)
                return
            end

            local files = vim.fn.globpath(dir, "*.json", false, true)

            if #files == 0 then
                vim.notify("No saved breakpoint sets found", vim.log.levels.WARN)
                return
            end

            local items = {}
            for _, filepath in ipairs(files) do
                local name = vim.fn.fnamemodify(filepath, ":t:r")
                table.insert(items, name)
            end

            vim.ui.select(items, {
                prompt = "Select breakpoint set to DELETE:",
            }, function(choice, idx)
                if not choice then
                    return
                end

                local filepath = files[idx]
                if vim.fn.delete(filepath) == 0 then
                    vim.notify("Deleted: " .. choice, vim.log.levels.INFO)
                else
                    vim.notify("Failed to delete: " .. choice, vim.log.levels.ERROR)
                end
            end)
        end

        vim.keymap.set("n", "<leader>dS", save_breakpoints, { desc = "Save Breakpoints" })
        vim.keymap.set("n", "<leader>dL", load_breakpoints, { desc = "Load Breakpoints" })
        vim.keymap.set("n", "<leader>dU", unload_breakpoints, { desc = "Unload Breakpoint Set" })
        vim.keymap.set("n", "<leader>dX", delete_breakpoint_set, { desc = "Delete Breakpoint Set" })

        -- ============================================================================
        -- Java Debug Configurations
        -- ============================================================================

        dap.configurations.java = dap.configurations.java or {}

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
                vim.b.completion = false
            end,
        })
    end,
}
