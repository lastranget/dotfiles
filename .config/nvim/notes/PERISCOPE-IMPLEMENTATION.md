# Periscope — Implementation Notes

## Applying the Patch

```bash
cfg apply periscope.patch
```

To reverse:
```bash
cfg apply -R periscope.patch
```

## Files Changed

| File | Change |
|------|--------|
| `lua/periscope.lua` | **New** — entire module (259 lines) |
| `lua/keymaps.lua` | **Append** — two keybinds added at end of file |

No changes to `keymap-groups.lua` — `<leader>t` already has the "Toggle" group registered with which-key.

## Implementation Decisions

### Mode A (viewport capture) chosen over Mode B (history capture)

The spec recommends starting with Mode A, which replaces the buffer with the pane's current visible content on every tick. This is simple, reliable, and mirrors exactly what the tmux pane shows. Mode B (scrollback history with `-S -N`) can be layered on later as a config option without changing the architecture.

### Singleton state

Only one Periscope window at a time. The `state` table is module-level. `M.open()` calls `M.close()` first to tear down any existing session before starting a new one. This keeps resource management simple and avoids orphaned timers.

### Toggle preserves the polling timer

`M.toggle()` hides the window (`nvim_win_close`) but does **not** stop the timer or delete the buffer. This means toggling back open is instant — the buffer already has fresh content. The timer's `vim.schedule_wrap` callback checks `vim.api.nvim_win_is_valid(state.win)` and skips the update when the window is hidden (the buffer still gets written to, but no cursor movement occurs since there's no window). If both `pane_id` and timer are nil, toggle falls through to `M.pick()`.

### baleia.nvim loaded via pcall

The existing `baleia.lua` plugin spec lazy-loads baleia on `BufRead *.txt|*.out`. Periscope uses `pcall(require, "baleia")` which triggers lazy.nvim's module auto-loader, so baleia will be available even if no `.txt` buffer has been opened yet. If baleia somehow fails to load, Periscope still works — just without ANSI color rendering.

A fresh `baleia.setup({})` instance is created per `M.open()` call rather than reusing `vim.g.baleia` from the plugin config. This avoids coupling to the global and keeps the periscope buffer's colorization independent.

### Nested tmux support (CASCADE_OUTER_TMUX)

`get_tmux_socket()` checks `vim.env.CASCADE_OUTER_TMUX` and extracts the socket path. All tmux commands (`list-panes`, `capture-pane`) are prefixed with `-S <socket>` when running inside a nested tmux session (e.g., sidekick). When not nested, the flag is an empty string and tmux uses its default socket.

### VimResized autocmd

A module-level `VimResized` autocmd recalculates the float's dimensions and position when the terminal is resized. This fires even when no Periscope is open (it checks `state.win` validity first and no-ops).

### Keybinds placement

The two global keymaps (`<leader>tp`, `<leader>tP`) are appended to `lua/keymaps.lua` rather than placed inside the module. This follows the existing convention in the config where all leader keymaps live in `keymaps.lua`. Buffer-local keymaps (`q`, `<C-f>`, `<C-r>`) are set inside `create_float()` and scoped to the periscope buffer.

### No new dependencies

Only uses `baleia.nvim` (already installed) and `tmux` (already the user's multiplexer). No additional plugins or external tools required.

## Config Defaults

| Setting | Value | Rationale |
|---------|-------|-----------|
| `width_ratio` | 0.4 | ~40% of editor width — wide enough for logs |
| `height_ratio` | 0.35 | ~35% of editor height — compact PiP feel |
| `border` | `"rounded"` | Matches common nvim float style |
| `refresh_ms` | 500 | Balance between responsiveness and CPU usage |
| `max_lines` | 1000 | Unused in Mode A but present for future Mode B |
| `winblend` | 10 | Slight transparency so code behind is visible |

## Known Limitations / Future Work

- **Single instance only** — no multi-pane dashboard yet (spec's "Future Enhancement #1")
- **baleia.once() runs every tick** — could be optimized by hashing buffer content and skipping if unchanged
- **No configurable position** — anchored bottom-right only; could add `"SE"/"SW"/"NE"/"NW"` config
- **Refresh rate is fixed** — could be adaptive (slow down when content is static)
