# sidekick-summary

A small tool that reports on the **running [sidekick.nvim](https://github.com/folke/sidekick.nvim)
CLI sessions** configured in `~/.config/nvim/lua/plugins/sidekick.lua` — the
`claude` / `claudeB` / `claudeC` variants and the `neovim` scratch/markdown tool.

It captures each session's tmux pane and reads its transcript to show — at a
glance — what every session was tasked with, how far it got, and whether it's
working or waiting on you, in an interactive, vim-like TUI where you can **jump
straight to** or **kill** any session. A headless **Haiku** can polish those
summaries on demand, but it never runs on its own.

The TUI has **two views** of the same sessions:

- **proxy** (default) — non-LLM info built from data we already have (liveness +
  the transcript's last user/assistant messages). It **auto-refreshes every 10s**
  (with a countdown in the header) and on demand with `r`. No LLM involved.
- **haiku** — the last Haiku summary, fetched **manually** with `s` (Haiku never
  runs on its own). Press `v` to toggle into it; the proxy view is never replaced.

Once a Haiku summary exists, its (5–10 word) **blurbs are sticky**: they're shown
in the list — and the detail header — in *both* views, surviving the 10s proxy
refreshes, and only change when you fetch a new summary with `s`.

The list is **grouped by git repo** (`▌`, aqua), and within a repo by **worktree**
(`▸`, grey) — the primary checkout as `Main Repo` and each linked worktree by its
branch. All of a repo's worktrees share one object store, so they're detected via
`git rev-parse --git-common-dir` and grouped under the same repo even though each
worktree is a separate cwd. A cwd that isn't in a git repo is shown as a flat
group.

```
 Sidekick Sessions · live · next refresh 12s · summarizing /
▌ ~/repos/biofinder                               │ Claude A
  ▸ Main Repo                                      │ tmux: claude 176d2ddf2d    [$49]
    *WAIT Claude A   Scaffold integration-API test │ cwd:  ~/.worktrees/biofinder-graphql
    *WAIT Claude env Build graphify knowledge graph│ state: WORKING   ·   Wire GraphQL resolver…
  ▸ graphql                                        │ ──────────────────────────────────────────
     WORK Claude A   Wire GraphQL resolver + tests │ WHAT IT'S FOR …
  *WAIT Claude A  Tasks-plugin CLAUDE.md doc       │ WHAT IT'S FOR …
                                      │ Fixed an issue where launching Claude inside …
 j/k ⏎jump l detail · s summarize v view(proxy→haiku) · r refresh x kill / filter q quit
```

## Quick start

```sh
~/repos/summary/sidekick-summary      # open the live TUI (non-LLM; auto-refreshes every 10s)
```

Other invocations:

| Command | What it does |
| --- | --- |
| `sidekick-summary` | Open the live TUI: instant non-LLM view, auto-refreshing every 10s (default). |
| `sidekick-summary --refresh SECONDS` | Set the auto-refresh interval (default 10, min 1). |
| `sidekick_summary.py --refresh-only` | Produce a full Haiku report and print the JSON path; no TUI. |
| `sidekick_summary.py --json PATH` | Open an existing report in the TUI (static — no live refresh, no Haiku). |
| `sk_tui.py PATH` | View any report JSON directly, statically (standalone). |

## TUI keys

**List mode**

| Key | Action |
| --- | --- |
| `j` / `k` / ↓ / ↑ | move selection |
| `gg` / `G` | jump to top / bottom |
| `Ctrl-d` / `Ctrl-u` | half-page down / up |
| `Enter` | **jump** to that tmux session (`tmux switch-client`, or `attach` if outside tmux). The summary stays running in its own pane so you can switch right back to it. |
| `l` / `Tab` | open the detail pane fullscreen |
| `x` | **kill** the session — opens a confirmation box; you must type `delete` |
| `/` | filter the list (Enter keeps, Esc clears) |
| `r` | refresh the **non-LLM** info now (also auto-runs every 10s) |
| `s` | fetch a **Haiku summary** (manual; runs in the background) |
| `v` | toggle between the **proxy** and **haiku** views |
| `y` | **copy** the selected session's Claude session id to the clipboard |
| `H` | **former sessions** — graveyard of closed claude sessions (see below) |
| `q` / `Esc` | quit |

**Detail mode** (`l`/`Tab` from the list): `j`/`k` scroll, `h`/`Esc`/`Tab` back, `Enter` jump, `y` copy id, `q` quit.

**Former sessions** (`H`): a "graveyard" view of claude sessions that were tracked
and then disappeared — whether killed via `x` or **externally** (detected by
diffing successive refreshes). The list is **grouped by the day each session was
last alive** (`Today` / `Yesterday` / weekday+date); each row shows the last-seen
state/label/blurb/cwd, and the detail pane shows its stored data (Claude session
id, last `RECAP`, purpose, latest response, …). `y` copies the id here too — feed
it to the `claude_resume` / `claude_env_resume` sidekick tools (defined in
`sidekick.lua`), which launch `claude --resume <clipboard id>`. `H`/`Esc` returns.

The graveyard **persists across launches** in `history.json` (next to the script):
it records every claude session keyed by tmux session name (UUID shown/copied when
known), written on each refresh and on kill, capped to the 2000 most recent.
`x`-kills appear immediately; sessions killed **externally** appear after the next
refresh (≤10s, or press `r`). Resuming a killed session with `claude_resume`
(same Claude UUID) hides its former entry while the resume is running, and entries
are deduped by UUID — so kill→resume→kill won't pile up duplicates.

State is color-coded — `WORK` (green), `WAIT` (yellow), `ATTN` (red), with aqua
section headers — and rows that are waiting on you or need attention are flagged
with a leading `*`. Colors use the **Everforest (light, medium)** palette (the
same one as `~/.tmux.conf`), mapped to the nearest standard xterm-256 index so
they render consistently through tmux without relying on palette redefinition.

## Files

| File | Role |
| --- | --- |
| `sidekick-summary` | Thin launcher → runs `sidekick_summary.py`. |
| `sidekick_summary.py` | **Data layer.** Discovers sessions, captures panes, reads transcripts, builds the instant provisional report + the background Haiku job, launches the TUI. |
| `sk_tui.py` | **Presentation.** A dependency-free `curses` modal TUI; runs the Haiku job in a background thread and live-updates when it returns. |
| `prompt.txt` | The Haiku instructions (analysis only → JSON). |
| `YYYY/MM/DD/HH-MM-SS.json` | Canonical report (consumed by the TUI). |
| `YYYY/MM/DD/HH-MM-SS.md` | Human-readable archive of the same report. |
| `history.json` | Persisted former-sessions graveyard (read on launch, written live). |

## How it works

1. **Discover.** The tool list is read **straight from `sidekick.lua`** each
   refresh (`load_tools()` parses `cli.tools`), so tools you add later — e.g.
   `claude_env` — show up automatically with no edits here. Each tool is
   classified as `claude` (runs the claude binary → has a `~/.claude`
   transcript), `editor` (the nvim scratch buffer), or `cli` (any other tool,
   screen-only). sidekick names each tmux session `"<tool> <sha256(cwd) prefix>"`
   (see sidekick `cli/session/init.lua`), so `discover_sessions()` matches each
   pane's session-name prefix against that tool list, grabs its `session_id` /
   `pane_id` / `cwd`, and skips the pane the tool itself is running in.
   (Override the config path with the `SIDEKICK_LUA` env var.)
2. **Capture + liveness + state.** Each pane is captured twice ~0.4s apart; a
   change means `active` (→ WORKING), no change means `idle`. Idle panes are then
   checked for a blocking prompt in their bottom interactive region (Claude's
   `❯ 1.`-style choice menu, or a `(y/n)`/"proceed?" confirmation) → those become
   **NEEDS_ATTENTION**, the rest **WAITING_ON_USER**. So WORK / WAIT / ATTN are
   all derived deterministically each refresh, without the LLM.
3. **Transcripts.** For Claude sessions it reads the tail of the
   `~/.claude/projects/<encoded-cwd>/*.jsonl` conversation — a far more accurate
   source for "what it was asked / how far it got" than scraping the TUI. With
   one session per cwd it uses the newest file; when **several claude sessions
   share a cwd** (e.g. `claude` + `claude_env` in the same repo) it disambiguates
   by matching each pane's on-screen text against the candidate transcripts'
   content. A session with no matching transcript (e.g. one running inside a
   container that doesn't write to the host `~/.claude`) falls back to its screen.
   It also extracts the latest **recap** — Claude Code's `system`/`away_summary`
   entry (shown in the TUI as `※ recap: …`), generated periodically (e.g. when
   you return after being away), not every turn — which is rendered as the first
   `RECAP` section of the detail in both views (screen fallback for container
   sessions). A trailing "Next…" sentence in the recap is split out into a
   `↳ NEXT` sub-header.
4. **Proxy report (instant, no LLM).** `make_provisional()` fills *every* field
   from data already in hand — `state` from the liveness signal, `summary_line`/
   `purpose`/`blurb` from the transcript's last user message, `latest` from the
   last assistant message, `progress` from recent tool activity. The TUI opens on
   this immediately and **re-fetches it every 10s** (a background `proxy_job`)
   plus on demand with `r`. No file is written for proxy refreshes.
5. **Haiku summary (manual).** `s` runs `summarize_job` in a daemon thread:
   collect fresh, send the screen dumps + liveness flags + transcript tails to
   `claude -p … --model haiku` with **no tools**, merge the JSON with the
   locally-known identity fields (so `session_id` can never be hallucinated),
   and write the dated `.json` + `.md` archive. It returns a *snapshot* payload.
6. **Two views.** The proxy view is the default and is never replaced; `v`
   toggles to the last Haiku snapshot. The header shows `live · next refresh Ns`,
   a `summarizing …` spinner while `s` is running, and `haiku summary <time>`
   when viewing a snapshot.
7. **Present.** `Enter` jumps and `x` kills by `session_id`. Killed sessions are
   remembered (the `sessions` property filters them from *both* views), so a
   later refresh or in-flight summary can't resurrect them.

### Report schema

```jsonc
{
  "generated_at": "2026-06-02 18:20:45 EDT",
  "pending_analysis": false,               // true in the provisional payload, false once Haiku lands
  "sessions": [
    {
      "label": "Claude A",                 // or Claude B/C, Scratch/Markdown (neovim)
      "tool": "claude",
      "session_name": "claude 176d2ddf2d",
      "session_id": "$49",                 // space-free tmux id used for jump/kill
      "claude_session_id": "be918bf7-…",   // Claude Code session UUID (transcript filename)
      "pane_id": "%193",
      "cwd": "/home/txl25/.config/nvim",
      "sidekick_tool": "claude",           // SIDEKICK_TOOL env cross-check
      "state": "WAITING_ON_USER",          // WORKING | WAITING_ON_USER | NEEDS_ATTENTION
      "blurb": "Strip Bedrock env var inside biofinder container",  // 5-10 word list label; sticky across proxy refreshes
      "summary_line": "…",                 // one-line assignment + progress (Summary section)
      "purpose": "…",                      // what the session is for
      "progress": "…",                     // how far it has gotten
      "waiting_on": "…",                   // where it left off / what it needs (empty if WORKING)
      "latest": "…",                       // Haiku's summary of its most recent response
      "latest_full": "…"                   // the verbatim last response (shown as "LATEST RESPONSE (FULL)")
    }
  ]
}
```

The detail pane renders `purpose` / `progress` / `waiting_on` / `latest` /
`latest_full` as separate headered sections (the full last response is shown
only once Haiku's summary differs from it). The decoupled JSON is intentionally UI-agnostic: a
future neovim/snacks picker can read the exact same report.

## tmux status bar integration

While the live TUI is open it publishes agent counts to three tmux user options,
which `~/.tmux.conf` shows on the right of the status bar
(`… attn │ … wait │ … work │ … vim │ …`):

- `@sk_attn` — sessions blocked on you (a choice/confirmation prompt)
- `@sk_wait` — sessions that have finished their turn and are idle
- `@sk_work` — sessions actively working

(Counts exclude the neovim scratch buffer.) They're refreshed on every proxy
update (~10s) and on kill, and set to `x` when the app exits — so `x wait` means
no summary app is currently tracking. The config seeds all three to `x` and
renders them with `#{@sk_attn}` / `#{@sk_wait}` / `#{@sk_work}` (no file, no
polling). If several apps run, the last to update wins; a closing one writes `x`
and a survivor overwrites with real counts within ~10s.

## Requirements

- `tmux` with running sidekick sessions
- `claude` CLI on `PATH` (Haiku access)
- Python 3 (stdlib only — `curses`; no pip installs)

## Notes

- Run the TUI from a normal tmux client (not a popup) so `Enter`'s
  `switch-client` lands on the target session.
- The proxy view (default) is **free** — no LLM — and refreshes itself every 10s.
  Only `s` spends a Haiku call; navigation and `r` never do.
- The `s` summary is a snapshot: it won't change as the proxy auto-refreshes
  underneath it. Press `s` again for a fresh one.
- Killing a session runs `tmux kill-session`, ending that session and the agent
  process inside it — hence the typed-`delete` confirmation.
- The `RECAP` section comes from Claude Code's native "away" recap, which only
  generates while the claude pane is *unfocused*. When you view claude through
  the sidekick float, a small focus bridge in `~/.config/nvim/lua/plugins/sidekick.lua`
  forwards a focus-out/in to the claude pane as you toggle/leave the float, so
  the recap actually fires and shows up here while you're away. Requires tmux
  `focus-events on` (set in `~/.tmux.conf`).
