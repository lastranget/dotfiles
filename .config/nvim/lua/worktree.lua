-- Git worktree picker + switcher.
--
-- Lists every worktree attached to the current repo (`git worktree list` is
-- repo-global, so this works whether nvim is sitting in the main checkout or in
-- one of the worktrees) and lets you switch nvim's cwd to the selected one.
--
-- Why this pairs with sidekick.nvim: sidekick names its tmux session
-- `<tool> <sha256(cwd)>` (see lua/sidekick/cli/session/init.lua `M.sid`). Each
-- worktree is a distinct absolute directory, so switching cwd here means the
-- next sidekick toggle attaches to *that worktree's* Claude session — fully
-- isolated, with no risk of reattaching to another worktree's session.
--
-- Switching also remaps open buffers from the old worktree root to the new one
-- (preserving window layout + cursor) so you and the CLI stay on the same
-- physical files. Unsaved buffers under the old root abort the switch.

local M = {}

local uv = vim.uv or vim.loop

-- Where new worktrees are created. Kept outside any repo so worktree dirs never
-- nest inside a checkout (which would pollute file pickers / grep).
local WORKTREE_ROOT = vim.fn.expand("~/.worktrees")

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

-- Lazy snacks accessor (mirrors obsidian-tasks-slop.nvim's UI module).
local function snacks()
  local ok, s = pcall(require, "snacks")
  return ok and s or nil
end

-- vim.ui.select with a Snacks.picker front-end when available.
local function select_with_fallback(items, opts, on_choice)
  local s = snacks()
  if s and s.picker then
    s.picker({
      title = opts.prompt or "Select",
      items = items,
      format = function(item) return { { item.text, "Normal" } } end,
      confirm = function(picker, item)
        picker:close()
        on_choice(item)
      end,
      layout = opts.layout or { preset = "select" },
    })
    return
  end
  local labels = {}
  for i, it in ipairs(items) do labels[i] = it.text end
  vim.ui.select(labels, { prompt = opts.prompt }, function(_, idx)
    on_choice(idx and items[idx] or nil)
  end)
end

-- vim.ui.input with a Snacks.input front-end when available.
local function input_with_fallback(opts, on_confirm)
  local s = snacks()
  if s and s.input then
    s.input(opts, on_confirm)
    return
  end
  vim.ui.input({ prompt = opts.prompt, default = opts.default }, on_confirm)
end

-- Run git in `dir`, return trimmed stdout lines (or nil + message on failure).
local function git(dir, args)
  local cmd = { "git", "-C", dir }
  vim.list_extend(cmd, args)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(out, "\n")
  end
  return out
end

-- Absolute root of the worktree that currently contains `dir`.
local function current_root(dir)
  local out = git(dir, { "rev-parse", "--show-toplevel" })
  return out and out[1] and normalize(out[1]) or nil
end

-- Parse `git worktree list --porcelain` into { path, branch, head, current }.
function M.list(dir)
  dir = dir or vim.fn.getcwd()
  local out, err = git(dir, { "worktree", "list", "--porcelain" })
  if not out then
    return nil, err or "not inside a git repository"
  end

  local here = current_root(dir)
  local items, cur = {}, nil
  for _, line in ipairs(out) do
    if line == "" then
      cur = nil
    else
      local key, val = line:match("^(%S+)%s*(.*)$")
      if key == "worktree" then
        cur = { path = normalize(val) }
        cur.current = cur.path == here
        items[#items + 1] = cur
      elseif cur and key == "HEAD" then
        cur.head = val:sub(1, 8)
      elseif cur and key == "branch" then
        cur.branch = val:gsub("^refs/heads/", "")
      elseif cur and key == "detached" then
        cur.branch = nil
      end
    end
  end
  return items
end

-- Buffers whose file lives under `root` (a "/"-terminated prefix).
-- Returns listed, loaded, normal-file buffers only.
local function buffers_under(root)
  local prefix = root .. "/"
  local ret = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "" and vim.fn.buflisted(buf) == 1 then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        name = normalize(name)
        if name:sub(1, #prefix) == prefix then
          ret[#ret + 1] = { buf = buf, name = name, rel = name:sub(#prefix + 1) }
        end
      end
    end
  end
  return ret
end

-- Switch nvim's cwd to `target` and remap buffers from the old root to it.
function M.switch(target)
  target = normalize(target)
  if uv.fs_stat(target) == nil then
    vim.notify("Worktree path does not exist:\n" .. target, vim.log.levels.ERROR)
    return
  end

  local old = current_root(vim.fn.getcwd())
  if old == target then
    vim.notify("Already in this worktree", vim.log.levels.INFO)
    return
  end
  if not old then
    -- Not in a git tree (or git unavailable): just cd, nothing to remap.
    vim.cmd.cd(vim.fn.fnameescape(target))
    vim.notify("cwd -> " .. vim.fn.fnamemodify(target, ":~"))
    return
  end

  local under = buffers_under(old)

  -- Guard: never strand unsaved edits in the old worktree.
  local dirty = {}
  for _, b in ipairs(under) do
    if vim.bo[b.buf].modified then
      dirty[#dirty + 1] = "  " .. b.rel
    end
  end
  if #dirty > 0 then
    vim.notify(
      "Unsaved changes block worktree switch:\n" .. table.concat(dirty, "\n"),
      vim.log.levels.WARN
    )
    return
  end

  vim.cmd.cd(vim.fn.fnameescape(target))

  -- Remap buffers shown in windows, preserving layout + cursor.
  local missing = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.bo[buf].buftype == "" then
      name = normalize(name)
      if name:sub(1, #old + 1) == old .. "/" then
        local rel = name:sub(#old + 2)
        local new = target .. "/" .. rel
        if uv.fs_stat(new) then
          local cursor = vim.api.nvim_win_get_cursor(win)
          vim.api.nvim_win_call(win, function()
            vim.cmd.edit(vim.fn.fnameescape(new))
            local lines = vim.api.nvim_buf_line_count(0)
            pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor[1], lines), cursor[2] })
          end)
        else
          missing[rel] = true
        end
      end
    end
  end

  -- Wipe orphaned old-root buffers (not displayed, not modified) so the
  -- buffer list reflects the new worktree rather than the old checkout.
  for _, b in ipairs(under) do
    if vim.api.nvim_buf_is_valid(b.buf)
      and vim.fn.bufwinid(b.buf) == -1
      and not vim.bo[b.buf].modified then
      pcall(vim.api.nvim_buf_delete, b.buf, {})
    end
  end

  local msg = "Worktree -> " .. vim.fn.fnamemodify(target, ":~")
  local miss = vim.tbl_keys(missing)
  if #miss > 0 then
    msg = msg .. ("\n(%d file(s) absent in this worktree, kept old buffer)"):format(#miss)
  end
  vim.notify(msg, vim.log.levels.INFO)
end

-- Repo name: basename of the directory holding the shared .git, so it's stable
-- whether nvim sits in the main checkout or in a worktree.
local function repo_name(dir)
  local out = git(dir, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
  if not (out and out[1]) then
    out = git(dir, { "rev-parse", "--git-common-dir" }) -- older git: may be relative
  end
  if not (out and out[1]) then return nil end
  return vim.fn.fnamemodify(normalize(out[1]), ":h:t") -- .../<repo>/.git -> <repo>
end

local function branch_exists(dir, branch)
  vim.fn.system({ "git", "-C", dir, "show-ref", "--verify", "--quiet", "refs/heads/" .. branch })
  return vim.v.shell_error == 0
end

-- Sanitize a branch name into a single filesystem-safe path component.
local function sanitize(name)
  return (name:gsub("[/\\:%s]+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", ""))
end

-- Run `cmd` in a floating terminal so its live progress is visible (git only
-- emits the "Updating files: X%" meter when stderr is a tty — a PTY gives it
-- one, which a plain pipe would not). On success the float auto-closes and
-- on_success() runs; on failure it stays open (q / <Esc> to dismiss).
local function run_with_progress(cmd, title, on_success)
  local height = math.min(14, vim.o.lines - 4)
  local width = math.min(100, math.floor(vim.o.columns * 0.7))
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
    title = " " .. title .. " ",
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.fn.termopen(cmd, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          -- brief pause so the final "HEAD is now at ..." line is glimpsable
          vim.defer_fn(function()
            close()
            on_success()
          end, 600)
        else
          pcall(vim.cmd, "stopinsert") -- leave terminal-mode so q/<Esc> map works
          vim.notify(title .. " failed (exit " .. code .. "). Press q to dismiss.", vim.log.levels.ERROR)
          for _, key in ipairs({ "q", "<Esc>" }) do
            vim.keymap.set("n", key, close, { buffer = buf, nowait = true, silent = true })
          end
        end
      end)
    end,
  })
  vim.cmd("startinsert") -- follow the output as it streams
end

-- git worktree add, then switch into it. Branches from current HEAD for a new
-- branch, or checks out an existing branch.
local function do_create(dir, branch, path)
  if uv.fs_stat(path) then
    vim.notify("Worktree path already exists:\n" .. path, vim.log.levels.ERROR)
    return
  end
  vim.fn.mkdir(WORKTREE_ROOT, "p")

  local cmd = { "git", "-C", dir, "worktree", "add" }
  if branch_exists(dir, branch) then
    vim.list_extend(cmd, { path, branch }) -- check out existing branch
  else
    vim.list_extend(cmd, { "-b", branch, path }) -- new branch off HEAD
  end

  run_with_progress(cmd, "worktree add → " .. vim.fn.fnamemodify(path, ":t"), function()
    vim.notify(("Created worktree %s (branch '%s')"):format(vim.fn.fnamemodify(path, ":~"), branch))
    M.switch(path)
  end)
end

-- Wizard: branch name -> timestamp choice -> create + switch.
-- Worktree dir is created as ~/.worktrees/<repo>-<branch>[-<timestamp>]. The
-- timestamp lives on the *directory* (not the branch) to keep branch names
-- clean while still avoiding collisions — same place claude-squad puts it.
function M.create()
  local dir = vim.fn.getcwd()
  if not current_root(dir) then
    vim.notify("Not inside a git repository", vim.log.levels.ERROR)
    return
  end
  local repo = repo_name(dir) or vim.fn.fnamemodify(current_root(dir), ":t")

  input_with_fallback({ prompt = "New worktree — branch name: " }, function(branch)
    if branch == nil then return end -- cancelled
    branch = vim.trim(branch)
    if branch == "" then
      vim.notify("Worktree creation cancelled (empty branch)", vim.log.levels.INFO)
      return
    end

    local base = repo .. "-" .. sanitize(branch)
    select_with_fallback({
      { text = "No timestamp        ~/.worktrees/" .. base, item = false },
      { text = "Append timestamp    ~/.worktrees/" .. base .. "-" .. os.date("%Y%m%d-%H%M%S"), item = true },
    }, { prompt = "Worktree directory name" }, function(choice)
      if choice == nil then return end -- cancelled
      local dirname = base
      if choice.item then
        dirname = dirname .. "-" .. os.date("%Y%m%d-%H%M%S")
      end
      do_create(dir, branch, WORKTREE_ROOT .. "/" .. dirname)
    end)
  end)
end

-- Snacks picker over the repo's worktrees.
function M.pick()
  local items, err = M.list()
  if not items then
    vim.notify("worktree: " .. err, vim.log.levels.ERROR)
    return
  end
  if #items <= 1 then
    vim.notify("Only one worktree for this repo", vim.log.levels.INFO)
    return
  end

  for _, it in ipairs(items) do
    it.text = (it.branch or "detached") .. " " .. it.path
  end

  require("snacks").picker({
    title = "Git Worktrees",
    items = items,
    format = function(item)
      local ret = {}
      ret[#ret + 1] = item.current and { "● ", "DiagnosticOk" } or { "  ", "Normal" }
      ret[#ret + 1] = { ("%-24s"):format(item.branch or "(detached)"), "Function" }
      ret[#ret + 1] = { " " .. (item.head or ""), "Comment" }
      ret[#ret + 1] = { "  " .. vim.fn.fnamemodify(item.path, ":~"), "Directory" }
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        M.switch(item.path)
      end
    end,
  })
end

return M
