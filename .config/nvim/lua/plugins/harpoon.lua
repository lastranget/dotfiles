return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim"
    },
    config = function(_, opts)
      local harpoon = require("harpoon")

      -- Helper function to parse JDT URIs (for Maven dependency files)
      local function parse_jdt_uri(uri)
        if not uri or not uri:match("^jdt://") then
          return nil
        end

        local result = {}

        -- Extract filename from the path portion (before the ?)
        -- Format: jdt://contents/jar-name.jar/package/ClassName.class?...
        local path_part = uri:match("^jdt://contents/[^/]+/[^/]+/([^?]+)")
        if path_part then
          result.filename = path_part
        end

        -- Extract maven coordinates from query string
        -- Format: ...=/maven.groupId=/org.cas.seti=/=/maven.artifactId=/models=/...
        local group_id = uri:match("maven%.groupId=/([^/=]+)")
        local artifact_id = uri:match("maven%.artifactId=/([^/=]+)")

        if group_id then
          result.group_id = group_id
        end
        if artifact_id then
          result.artifact_id = artifact_id
        end

        return result
      end

      -- Format a parsed JDT result for display
      local function format_jdt_display(parsed)
        if not parsed then
          return nil
        end

        local display = parsed.filename or "[Unknown]"

        if parsed.group_id and parsed.artifact_id then
          display = display .. " [" .. parsed.group_id .. ":" .. parsed.artifact_id .. "]"
        elseif parsed.artifact_id then
          display = display .. " [" .. parsed.artifact_id .. "]"
        end

        return display
      end

      -- Format any file path for display (handles both JDT and normal files)
      local function format_file_display(filepath)
        local jdt_parsed = parse_jdt_uri(filepath)
        if jdt_parsed then
          return format_jdt_display(jdt_parsed)
        end
        -- For normal files, just show the filename
        return vim.fn.fnamemodify(filepath, ":t")
      end

      -- REQUIRED
      harpoon:setup(vim.tbl_deep_extend("force", opts or {}, {
        settings = {
          save_on_toggle = true,
          sync_on_ui_close = true,
        },
        -- Custom display function for the quick menu
        default = {
          display = function(list_item)
            return format_file_display(list_item.value)
          end,
        },
      }))
      -- REQUIRED

      -- picker configuration for harpoon
      local function toggle_picker(harpoon_files)
          local items = {}

          for i = 1, harpoon_files._length do
              local item = harpoon_files.items[i]
              if item then
                local display = format_file_display(item.value)
                table.insert(items, {
                  text = display,
                  file = item.value,
                })
              end
          end

          require("snacks").picker.pick({
              source = "harpoon",
              title = "Harpoon",
              items = items,
              show_empty = true,
              format = function(item)
                return {{ item.text }}
              end,
              confirm = function(picker, item)
                picker:close()
                if item and item.file then
                  vim.cmd("edit " .. vim.fn.fnameescape(item.file))
                end
              end,
          })
      end

      vim.keymap.set("n", "<leader>fh", function() toggle_picker(harpoon:list()) end, { desc = "Open harpoon window" })
      vim.keymap.set("n", "<leader>a", function() harpoon:list():prepend() end, { desc = "Add to harpoon list" })
      vim.keymap.set("n", "<C-s>", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

      -- Removing, because we're going to use it for vim tmux navigator
      -- vim.keymap.set("n", "<C-j>", function() harpoon:list():select(1) end)
      -- vim.keymap.set("n", "<C-k>", function() harpoon:list():select(2) end)
      -- vim.keymap.set("n", "<C-l>", function() harpoon:list():select(3) end)
      -- vim.keymap.set("n", "<C-;>", function() harpoon:list():select(4) end)

      -- Toggle previous & next buffers stored within Harpoon list
      vim.keymap.set("n", "<C-S-P>", function() harpoon:list():prev() end)
      vim.keymap.set("n", "<C-S-N>", function() harpoon:list():next() end)
    end
}
