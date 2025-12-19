-- lua/plugins/metals.lua
-- nvim-metals configuration for Scala LSP and debugging
return {
    "scalameta/nvim-metals",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "mfussenegger/nvim-dap",
        "j-hui/fidget.nvim",
    },
    ft = { "scala", "sbt" },  -- Removed "java" to avoid conflict with jdtls
    opts = function()
        local metals_config = require("metals").bare_config()


        metals_config.settings = {
            showImplicitArguments = true,
            showImplicitConversionsAndClasses = true,
            showInferredType = true,
            fallbackScalaVersion = "2.11.12",  -- Match your project's Scala version
            javaHome = "/usr/lib/jvm/java-21-openjdk-amd64",  -- Same as your jdtls
            excludedPackages = {
                "akka.actor.typed.javadsl",
                "com.github.swagger.akka.javadsl",
            },
            defaultBspToBuildTool = true,
        }

        -- Disable status bar provider to use fidget.nvim for progress
        metals_config.init_options = {
            statusBarProvider = "off",
        }

        -- Use blink.cmp capabilities (matching your existing setup)
        metals_config.capabilities = require("blink.cmp").get_lsp_capabilities()

        metals_config.on_attach = function(client, bufnr)
            -- Enable DAP integration
            require("metals").setup_dap()

            local opts = { buffer = bufnr, silent = true }

            -- Metals-specific commands
            vim.keymap.set("n", "<leader>mc", function()
                require("metals").commands()
            end, vim.tbl_extend("force", opts, { desc = "Metals Commands" }))

            vim.keymap.set("n", "<leader>mw", function()
                require("metals").hover_worksheet()
            end, vim.tbl_extend("force", opts, { desc = "Metals Worksheet Hover" }))

            vim.keymap.set("n", "<leader>mi", function()
                require("metals").import_build()
            end, vim.tbl_extend("force", opts, { desc = "Metals Import Build" }))

            vim.keymap.set("n", "<leader>md", function()
                require("metals").run_doctor()
            end, vim.tbl_extend("force", opts, { desc = "Metals Doctor" }))

            -- DAP attach for Scala (same JVM debug protocol as Java)
            vim.keymap.set("n", "<leader>da", function()
                local port = vim.fn.input("Debug port: ", "5006")
                require("dap").run({
                    type = "scala",
                    request = "attach",
                    name = "Attach to Scala JVM",
                    hostName = "127.0.0.1",
                    port = tonumber(port),
                    buildTarget = vim.fn.input("Build target (empty for auto): ", ""),
                })
            end, vim.tbl_extend("force", opts, { desc = "Attach to Remote Debugger" }))
            -- In metals.lua on_attach function
            vim.keymap.set("n", "<leader>da", function()
                local port = vim.fn.input("Debug port: ", "5006")
                require("dap").run({
                    type = "scala",
                    request = "attach",
                    name = "Attach to port " .. port,
                    hostName = "127.0.0.1",
                    port = tonumber(port),
                })
            end, vim.tbl_extend("force", opts, { desc = "Attach to Remote Debugger" }))
        end

        return metals_config
    end,
    config = function(self, metals_config)
        -- Set JAVA_HOME for Metals to use Java 21
        vim.env.JAVA_HOME = "/usr/lib/jvm/java-21-openjdk-amd64"

        -- Setup fidget for LSP progress notifications
        require("fidget").setup({})

        -- DAP configurations for Scala
        local dap = require("dap")

        dap.configurations.scala = {
            {
                type = "scala",
                request = "launch",
                name = "Run or Test File",
                metals = {
                    runType = "runOrTestFile",
                },
            },
            {
                type = "scala",
                request = "launch",
                name = "Test Target",
                metals = {
                    runType = "testTarget",
                },
            },
            {
                type = "scala",
                request = "attach",
                name = "Attach to Scala (5005)",
                hostName = "127.0.0.1",
                port = 5005,
            },
            {
                type = "scala",
                request = "attach",
                name = "Attach to Scala (5006)",
                hostName = "127.0.0.1",
                port = 5006,
            },
        }

        -- Auto-attach to Scala/sbt files
        local nvim_metals_group = vim.api.nvim_create_augroup("nvim-metals", { clear = true })
        vim.api.nvim_create_autocmd("FileType", {
            pattern = self.ft,
            callback = function()
                require("metals").initialize_or_attach(metals_config)
            end,
            group = nvim_metals_group,
        })
    end,
}
