#!/usr/bin/env python3
"""sk_tui.py — a dependency-free, vim-like modal TUI over a sidekick summary JSON.

Reads the JSON produced by sidekick_summary.py and presents:
  - a left list of sessions (one line each, colored by state), and
  - a live right detail pane for the highlighted session.

There are two views of the same sessions: the default **proxy** view (non-LLM
info — liveness + the transcript's last messages, auto-refreshed every 10s) and
a **haiku** view (the last manually-fetched Haiku summary). Haiku never runs
automatically.

Keys (LIST mode):
  j / k / ↓ / ↑   move selection            gg / G        top / bottom
  Ctrl-d / Ctrl-u half-page down / up       /             filter (Enter/Esc end)
  Enter           jump to that tmux session l / Tab       fullscreen detail
  x               kill session (type 'delete' to confirm)
  r               refresh non-LLM info      s             fetch Haiku summary
  v               toggle proxy / haiku view y             copy Claude session id
  H               former sessions (graveyard of closed claude sessions; y works there)
  q / Esc         quit
Keys (DETAIL mode):
  j / k           scroll detail             h / Esc / Tab back to list
  Enter           jump                      q             quit

Run standalone:  python3 sk_tui.py path/to/report.json   (static, no live refresh)
"""
from __future__ import annotations

import curses
import datetime
import json
import os
import queue
import re
import subprocess
import sys
import textwrap
import threading
import time
from pathlib import Path

STATE_TAG = {"WORKING": "WORK", "WAITING_ON_USER": "WAIT", "NEEDS_ATTENTION": "ATTN"}
STATE_BELL = {"WAITING_ON_USER", "NEEDS_ATTENTION"}
CP = {"WORKING": 1, "WAITING_ON_USER": 2, "NEEDS_ATTENTION": 3}  # color pair ids
HEADER_CP = 4  # detail section headers + repo group headers (aqua)
SUB_CP = 5     # worktree subgroup headers (grey)
SPINNER = "|/-\\"

# Everforest (light, medium) palette — https://github.com/sainnhe/everforest
# Kept in sync with the @everforest_* vars in ~/.tmux.conf.
EVERFOREST = {
    "red": "#f85552", "orange": "#f57d26", "yellow": "#dfa000",
    "green": "#8da101", "aqua": "#35a77c", "grey": "#939f91",
}
STATE_COLOR = {"WORKING": "green", "WAITING_ON_USER": "yellow",
               "NEEDS_ATTENTION": "red"}
_ANSI_FALLBACK = {"red": curses.COLOR_RED, "orange": curses.COLOR_YELLOW,
                  "yellow": curses.COLOR_YELLOW, "green": curses.COLOR_GREEN,
                  "aqua": curses.COLOR_CYAN, "grey": curses.COLOR_WHITE}
_CUBE = (0, 95, 135, 175, 215, 255)  # xterm-256 color-cube levels


def _nearest_256(hexv: str) -> int:
    """Closest xterm-256 index (cube 16-231 + greyscale 232-255) to a hex color."""
    r, g, b = (int(hexv[i:i + 2], 16) for i in (1, 3, 5))
    best, bestd = 16, 1 << 30
    for i, rl in enumerate(_CUBE):
        for j, gl in enumerate(_CUBE):
            for k, bl in enumerate(_CUBE):
                d = (rl - r) ** 2 + (gl - g) ** 2 + (bl - b) ** 2
                if d < bestd:
                    bestd, best = d, 16 + 36 * i + 6 * j + k
    for s in range(24):
        v = 8 + 10 * s
        d = (v - r) ** 2 + (v - g) ** 2 + (v - b) ** 2
        if d < bestd:
            bestd, best = d, 232 + s
    return best


def _color_resolver():
    """name -> curses color number for the everforest palette.

    Uses the nearest *standard* xterm-256 index (cube/greyscale) rather than
    redefining palette slots via init_color: those fixed indices always render
    the intended hue, whereas init_color redefinitions are unreliable through a
    tmux + terminal stack (they can silently fall back to a grey slot). Drops to
    basic ANSI on a <256-color terminal."""
    use256 = curses.COLORS >= 256
    cache: dict[str, int] = {}

    def resolve(name: str) -> int:
        if name not in cache:
            cache[name] = (_nearest_256(EVERFOREST[name]) if use256
                           else _ANSI_FALLBACK[name])
        return cache[name]

    return resolve
SK_ATTN_OPT = "@sk_attn"   # tmux user options read by the status bar
SK_WAIT_OPT = "@sk_wait"
SK_WORK_OPT = "@sk_work"
HISTORY_FILE = Path(__file__).resolve().parent / "history.json"  # persisted graveyard


def _short_cwd(cwd: str) -> str:
    home = str(Path.home())
    return "~" + cwd[len(home):] if cwd.startswith(home) else cwd


# Segues that introduce the "next steps" part of a recap. Each is a regex matched
# case-insensitively against the whole recap; its FIRST GROUP must start exactly
# where the Next-section begins (the boundary chars before it are matched but not
# captured). The match whose group starts LATEST in the recap wins (the
# Next-section is normally the tail). To support a new recap phrasing, just add a
# pattern here — see CLAUDE.md › "Recap 'Next' parsing" for the contract.
_NEXT_SEGUES = (
    r"(?:^|[.!?]\s+)(Next\b)",            # "Next: …" / "Next steps: …" / "Next, …" (sentence start)
    r"(?:[;,.]\s+)(next action\b)",        # casual: "…; next action is yours, …"
    r"(?:[;,.]\s+)(next step\b)",          # casual: "…, next step is …"
    r"(?:[;,.]\s+)(next up\b)",            # casual: "…; next up …"
)


def _split_recap(recap: str) -> tuple[str, str]:
    """Split a recap into (body, next_step).

    Claude's recaps usually end with a "next steps" segue (e.g. "Next: …",
    "Next steps: …", or a casual "…; next action is yours…"). Pull that trailing
    segment out so it can be shown under its own sub-header. The set of recognized
    segues is `_NEXT_SEGUES` (extensible). Returns (recap, "") when there's no
    segue, or when the whole recap is the Next statement."""
    recap = (recap or "").strip()
    if not recap:
        return "", ""
    best = -1
    for pat in _NEXT_SEGUES:
        for m in re.finditer(pat, recap, re.IGNORECASE):
            best = max(best, m.start(1))
    if best <= 0:                         # no segue, or it's at the very start
        return recap, ""
    body = recap[:best].rstrip(" ;,")     # drop the trailing clause separator
    if not body:
        return recap, ""
    nxt = recap[best:].strip()
    # drop a leading "Next … :" label (the sub-header already says NEXT); else, if
    # "Next" is followed by a bare delimiter ("Next," / "Next —"), drop that too;
    # otherwise (e.g. "next action is yours…") keep the segue text verbatim.
    stripped = re.sub(r"^Next\b[^:.!?\n]{0,40}:\s*", "", nxt, flags=re.IGNORECASE)
    if stripped == nxt:
        stripped = re.sub(r"^Next\b\s*[,;:–—-]\s*", "", nxt, flags=re.IGNORECASE)
    return body, (stripped.strip() or nxt)


def _copy_clipboard(text: str) -> bool:
    """Copy text to the system clipboard. Prefers `tmux set-buffer -w` (rides the
    user's set-clipboard → terminal passthrough), then wl-copy/xclip/xsel/pbcopy."""
    if os.environ.get("TMUX"):
        if subprocess.run(["tmux", "set-buffer", "-w", text],
                          capture_output=True).returncode == 0:
            return True
    for cmd in (["wl-copy"], ["xclip", "-selection", "clipboard"],
                ["xsel", "-ib"], ["pbcopy"]):
        try:
            if subprocess.run(cmd, input=text, text=True,
                              capture_output=True).returncode == 0:
                return True
        except OSError:
            continue
    return False


def _set_status_counts(attn, wait, work):
    """Publish the attention/waiting/working counts to tmux user options for the
    status bar (no-op outside tmux). Pass 'x' to indicate 'not being tracked'."""
    if not os.environ.get("TMUX"):
        return
    try:
        subprocess.run(["tmux", "set", "-g", SK_ATTN_OPT, str(attn),
                        ";", "set", "-g", SK_WAIT_OPT, str(wait),
                        ";", "set", "-g", SK_WORK_OPT, str(work)],
                       capture_output=True)
    except OSError:
        pass


# Host-side helper that re-sends SIGWINCH to sandboxed Claude sessions.
SRT_SEND_WINCH = os.path.expanduser("~/.local/bin/srt-send-winch")


def _nudge_winch(target: str):
    """Tell a sandboxed (srt/bubblewrap) Claude in tmux session `target` to
    re-read its terminal size.

    srt runs claude under `bwrap --new-session`, detaching it from the
    controlling tty, so the kernel never delivers SIGWINCH to it on resize.
    Jumping (switch-client / attach) resizes the target session's panes, but the
    detached claude keeps rendering at its old size until nudged. The host helper
    walks the session's pane process trees and signals any claude. Fire-and-
    forget; a no-op if the helper isn't installed or the session has no sandboxed
    claude. (The tmux client-session-changed hook also covers the switch-client
    path, but calling it here makes the jump self-sufficient and also catches the
    outside-tmux attach path that the hook doesn't fire for.)"""
    if not target or not os.access(SRT_SEND_WINCH, os.X_OK):
        return
    try:
        subprocess.Popen([SRT_SEND_WINCH, "-s", target],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


WINCH_POLL_SECS = 1.0  # how often to check claude pane sizes for an un-nudged resize


def _pane_sizes() -> dict[str, str]:
    """{pane_id: 'WxH'} for every tmux pane, via one cheap list-panes call."""
    try:
        out = subprocess.run(
            ["tmux", "list-panes", "-a", "-F", "#{pane_id} #{pane_width}x#{pane_height}"],
            capture_output=True, text=True).stdout
    except OSError:
        return {}
    sizes = {}
    for line in out.splitlines():
        pid, _, wh = line.partition(" ")
        if pid and wh:
            sizes[pid] = wh
    return sizes


def _winch_poller(app: "App", interval: float = WINCH_POLL_SECS):
    """Re-SIGWINCH sandboxed claude panes whose tmux size changed (daemon thread).

    srt's `bwrap --new-session` detaches claude from its controlling tty, so the
    kernel never delivers SIGWINCH on resize and it renders at a stale size until
    nudged. The ~/.tmux.conf hooks (client-resized / client-session-changed) cover
    a terminal resize and a *direct* session switch, but NOT tmux's automatic size
    recalculation — with window-size=latest / aggressive-resize, a session reflows
    whenever its constraining client changes (another client becomes "latest", or
    a client detaches), and tmux 3.6 fires no hook for that. So claude garbles with
    nothing to nudge it. This poll closes that gap: it diffs each live claude pane's
    size and nudges any that changed — plus each newly-seen pane once, to heal a
    render that was already stale when the TUI launched. A winch to a correctly-
    sized claude is just a harmless redraw, so over-firing is safe."""
    seen: dict[str, str] = {}
    while True:
        time.sleep(interval)
        try:
            payload = app.proxy  # snapshot; set_proxy swaps in a new dict atomically
            targets = {s["pane_id"]: (s.get("session_id") or s["session_name"])
                       for s in payload.get("sessions", [])
                       if s.get("kind") == "claude" and s.get("pane_id")
                       and s["session_id"] not in app.killed_ids}
            if not targets:
                continue
            sizes = _pane_sizes()
            for pid, target in targets.items():
                cur = sizes.get(pid)
                if cur and seen.get(pid) != cur:
                    seen[pid] = cur
                    _nudge_winch(target)
        except Exception:  # noqa: BLE001 — a poll glitch must never kill the thread
            pass


class App:
    def __init__(self, proxy: dict, live: bool = True, haiku: dict | None = None):
        # Two views of the same sessions:
        #   proxy  — the non-LLM info (liveness + transcript), refreshed live.
        #   haiku  — the last manually-fetched Haiku summary (a snapshot).
        self.proxy = proxy
        self.haiku = haiku
        # Haiku blurbs are sticky: once a summary exists, its blurbs are shown in
        # BOTH views and only change when a new summary is fetched.
        self.haiku_blurbs: dict[str, str] = self._blurbs_from(haiku)
        self.view = "proxy"          # "proxy" | "haiku"
        self.live = live
        self.sel = 0
        self.mode = "list"          # "list" | "detail"
        self.detail_scroll = 0
        self.filter = ""
        self.filtering = False
        self.pending_g = False      # for the gg motion
        self.message = ""
        self.confirming_kill = False
        self.kill_input = ""
        self.kill_target: dict | None = None
        # async jobs / live refresh
        self.tick = 0               # spinner frame counter
        self.countdown = 0          # seconds until next auto proxy-refresh
        self.proxy_pending = False  # non-LLM refresh in flight
        self.haiku_pending = False  # Haiku summary in flight
        self.want_refresh = False   # 'r' — re-fetch proxy info
        self.want_summary = False   # 's' — fetch Haiku summary
        self.killed_ids: set[str] = set()
        # History "graveyard": tmux session_name -> last-seen snapshot, so we can
        # still surface the id + last data for sessions that vanished — whether we
        # killed them or they were killed externally (detected by diffing proxy).
        # Persisted to HISTORY_FILE so it survives across launches.
        self.history = False
        self.history_store: dict[str, dict] = {}
        if self.live:
            self._load_history()
        self._record_history()

    # -- active view ------------------------------------------------------- #
    def _active(self) -> dict:
        return self.haiku if (self.view == "haiku" and self.haiku) else self.proxy

    @property
    def sessions(self) -> list[dict]:
        active = self._active().get("sessions", [])
        return [s for s in active if s["session_id"] not in self.killed_ids]

    def _clamp(self):
        n = len(self.visible())
        self.sel = max(0, min(self.sel, n - 1))

    def set_proxy(self, payload: dict):
        self.proxy = payload
        if self.view == "proxy":
            self._clamp()
        self.push_counts()
        self._record_history()

    def _record(self, s: dict):
        """Snapshot one claude session into the graveyard, keyed by its stable
        tmux session name (the Claude UUID is kept as a field for display/copy but
        isn't always resolved). Stores the *displayed* blurb + a last-seen time
        (used to group/order the graveyard by the day a session was last alive)."""
        if s.get("kind") != "claude":
            return
        snap = dict(s)
        snap["blurb"] = self._blurb(s)
        snap["last_seen"] = time.time()
        self.history_store[s["session_name"]] = snap

    def _record_history(self):
        """Record every live claude session so its data survives after it's gone."""
        for s in self.proxy.get("sessions", []):
            self._record(s)
        if self.live:
            self._save_history()

    def _load_history(self):
        try:
            data = json.loads(HISTORY_FILE.read_text())
        except (OSError, ValueError):
            return
        for snap in data.get("sessions", []):
            name = snap.get("session_name")
            if name:
                self.history_store[name] = snap

    def _save_history(self):
        snaps = sorted(self.history_store.values(),
                       key=lambda s: s.get("last_seen", 0), reverse=True)[:2000]
        try:
            HISTORY_FILE.write_text(json.dumps({"version": 1, "sessions": snaps}, indent=2))
        except OSError:
            pass

    def _dead_sessions(self) -> list[dict]:
        """Former claude sessions, ordered for display: newest day first, and —
        within each day — clustered by repo group then worktree subgroup (so the
        graveyard nests like the live list), with each cluster ordered by its
        most-recent member. `self.sel` indexes this list directly, so this order
        is also the navigation order.

        A recorded session is excluded if its slot (session_name) is live, OR if
        its Claude UUID is currently live — e.g. you killed `claude <h>` and
        resumed it via `claude_resume` (a different session_name) which continues
        the same UUID; the original shouldn't show as dead while the resume runs.
        Entries sharing a UUID are collapsed to the most recent, so a
        kill→resume→kill cycle yields one entry, not several. (`killed_ids` is
        excluded from 'live' so an x-kill shows up before the next refresh.)"""
        live = [s for s in self.proxy.get("sessions", [])
                if s.get("kind") == "claude" and s["session_id"] not in self.killed_ids]
        present_names = {s["session_name"] for s in live}
        present_uuids = {s["claude_session_id"] for s in live if s.get("claude_session_id")}
        dead, seen_uuids = [], set()
        for snap in sorted(self.history_store.values(),
                           key=lambda s: s.get("last_seen", 0), reverse=True):
            uid = snap.get("claude_session_id")
            if snap.get("session_name") in present_names:
                continue
            if uid and uid in present_uuids:   # alive again (resumed elsewhere)
                continue
            if uid:
                if uid in seen_uuids:          # newer entry for this UUID already kept
                    continue
                seen_uuids.add(uid)
            dead.append(snap)
        # `dead` is newest-first, so days are already contiguous; cluster each
        # day's run by (group, sub) in an order-preserving pass (most-recent
        # cluster stays on top) and flatten back out.
        ordered, i = [], 0
        while i < len(dead):
            day = self._day_label(dead[i].get("last_seen"))
            run = []
            while i < len(dead) and self._day_label(dead[i].get("last_seen")) == day:
                run.append(dead[i])
                i += 1
            groups: dict = {}
            for s in run:
                groups.setdefault(s.get("repo_group", s["cwd"]), {}).setdefault(
                    s.get("subgroup"), []).append(s)
            for subs in groups.values():
                for members in subs.values():
                    ordered.extend(members)
        return ordered

    @staticmethod
    def _day_label(ts) -> str:
        """Friendly 'day killed' label from a last-seen epoch timestamp."""
        if not ts:
            return "Unknown date"
        d = datetime.date.fromtimestamp(ts)
        today = datetime.date.today()
        if d == today:
            return "Today"
        if d == today - datetime.timedelta(days=1):
            return "Yesterday"
        return d.strftime("%A %Y-%m-%d")

    def _proxy_sessions(self) -> list[dict]:
        return [s for s in self.proxy.get("sessions", [])
                if s["session_id"] not in self.killed_ids]

    def push_counts(self):
        """Publish attention/waiting/working counts to tmux. Counts agent
        sessions only (claude/cli) — the neovim scratch buffer is not an agent."""
        if not self.live:
            return
        sess = [s for s in self._proxy_sessions() if s.get("kind") != "editor"]
        attn = sum(1 for s in sess if s["state"] == "NEEDS_ATTENTION")
        work = sum(1 for s in sess if s["state"] == "WORKING")
        _set_status_counts(attn, len(sess) - attn - work, work)

    def set_haiku(self, payload: dict):
        self.haiku = payload
        self.haiku_blurbs = self._blurbs_from(payload)
        if self.view == "haiku":
            self._clamp()

    @staticmethod
    def _blurbs_from(payload) -> dict[str, str]:
        return {s["session_id"]: s["blurb"]
                for s in (payload or {}).get("sessions", []) if s.get("blurb")}

    def _blurb(self, s: dict) -> str:
        """The blurb to display: the sticky Haiku blurb if we have one, else the
        session's own (non-LLM) blurb."""
        return self.haiku_blurbs.get(s["session_id"]) or s.get("blurb", "")

    def toggle_view(self):
        if self.view == "proxy":
            if not self.haiku:
                self.message = " no summary yet — press s to generate "
                return
            self.view = "haiku"
        else:
            self.view = "proxy"
        self.mode = "list"
        self.detail_scroll = 0
        self._clamp()

    # -- filtering --------------------------------------------------------- #
    def visible(self) -> list[int]:
        sessions = self.sessions
        if not self.filter:
            return list(range(len(sessions)))
        f = self.filter.lower()
        return [i for i, s in enumerate(sessions)
                if f in f"{s['label']} {s['cwd']} {s['summary_line']}".lower()]

    def current(self):
        if self.history:
            dead = self._dead_sessions()
            if not dead:
                return None
            self.sel = max(0, min(self.sel, len(dead) - 1))
            return dead[self.sel]
        vis = self.visible()
        if not vis:
            return None
        self.sel = max(0, min(self.sel, len(vis) - 1))
        return self.sessions[vis[self.sel]]

    # -- drawing ----------------------------------------------------------- #
    def draw(self, stdscr):
        stdscr.erase()
        h, w = stdscr.getmaxyx()
        spin = SPINNER[self.tick % 4]
        gen = self._active().get("generated_at", "")
        if self.history:
            title = f" Former Claude sessions ({len(self._dead_sessions())}) · H/Esc to return "
        elif self.view == "haiku":
            title = " ".join([" Sidekick Sessions", f"· haiku summary {gen}"]) + " "
        else:
            parts = [" Sidekick Sessions", "· live"]
            if self.proxy_pending:
                parts.append(f"· refreshing {spin}")
            elif self.live:
                parts.append(f"· next refresh {self.countdown}s")
            if self.haiku_pending:
                parts.append(f"· summarizing {spin}")
            title = " ".join(parts) + " "
        stdscr.attron(curses.A_REVERSE)
        stdscr.addnstr(0, 0, title.ljust(w), w)
        stdscr.attroff(curses.A_REVERSE)

        body_h = h - 2
        if self.mode == "detail":
            self._draw_detail(stdscr, 1, 0, body_h, w, full=True)
        else:
            list_w = max(28, int(w * 0.52))
            if self.history:
                self._draw_history_list(stdscr, 1, 0, body_h, list_w)
            else:
                self._draw_list(stdscr, 1, 0, body_h, list_w)
            for y in range(1, 1 + body_h):
                self._safe(stdscr, y, list_w, "│")
            self._draw_detail(stdscr, 1, list_w + 2, body_h, w - list_w - 2, full=False)

        self._draw_footer(stdscr, h, w)
        if self.confirming_kill:
            self._draw_kill_box(stdscr, h, w)
        stdscr.refresh()

    def _list_rows(self, vis):
        """Interleave repo group headers and worktree subgroup headers with the
        selectable session rows.

        Returns ("group"|"sub"|"sess"|"blank", value) render rows; only "sess"
        rows are selectable (value = session index).
        """
        rows = []
        last_group = last_sub = None
        for vi in vis:
            s = self.sessions[vi]
            group = s.get("repo_group", s["cwd"])
            sub = s.get("subgroup")
            if group != last_group:
                if last_group is not None:
                    rows.append(("blank", ""))
                rows.append(("group", group))
                last_group, last_sub = group, None
            if sub and sub != last_sub:
                rows.append(("sub", sub))
                last_sub = sub
            rows.append(("sess", vi))
        return rows

    def _draw_list(self, stdscr, top, left, height, width):
        vis = self.visible()
        if not vis:
            self._safe(stdscr, top, left, "(no matching sessions)")
            return
        rows = self._list_rows(vis)
        sel_vi = vis[self.sel]
        sel_row = next(i for i, r in enumerate(rows) if r == ("sess", sel_vi))
        start = sel_row - height + 1 if sel_row >= height else 0
        start = max(0, min(start, max(0, len(rows) - height)))
        for off, (kind, val) in enumerate(rows[start:start + height]):
            y = top + off
            if kind == "blank":
                continue
            if kind == "group":
                self._safe(stdscr, y, left, ("▌ " + _short_cwd(val)).ljust(width)[:width],
                           curses.color_pair(HEADER_CP) | curses.A_BOLD)
                continue
            if kind == "sub":
                self._safe(stdscr, y, left, ("  ▸ " + val).ljust(width)[:width],
                           curses.color_pair(SUB_CP))
                continue
            s = self.sessions[val]
            tag = STATE_TAG.get(s["state"], "????")
            bell = "*" if s["state"] in STATE_BELL else " "
            indent = "    " if s.get("subgroup") else "  "
            text = f"{indent}{bell}{tag} {s['label']}  {self._blurb(s)}".rstrip()
            attr = curses.color_pair(CP.get(s["state"], 0))
            if val == sel_vi and self.mode == "list":
                attr |= curses.A_REVERSE | curses.A_BOLD
            self._safe(stdscr, y, left, text.ljust(width)[:width], attr)

    def _history_rows(self, dead):
        """Interleave "day killed" headers and — within each day — repo group /
        worktree subgroup headers with the selectable snapshot rows (mirrors
        `_list_rows`). `dead` is already in display order (see `_dead_sessions`),
        so this is a single linear pass that emits a header whenever the
        day/group/sub changes.

        Returns ("day"|"group"|"sub"|"sess"|"blank", value) rows; only "sess"
        rows are selectable (value = index into `dead`).
        """
        rows = []
        last_day = last_group = last_sub = None
        for i, s in enumerate(dead):
            day = self._day_label(s.get("last_seen"))
            group = s.get("repo_group", s["cwd"])
            sub = s.get("subgroup")
            if day != last_day:
                if last_day is not None:
                    rows.append(("blank", ""))
                rows.append(("day", day))
                last_day, last_group, last_sub = day, None, None
            if group != last_group:
                rows.append(("group", group))
                last_group, last_sub = group, None
            if sub and sub != last_sub:
                rows.append(("sub", sub))
                last_sub = sub
            rows.append(("sess", i))
        return rows

    def _draw_history_list(self, stdscr, top, left, height, width):
        dead = self._dead_sessions()
        if not dead:
            self._safe(stdscr, top, left, "(no former sessions yet)", curses.A_DIM)
            return
        self.sel = max(0, min(self.sel, len(dead) - 1))
        rows = self._history_rows(dead)
        sel_row = next(r for r, (k, v) in enumerate(rows) if k == "sess" and v == self.sel)
        start = sel_row - height + 1 if sel_row >= height else 0
        start = max(0, min(start, max(0, len(rows) - height)))
        for off, (kind, val) in enumerate(rows[start:start + height]):
            y = top + off
            if kind == "blank":
                continue
            if kind == "day":
                self._safe(stdscr, y, left, ("▌ " + val).ljust(width)[:width],
                           curses.color_pair(HEADER_CP) | curses.A_BOLD)
                continue
            if kind == "group":
                self._safe(stdscr, y, left, ("  ▌ " + _short_cwd(val)).ljust(width)[:width],
                           curses.color_pair(HEADER_CP) | curses.A_BOLD)
                continue
            if kind == "sub":
                self._safe(stdscr, y, left, ("    ▸ " + val).ljust(width)[:width],
                           curses.color_pair(SUB_CP))
                continue
            s = dead[val]
            tag = STATE_TAG.get(s["state"], "????")
            bell = "*" if s["state"] in STATE_BELL else " "
            indent = "      " if s.get("subgroup") else "    "
            text = f"{indent}{bell}{tag} {s['label']}  {s.get('blurb', '')}".rstrip()
            attr = curses.color_pair(CP.get(s["state"], 0))
            attr |= (curses.A_REVERSE | curses.A_BOLD) if val == self.sel else curses.A_DIM
            self._safe(stdscr, y, left, text.ljust(width)[:width], attr)

    def _detail_lines(self, s, width, full):
        """Build the detail view as a list of (text, attr) pairs."""
        wrapw = max(10, width)
        out: list[tuple[str, int]] = []
        out.append((("» " if full else "") + s["label"], curses.A_BOLD))
        out.append((f"tmux: {s['session_name']}    [{s['session_id']}]", 0))
        if s.get("claude_session_id"):
            out.append((f"claude session: {s['claude_session_id']}", 0))
        out.append((f"cwd:  {s['cwd']}", 0))
        b = self._blurb(s)
        blurb = f"   ·   {b}" if b else ""
        out.append((f"state: {s['state']}{blurb}",
                    curses.color_pair(CP.get(s["state"], 0)) | curses.A_BOLD))
        out.append(("─" * min(wrapw, 80), curses.A_DIM))

        def section(title, body, sub=False):
            if not (body or "").strip():
                return
            if out and out[-1][0] != "":
                out.append(("", 0))
            if sub:   # nested sub-header (e.g. RECAP → NEXT), indented + not bold
                out.append(("  ↳ " + title.upper(), curses.color_pair(HEADER_CP)))
                indent, body_w = "    ", max(10, wrapw - 4)
            else:
                out.append((title.upper(), curses.color_pair(HEADER_CP) | curses.A_BOLD))
                indent, body_w = "", wrapw
            for para in body.split("\n"):
                if not para.strip():
                    out.append(("", 0))
                    continue
                for wl in (textwrap.wrap(para, width=body_w) or [""]):
                    out.append((indent + wl, 0))

        recap_body, recap_next = _split_recap(s.get("recap", ""))
        section("Recap", recap_body)
        section("Next", recap_next, sub=True)
        section("What it's for", s.get("purpose", ""))
        section("Progress so far", s.get("progress", ""))
        section("Where it left off / needs you", s.get("waiting_on", ""))
        section("Latest response", s.get("latest", ""))
        full = s.get("latest_full", "")
        if full and full.strip() != (s.get("latest") or "").strip():
            section("Latest response (full)", full)
        return out

    def _draw_detail(self, stdscr, top, left, height, width, full):
        s = self.current()
        if s is None:
            self._safe(stdscr, top, left, "(nothing selected)")
            return
        lines = self._detail_lines(s, width, full)
        max_scroll = max(0, len(lines) - height)
        self.detail_scroll = max(0, min(self.detail_scroll, max_scroll))
        view = lines[self.detail_scroll:self.detail_scroll + height]
        for row, (txt, attr) in enumerate(view):
            self._safe(stdscr, top + row, left, txt[:width], attr)
        if max_scroll and self.mode == "detail":
            pct = int(100 * self.detail_scroll / max_scroll)
            self._safe(stdscr, top + height - 1, left + width - 6, f"{pct:>3}%",
                       curses.A_DIM)

    def _draw_footer(self, stdscr, h, w):
        if self.filtering:
            foot = f"/{self.filter}"
        elif self.message:
            foot = self.message
        elif self.mode == "detail":
            foot = " j/k scroll · h/Esc back · y copy-id · q quit "
        elif self.history:
            foot = " former sessions · j/k move · l detail · y copy-id · r refresh · H/Esc back · q quit "
        else:
            view = "haiku→proxy" if self.view == "haiku" else "proxy→haiku"
            foot = (f" j/k ⏎jump l detail · s summarize v view({view}) y copy-id "
                    f"· r refresh x kill H former / filter q quit ")
        stdscr.attron(curses.A_REVERSE)
        self._safe(stdscr, h - 1, 0, foot.ljust(w)[:w])
        stdscr.attroff(curses.A_REVERSE)

    def _draw_kill_box(self, stdscr, h, w):
        s = self.kill_target or {}
        bw = min(w - 4, 64)
        bh = 8
        top = max(0, (h - bh) // 2)
        left = max(0, (w - bw) // 2)
        red = curses.color_pair(CP["NEEDS_ATTENTION"])
        for i in range(bh):
            self._safe(stdscr, top + i, left, " " * bw, curses.A_REVERSE)
        self._safe(stdscr, top, left, " Kill sidekick session ".center(bw),
                   curses.A_REVERSE | curses.A_BOLD | red)
        self._safe(stdscr, top + 2, left + 2,
                   f"{s.get('label', '?')}  —  {_short_cwd(s.get('cwd', ''))}"[:bw - 4],
                   curses.A_REVERSE)
        self._safe(stdscr, top + 3, left + 2,
                   f"tmux: {s.get('session_name', '?')}"[:bw - 4], curses.A_REVERSE)
        self._safe(stdscr, top + 4, left + 2,
                   "Type 'delete' to confirm, Esc to cancel:"[:bw - 4],
                   curses.A_REVERSE)
        field = (self.kill_input + "█").ljust(bw - 6)[:bw - 6]
        self._safe(stdscr, top + 5, left + 2, "> " + field,
                   curses.A_REVERSE | curses.A_BOLD)

    @staticmethod
    def _safe(stdscr, y, x, text, attr=0):
        # curses can't render NULs/other C0 control chars (addnstr raises
        # ValueError on an embedded \x00); strip them — pane captures can
        # carry stray control bytes.
        if "\x00" in text or any(ord(c) < 32 and c not in "\t" for c in text):
            text = "".join(c if c == "\t" or ord(c) >= 32 else " "
                           for c in text)
        try:
            stdscr.addnstr(y, x, text, max(0, curses.COLS - x - 1), attr)
        except curses.error:
            pass

    # -- input ------------------------------------------------------------- #
    def handle(self, ch) -> bool:
        """Return False to quit the loop."""
        self.message = ""
        if self.confirming_kill:
            return self._handle_kill_confirm(ch)
        if self.filtering:
            return self._handle_filter(ch)

        n = len(self._dead_sessions()) if self.history else len(self.visible())

        if ch in (ord("q"),):
            return False
        if ch == 27:  # Esc
            if self.mode == "detail":
                self.mode = "list"
            elif self.history:
                self.history, self.sel = False, 0
            else:
                return False
            return True

        if ch in (ord("j"), curses.KEY_DOWN):
            if self.mode == "detail":
                self.detail_scroll += 1
            elif n:
                self.sel = (self.sel + 1) % n
            self.pending_g = False
        elif ch in (ord("k"), curses.KEY_UP):
            if self.mode == "detail":
                self.detail_scroll = max(0, self.detail_scroll - 1)
            elif n:
                self.sel = (self.sel - 1) % n
            self.pending_g = False
        elif ch == ord("g"):
            if self.pending_g:
                self.sel, self.detail_scroll, self.pending_g = 0, 0, False
            else:
                self.pending_g = True
        elif ch == ord("G"):
            if self.mode == "detail":
                self.detail_scroll = 10 ** 9  # clamped on draw
            elif n:
                self.sel = n - 1
            self.pending_g = False
        elif ch == 4:   # Ctrl-d
            self._move(n, (curses.LINES - 2) // 2)
        elif ch == 21:  # Ctrl-u
            self._move(n, -((curses.LINES - 2) // 2))
        elif ch in (ord("l"), ord("\t"), curses.KEY_RIGHT):
            if self.mode == "list":
                self.mode = "detail"
                self.detail_scroll = 0
        elif ch in (ord("h"), curses.KEY_LEFT):
            self.mode = "list"
        elif ch in (curses.KEY_ENTER, 10, 13):
            if self.history:
                self.message = " former session — no longer running "
            else:
                self._jump()   # stays running so you can switch back
        elif ch == ord("x"):
            if self.history:
                self.message = " former session — already gone "
            elif self.current() is not None:
                self.confirming_kill = True
                self.kill_input = ""
                self.kill_target = self.current()
        elif ch == ord("H"):
            self.history = not self.history
            self.mode, self.sel, self.detail_scroll = "list", 0, 0
        elif ch == ord("/"):
            if not self.history:        # filtering the graveyard isn't supported
                self.filtering = True
                self.filter = ""
        elif ch == ord("r"):
            self.want_refresh = True
            self.message = " refreshing info… "
        elif ch == ord("s"):
            if not self.history:
                self.want_summary = True
        elif ch == ord("v"):
            if not self.history:
                self.toggle_view()
        elif ch == ord("y"):
            self._copy_session_id()
        else:
            self.pending_g = False
        return True

    def _copy_session_id(self):
        s = self.current()
        if not s:
            return
        cid = s.get("claude_session_id") or ""
        if not cid:
            self.message = " no Claude session id for this session "
            return
        ok = _copy_clipboard(cid)
        self.message = (f" copied Claude session id: {cid} " if ok
                        else " clipboard copy failed (no tmux/wl-copy/xclip/pbcopy) ")

    def _move(self, n, delta):
        if self.mode == "detail":
            self.detail_scroll = max(0, self.detail_scroll + delta)
        elif n:
            self.sel = max(0, min(n - 1, self.sel + delta))

    def _handle_filter(self, ch) -> bool:
        if ch in (27,):                     # Esc cancels filter
            self.filtering, self.filter = False, ""
        elif ch in (curses.KEY_ENTER, 10, 13):
            self.filtering = False
        elif ch in (curses.KEY_BACKSPACE, 127, 8):
            self.filter = self.filter[:-1]
        elif 32 <= ch < 127:
            self.filter += chr(ch)
        self.sel = 0
        return True

    def _handle_kill_confirm(self, ch) -> bool:
        if ch == 27:                                  # Esc cancels
            self.confirming_kill, self.kill_input, self.kill_target = False, "", None
        elif ch in (curses.KEY_ENTER, 10, 13):
            if self.kill_input.strip().lower() == "delete":
                self._kill(self.kill_target)
            else:
                self.message = " not killed — you must type 'delete' "
            self.confirming_kill, self.kill_input, self.kill_target = False, "", None
        elif ch in (curses.KEY_BACKSPACE, 127, 8):
            self.kill_input = self.kill_input[:-1]
        elif 32 <= ch < 127:
            self.kill_input += chr(ch)
        return True

    # -- actions ----------------------------------------------------------- #
    def _kill(self, target):
        if not target:
            return
        sid = target["session_id"]
        res = subprocess.run(["tmux", "kill-session", "-t", sid],
                             capture_output=True, text=True)
        if res.returncode != 0:
            self.message = f" kill failed: {res.stderr.strip() or sid} "
            return
        # drop it locally and remember it, so an in-flight Haiku upgrade or a
        # later refresh/summary won't resurrect the killed session (the
        # `sessions` property filters on killed_ids across both views).
        self.killed_ids.add(sid)
        self._record(target)   # graveyard it now, so it appears immediately
        if self.live:
            self._save_history()
        self._clamp()
        self.mode = "list"
        self.message = f" killed {target['label']} ({target['session_name']}) "
        self.push_counts()

    def _jump(self):
        """Move the current tmux client to the selected session, WITHOUT exiting.

        Inside tmux we switch-client, so this TUI keeps running in its own pane
        and you can switch right back to it. Outside tmux we leave curses, attach
        (blocking), then resume the loop when you detach.
        """
        s = self.current()
        if not s:
            return
        sid = s["session_id"]
        # sidekick.nvim starts each CLI session with a session-local `status off`
        # to keep the bar out of its borderless float. Force it back on for the
        # target session only (no -g) before handing off, so jumping there shows
        # the status bar. No-op cost if it's already on.
        subprocess.run(["tmux", "set-option", "-t", sid, "status", "on"],
                       capture_output=True, text=True)
        if os.environ.get("TMUX"):
            res = subprocess.run(["tmux", "switch-client", "-t", sid],
                                 capture_output=True, text=True)
            if res.returncode != 0:
                self.message = f" jump failed: {res.stderr.strip() or sid} "
            else:
                # switching resized the target session's panes; nudge any
                # detached (sandboxed) claude there to re-read its size.
                _nudge_winch(sid)
                self.message = f" switched to {s['label']} — this summary is still running here "
        else:
            curses.endwin()
            # attach resizes the session to the new client; a detached claude
            # won't get SIGWINCH itself, so fire the nudge just after attach starts.
            threading.Timer(0.4, _nudge_winch, args=(sid,)).start()
            subprocess.run(["tmux", "attach-session", "-t", sid])
            self.message = f" back from {s['label']} "

REFRESH_SECS = 10  # auto proxy-refresh interval


def run(proxy: dict, collect_fn=None, summarize_fn=None,
        live: bool = True, haiku: dict | None = None,
        refresh_secs: float = REFRESH_SECS) -> int:
    """Render the TUI.

    proxy       : initial non-LLM payload (shown immediately, the default view).
    collect_fn  : () -> proxy_payload. Re-fetches the non-LLM info (the 'r' key
                  and the auto-refresh). Run in a background thread.
    summarize_fn: () -> haiku_payload|None. Fetches a Haiku summary (the 's'
                  key). Run in a background thread; never auto-invoked.
    live        : enable the auto proxy-refresh + countdown.
    haiku       : an initial Haiku payload (used by the --json static viewer).
    refresh_secs: auto proxy-refresh interval in seconds (default 10).
    """
    refresh_secs = max(1.0, float(refresh_secs))
    app = App(proxy, live=live, haiku=haiku)
    app.push_counts()  # seed the status bar immediately
    # Self-heal sandboxed-claude panes that tmux resizes without firing a hook
    # (see _winch_poller). Only worth running live and when the host helper exists.
    if live and collect_fn and os.access(SRT_SEND_WINCH, os.X_OK):
        threading.Thread(target=_winch_poller, args=(app,), daemon=True).start()
    results: "queue.Queue[tuple[str, object]]" = queue.Queue()

    def bg(tag, fn):
        def work():
            try:
                results.put((tag, fn()))
            except Exception as e:  # noqa: BLE001 — surface job failures
                results.put(("err", (tag, str(e))))
        threading.Thread(target=work, daemon=True).start()

    def start_proxy():
        if not collect_fn or app.proxy_pending:
            return
        app.proxy_pending = True
        bg("proxy", collect_fn)

    def start_haiku():
        if app.haiku_pending:
            return
        if not summarize_fn:
            app.message = " summary unavailable in this mode "
            return
        app.haiku_pending = True
        app.message = " summarizing with Haiku… "
        bg("haiku", summarize_fn)

    def _loop(stdscr):
        curses.curs_set(0)
        curses.use_default_colors()
        resolve = _color_resolver()
        for state, pair in CP.items():
            curses.init_pair(pair, resolve(STATE_COLOR[state]), -1)
        curses.init_pair(HEADER_CP, resolve("aqua"), -1)
        curses.init_pair(SUB_CP, resolve("grey"), -1)

        deadline = time.monotonic() + refresh_secs

        while True:
            busy = app.proxy_pending or app.haiku_pending
            stdscr.timeout(200 if (live or busy) else -1)
            if live:
                app.countdown = max(0, int(deadline - time.monotonic() + 0.999))
            app.draw(stdscr)
            ch = stdscr.getch()

            # drain finished background jobs
            while True:
                try:
                    tag, val = results.get_nowait()
                except queue.Empty:
                    break
                if tag == "proxy":
                    app.proxy_pending = False
                    app.set_proxy(val)
                elif tag == "haiku":
                    app.haiku_pending = False
                    if val is None:
                        app.message = " nothing to summarize "
                    else:
                        app.set_haiku(val)
                        app.message = " Haiku summary ready — press v to view "
                elif tag == "err":
                    which, msg = val
                    if which == "proxy":
                        app.proxy_pending = False
                    else:
                        app.haiku_pending = False
                    app.message = f" {which} failed: {msg} "

            # 10s auto proxy-refresh
            if live and time.monotonic() >= deadline:
                if not app.proxy_pending:
                    start_proxy()
                deadline = time.monotonic() + refresh_secs

            if busy:
                app.tick += 1

            if ch == -1:            # timeout tick, no key
                continue
            if not app.handle(ch):
                break
            if app.want_refresh:
                app.want_refresh = False
                start_proxy()
                deadline = time.monotonic() + refresh_secs
            if app.want_summary:
                app.want_summary = False
                start_haiku()

    try:
        curses.wrapper(_loop)
    finally:
        # mark the status bar as no-longer-tracked when we exit (even on crash);
        # any other running summary app will overwrite with real counts shortly.
        if live:
            _set_status_counts("x", "x", "x")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: sk_tui.py path/to/report.json", file=sys.stderr)
        raise SystemExit(2)
    _payload = json.loads(Path(sys.argv[1]).read_text())
    # Static viewer: no live refresh; both views show the loaded report.
    raise SystemExit(run(_payload, collect_fn=None, summarize_fn=None,
                         live=False, haiku=_payload))
