-- plugins/picker.lua

-- State for toggling file search to include gitignored/hidden files
-- (e.g. generated sources under Maven `target/` dirs). When enabled,
-- <leader>ff stops respecting .gitignore so build output shows up.
local target_search = {
  enabled = false,
}

-- ── sidekick CLI picker preview ────────────────────────────────────────────
-- The sidekick tool picker (<leader>ss / <c-space>) is a `vim.ui.select` with
-- `kind = "sidekick_cli"`, which snacks routes through its `select` source. We
-- hook it via `picker.kinds.sidekick_cli` below (snacks merges that config on
-- top of sidekick's, so its nice formatted item list is untouched) to add a
-- preview: for an option backed by a live tmux session, show a snapshot of that
-- pane so you can tell what each session is about before attaching.
--
-- `tmux capture-pane` grabs the pane at its *current* size, which for a detached
-- (or otherwise larger) session can be much bigger than the 0.8×0.8 float it'll
-- reopen into — the snapshot wouldn't match the eventual layout anyway. So we
-- only show the bottom-left corner (the most recent output, left-aligned),
-- cropped to the preview window's own size: enough of a clue to identify the
-- session without pretending to be a faithful render.
local function sidekick_session_preview(ctx)
  local preview, item = ctx.preview, ctx.item
  -- the select finder wraps each tool state as `item.item` (with __index back to
  -- it as well); fall through to the item itself just in case.
  local state = item.item or item
  local session = state and state.session

  preview:reset()
  preview:minimal()

  local name = (state and state.tool and state.tool.name) or "sidekick"

  if not session then
    preview:set_title(name)
    preview:set_lines({
      "",
      "  No running session.",
      "",
      "  Selecting this starts a fresh one.",
    })
    return
  end

  -- Only tmux-backed sessions can be captured. `tmux_pane_id` is the exact pane;
  -- fall back to the session name (tmux captures its active pane) or the sid.
  local backend = session.mux_backend or session.backend
  local target = session.tmux_pane_id or session.mux_session or session.sid
  if backend ~= "tmux" or not target then
    preview:set_title(name)
    preview:set_lines({ "", "  No tmux pane to preview for this session." })
    return
  end

  -- Crop to the preview window so we show the bottom-left corner. Fall back to
  -- sane defaults if the window isn't sized/valid yet.
  local win = ctx.win
  local sized = win and vim.api.nvim_win_is_valid(win)
  local height = sized and vim.api.nvim_win_get_height(win) or 30
  local width = sized and vim.api.nvim_win_get_width(win) or 120

  local out = vim.fn.systemlist({ "tmux", "capture-pane", "-p", "-t", target })
  if vim.v.shell_error ~= 0 then
    preview:set_title(name)
    preview:set_lines({ "", "  tmux capture-pane failed for " .. target })
    return
  end

  -- Drop trailing blank lines so the *bottom* of our crop is the last real
  -- output (TUIs leave the lower rows of the pane empty).
  while #out > 0 and out[#out]:match("^%s*$") do
    out[#out] = nil
  end

  -- Bottom: keep only the last `height` lines.
  if #out > height then
    out = vim.list_slice(out, #out - height + 1, #out)
  end

  -- Left: truncate each line to the window width (character-aware) so long
  -- lines don't push the interesting left edge off-screen.
  for i, line in ipairs(out) do
    if vim.fn.strdisplaywidth(line) > width then
      out[i] = vim.fn.strcharpart(line, 0, width)
    end
  end

  if #out == 0 then
    out = { "", "  (pane is empty)" }
  end

  local cwd = vim.fn.fnamemodify(session.cwd or "", ":~")
  preview:set_title(cwd ~= "" and (name .. "  ·  " .. cwd) or name)
  preview:set_lines(out)
end

return {
  "folke/snacks.nvim",
  lazy = false, -- Load immediately so sidekick can use picker for its menus
  opts = {
    picker = {
      -- Per-`vim.ui.select` kind overrides. `sidekick_cli` is the kind the
      -- sidekick tool picker uses; we attach a tmux-pane preview and unhide the
      -- preview window (the `select` preset hides it by default), and grow the
      -- float so the snapshot has room. See sidekick_session_preview above.
      kinds = {
        sidekick_cli = {
          preview = sidekick_session_preview,
          layout = {
            preset = "select",
            hidden = {}, -- unhide the preview window
            layout = {
              width = 0.8,
              max_width = 500, -- lift the select preset's 100-col cap (0 != unlimited)
              height = 0.8,
              min_height = 20,
            },
          },
        },
      },
      -- Sidekick integration actions
      actions = {
        sidekick_send = function(...)
          return require("sidekick.cli.picker.snacks").send(...)
        end,
        sidekick_send_context = function(picker)
          require("sidekick.cli.picker.snacks").action(
            require("sidekick.cli.picker")._send_cb({ kind = "position" })
          )(picker)
        end,
        -- Delete items from lists (harpoon, buffers, marks)
        list_delete = function(picker)
          local selected = picker:selected({ fallback = true })
          if #selected == 0 then return end

          local source = picker.opts.source or ""

          if source == "harpoon" then
            local harpoon = require("harpoon")
            local list = harpoon:list()
            local to_remove = {}
            for _, item in ipairs(selected) do
              to_remove[item.file] = true
            end
            for i = list._length, 1, -1 do
              if list.items[i] and to_remove[list.items[i].value] then
                list:remove_at(i)
              end
            end
            picker:refresh()
          elseif source == "buffers" then
            picker.preview:reset()
            for _, item in ipairs(selected) do
              if item.buf then
                Snacks.bufdelete.delete(item.buf)
              end
            end
            picker:refresh()
          elseif source == "marks" then
            for _, item in ipairs(selected) do
              if item.label then
                if item.buf then
                  vim.api.nvim_buf_del_mark(item.buf, item.label)
                else
                  vim.api.nvim_del_mark(item.label)
                end
              end
            end
            picker:refresh()
          else
            Snacks.notify.warn("Delete not supported for this picker", { title = "Snacks Picker" })
          end
        end,
      },
      -- Add sidekick keybinding to picker input
      win = {
        input = {
          keys = {
            ["?"] = { "toggle_help_input", desc = "Help" },
            ["<C-x>"] = {
              "sidekick_send",
              mode = { "n", "i" },
            },
            ["<C-y>"] = {
              "sidekick_send_context",
              mode = { "n", "i" },
              desc = "Sidekick",
            },
            ["<Tab>"] = { "select_and_next", mode = { "i", "n" }, desc = "Select" },
            ["<C-a>"] = { "select_all", mode = { "n", "i" }, desc = "All" },
            ["<C-d>"] = { "list_delete", mode = { "n", "i" }, desc = "Del" },
            ["<C-v>"] = { "edit_vsplit", mode = { "i", "n" }, desc = "VS" },
          },
          footer = {
            { " ", "SnacksFooter" },
            { "?", "SnacksFooterKey" },
            { " Help ", "SnacksFooterDesc" },
            { "<C-y>", "SnacksFooterKey" },
            { " Sidekick ", "SnacksFooterDesc" },
            { "<Tab>", "SnacksFooterKey" },
            { " Sel ", "SnacksFooterDesc" },
            { "<C-a>", "SnacksFooterKey" },
            { " All ", "SnacksFooterDesc" },
            { "<C-d>", "SnacksFooterKey" },
            { " Del ", "SnacksFooterDesc" },
            { "<C-v>", "SnacksFooterKey" },
            { " VS ", "SnacksFooterDesc" },
            { " ", "SnacksFooter" },
          },
        },
        preview = {
          wo = {
            foldenable = false,
          },
        },
        list = {
          keys = {
            ["?"] = { "toggle_help_list", desc = "Help" },
            ["<C-y>"] = {
              "sidekick_send_context",
              mode = { "n" },
              desc = "Sidekick",
            },
            ["<Tab>"] = { "select_and_next", mode = { "n", "x" }, desc = "Select" },
            ["<C-a>"] = { "select_all", desc = "All" },
            ["<C-d>"] = { "list_delete", desc = "Del" },
            ["<C-v>"] = { "edit_vsplit", desc = "VS" },
          },
          footer = {
            { " ", "SnacksFooter" },
            { "?", "SnacksFooterKey" },
            { " Help ", "SnacksFooterDesc" },
            { "<C-y>", "SnacksFooterKey" },
            { " Sidekick ", "SnacksFooterDesc" },
            { "<Tab>", "SnacksFooterKey" },
            { " Sel ", "SnacksFooterDesc" },
            { "<C-a>", "SnacksFooterKey" },
            { " All ", "SnacksFooterDesc" },
            { "<C-d>", "SnacksFooterKey" },
            { " Del ", "SnacksFooterDesc" },
            { "<C-v>", "SnacksFooterKey" },
            { " VS ", "SnacksFooterDesc" },
            { " ", "SnacksFooter" },
          },
        },
      },
    },
  },
  keys = {
    {
      "<leader>fl",
      function()
        require("snacks").picker.resume()
      end,
      desc = "Picker resume last search",
    },
    {
      "<leader>fr",
      function()
        require("snacks").picker.lsp_references()
      end,
      desc = "Picker find lsp references",
      noremap = true,
      silent = true
    },
    {
      "<leader>ff",
      function()
        if target_search.enabled then
          require("snacks").picker.files({ hidden = true, ignored = true })
        else
          require("snacks").picker.files()
        end
      end,
      desc = "Picker find files",
    },
    {
      "<leader>fF",
      function()
        target_search.enabled = not target_search.enabled
        require("snacks").notify(
          target_search.enabled and "File search: including gitignored/hidden (target/ visible)"
            or "File search: respecting .gitignore",
          { title = "Picker" }
        )
      end,
      desc = "Picker toggle gitignored/hidden file search",
    },
    {
      "<leader>fg",
      function()
        local mode = vim.fn.mode()
        if mode == "v" or mode == "V" or mode == "\22" then
          -- Yank the visual selection into a temp register and grep for it
          local save = vim.fn.getreg("z")
          local save_type = vim.fn.getregtype("z")
          vim.cmd('noautocmd normal! "zy')
          local selection = vim.fn.getreg("z")
          vim.fn.setreg("z", save, save_type)
          require("snacks").picker.grep({ search = selection })
        else
          require("snacks").picker.grep()
        end
      end,
      mode = { "n", "x" },
      desc = "Picker live grep",
    },
    {
      "<leader>ft",
      function()
        require("snacks").picker.grep({ search = vim.fn.expand("<cword>") })
      end,
      desc = "Picker grep word under cursor",
    },
    {
      "<leader>fb",
      function()
        require("snacks").picker.buffers()
      end,
      desc = "Picker buffers",
    },
    {
      "<leader>fa",
      function()
        require("snacks").picker.help()
      end,
      desc = "Picker help tags",
    },
  },
}
