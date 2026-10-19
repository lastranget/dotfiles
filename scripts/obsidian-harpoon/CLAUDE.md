# obsidian-harpoon

Harpoon-style pinned-note list for the Obsidian vault at `~/vaults/Main`
(override with `$HARPOON_VAULT`). The whole tool is one bash script, `harpoon`.
Its usage text is the header comment at the top of the file. The `*)` case
prints that comment with `sed -n '2,19p'`, so update the range when the header
changes length.

## Files

- `harpoon`: the script (deps: `jq`, `fzf`, `nvim`)
- `harpoon.json`: user-pinned notes, a JSON array of vault-relative paths,
  newest first. Per machine and not tracked.

`harpoon` and this file are tracked in the dotfiles bare repo (`cfg` alias,
git dir `~/.cfg`, work tree `$HOME`). This directory is not its own git repo.
Branch `master` is shared. Branch `work` is `master` plus exactly one commit of
machine-specific tweaks. Commit shared changes to `master`, then rebase `work`.

## List layout

`cmd_ls` builds the list shown everywhere (`ls`, `numbered`, picker, `open N`):

1. `$EINK`: `work/fleeting/Work Eink Tasks.md`, the same file the `eink` alias
   opens. That alias in `~/.bash_aliases` hardcodes the path too, so change
   both together.
2. `weekly()`: this week's log (ISO `%G`/`%V`), always the one that nvim's
   `<leader>ow` opens.
3. and up: `stored()` entries from `harpoon.json`, minus anything equal to a pin.

The pins are computed, never stored. `rm` on a pin does nothing.

## Weekly-note coupling with nvim

- `$OBSIDIAN_OW` decides which log `<leader>ow` opens: `work` gives
  `work/weekly/`, anything else (or unset) gives `weekly/`. `<leader>oW` opens
  the other one. It is exported in `~/.bash_aliases`: `personal` on `master`,
  flipped to `work` by the single `work`-branch commit. It is read by
  `~/.config/nvim/lua/plugins/obsidian.lua` (`OW_IS_WORK`) and by `weekly()`
  here. An nvim that isn't started from bash doesn't see it and falls back to
  personal.
- `weekly()` duplicates the path logic of `open_weekly()` in obsidian.lua.
  Keep the two in sync.
- `open_files()` never opens the weekly path directly. It runs
  `nvim -c ObsOwWeekly` instead, so a missing note gets created from its
  template, back-linked to the newest earlier weekly note. `ObsOwWeekly` is in the
  lazy.nvim spec's `cmd` so it loads obsidian.nvim even when no markdown file
  is open.

## Aliases (`~/.bash_aliases`)

- `h`: picker (`harpoon open`)
- `ha`: add notes (`harpoon add`)
- `h1`..`h9`, `h0`: `harpoon open N`, opens entry N without the picker
  (1-based; `0` means entry 10, matching the picker's 1-9,0 keys)

## Testing

Safe, with no nvim launched: `./harpoon ls`, `./harpoon numbered`,
`OBSIDIAN_OW=personal ./harpoon ls`. To test the nvim side headless:
`nvim --headless -c ObsOwWeekly -c 'lua io.stdout:write(vim.fn.expand("%:p"))' -c 'qa!'`.
This creates this week's note if it doesn't exist yet.
