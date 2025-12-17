-- after/ftplugin/java.lua
-- Java-specific configuration using nvim-jdtls with DAP support

local status, jdtls = pcall(require, "jdtls")
if not status then
    return
end

-- ============================================================================
-- Helper Functions
-- ============================================================================

local function get_os()
    local handle = io.popen("uname -s 2>/dev/null")
    if handle then
        local os_name = handle:read("*a"):lower():gsub("\n", "")
        handle:close()

        if os_name:find("linux") then
            return "linux"
        elseif os_name:find("darwin") then
            return "macos"
        end
    end
    return "unknown"
end

local function format_code()
    local bufnr = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local filetype = vim.bo[bufnr].filetype

    -- Save cursor position
    local cursor_pos = vim.api.nvim_win_get_cursor(0)

    if filetype == "java" or filename:match("%.java$") then
        if filename == "" then
            print("Save the file first before formatting")
            return
        end
        local idea_cmd = "idea format -allowDefaults " .. vim.fn.shellescape(filename)
        local idea_result = vim.fn.system(idea_cmd)

        if vim.v.shell_error == 0 then
            vim.api.nvim_win_set_cursor(0, cursor_pos)
            print("Formatted with IntelliJ")
            return
        else
            print("IntelliJ formatter not installed or failed")
            return
        end
    end
    print("No formatter available for " .. filetype)
end

vim.api.nvim_create_user_command("JdtFormat", format_code, {
    desc = "Format current file with IntelliJ",
})

-- ============================================================================
-- Path Configuration
-- ============================================================================

local HOME = os.getenv("HOME")
local ROOT_DIR = require("jdtls.setup").find_root({ 'pom.xml', 'build.gradle', 'gradlew', '.git' })
local CONFIG_DIR = get_os() == "linux" and "config_linux" or "config_mac"
local DEFAULT_JDK_PATH = get_os() == "linux" and "/usr/lib/jvm/java-21-openjdk-amd64" or "/usr/local/opt/openjdk@21"

-- ============================================================================
-- Debug Bundles Configuration
-- ============================================================================

--- Retrieves java-debug and vscode-java-test bundles
--- @return table List of jar file paths for debug bundles
local function get_debug_bundles()
    local bundles = {}

    -- Define possible locations for java-debug-adapter
    local java_debug_paths = {
        -- Custom location in your config
        HOME .. "/.config/nvim/jdtls_dependencies/bundles/com.microsoft.java.debug.plugin-*.jar",
        -- Mason installation location
        HOME .. "/.local/share/nvim/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
        HOME .. "/.local/share/nvim/mason/share/java-debug-adapter/com.microsoft.java.debug.plugin-*.jar",
        -- Manual installation locations
        HOME .. "/.local/share/java-debug/com.microsoft.java.debug.plugin/target/com.microsoft.java.debug.plugin-*.jar",
    }

    -- Find and add java-debug bundle
    for _, path_pattern in ipairs(java_debug_paths) do
        local debug_jar = vim.fn.glob(path_pattern, true)
        if debug_jar ~= "" then
            -- Handle case where glob returns multiple files (newline-separated)
            for _, jar in ipairs(vim.split(debug_jar, "\n")) do
                if jar ~= "" and vim.fn.filereadable(jar) == 1 then
                    table.insert(bundles, jar)
                    break -- Only need one java-debug jar
                end
            end
            if #bundles > 0 then
                break
            end
        end
    end

    -- Define possible locations for vscode-java-test
    local java_test_paths = {
        -- Custom location in your config
        HOME .. "/.config/nvim/jdtls_dependencies/bundles/vscode-java-test/*.jar",
        -- Mason installation location
        HOME .. "/.local/share/nvim/mason/packages/java-test/extension/server/*.jar",
        HOME .. "/.local/share/nvim/mason/share/java-test/*.jar",
        -- Manual installation locations
        HOME .. "/.local/share/vscode-java-test/server/*.jar",
    }

    -- JARs to exclude from vscode-java-test (they cause issues)
    local excluded_jars = {
        "com.microsoft.java.test.runner-jar-with-dependencies.jar",
        "jacocoagent.jar",
    }

    -- Find and add vscode-java-test bundles
    for _, path_pattern in ipairs(java_test_paths) do
        local test_jars = vim.fn.glob(path_pattern, true)
        if test_jars ~= "" then
            for _, jar in ipairs(vim.split(test_jars, "\n")) do
                if jar ~= "" and vim.fn.filereadable(jar) == 1 then
                    local jar_name = vim.fn.fnamemodify(jar, ":t")
                    local is_excluded = false
                    for _, excluded in ipairs(excluded_jars) do
                        if jar_name == excluded then
                            is_excluded = true
                            break
                        end
                    end
                    if not is_excluded then
                        table.insert(bundles, jar)
                    end
                end
            end
            break -- Found test jars, stop searching
        end
    end

    return bundles
end

--- Retrieves any additional supplementary dependencies
--- @return table List of additional jar file paths
local function retrieve_supplementary_dependencies()
    local dependency_bundle = {}
    local jdtls_dependencies_dir = HOME .. "/.config/nvim/jdtls_dependencies"
    local dep_jars = vim.fn.glob(jdtls_dependencies_dir .. "/bundles/*.jar", true)
    if dep_jars ~= "" then
        for _, jar in ipairs(vim.split(dep_jars, "\n")) do
            if jar ~= "" and vim.fn.filereadable(jar) == 1 then
                -- Avoid duplicates with debug bundles
                local jar_name = vim.fn.fnamemodify(jar, ":t")
                if not jar_name:match("^com%.microsoft%.java%.debug%.plugin") and
                   not jar_name:match("^com%.microsoft%.java%.test") then
                    table.insert(dependency_bundle, jar)
                end
            end
        end
    end
    return dependency_bundle
end

-- Combine all bundles
local all_bundles = get_debug_bundles()
vim.list_extend(all_bundles, retrieve_supplementary_dependencies())

-- ============================================================================
-- LSP Capabilities
-- ============================================================================

local capabilities = require('blink.cmp').get_lsp_capabilities()
local extendedClientCapabilities = require("jdtls").extendedClientCapabilities
extendedClientCapabilities.resolveAdditionalTextEditsSupport = true

-- ============================================================================
-- JDTLS Configuration
-- ============================================================================

local config = {
    cmd = {
        "java",
        "-Declipse.application=org.eclipse.jdt.ls.core.id1",
        "-Dosgi.bundles.defaultStartLevel=4",
        "-Declipse.product=org.eclipse.jdt.ls.core.product",
        "-Dlog.protocol=true",
        "-Dlog.level=ALL",
        "-Xms1g",
        "--add-modules=ALL-SYSTEM",
        "--add-opens",
        "java.base/java.util=ALL-UNNAMED",
        "--add-opens",
        "java.base/java.lang=ALL-UNNAMED",
        "-jar",
        HOME .. "/.local/bin/jdtls",
        "-configuration",
        HOME .. "/.local/share/language.servers/java/jdtls/" .. CONFIG_DIR,
        "-data",
        HOME .. "/.cache/jdtls/workspace/" .. vim.fn.fnamemodify(ROOT_DIR or vim.fn.getcwd(), ":p:h:t")
    },
    root_dir = ROOT_DIR,
    filetypes = { 'java' },

    settings = {
        java = {
            eclipse = {
                downloadSources = true,
            },
            configuration = {
                updateBuildConfiguration = "interactive",
                runtimes = {
                    {
                        name = "JavaSE-21",
                        path = DEFAULT_JDK_PATH,
                    }
                }
            },
            maven = {
                downloadSources = true,
            },
            implementationCodeLens = {
                enabled = false,
            },
            referenceCodeLens = {
                enabled = false,
            },
            references = {
                includeDecompiledSources = true,
            },
            format = {
                enabled = false
            },
        }
    },

    completion = {
        favoriteStaticMembers = {
            "org.hamcrest.MatcherAssert.assertThat",
            "org.hamcrest.Matchers.*",
            "org.hamcrest.CoreMatchers.*",
            "org.junit.jupiter.api.Assertions.*",
            "java.util.Objects.requireNonNull",
            "java.util.Objects.requireNonNullElse",
            "org.mockito.Mockito.*",
        }
    },

    contentProvider = { preferred = "fernflower" },

    extendedClientCapabilities = extendedClientCapabilities,

    sources = {
        organizeImports = {
            starThreshold = 9999,
            staticStarThreshold = 9999,
        },
    },

    codeGeneration = {
        toString = {
            template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
        },
        useBlocks = true,
    },

    flags = {
        allow_incremental_sync = true,
    },

    -- Debug bundles are passed here
    init_options = {
        bundles = all_bundles,
        extendedClientCapabilities = extendedClientCapabilities,
    },

    capabilities = capabilities,

    on_attach = function(client, bufnr)
        if client.name == "jdtls" then
            -- Set up DAP integration
            local dap_status, _ = pcall(require, "dap")
            if dap_status then
                -- Configure DAP with hotcode replace
                require("jdtls").setup_dap({ hotcodereplace = "auto" })
                -- Discover main classes for debugging
                require("jdtls.dap").setup_dap_main_class_configs()
            end

            -- ================================================================
            -- Java-specific keymaps (buffer-local)
            -- ================================================================

            local opts = { buffer = bufnr, silent = true }

            -- Code organization
            vim.keymap.set("n", "<leader>jo", jdtls.organize_imports, vim.tbl_extend("force", opts, { desc = "Organize Imports" }))

            -- Refactoring
            vim.keymap.set("n", "<leader>jv", jdtls.extract_variable, vim.tbl_extend("force", opts, { desc = "Extract Variable" }))
            vim.keymap.set("v", "<leader>jv", function() jdtls.extract_variable(true) end, vim.tbl_extend("force", opts, { desc = "Extract Variable" }))
            vim.keymap.set("n", "<leader>jc", jdtls.extract_constant, vim.tbl_extend("force", opts, { desc = "Extract Constant" }))
            vim.keymap.set("v", "<leader>jc", function() jdtls.extract_constant(true) end, vim.tbl_extend("force", opts, { desc = "Extract Constant" }))
            vim.keymap.set("v", "<leader>jm", function() jdtls.extract_method(true) end, vim.tbl_extend("force", opts, { desc = "Extract Method" }))

            -- Testing (requires vscode-java-test bundles)
            vim.keymap.set("n", "<leader>dtc", jdtls.test_class, vim.tbl_extend("force", opts, { desc = "Test Class" }))
            vim.keymap.set("n", "<leader>dtm", jdtls.test_nearest_method, vim.tbl_extend("force", opts, { desc = "Test Nearest Method" }))

            -- Debugging keymaps
            vim.keymap.set("n", "<leader>dc", repeatable(function() require("dap").continue() end), vim.tbl_extend("force", opts, { desc = "Debug Continue" }))
            vim.keymap.set("n", "<leader>do", repeatable(function() require("dap").step_over() end), vim.tbl_extend("force", opts, { desc = "Debug Step Over" }))
            vim.keymap.set("n", "<leader>di", repeatable(function() require("dap").step_into() end), vim.tbl_extend("force", opts, { desc = "Debug Step Into" }))
            vim.keymap.set("n", "<leader>dO", repeatable(function() require("dap").step_out() end), vim.tbl_extend("force", opts, { desc = "Debug Step Out" }))
            vim.keymap.set("n", "<leader>dt", repeatable(function() require("dap").terminate() end), vim.tbl_extend("force", opts, { desc = "Debug Terminate" }))

            -- Remote attach with auto-detected project name
            vim.keymap.set("n", "<leader>da", function()
                local root = require("jdtls.setup").find_root({"pom.xml", "build.gradle", ".git"})
                local project = vim.fn.fnamemodify(root, ":t")
                local port = vim.fn.input("Debug port: ", "5006")
                require("dap").run({
                    type = "java",
                    request = "attach",
                    name = "Attach to port " .. port,
                    hostName = "127.0.0.1",
                    port = tonumber(port),
                    projectName = project,
                })
            end, vim.tbl_extend("force", opts, { desc = "Attach to Remote Debugger" }))

            -- Useful JDTLS commands reminder
            print("JDTLS attached. Use :JdtUpdateDebugConfig to refresh debug configs.")
        end
    end
}

-- ============================================================================
-- Start JDTLS
-- ============================================================================

require('jdtls').start_or_attach(config)
