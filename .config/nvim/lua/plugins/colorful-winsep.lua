-- https://github.com/nvim-zh/colorful-winsep.nvim
--
-- Draws a colored window separator, but never lets a *horizontal* separator
-- line appear. The plugin stays active for any layout made up purely of
-- side-by-side vsplits (a single window, two, three, ... all fine), and draws
-- nothing the moment a stacked split would introduce a horizontal line.
--
-- The plugin has no built-in layout filter. Earlier this was driven via the
-- plugin's enable()/disable() from window autocmds, but that races the plugin's
-- own scheduler: the plugin schedules view.render() directly and render() never
-- re-checks the enabled flag at execution time (only its autocmd callback does,
-- at event-fire time). So a render queued while still "enabled" would re-draw a
-- separator *after* disable() had hidden it, leaving an orphaned, stuck line.
--
-- Instead we gate render() itself: we wrap view.render so that whenever it
-- actually runs it inspects the live layout and hides everything if a stacked
-- split exists. The plugin looks up view.render at call time, so every render
-- it schedules flows through the gate -- no flag, no scheduling race.
return {
  "nvim-zh/colorful-winsep.nvim",
  event = "VeryLazy",
  config = function()
    require("colorful-winsep").setup({
      -- Match the tmux active pane border colour (pane-active-border-style fg
      -- = @everforest_blue in ~/.tmux.conf).
      highlight = "#3a94c5",
      -- No center arrow pointing at the active window.
      indicator_for_2wins = { position = false },
      -- No slide/animation when the separator appears or moves.
      animate = { enabled = false },
    })

    local view = require("colorful-winsep.view")

    -- A horizontal separator only exists where windows are stacked, which shows
    -- up as a "col" node in winlayout()'s tree. So the layout is OK (no
    -- horizontal line) exactly when the tree contains no "col" node -- i.e. a
    -- single leaf or any nesting of "row" splits. winlayout() ignores floating
    -- windows, so floats (sidekick, which-key, ...) don't affect this.
    --   single window  -> { "leaf", win }                         -> ok
    --   vsplits (rows)  -> { "row", { {"leaf"}, {"leaf"}, ... } }  -> ok
    --   stacked (col)   -> { "col", { ... } }                      -> not ok
    local function has_col(node)
      local kind = node[1]
      if kind == "col" then
        return true
      elseif kind == "row" then
        for _, child in ipairs(node[2]) do
          if has_col(child) then
            return true
          end
        end
      end
      return false -- leaf
    end

    -- Gate the plugin's renderer. When the current layout would produce a
    -- horizontal line, hide all separators and skip drawing; otherwise defer to
    -- the original render. This runs at render time, so it's immune to whatever
    -- order the plugin's scheduled callbacks happen to flush in.
    local original_render = view.render
    view.render = function(...)
      if has_col(vim.fn.winlayout()) then
        view.hide_all()
        return
      end
      return original_render(...)
    end

    -- The plugin only renders on WinEnter/WinResized/BufWinEnter. Cover the
    -- layout-changing events it misses (e.g. closing a window to return to an
    -- all-vsplit layout) so the gate re-evaluates and redraws/hides as needed.
    vim.api.nvim_create_autocmd(
      { "WinNew", "WinClosed", "WinLeave", "VimResized", "TabEnter" },
      {
        group = vim.api.nvim_create_augroup("ColorfulWinsepLayoutGate", { clear = true }),
        callback = function()
          vim.schedule(view.render)
        end,
      }
    )

    -- Apply once for the layout that already exists at load time.
    vim.schedule(view.render)
  end,
}
