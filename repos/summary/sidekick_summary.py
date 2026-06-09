#!/usr/bin/env python3
"""sidekick_summary.py — collect + summarize running sidekick.nvim CLI sessions.

This is the *data layer*. It is deliberately decoupled from any UI: it produces a
single JSON file describing every running sidekick session, which the bundled
curses TUI (sk_tui.py) renders — and which a future neovim/snacks picker could
read verbatim.

Pipeline:
  1. Discover the sidekick tmux sessions configured in
     ~/.config/nvim/lua/plugins/sidekick.lua (the claude / claudeB / claudeC
     variants and the "neovim" scratch/markdown tool). Sessions are named
     "<tool> <sha256(cwd) prefix>" by sidekick (see cli/session/init.lua).
  2. For each pane: capture it twice ~0.4s apart for a deterministic
     working/idle liveness signal, and grab a plain-text screen dump.
  3. For Claude sessions: read the tail of the real conversation transcript
     (~/.claude/projects/<encoded-cwd>/<newest>.jsonl) for accurate task/progress.
  4. Send all of that to a headless Haiku, which returns JSON analysis only.
  5. Merge Haiku's analysis with the *bash-known* identity fields (so the
     session_id used for jumping can never be hallucinated) and write
     <script dir>/YYYY/MM/DD/HH-MM-SS.json plus a human-readable .md archive.

By default it then launches the TUI on the fresh JSON. Use --refresh-only to
just produce the data (prints the JSON path), or --json PATH to view existing
data in the TUI without refreshing.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROMPT_FILE = SCRIPT_DIR / "prompt.txt"

SIDEKICK_LUA = Path(
    os.environ.get("SIDEKICK_LUA",
                   Path.home() / ".config/nvim/lua/plugins/sidekick.lua")
)

# Nice labels for the well-known tools; anything else gets a generated label.
KNOWN_LABELS = {
    "claude": "Claude A",
    "claudeB": "Claude B",
    "claudeC": "Claude C",
    "neovim": "Scratch/Markdown (neovim)",
}
# Used only if the config can't be read/parsed.
DEFAULT_TOOLS = {
    "claude": {"label": "Claude A", "kind": "claude"},
    "claudeB": {"label": "Claude B", "kind": "claude"},
    "claudeC": {"label": "Claude C", "kind": "claude"},
    "neovim": {"label": "Scratch/Markdown (neovim)", "kind": "editor"},
}

SCREEN_LINES = 200      # lines of scrollback to feed Haiku for state detection
TRANSCRIPT_CHARS = 6000  # max chars of transcript tail per session
LIVENESS_DELAY = 0.4     # seconds between the two liveness snapshots


# --------------------------------------------------------------------------- #
# Read the tool list straight from sidekick.lua so new tools (e.g. claude_env)
# show up automatically without editing this script.
# --------------------------------------------------------------------------- #
def _label_for(name: str, kind: str) -> str:
    if name in KNOWN_LABELS:
        return KNOWN_LABELS[name]
    if name.startswith("claude"):
        rest = name[len("claude"):].lstrip("_")
        return f"Claude {rest}" if rest else "Claude"
    if kind == "editor":
        return f"Scratch/Markdown ({name})"
    return name[:1].upper() + name[1:]


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def load_tools() -> dict:
    """Parse `cli.tools` from sidekick.lua → {name: {"label", "kind"}}.

    kind: "claude" (runs the claude binary → has a ~/.claude transcript),
          "editor" (nvim buffer), or "cli" (any other tool, screen-only).
    Falls back to DEFAULT_TOOLS if the file is missing or unparseable.
    """
    try:
        text = SIDEKICK_LUA.read_text()
    except OSError:
        return dict(DEFAULT_TOOLS)

    lines = text.splitlines()
    # locate the `tools = {` line
    start = next((i for i, ln in enumerate(lines)
                  if re.match(r"\s*tools\s*=\s*\{", ln)), None)
    if start is None:
        return dict(DEFAULT_TOOLS)
    base = _indent(lines[start])

    # block runs until the first non-blank line indented back to `base` (the `}`)
    block = []
    for ln in lines[start + 1:]:
        if ln.strip() and _indent(ln) <= base:
            break
        block.append(ln)

    key_re = re.compile(r"^(\s*)([A-Za-z_]\w*)\s*=\s*\{")
    keyed = [(i, m) for i, ln in enumerate(block) for m in [key_re.match(ln)] if m]
    if not keyed:
        return dict(DEFAULT_TOOLS)
    key_indent = min(m.group(1).__len__() for _, m in keyed)
    starts = [(i, m.group(2)) for i, m in keyed if len(m.group(1)) == key_indent]

    tools = {}
    for idx, (line_i, name) in enumerate(starts):
        end_i = starts[idx + 1][0] if idx + 1 < len(starts) else len(block)
        body = "\n".join(block[line_i:end_i])
        # claude-family tools all start with "claude" (claude, claudeB,
        # claude_env, claude_resume, …); also catch a literal "claude" in the cmd.
        if name.startswith("claude") or re.search(r'"claude"', body):
            kind = "claude"
        elif name == "neovim" or re.search(r'"nvim"', body):
            kind = "editor"
        else:
            kind = "cli"
        tools[name] = {"label": _label_for(name, kind), "kind": kind}
    return tools or dict(DEFAULT_TOOLS)


# --------------------------------------------------------------------------- #
# tmux helpers
# --------------------------------------------------------------------------- #
def _tmux(*args: str) -> str:
    return subprocess.run(
        ["tmux", *args], capture_output=True, text=True
    ).stdout


def _git_info(cwd: str) -> tuple[str, str | None]:
    """Map a cwd to (group, subgroup) for the worktree-aware list grouping:

      - group:    the MAIN repo root — all of a repo's worktrees share its git
                  object store, so they group together. Falls back to the cwd
                  itself when not in a git repo.
      - subgroup: "Main Repo" for the primary checkout, the branch (or worktree
                  dir name) for a linked worktree, or None when not in a repo.
    """
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--path-format=absolute",
             "--git-common-dir", "--show-toplevel"],
            capture_output=True, text=True)
    except OSError:
        return cwd, None
    if out.returncode != 0:
        return cwd, None
    parts = out.stdout.splitlines()
    common = parts[0].strip() if parts else ""
    toplevel = parts[1].strip() if len(parts) > 1 else ""
    if not common or not toplevel:
        return cwd, None
    common = common.rstrip("/")
    repo_root = os.path.dirname(common) if os.path.basename(common) == ".git" else toplevel
    if toplevel == repo_root:
        return repo_root, "Main Repo"
    # linked worktree → label by branch, falling back to the worktree dir name
    br = subprocess.run(["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
                        capture_output=True, text=True)
    label = br.stdout.strip()
    if not label or label == "HEAD":
        label = os.path.basename(toplevel.rstrip("/"))
    return repo_root, label


def discover_sessions() -> list[dict]:
    """Return the live sidekick panes as identity dicts (no analysis yet).

    The set of tools is read fresh from sidekick.lua each call, so newly-defined
    tools appear on the next refresh without restarting.
    """
    tools = load_tools()
    ginfo: dict[str, tuple[str, str | None]] = {}  # memo per cwd within this call
    self_pane = os.environ.get("TMUX_PANE", "")
    fmt = "#{session_name}|#{session_id}|#{pane_id}|#{pane_pid}|#{pane_active}|" \
          "#{?pane_current_path,#{pane_current_path},#{pane_start_path}}"
    out = _tmux("list-panes", "-a", "-F", fmt)
    # One sidekick tmux session == one agent, but a session may transiently
    # carry an extra pane (e.g. a leftover shell from the resume wrapper). Keep
    # a single entry per session_name, preferring the active pane (the one
    # running the agent); first-seen wins on a tie.
    by_name: dict[str, tuple[bool, dict]] = {}
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) != 6:
            continue
        sname, sid, pane_id, pane_pid, pane_active, cwd = parts
        if not sname or pane_id == self_pane:
            continue
        tool, _, hashpart = sname.partition(" ")
        info = tools.get(tool)
        if info is None or not re.fullmatch(r"[0-9a-f]+", hashpart):
            continue
        active = pane_active == "1"
        prev = by_name.get(sname)
        if prev is not None and not (active and not prev[0]):
            continue
        if cwd not in ginfo:
            ginfo[cwd] = _git_info(cwd)
        group, subgroup = ginfo[cwd]
        by_name[sname] = (active, {
            "label": info["label"],
            "tool": tool,
            "kind": info["kind"],     # "claude" | "editor" | "cli"
            "session_name": sname,
            "session_id": sid,        # e.g. "$42" — space-free, safe to target
            "pane_id": pane_id,       # e.g. "%195"
            "cwd": cwd,
            "repo_group": group,      # main repo root (groups its worktrees too)
            "subgroup": subgroup,     # "Main Repo" | branch/worktree | None
            "sidekick_tool": _sidekick_tool_env(pane_pid),
        })
    sessions = [d for _, d in by_name.values()]
    # group by repo, "Main Repo" subgroup first, then worktrees, then label
    sessions.sort(key=lambda s: (s["repo_group"],
                                 0 if s["subgroup"] == "Main Repo" else 1,
                                 s["subgroup"] or "", s["label"]))
    return sessions


def _sidekick_tool_env(pane_pid: str) -> str:
    """Best-effort: find SIDEKICK_TOOL on the pane's process subtree."""
    try:
        queue = [int(pane_pid)]
    except ValueError:
        return ""
    seen = set()
    while queue:
        pid = queue.pop(0)
        if pid in seen:
            continue
        seen.add(pid)
        try:
            data = Path(f"/proc/{pid}/environ").read_bytes()
            for kv in data.split(b"\0"):
                if kv.startswith(b"SIDEKICK_TOOL="):
                    return kv[len(b"SIDEKICK_TOOL="):].decode(errors="replace")
        except OSError:
            pass
        try:
            kids = subprocess.run(
                ["pgrep", "-P", str(pid)], capture_output=True, text=True
            ).stdout.split()
            queue.extend(int(k) for k in kids)
        except (OSError, ValueError):
            pass
    return ""


def capture_pane(pane_id: str, lines: int = SCREEN_LINES) -> str:
    return _tmux("capture-pane", "-p", "-t", pane_id, "-S", f"-{lines}", "-E", "-")


def liveness(pane_id: str) -> str:
    """'active' if the pane changes across a short interval, else 'idle'."""
    a = capture_pane(pane_id, 50)
    time.sleep(LIVENESS_DELAY)
    b = capture_pane(pane_id, 50)
    return "active" if a != b else "idle"


# --------------------------------------------------------------------------- #
# Claude Code transcript tail
# --------------------------------------------------------------------------- #
def _encode_cwd(cwd: str) -> str:
    # Claude Code encodes the project dir by replacing '/' and '.' with '-'.
    return re.sub(r"[/.]", "-", cwd)


def _project_jsonls(cwd: str) -> list[Path]:
    """Candidate transcript files for a cwd, newest-modified first."""
    proj = Path.home() / ".claude" / "projects" / _encode_cwd(cwd)
    if not proj.is_dir():
        return []
    return sorted(proj.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)


def _is_user_prompt(obj: dict) -> bool:
    """True if a transcript entry is a genuine user-typed prompt — not a
    tool_result (also `type:user`) or a meta/system-injected entry. Used to tell
    whether the conversation has moved on past a recap."""
    role = obj.get("type") or obj.get("message", {}).get("role")
    if role != "user" or obj.get("isMeta"):
        return False
    content = obj.get("message", {}).get("content", "")
    if isinstance(content, str):
        return bool(content.strip())
    if isinstance(content, list):
        return any(isinstance(b, dict) and b.get("type") == "text"
                   and b.get("text", "").strip() for b in content)
    return False


def _parse_transcript_file(path: Path) -> tuple[list[dict], str]:
    """Parse one transcript file into (entries, recap).

    entries: ordered {role, text, tools} for the recent user/assistant turns.
    recap:   the latest Claude Code "recap" — a `type:system, subtype:away_summary`
             entry's content (shown in the TUI as `※ recap: …`). Generated
             periodically (e.g. when you return after being away), not every turn.
             Suppressed (→ "") once the conversation has moved on past it: a recap
             describes an idle moment, so a new user prompt after it makes it stale.
    """
    try:
        raw_lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return [], ""
    # latest recap: scan all lines (cheap substring pre-filter), keep the last
    recap, recap_idx = "", -1
    for i, raw in enumerate(raw_lines):
        if "away_summary" not in raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if obj.get("type") == "system" and obj.get("subtype") == "away_summary":
            c = obj.get("content", "")
            if isinstance(c, str) and c.strip():
                recap = re.sub(r"\(disable recaps.*?\)", "", c).strip()
                recap_idx = i
    # Drop the recap if the user has typed a new prompt since it was generated —
    # they've moved on, so the old idle-state recap is just confusing.
    for raw in raw_lines[recap_idx + 1:] if recap_idx >= 0 else ():
        if '"user"' not in raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if _is_user_prompt(obj):
            recap = ""
            break
    # recent conversation turns
    entries: list[dict] = []
    for raw in raw_lines[-80:]:
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            continue
        role = obj.get("type") or obj.get("message", {}).get("role")
        if role not in ("user", "assistant"):
            continue
        text, tools = _text_and_tools(obj.get("message", {}).get("content", ""))
        if text or tools:
            entries.append({"role": role, "text": text, "tools": tools})
    return entries, recap


def _recap_from_screen(screen: str) -> str:
    """Best-effort recap from a pane screen (for sessions with no host
    transcript, e.g. a containerized claude_env). Grabs the `※ recap:` line and
    its wrapped continuation, dropping the `(disable recaps …)` affordance."""
    lines = screen.splitlines()
    for i in range(len(lines) - 1, -1, -1):
        if "recap:" in lines[i].lower():
            chunk = [lines[i].split("recap:", 1)[1]]
            for nxt in lines[i + 1:]:
                t = nxt.strip()
                if not t or t[0] in "─—│╭╰❯✻⏺※·•":  # next TUI element
                    break
                chunk.append(nxt)
            text = " ".join(c.strip() for c in chunk)
            return re.sub(r"\(disable recaps.*?\)", "", text).strip()
    return ""


# --- map each pane to its own transcript when several share a cwd ----------- #
def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text).lower()


def _read_tail(path: Path, maxbytes: int = 400_000) -> str:
    try:
        size = path.stat().st_size
        with open(path, "rb") as fh:
            if size > maxbytes:
                fh.seek(size - maxbytes)
            return fh.read().decode("utf-8", "replace")
    except OSError:
        return ""


def _fingerprints(screen: str) -> list[str]:
    """Distinctive normalized snippets of real conversation text on the screen
    (skipping TUI chrome), used to recognize which transcript this pane is in."""
    cores = []
    for ln in screen.splitlines():
        t = ln.strip(" │╎┃>⏺⎿•*-")
        if len(t) < 25 or sum(c.isalnum() for c in t) < 15:
            continue
        if set(t) <= set("─—-=_•. "):           # rule/separator lines
            continue
        n = _norm(t)
        cores.append(n[3:43] if len(n) > 46 else n)   # middle slice dodges wrap edges
    # longest first = most distinctive; de-dup
    return sorted(set(cores), key=len, reverse=True)[:15]


def _match_by_content(panes: list[tuple[int, str]], jsonls: list[Path]) -> dict:
    """Assign each pane (index, screen) the transcript whose recent text best
    contains the pane's on-screen snippets. Unmatched panes -> None (no transcript)."""
    jnorm = {j: _norm(_read_tail(j)) for j in jsonls}
    fps = {i: _fingerprints(screen) for i, screen in panes}
    ranked = []
    for i, _ in panes:
        for j in jsonls:
            score = sum(1 for c in fps[i] if c and c in jnorm[j])
            ranked.append((score, i, str(j), j))
    ranked.sort(reverse=True)
    out: dict[int, Path | None] = {}
    taken_j = set()
    for score, i, _, j in ranked:
        if score <= 0:
            break
        if i in out or j in taken_j:
            continue
        out[i] = j
        taken_j.add(j)
    for i, _ in panes:
        out.setdefault(i, None)
    return out


def _resolve_transcripts(sessions: list[dict], base: list[dict]) -> dict:
    """Return {session_id: transcript Path|None} for claude-kind sessions,
    disambiguating panes that share a cwd by on-screen content."""
    out: dict[str, Path | None] = {}
    by_cwd: dict[str, list[int]] = {}
    for i, s in enumerate(sessions):
        if s["kind"] == "claude":
            by_cwd.setdefault(s["cwd"], []).append(i)
    for cwd, idxs in by_cwd.items():
        jsonls = _project_jsonls(cwd)
        if not jsonls:
            for i in idxs:
                out[sessions[i]["session_id"]] = None
        else:
            # Even a lone session must be content-matched: a *just-started*
            # session hasn't written its transcript yet, so the newest .jsonl in
            # the cwd belongs to a previous (now-dead) session — adopting it
            # blindly shows that dead session's stale prompt/detail. A fresh pane
            # (welcome banner, no conversation) matches nothing -> None -> screen
            # fallback. An ongoing session matches its own transcript as before.
            assign = _match_by_content([(i, base[i]["screen"]) for i in idxs], jsonls)
            for i in idxs:
                out[sessions[i]["session_id"]] = assign.get(i)
    return out


def _text_and_tools(content):
    """Return (prose_text, [tool_names]) for a message's content."""
    if isinstance(content, str):
        return content.strip(), []
    if not isinstance(content, list):
        return "", []
    prose, tools = [], []
    for block in content:
        if not isinstance(block, dict):
            continue
        btype = block.get("type")
        if btype == "text":
            prose.append(block.get("text", "").strip())
        elif btype == "tool_use":
            tools.append(block.get("name", "?"))
    return " ".join(p for p in prose if p).strip(), tools


def transcript_parts_from_entries(entries: list[dict],
                                  max_chars: int = TRANSCRIPT_CHARS) -> dict:
    """Derive both the Haiku blob and the instant-proxy pieces from parsed entries."""
    if not entries:
        return {}
    chunks = []
    for e in entries:
        line = f"[{e['role']}] {e['text']}".strip()
        if e["tools"]:
            line += f"  (tools: {', '.join(e['tools'])})"
        if line.strip("[] "):
            chunks.append(line)
    blob = "\n".join(chunks).strip()
    if len(blob) > max_chars:
        blob = "…(truncated)…\n" + blob[-max_chars:]

    last_user = next((e["text"] for e in reversed(entries)
                      if e["role"] == "user" and e["text"]), "")
    last_assistant = next((e["text"] for e in reversed(entries)
                           if e["role"] == "assistant" and e["text"]), "")
    recent_tools: list[str] = []
    for e in reversed(entries):
        for t in reversed(e["tools"]):
            if t not in recent_tools:
                recent_tools.append(t)
        if len(recent_tools) >= 6:
            break
    recent_tools.reverse()
    return {"blob": blob, "last_user": last_user,
            "last_assistant": last_assistant, "recent_tools": recent_tools[-6:]}


# --------------------------------------------------------------------------- #
# Haiku call + merge
# --------------------------------------------------------------------------- #
def build_prompt(sessions: list[dict], collected: list[dict]) -> str:
    base = PROMPT_FILE.read_text()
    now = dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    ctx = [
        "CONTEXT",
        "=======",
        f"Current local time: {now}",
        f"Number of sessions: {len(sessions)}",
        "",
    ]
    for i, (s, c) in enumerate(zip(sessions, collected), start=1):
        ctx += [
            f"----- SESSION index={i} -----",
            f"label: {s['label']}",
            f"cwd: {s['cwd']}",
            f"liveness: {c['liveness']}",
            "SCREEN:",
            "```",
            c["screen"].rstrip(),
            "```",
        ]
        if c["transcript"]:
            ctx += ["TRANSCRIPT (conversation tail):", "```", c["transcript"], "```"]
        else:
            ctx += ["TRANSCRIPT: (none — not a Claude session)"]
        ctx.append("")
    return base + "\n" + "\n".join(ctx)


def call_haiku(prompt: str) -> list[dict]:
    proc = subprocess.run(
        ["claude", "-p", prompt, "--model", "haiku"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"claude failed (rc={proc.returncode}): {proc.stderr.strip()}")
    return _parse_json_array(proc.stdout)


def _parse_json_array(text: str) -> list[dict]:
    text = text.strip()
    # strip ```json ... ``` fences if present
    fence = re.match(r"^```(?:json)?\s*(.*?)\s*```$", text, re.DOTALL)
    if fence:
        text = fence.group(1).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # fallback: grab the outermost [...] span
    start, end = text.find("["), text.rfind("]")
    if start != -1 and end != -1 and end > start:
        return json.loads(text[start:end + 1])
    raise ValueError("could not parse JSON array from Haiku output:\n" + text[:500])


def merge(sessions: list[dict], analysis: list[dict]) -> list[dict]:
    by_index = {a.get("index"): a for a in analysis if isinstance(a, dict)}
    final = []
    for i, s in enumerate(sessions, start=1):
        a = by_index.get(i)
        if a is None and i - 1 < len(analysis) and isinstance(analysis[i - 1], dict):
            a = analysis[i - 1]  # positional fallback
        a = a or {}
        merged = dict(s)  # trusted identity fields win
        merged.update({
            "state": a.get("state", "WAITING_ON_USER"),
            "blurb": a.get("blurb", ""),
            "summary_line": a.get("summary_line", "(no summary)"),
            "purpose": a.get("purpose", ""),
            "progress": a.get("progress", ""),
            "waiting_on": a.get("waiting_on", ""),
            "latest": a.get("latest", ""),
        })
        final.append(merged)
    return final


# --------------------------------------------------------------------------- #
# Output
# --------------------------------------------------------------------------- #
def _stamp(now: dt.datetime) -> str:
    return now.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def _dated_paths(now: dt.datetime) -> tuple[Path, Path]:
    out_dir = SCRIPT_DIR / now.strftime("%Y") / now.strftime("%m") / now.strftime("%d")
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = now.strftime("%H-%M-%S")
    return out_dir / f"{stem}.json", out_dir / f"{stem}.md"


STATE_BELL = {"WAITING_ON_USER", "NEEDS_ATTENTION"}


def render_md(payload: dict) -> str:
    lines = [f"# Sidekick Session Summary — {payload['generated_at']}", "", "## Summary", ""]
    for s in payload["sessions"]:
        bell = "🔔 " if s["state"] in STATE_BELL else ""
        blurb = f" — _{s['blurb']}_" if s.get("blurb") else ""
        lines.append(
            f"- {bell}**{s['label']}**{blurb} (`{s['cwd']}`) — {s['summary_line']}. "
            f"**State:** {s['state']}"
        )
    lines += ["", "## Sessions", ""]
    for s in payload["sessions"]:
        lines += [
            f"### {s['label']} — {s['cwd']}",
            f"- **tmux session:** `{s['session_name']}`  ·  **State:** {s['state']}"
            + (f"  ·  _{s['blurb']}_" if s.get("blurb") else ""),
        ]
        if s.get("claude_session_id"):
            lines.append(f"- **Claude session:** `{s['claude_session_id']}`")
        lines.append("")
        if s.get("recap"):
            lines += ["**Recap**", "", s["recap"], ""]
        if s.get("purpose"):
            lines += ["**What it's for**", "", s["purpose"], ""]
        if s.get("progress"):
            lines += ["**Progress so far**", "", s["progress"], ""]
        if s.get("waiting_on"):
            lines += ["**Where it left off / what it needs**", "", s["waiting_on"], ""]
        if s.get("latest"):
            lines += ["**Latest response**", "", s["latest"], ""]
        full = s.get("latest_full", "")
        if full and full.strip() != (s.get("latest") or "").strip():
            lines += ["**Latest response (full)**", "", full, ""]
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------- #
# Provisional (instant) payload — every field filled from data we already have,
# so the TUI is useful before Haiku returns.
# --------------------------------------------------------------------------- #
def _one_line(text: str, n: int) -> str:
    line = " ".join((text or "").split())
    return (line[: n - 1] + "…") if len(line) > n else line


def _few_words(text: str, n: int) -> str:
    words = " ".join((text or "").split()).split(" ")
    blurb = " ".join(words[:n])
    return blurb + ("…" if len(words) > n else "")


def collect() -> tuple[list[dict], list[dict]]:
    """Fast: discover sessions and gather liveness, screen, and transcript parts."""
    sessions = discover_sessions()
    if not sessions:
        return [], []
    # Phase 1: per-pane liveness + screen (the screen is also used to match
    # which transcript a pane belongs to when several share a cwd).
    base = [{"liveness": liveness(s["pane_id"]), "screen": capture_pane(s["pane_id"])}
            for s in sessions]
    # Phase 2: resolve each claude session's own transcript file.
    tpaths = _resolve_transcripts(sessions, base)

    collected = []
    for s, b in zip(sessions, base):
        path = tpaths.get(s["session_id"])
        if path:
            entries, recap = _parse_transcript_file(path)
            parts = transcript_parts_from_entries(entries)
        else:
            parts, recap = {}, ""
        collected.append({
            "liveness": b["liveness"],
            "screen": b["screen"],
            "transcript": parts.get("blob", ""),
            "last_user": parts.get("last_user", ""),
            "last_assistant": parts.get("last_assistant", ""),
            "recent_tools": parts.get("recent_tools", []),
            # Trust the transcript's recap when we have one (it also decides a
            # stale recap is gone — see _parse_transcript_file); only fall back to
            # the on-screen `※ recap:` when there's no host transcript at all.
            "recap": recap if path else _recap_from_screen(b["screen"]),
            # Claude Code session UUID = the transcript filename stem
            "claude_session_id": path.stem if path else "",
        })
    return sessions, collected


_ATTN_PHRASES = (
    "do you want to proceed", "would you like to proceed",
    "do you want to continue", "(y/n)", "[y/n]", "[y/n/a]",
    "press enter to continue", "waiting for your response",
)


def _looks_attention(screen: str) -> bool:
    """Heuristic (no LLM): is an idle pane *blocked* on a user decision rather
    than just finished? Detects Claude's choice/confirmation prompts, where the
    `❯` cursor sits on a numbered option (vs the normal `❯ <text>` input).

    Only the bottom interactive region is examined, so menu-like text elsewhere
    in the scrollback (docs, code, prior output) doesn't trigger a false match.
    """
    lines = screen.splitlines()
    region = "\n".join(lines[-10:])
    # cursor on a numbered option, plus at least one more option line → a menu
    if re.search(r"❯\s*\d+[.)]", region) and \
       re.search(r"(?m)^\s*\d+[.)]\s+\S", region):
        return True
    foot = "\n".join(lines[-6:]).lower()
    return any(p in foot for p in _ATTN_PHRASES)


def make_provisional(sessions: list[dict], collected: list[dict],
                     now: dt.datetime) -> dict:
    out = []
    for s, c in zip(sessions, collected):
        if c["liveness"] == "active":
            state = "WORKING"
        elif _looks_attention(c["screen"]):
            state = "NEEDS_ATTENTION"
        else:
            state = "WAITING_ON_USER"
        has_transcript = bool(c["transcript"] or c["last_user"] or c["last_assistant"])
        if s["kind"] != "claude" or not has_transcript:  # no transcript → use screen
            screen = c["screen"].strip()
            first = next((ln for ln in screen.splitlines() if ln.strip()), "")
            buf = screen[-3000:] if screen else "(empty)"
            editor = s["kind"] == "editor"
            fields = {
                "blurb": "scratch buffer" if editor
                         else (_few_words(first, 9) or s["label"]),
                "summary_line": _one_line(first, 100)
                                or ("Scratch / markdown buffer" if editor else s["label"]),
                "purpose": "Scratch/markdown neovim buffer." if editor
                           else f"{s['label']} session (no transcript available).",
                "progress": "",
                "waiting_on": "Scratch buffer (no agent)." if editor
                              else ("" if state == "WORKING"
                                    else "Idle — awaiting your input."),
                "latest": buf,
                "latest_full": buf,
            }
        else:
            lu, la = c["last_user"], c["last_assistant"]
            tools = c["recent_tools"]
            fields = {
                "blurb": _few_words(lu, 9) or s["cwd"].rstrip("/").rsplit("/", 1)[-1],
                "summary_line": _one_line(lu, 100) or "(no recorded prompt yet)",
                "purpose": lu or "(no recorded prompt yet)",
                "progress": ("Recent tool activity: " + ", ".join(tools))
                            if tools else "(no recorded tool activity yet)",
                "waiting_on": "" if state == "WORKING"
                              else "Idle at the prompt — awaiting your input.",
                "latest": la or "(no assistant response captured yet)",
                "latest_full": la or "(no assistant response captured yet)",
            }
        out.append({**s, "state": state, "recap": c.get("recap", ""),
                    "claude_session_id": c.get("claude_session_id", ""), **fields})
    return {"generated_at": _stamp(now), "sessions": out, "pending_analysis": True}


def analyze_payload(sessions: list[dict], collected: list[dict],
                    now: dt.datetime) -> dict:
    analysis = call_haiku(build_prompt(sessions, collected))
    final = merge(sessions, analysis)
    # Keep the verbatim last response alongside Haiku's summarized `latest`.
    for s, c in zip(final, collected):
        full = c.get("last_assistant", "") or c.get("screen", "").strip()[-3000:]
        s["latest_full"] = (full or "(no assistant response captured)")[:6000]
        s["recap"] = c.get("recap", "")
        s["claude_session_id"] = c.get("claude_session_id", "")
    return {"generated_at": _stamp(now), "sessions": final, "pending_analysis": False}


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def proxy_job() -> dict:
    """Fast: re-fetch the non-LLM info as a provisional payload (no Haiku, no
    file written — this is ephemeral live state). Empty-safe."""
    sessions, collected = collect()
    return make_provisional(sessions, collected, dt.datetime.now())


def _write_summary(sessions, collected, now) -> tuple[dict, Path]:
    json_path, md_path = _dated_paths(now)
    final = analyze_payload(sessions, collected, now)
    json_path.write_text(json.dumps(final, indent=2))
    md_path.write_text(render_md(final))
    return final, json_path


def summarize_job() -> dict | None:
    """Slow: collect fresh + run Haiku, write the dated .json/.md archive, and
    return the summarized payload. None if there are no sessions."""
    sessions, collected = collect()
    if not sessions:
        return None
    return _write_summary(sessions, collected, dt.datetime.now())[0]


def refresh_only() -> Path | None:
    """Blocking full Haiku report (no TUI); returns the JSON path."""
    sessions, collected = collect()
    if not sessions:
        return None
    return _write_summary(sessions, collected, dt.datetime.now())[1]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Summarize running sidekick sessions.")
    ap.add_argument("--refresh-only", action="store_true",
                    help="produce a Haiku JSON report and print its path; no TUI")
    ap.add_argument("--json", metavar="PATH",
                    help="open an existing report in the TUI (static, no live refresh)")
    ap.add_argument("--refresh", type=float, metavar="SECONDS", default=None,
                    help="auto-refresh interval in seconds (default 10; min 1)")
    args = ap.parse_args(argv)

    import sk_tui
    refresh_secs = args.refresh if (args.refresh and args.refresh > 0) else sk_tui.REFRESH_SECS

    if args.json:
        payload = json.loads(Path(args.json).read_text())
        return sk_tui.run(payload, collect_fn=None, summarize_fn=None,
                          live=False, haiku=payload)

    if args.refresh_only:
        json_path = refresh_only()
        if json_path is None:
            print("No running sidekick (claude / claudeB / claudeC / neovim) sessions found.",
                  file=sys.stderr)
        else:
            print(json_path)
        return 0

    # Default: show the non-LLM report instantly; Haiku is manual ('s').
    print("Collecting sessions…", file=sys.stderr)
    sessions, collected = collect()
    if not sessions:
        print("No running sidekick (claude / claudeB / claudeC / neovim) sessions found.",
              file=sys.stderr)
        return 0
    proxy0 = make_provisional(sessions, collected, dt.datetime.now())
    return sk_tui.run(proxy0, collect_fn=proxy_job, summarize_fn=summarize_job,
                      live=True, refresh_secs=refresh_secs)


if __name__ == "__main__":
    sys.path.insert(0, str(SCRIPT_DIR))
    raise SystemExit(main())
