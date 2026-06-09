# CLAUDE.md — sidekick-summary

A tool that summarizes the **running sidekick.nvim CLI sessions** (Claude/agent
sessions living in tmux panes) in an interactive, vim-like curses TUI. See
`README.md` for the user-facing guide; this file is for working on the code.

Python 3 stdlib only (no pip installs). Not a git repo. Run `python3 -m
py_compile sidekick_summary.py sk_tui.py` after edits.

## Files

| File | Role |
| --- | --- |
| `sidekick-summary` | Thin bash launcher → `sidekick_summary.py`. |
| `sidekick_summary.py` | **Data layer.** Discovery, capture, transcripts, recap, Haiku call, JSON payloads, dated archive. No curses. |
| `sk_tui.py` | **Presentation.** Dependency-free `curses` TUI over a payload dict. Background jobs, tmux status, clipboard. |
| `prompt.txt` | Haiku instructions (analysis → JSON only; no tools). |
| `YYYY/MM/DD/HH-MM-SS.{json,md}` | Dated report archive (json is canonical; md is human-readable). |
| `history.json` | Persisted former-sessions graveyard (loaded on launch, written live). |

## Architecture / data flow

1. **Discover** (`discover_sessions`): `tmux list-panes -a`, keep panes whose
   session-name prefix is a tool from the config (see below). Skip the tool's
   own pane (`$TMUX_PANE`). Target panes by `pane_id` (`%nn`), never by session
   name (names contain spaces). **One entry per `session_name`** — a sidekick
   tmux session is a single agent, but may transiently carry an extra pane (e.g.
   a leftover shell from the resume wrapper), so panes are collapsed by
   session_name, keeping the **active** pane (the one running the agent;
   first-seen wins on a tie). Without this, a multi-pane session is listed twice.
   Each session dict carries identity + `repo_group`/`subgroup` (grouping) +
   `kind`.
2. **Collect** (`collect`): per pane, `liveness` (double-capture ~0.4s apart),
   `screen` capture, and — for `kind=="claude"` — the resolved transcript's
   parts + `recap` + `claude_session_id`.
3. **Provisional payload** (`make_provisional`): fills *every* field from
   non-LLM data so the TUI is useful instantly. `pending_analysis: true`.
4. **Haiku payload** (`analyze_payload`): `claude -p … --model haiku` with
   **no tools**, returns JSON; merged with the bash-known identity fields so
   `session_id`/`claude_session_id` can never be hallucinated.
5. **TUI** (`sk_tui.run`): opens on the provisional payload, runs jobs in
   daemon threads, renders, handles keys.

The payload `sessions[]` is the contract between the two halves (a future
neovim/snacks picker could read the same JSON). Fields: identity
(`label,tool,kind,session_name,session_id,claude_session_id,pane_id,cwd,
repo_group,subgroup`), state (`state`), and analysis (`blurb,summary_line,
purpose,progress,waiting_on,latest,latest_full,recap`).

## Two views (don't conflate)

- **proxy** (default): non-LLM info, **auto-refreshes every 10s** (overridable via
  `--refresh SECONDS` → `run(refresh_secs=…)`, min 1) + on `r`.
- **haiku**: the last *manual* summary (`s`), a snapshot; `v` toggles to it.
  Haiku **never runs automatically.** The proxy view is never replaced.
- **Sticky blurbs**: once a Haiku summary exists, its blurbs are shown in the
  list/detail in *both* views (`App.haiku_blurbs`) and only change on a new `s`.
- **Former-sessions graveyard** (`H`): `App.history_store` maps **tmux
  session_name** → last-seen snapshot (`_record`/`_record_history`, stores the
  *displayed* blurb + a `last_seen` timestamp); keyed by name (stable) not UUID, so it
  records **all** claude-kind sessions — the Claude UUID is just a field, shown/
  copied when resolved. `_dead_sessions()` = recorded sessions whose slot
  (session_name) isn't live AND whose UUID isn't live, deduped by UUID to the
  newest. "live" **excludes `killed_ids`** (so an `x`-kill — which also calls
  `_record` — shows immediately, before the proxy refresh drops it). The UUID
  checks handle **resume**: `claude_resume` runs the same UUID under a different
  session_name, so while it's alive the original killed entry is hidden, and a
  kill→resume→kill cycle collapses to a single entry. External kills appear after
  the next refresh (proxy diff). In history mode the
  list/detail show snapshots; `current()` returns the selected dead snapshot so
  `y` works; jump/kill/summarize/filter/`v` are disabled there. **Persisted** to
  `history.json` (`HISTORY_FILE`, next to the script): `_load_history` on launch
  (live only), `_save_history` on each record + on kill, capped to 2000 newest by
  `last_seen`. The history list is **grouped by day** via `_day_label(last_seen)`
  (Today/Yesterday/weekday+date) and, *within each day*, **subgrouped by repo
  group → worktree subgroup** like the live list. `_dead_sessions()` returns the
  snapshots already in this display order (newest day first; within a day,
  clusters ordered by their most-recent member), so `self.sel` indexes it
  directly and `j`/`k` move linearly; `_history_rows` is then a single
  header-inserting pass (mirrors `_list_rows`).

## Key decisions (preserve these)

- **State is deterministic, no LLM needed**: `liveness` double-capture decides
  WORKING vs idle (authoritative); idle panes are checked for a blocking
  choice/confirmation prompt **only in the bottom ~10 lines** (`_looks_attention`)
  → NEEDS_ATTENTION vs WAITING_ON_USER. Bottom-region only = avoids matching
  menu-like text in scrollback.
- **Tool list is read from `~/.config/nvim/lua/plugins/sidekick.lua`** each
  refresh (`load_tools`, parses `cli.tools`), so new tools (e.g. `claude_env`,
  `claude_resume`) appear automatically. Classified `claude` (→ has a `~/.claude`
  transcript), `editor` (nvim scratch), or `cli`. Classification: name starts with
  `claude` **or** the cmd body contains a literal `"claude"` → claude (the name
  rule matters because some cmds are built by a helper fn, so `"claude"` isn't in
  the tool's body); `neovim`/`"nvim"` → editor; else cli. Override path with
  `SIDEKICK_LUA`. Falls back to `DEFAULT_TOOLS` if unparseable.
- **Transcripts**: `~/.claude/projects/<cwd with / and . → ->/*.jsonl`. One
  session per cwd → newest file. **Multiple claude sessions in one cwd**
  (worktrees, claude+claude_env) → disambiguate by matching each pane's on-screen
  text against candidate transcripts (`_match_by_content`); no match → screen
  fallback (e.g. containerized `claude_env` writing to a non-host `~/.claude`).
- **Recap** = Claude Code's `type:system, subtype:away_summary` entry (shown in
  TUI as `※ recap:`). Periodic (idle+unfocused ≥3min), not per-turn. Extracted
  as the first `RECAP` detail section; screen fallback strips `(disable recaps…)`.
  Its trailing "Next…" segue is split out by `_split_recap` and shown under a
  `↳ NEXT` sub-header — see "Recap 'Next' parsing" below.
- **Stale recap suppression**: a recap describes an *idle moment*, so once you've
  moved on past it, it's just confusing. `_parse_transcript_file` records the last
  `away_summary`'s line index and **drops the recap (→ "") if a genuine user
  prompt appears after it** in the transcript (`_is_user_prompt`: `type:user` with
  real text — not a `tool_result`, which is also `type:user`, nor an `isMeta`
  entry). Deterministic, no LLM. Consequence in `collect()`: when a host
  transcript exists its recap is trusted verbatim (incl. an empty/stale one), and
  the on-screen `※ recap:` fallback (`_recap_from_screen`) is used **only when
  there's no transcript at all** — otherwise it would resurrect the suppressed
  recap from the still-visible screen line. Refreshes with the proxy (10s / `r`).

### Recap "Next" parsing (extensible)

`_split_recap(recap)` (sk_tui.py) separates the recap body from its trailing
"next steps" segue. Recap phrasing varies a lot, so the recognized segues live in
the tuple **`_NEXT_SEGUES`** — *to support a new phrasing, add one regex there.*

Contract for each `_NEXT_SEGUES` pattern:
- matched case-insensitively against the whole recap;
- **group(1) must start exactly where the Next-section begins** — put the
  boundary chars (e.g. `. ` after a sentence, or `; ` mid-sentence) *outside* the
  group as a non-capturing prefix so they aren't shown;
- the match whose group starts **latest** in the recap wins (the segue is the tail).

After the split, the displayed NEXT text gets a leading "Next … :" label or a
bare "Next" + delimiter stripped; other segues (e.g. "next action is yours…")
show verbatim. Handled so far: `Next:` / `Next steps:` / `Next, …` (sentence
start), and casual `; next action|step|up …`. Add more as recaps reveal them; the
unit cases in this session's history are a good regression set.
- **Grouping**: by **main repo** (`git rev-parse --git-common-dir` → its parent),
  so all of a repo's worktrees group together; subgroup = `"Main Repo"` or the
  worktree branch. Non-git cwd → flat group.
- **Colors**: Everforest (light, medium), mapped to the **nearest standard
  xterm-256 index** (`_nearest_256`) — NOT `init_color` (palette redefinition is
  unreliable through tmux). WORK=green, WAIT=yellow, ATTN=red, headers=aqua.
- **Jump (`Enter`) stays resident**: inside tmux it `switch-client`s without
  tearing down curses, so the summary keeps running in its pane. After the switch
  (and on the outside-tmux `attach` fallback) it calls `_nudge_winch(sid)` to
  resize sandboxed Claude — see the sandbox note under "Related config" below.
- **Kill (`x`)** requires typing `delete`; killed ids are remembered
  (`killed_ids`) so an in-flight refresh/summary can't resurrect them.

## tmux integration

- **Status counts**: while live, publishes `@sk_attn`/`@sk_wait`/`@sk_work` tmux
  user options (`_set_status_counts`, agent sessions only — excludes editor),
  set to `x` on exit (try/finally). `~/.tmux.conf` seeds them to `x` and renders
  `#{@sk_attn} attn │ … wait │ … work` in `status-right`.
- **Clipboard** (`y`): `_copy_clipboard` prefers `tmux set-buffer -w` (rides
  `set-clipboard external` → kitty), then wl-copy/xclip/xsel/pbcopy.
- **Resize self-heal poll** (`_winch_poller`, daemon thread started in `run()`
  when live + helper installed): every `WINCH_POLL_SECS` (1s) it diffs each live
  claude pane's `WxH` (`_pane_sizes`, one `list-panes -a`) and `_nudge_winch`es any
  that changed — plus each newly-seen pane once. This exists because a sandboxed
  claude (`bwrap --new-session`, no controlling tty → no kernel SIGWINCH) renders
  at a stale size after a resize, and the `~/.tmux.conf` hooks only fire for a
  client's own terminal resize (`client-resized`) and a direct session switch
  (`client-session-changed`) — **NOT** tmux's *automatic* size recalculation
  (`window-size=latest`/`aggressive-resize` reflowing a session when its
  constraining client changes or detaches), for which tmux 3.6 fires no hook. The
  poll closes that gap. **Limit (inherent to SIGWINCH, not the poll):** it fixes
  the dynamic region (input box, active spinner, new output) and all rendering
  going forward, but cannot rewrap conversation history already committed to ink's
  `<Static>` region at the wrong width — that frozen scrollback stays garbled
  until claude emits new output. A winch to a correctly-sized claude is a harmless
  redraw, so over-firing (and the once-per-pane startup nudge) is safe.

## Related config OUTSIDE this project (don't forget when debugging recaps)

- `~/.config/nvim/lua/plugins/sidekick.lua` — **focus bridge** (in the `config`
  fn): forwards focus-out/in to the claude pane on sidekick WinLeave/WinEnter/
  Focus events, so Claude's away-recap fires when you toggle/leave the float.
  Also defines the **`claude_resume` / `claude_env_resume`** tools (via
  `claude_resume_wrap`), which run `claude --resume <clipboard id>` — i.e. the id
  copied with `y` here; `claude_env_resume` wraps it in biofinder's `env.sh` like
  `claude_env`. (These start with `claude`, so they classify as claude-kind.)
- `~/.tmux.conf` — `set -g focus-events on` (required for the above) + the
  `@sk_*` defaults and `status-right` sections.
- `~/.local/bin/srt-send-winch` (+ `~/.tmux.conf` resize hooks) — Claude run under
  the `srt` sandbox is launched with `bwrap --new-session`, which detaches it from
  the controlling tty so the kernel never delivers SIGWINCH on resize; it then
  renders at a stale size. Jumping here resizes the target session's panes, so
  `_jump` calls `_nudge_winch` (which runs that host helper) to re-send SIGWINCH.
  The full story + the tmux hooks and the sidekick.lua float-toggle nudge live in
  `~/.sandbox/srt/CLAUDE.md`.

## TUI keys

`j/k gg/G ⌃d/⌃u` move · `Enter` jump (resident) · `l`/`Tab` detail · `s`
summarize (Haiku) · `v` toggle proxy/haiku · `y` copy Claude session id · `H`
former-sessions graveyard · `r` refresh proxy · `x` kill (type `delete`) · `/`
filter · `q`/`Esc` quit.

## Testing (no live TTY here)

- Logic: import modules, call functions, assert. (curses-independent code:
  `App` methods, parsing, grouping, detectors.)
- **Render**: run in a throwaway tmux session and capture —
  `tmux new-session -d -s t -x132 -y28 "python3 …/sidekick_summary.py"; sleep 2.5;
  tmux capture-pane -p -t t`. Add `-e` to capture ANSI (verify colors via
  `38;5;<idx>`). Send keys with `tmux send-keys -t t …`. Clean up with
  `tmux kill-session`.
- `--refresh-only` produces a full Haiku report and prints its path (no TUI).
- After dev, prune extra dated reports to one sample, and `rm -rf __pycache__`.

## Gotchas

- A `json_extensions` `.pth` traceback prints to stderr on every Python run
  here — it's a pre-existing environment quirk, unrelated to this code.
- Capturing/targeting panes: by `pane_id`, not session name (spaces).
- Don't send keystrokes to agent panes except the focus escapes / clipboard;
  the dump path is read-only by design.
