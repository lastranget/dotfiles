-- Diffview revision-range picker.
--
-- `<leader>co` diffs the working tree against the index; this (`<leader>cr`)
-- diffs any two points in the current branch's history. Two pickers run back to
-- back: the first chooses the *newer* side of the diff, the second is narrowed
-- to revisions the first pick descends from. Narrowing is the point -- it means
-- you can't assemble a range that git would resolve to an empty or inverted
-- diff, so the second list is always a valid answer to "compare back to what?".
--
-- Both pickers reuse snacks' own `git_log` row format and `git_show` preview, so
-- they look and behave like `Snacks.picker.git_log()`.
--
-- Everything is scoped to nvim's cwd (via its git toplevel) rather than the
-- current buffer, and diffview is handed the same toplevel with `-C` so the
-- revisions it resolves are guaranteed to be the ones listed in the pickers.

local M = {}

-- Commits offered per picker. History can be enormous; this is a display cap,
-- not a correctness one -- the second picker re-queries from the chosen commit
-- rather than slicing the first list, so a deep pick still gets 100 ancestors.
local COMMIT_LIMIT = 100

-- Field separator for the log format. Commit subjects can contain parentheses
-- and angle brackets, so splitting on a control char is unambiguous where a
-- regex over "<hash> <subject> (<date>) <<author>>" would not be.
local SEP = "\31"

local function notify(msg, level)
  Snacks.notify(msg, { title = "Diffview Range", level = level })
end

---Run git in `cwd`. Returns nil plus stderr on failure.
---@return string[]|nil lines, string|nil err
local function git(cwd, args)
  local cmd = { "git", "-C", cwd }
  vim.list_extend(cmd, args)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(out, "\n")
  end
  return out
end

local function git_root(cwd)
  local out = git(cwd, { "rev-parse", "--show-toplevel" })
  local root = out and out[1] and vim.trim(out[1])
  return (root and root ~= "") and root or nil
end

---Commits reachable from `rev`, newest first.
---@param skip integer entries to drop from the front. `git log <rev>` leads with
---`<rev>` itself, so skip=1 turns "rev and its ancestors" into "rev's ancestors"
---without `<rev>^`, which errors on a root commit.
---@return snacks.picker.finder.Item[]|nil items, string|nil err
local function log_items(root, rev, skip)
  local out, err = git(root, {
    "log",
    "--max-count=" .. COMMIT_LIMIT,
    "--skip=" .. skip,
    "--no-show-signature",
    "--pretty=format:%h" .. SEP .. "%s" .. SEP .. "%ch" .. SEP .. "%an",
    rev,
  })
  if not out then
    return nil, err
  end

  local items = {}
  for _, line in ipairs(out) do
    local p = vim.split(line, SEP, { plain = true })
    if p[1] and p[1] ~= "" then
      items[#items + 1] = {
        commit = p[1],
        msg = p[2] or "",
        date = p[3] or "",
        author = p[4] or "",
        cwd = root, -- `preview.git_show` / `preview.cmd` run git here
        text = table.concat({ p[1], p[2] or "", p[4] or "" }, " "),
      }
    end
  end
  return items
end

-- Staged and unstaged both count, which is why the row reads "Local Changes":
-- diffview's newer side here is LOCAL (the working tree), and that reflects the
-- index and the worktree alike. Untracked files are the one exclusion --
-- diffview won't show them without `-u`, so their presence alone shouldn't add a
-- row that then diffs as empty.
local function is_dirty(root)
  local out = git(root, { "status", "--porcelain", "--untracked-files=no" })
  return out ~= nil and #out > 0
end

local function format_item(item, picker)
  if not item.working_tree then
    return Snacks.picker.format.git_log(item, picker)
  end
  -- Mirror git_log's column widths (8-wide ref, 16-wide date) so this row's
  -- message lines up with the commit rows beneath it.
  local a = Snacks.picker.util.align
  return {
    { picker.opts.icons.git.modified, "SnacksPickerGitStatus" },
    { a("LOCAL", 8, { truncate = true }), "SnacksPickerGitStatus" },
    { " " },
    { a("", 16) },
    { " " },
    { "Local Changes", "SnacksPickerGitMsg" },
  }
end

local function preview_item(ctx)
  if not ctx.item.working_tree then
    return Snacks.picker.preview.git_show(ctx)
  end
  -- vs HEAD rather than the index, so the preview covers staged and unstaged
  -- together -- matching what diffview shows for this row.
  Snacks.picker.preview.cmd({ "git", "--no-pager", "diff", "HEAD" }, ctx, { ft = "git" })
end

local function pick(title, items, on_choice)
  Snacks.picker({
    title = title,
    items = items,
    format = format_item,
    preview = preview_item,
    -- Keep git's ordering (newest first) when no filter is typed.
    sort = { fields = { "score:desc", "idx" } },
    confirm = function(picker, item)
      picker:close()
      if item then
        -- Deferred so the picker window is fully torn down before the next
        -- picker (or diffview) claims the screen.
        vim.schedule(function()
          on_choice(item)
        end)
      end
    end,
  })
end

function M.pick()
  if not (Snacks and Snacks.picker) then
    vim.notify("snacks.nvim picker not available", vim.log.levels.ERROR)
    return
  end

  local cwd = vim.fn.getcwd()
  local root = git_root(cwd)
  if not root then
    notify("Not a git repository: " .. cwd, vim.log.levels.ERROR)
    return
  end

  local commits, err = log_items(root, "HEAD", 0)
  if not commits then
    notify("git log failed:\n" .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local newer = {}
  if is_dirty(root) then
    newer[1] = { working_tree = true, cwd = root, text = "local changes working tree staged unstaged" }
  end
  vim.list_extend(newer, commits)

  if #newer == 0 then
    notify("No commits in " .. vim.fn.fnamemodify(root, ":~"), vim.log.levels.WARN)
    return
  end

  pick("Diff newer side", newer, function(new_rev)
    -- Revisions the newer pick descends from. For the working tree that's every
    -- commit reachable from HEAD; for a commit it's its ancestors. Re-querying
    -- git (rather than slicing the first list) is what makes this correct across
    -- merges, where a commit listed above another isn't necessarily its child.
    local rev, skip = "HEAD", 0
    if not new_rev.working_tree then
      rev, skip = new_rev.commit, 1
    end

    local older, log_err = log_items(root, rev, skip)
    if not older then
      notify("git log failed:\n" .. (log_err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    if #older == 0 then
      notify("No revisions older than " .. new_rev.commit .. " (root commit)", vim.log.levels.WARN)
      return
    end

    pick("Diff older side (vs " .. (new_rev.commit or "LOCAL") .. ")", older, function(old_rev)
      -- `A..B` resolves to left=A, right=B. A bare rev leaves the right side as
      -- diffview's LOCAL (the working tree), which is exactly the working-tree
      -- case -- so no explicit range is needed there.
      local rev_arg = new_rev.working_tree and old_rev.commit
        or (old_rev.commit .. ".." .. new_rev.commit)
      require("diffview").open({ "-C" .. root, rev_arg })
    end)
  end)
end

return M
