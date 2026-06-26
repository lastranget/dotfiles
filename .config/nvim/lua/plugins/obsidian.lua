-- plugins/obsidian.lua
--
-- obsidian.nvim plus a small set of custom "MOC-tree" maintenance commands.
--
-- The vault's organization scheme treats the `parents:` frontmatter list as the
-- single source of truth for where a note lives in the subject tree (see the
-- vault's organization notes). These helpers make that field cheap to maintain
-- from neovim without Dataview:
--
--   <leader>on / <leader>oN  new note  → template picker → name → MOC parent picker
--   <leader>op               add parent → add MOC(s) to the current note's parents
--   <leader>oS               MOC swap  → re-parent notes OFF the current MOC onto others
--   <leader>oP               add parent → add MOC(s) to picked notes' parents
--   <leader>org / :ObsLint    generate the vault hygiene report
--   <leader>or{o,u,d,b,m}     picker per lint category (orphans/untyped/desc/broken/malformed)
--   <leader>or{O,U,D,B,M}     resolve that category (assign parent/type/description, fix/open)
--   <leader>ow / :ObsWeedy    weedy triage queue
--   <leader>oa / oA          insert #tag(s) at cursor / add tag(s) to frontmatter
--   <leader>om / oQ          MOC quick-switch (breadcrumb picker; subtree-aware)
--   <leader>ov / oV          move current file / picked files to a directory
--   <leader>oq / ob / ol     note pickers (all notes / backlinks / outgoing links)
--   <leader>oB               parent-backlinks (notes that declare this note a parent)
-- Any picker that opens notes: Enter opens the highlighted one; Tab marks several,
-- which are then added to the buffer list in the background (open_notes).
--
-- Frontmatter is read and rewritten through obsidian.nvim's OWN yaml module
-- (`obsidian.yaml` + `obsidian.frontmatter`) rather than hand-rolled string
-- munging. `yaml.loads` returns the key order, and `Frontmatter.dump(data, order)`
-- round-trips it, so we preserve every key and its order and only change
-- `parents:`. We deliberately do NOT route through the note's frontmatter
-- function (`builtin.frontmatter`), because that injects an `id:` field into
-- every note — exactly what `frontmatter.enabled = false` (set below for Obsidian
-- Sync stability) is there to avoid.

local uv = vim.uv or vim.loop

-- Single workspace. Keep in sync with `workspaces` below.
local VAULT = vim.fn.expand("~/vaults/Main")

-- Descriptions the old templates injected; the lint treats these as "missing".
local BOILERPLATE_DESC = {
  ["default template for new notes"] = true,
  ["default template for new work notes"] = true,
  ["default template for new biofinder notes"] = true,
}

-- Where :ObsLint writes its report (vault-relative). A generated, disposable file.
local LINT_REPORT = "Lint Report.md"

-- ── small utilities ─────────────────────────────────────────────────────────

local function relpath(path)
  return (path:gsub("^" .. vim.pesc(VAULT .. "/"), ""))
end

-- Drop empty strings from a `systemlist` result.
local function nonempty(list)
  local r = {}
  for _, s in ipairs(list or {}) do
    if s ~= "" then
      r[#r + 1] = s
    end
  end
  return r
end

-- The link target inside a "[[Target#section|alias]]" string, lower-cased and
-- trimmed (so it can be matched against a note's reference ids). nil if not a link.
local function link_target(link)
  if type(link) ~= "string" then
    return nil
  end
  local inner = link:match("%[%[(.-)%]%]")
  if not inner then
    return nil
  end
  inner = inner:gsub("#.*$", ""):gsub("|.*$", "")
  return vim.trim(inner):lower()
end

-- ── frontmatter read / write (via obsidian.nvim's yaml) ──────────────────────

-- Read a markdown file and split out its YAML frontmatter.
---@return { lines: string[], fm_end: integer|nil, data: table, order: string[], ok: boolean, has_fm: boolean }|nil
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()

  local function is_fence(l)
    return l ~= nil and l:match("^%-%-%-+%s*$") ~= nil
  end

  if not is_fence(lines[1]) then
    return { lines = lines, fm_end = nil, data = {}, order = {}, ok = true, has_fm = false }
  end

  local fm_end
  for i = 2, #lines do
    if is_fence(lines[i]) then
      fm_end = i
      break
    end
  end
  if not fm_end then
    -- Opened frontmatter that never closed → malformed.
    return { lines = lines, fm_end = nil, data = {}, order = {}, ok = false, has_fm = true }
  end

  local body = {}
  for i = 2, fm_end - 1 do
    body[#body + 1] = lines[i]
  end

  local yaml = require("obsidian.yaml")
  local ok, data, order = pcall(yaml.loads, table.concat(body, "\n"))
  if not ok or type(data) ~= "table" then
    return { lines = lines, fm_end = fm_end, data = {}, order = {}, ok = false, has_fm = true }
  end
  return { lines = lines, fm_end = fm_end, data = data, order = order or {}, ok = true, has_fm = true }
end

-- Read ONLY the frontmatter, stopping at the closing fence. Used by the vault
-- index so we never read the body of large notes (e.g. multi-thousand-line logs).
---@return { data: table, ok: boolean, has_fm: boolean }|nil
local function read_fm(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local first = f:read("*l")
  if not first or not first:match("^%-%-%-+%s*$") then
    f:close()
    return { data = {}, ok = true, has_fm = false }
  end
  local body, closed = {}, false
  for line in f:lines() do
    if line:match("^%-%-%-+%s*$") then
      closed = true
      break
    end
    body[#body + 1] = line
  end
  f:close()
  if not closed then
    return { data = {}, ok = false, has_fm = true }
  end
  local yaml = require("obsidian.yaml")
  local ok, data = pcall(yaml.loads, table.concat(body, "\n"))
  if not ok or type(data) ~= "table" then
    return { data = {}, ok = false, has_fm = true }
  end
  return { data = data, ok = true, has_fm = true }
end

-- Reference ids a note can be linked by: filename stem, vault-relative path
-- (both without extension), and aliases — all lower-cased.
local function note_ref_ids(path, data)
  local ids = {}
  ids[(vim.fn.fnamemodify(path, ":t:r")):lower()] = true
  ids[(relpath(path):gsub("%.md$", "")):lower()] = true
  if data and type(data.aliases) == "table" then
    for _, a in ipairs(data.aliases) do
      if type(a) == "string" then
        ids[a:lower()] = true
      end
    end
  end
  return ids
end

-- Round-trip a note's frontmatter through obsidian.nvim's YAML, applying
-- `mutate(data)` and preserving key order; the body is untouched. `ensure_keys`
-- are prepended to the key order if missing (so a newly-added field is emitted).
---@return boolean ok, string|nil reason
local function edit_frontmatter(path, mutate, ensure_keys)
  local fm = read_file(path)
  if not fm then
    return false, "unreadable"
  end
  if not fm.ok then
    return false, "malformed frontmatter"
  end

  local data, order = fm.data, fm.order
  mutate(data)
  for _, k in ipairs(ensure_keys or {}) do
    if not vim.tbl_contains(order, k) then
      table.insert(order, 1, k)
    end
  end

  local fm_lines = require("obsidian.frontmatter").dump(data, order) -- { "---", ..., "---" }
  local out = {}
  vim.list_extend(out, fm_lines)
  local body_start = fm.has_fm and (fm.fm_end + 1) or 1
  for i = body_start, #fm.lines do
    out[#out + 1] = fm.lines[i]
  end

  local fh, err = io.open(path, "w")
  if not fh then
    return false, tostring(err)
  end
  fh:write(table.concat(out, "\n") .. "\n")
  fh:close()

  -- Reload any buffer already showing this file.
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == path then
      vim.api.nvim_buf_call(b, function()
        vim.cmd("checktime")
      end)
    end
  end
  return true
end

-- Replace a note's `parents` list.
---@return boolean ok, string|nil reason
local function write_parents(path, parents)
  return edit_frontmatter(path, function(d)
    d.parents = parents
  end, { "parents" })
end

-- Add a tag to a note (no-op if already present).
local function add_tag_on(path, tag)
  return edit_frontmatter(path, function(d)
    local tags = (type(d.tags) == "table") and d.tags or {}
    if not vim.tbl_contains(tags, tag) then
      tags[#tags + 1] = tag
    end
    d.tags = tags
  end, { "tags" })
end

-- Set a note's one-line description.
local function set_description_on(path, desc)
  return edit_frontmatter(path, function(d)
    d.description = desc
  end, { "description" })
end

-- ── vault scanning (ripgrep) ─────────────────────────────────────────────────

local function have_rg()
  if vim.fn.executable("rg") ~= 1 then
    vim.notify("ripgrep (rg) is required for Obsidian tooling", vim.log.levels.ERROR)
    return false
  end
  return true
end

-- All markdown notes in the vault (absolute paths), excluding templates and
-- hidden dirs (.git/.obsidian/.trash are skipped by rg by default).
local function vault_md_files()
  if not have_rg() then
    return {}
  end
  return nonempty(vim.fn.systemlist({
    "rg", "--files", "--no-ignore", "--color=never",
    "-g", "*.md", "-g", "!templates/**",
    VAULT,
  }))
end

-- Files containing `pattern` (fixed string if `fixed`), markdown only, no templates.
local function rg_files_matching(pattern, fixed)
  if not have_rg() then
    return {}
  end
  local cmd = { "rg", "--files-with-matches", "--no-ignore", "--color=never", "-g", "*.md", "-g", "!templates/**" }
  if fixed then
    cmd[#cmd + 1] = "-F"
  end
  cmd[#cmd + 1] = pattern
  cmd[#cmd + 1] = VAULT
  return nonempty(vim.fn.systemlist(cmd))
end

-- Every note tagged `type/moc`. Returns { path, stem, display, link, parents, refids }.
local function collect_mocs()
  local mocs = {}
  for _, path in ipairs(rg_files_matching("type/moc")) do
    local fm = read_file(path)
    if fm and fm.ok and type(fm.data.tags) == "table" and vim.tbl_contains(fm.data.tags, "type/moc") then
      local stem = vim.fn.fnamemodify(path, ":t:r")
      local display = stem
      if type(fm.data.aliases) == "table" and type(fm.data.aliases[1]) == "string" then
        display = fm.data.aliases[1]
      end
      mocs[#mocs + 1] = {
        path = path,
        stem = stem,
        display = display,
        link = "[[" .. stem .. "]]",
        parents = (type(fm.data.parents) == "table") and fm.data.parents or {},
        refids = note_ref_ids(path, fm.data),
      }
    end
  end
  table.sort(mocs, function(a, b)
    return a.display:lower() < b.display:lower()
  end)
  return mocs
end

-- Picker items for MOCs, each labelled with its ancestor breadcrumb, e.g.
-- "tui moc  ⟵ computer moc  ⟵ home". The breadcrumb is also the match text, so
-- typing an ancestor's name (e.g. "computer") keeps that MOC's whole subtree in
-- the list: the MOC whose own name matches sorts first (match at the start gets
-- fzf's first-char bonus), and its descendants rank below it, roughly by depth
-- (the match falls further right in longer breadcrumbs).
local function moc_items(mocs)
  local by_refid = {}
  for _, m in ipairs(mocs) do
    for id in pairs(m.refids or {}) do
      by_refid[id] = by_refid[id] or m
    end
  end
  -- Walk a MOC's parent chain upward (cycle-guarded), collecting ancestor names.
  local function lineage(m)
    local chain, seen, cur = {}, { [m.path] = true }, m
    while true do
      local up
      for _, e in ipairs(cur.parents or {}) do
        local t = link_target(e)
        local pm = t and by_refid[t] or nil
        if pm and not seen[pm.path] then
          up = pm
          break
        end
      end
      if not up then
        break
      end
      seen[up.path] = true
      chain[#chain + 1] = up.display
      cur = up
    end
    return chain
  end

  local items = {}
  for _, m in ipairs(mocs) do
    local chain = lineage(m)
    local text = m.display
    if #chain > 0 then
      text = text .. "  ⟵ " .. table.concat(chain, "  ⟵ ")
    end
    items[#items + 1] = { text = text, name = m.display, file = m.path, moc = m }
  end
  return items
end

-- Notes that declare `moc` in their `parents:` frontmatter. Candidate files are
-- found by ripgrep (by stem and aliases), then confirmed by parsing parents — so
-- this is scoped to parents-frontmatter links, not generic backlinks.
local function collect_children(moc)
  local fm = read_file(moc.path)
  local refids = note_ref_ids(moc.path, fm and fm.data or {})

  local patterns = { "[[" .. moc.stem }
  if fm and type(fm.data.aliases) == "table" then
    for _, a in ipairs(fm.data.aliases) do
      if type(a) == "string" then
        patterns[#patterns + 1] = "[[" .. a
      end
    end
  end

  local seen, candidates = {}, {}
  for _, pat in ipairs(patterns) do
    for _, p in ipairs(rg_files_matching(pat, true)) do
      if not seen[p] then
        seen[p] = true
        candidates[#candidates + 1] = p
      end
    end
  end

  local children = {}
  for _, p in ipairs(candidates) do
    if p ~= moc.path then
      local cfm = read_file(p)
      if cfm and cfm.ok and type(cfm.data.parents) == "table" then
        for _, e in ipairs(cfm.data.parents) do
          if refids[link_target(e) or ""] then
            children[#children + 1] = { path = p }
            break
          end
        end
      end
    end
  end
  return children
end

-- ── MOC subtree expansion (descendants of selected MOCs) ─────────────────────
--
-- One pass over the vault builds the parents graph; expansion is then pure
-- in-memory BFS. We follow `parents:` edges directly (exactly the relationship we
-- want, and far cheaper than repeated per-MOC backlink searches).

-- Single-pass index of the whole vault: parent→children plus a moc flag.
---@return { children_of: table<string, string[]>, is_moc: table<string, boolean> }
local function build_index()
  local notes, path_of = {}, {}
  for _, p in ipairs(vault_md_files()) do
    local fm = read_fm(p)
    if fm then
      local data = fm.data
      notes[p] = {
        parents = (type(data.parents) == "table") and data.parents or {},
        is_moc = type(data.tags) == "table" and vim.tbl_contains(data.tags, "type/moc"),
      }
      for id in pairs(note_ref_ids(p, data)) do
        path_of[id] = path_of[id] or p -- first wins on basename collisions
      end
    end
  end

  local children_of, is_moc = {}, {}
  for p, n in pairs(notes) do
    is_moc[p] = n.is_moc
    for _, entry in ipairs(n.parents) do
      local tgt = link_target(entry)
      local parent_path = tgt and path_of[tgt] or nil
      if parent_path then
        local list = children_of[parent_path]
        if not list then
          list = {}
          children_of[parent_path] = list
        end
        list[#list + 1] = p
      end
    end
  end
  return { children_of = children_of, is_moc = is_moc }
end

-- For each selected root MOC, BFS down the children graph recording the minimum
-- depth at which each note is reached. A per-root visited set means every MOC is
-- expanded at most once, so a cyclic parents graph can't loop forever.
---@return table<string, { roots: integer, depth: integer }>
local function expand_descendants(root_paths, idx)
  local agg = {}
  for _, root in ipairs(root_paths) do
    local dist = {} -- path -> min depth from this root (>= 1)
    local visited = { [root] = true } -- MOCs already expanded under this root
    local queue, head = { { root, 0 } }, 1
    while head <= #queue do
      local mpath, depth = queue[head][1], queue[head][2]
      head = head + 1
      for _, child in ipairs(idx.children_of[mpath] or {}) do
        local nd = depth + 1
        if dist[child] == nil or nd < dist[child] then
          dist[child] = nd
        end
        if idx.is_moc[child] and not visited[child] then
          visited[child] = true
          queue[#queue + 1] = { child, nd }
        end
      end
    end
    for path, d in pairs(dist) do
      local a = agg[path]
      if not a then
        agg[path] = { roots = 1, depth = d }
      else
        a.roots = a.roots + 1
        if d < a.depth then
          a.depth = d
        end
      end
    end
  end
  return agg
end

-- Rank: reached from the most selected MOCs first (factor 1), then shallowest
-- first (factor 2). `×N` = number of selected roots reaching it, `dK` = min depth.
local function moc_tree_items(agg)
  local items = {}
  for path, a in pairs(agg) do
    items[#items + 1] = {
      text = ("×%d  d%d  %s"):format(a.roots, a.depth, relpath(path)),
      file = path,
      roots = a.roots,
      depth = a.depth,
    }
  end
  table.sort(items, function(x, y)
    if x.roots ~= y.roots then
      return x.roots > y.roots
    end
    if x.depth ~= y.depth then
      return x.depth < y.depth
    end
    return x.text < y.text
  end)
  return items
end

local function all_note_items()
  local items = {}
  for _, p in ipairs(vault_md_files()) do
    items[#items + 1] = { text = relpath(p), file = p }
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  return items
end

local function template_items()
  local items = {}
  for _, p in ipairs(vim.fn.globpath(VAULT .. "/templates", "*.md", false, true)) do
    items[#items + 1] = { text = vim.fn.fnamemodify(p, ":t:r"), file = p }
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  return items
end

-- ── snacks picker wrapper ────────────────────────────────────────────────────
--
-- For multi-select pickers (`fallback = true`): <Enter> on a highlighted item
-- operates on just that item; <Tab> marks several (see plugins/picker.lua), then
-- <Enter> operates on the whole marked set. Single-select pickers confirm the
-- item under the cursor.
-- Picker line formatter: a MOC item (which carries `.name`) shows its own name
-- in the normal colour and the rest of its breadcrumb (parents + arrows) dimmed;
-- every other item renders as plain text. snacks overlays match highlights on top.
local function picker_format(item)
  local name, text = item.name, item.text or ""
  if name and #text > #name then
    return { { name }, { text:sub(#name + 1), "SnacksPickerDimmed" } }
  end
  return { { text } }
end

local function pick(o)
  require("snacks").picker.pick({
    source = o.source,
    title = o.title,
    items = o.items,
    format = picker_format,
    -- Preview the highlighted item's file content by default (every note/file
    -- item carries `file`). Callers override (e.g. "directory") when items aren't notes.
    preview = o.preview or "file",
    confirm = function(picker, item)
      local sel
      if o.multi then
        -- fallback = true: Enter on a highlighted item (no Tab-marks) operates on
        -- just that item; Tab-mark several, then Enter operates on the whole set.
        sel = picker:selected({ fallback = true })
      else
        sel = item and { item } or {}
      end
      picker:close()
      vim.schedule(function()
        o.on_choice(sel)
      end)
    end,
  })
end

-- Open picked notes: a single selection is opened (focused); multiple selections
-- are added to the buffer list in the background so you can :bnext through them.
local function open_notes(items)
  if not items or #items == 0 then
    return
  end
  if #items == 1 then
    if items[1].file then
      vim.cmd.edit(vim.fn.fnameescape(items[1].file))
    end
    return
  end
  local n = 0
  for _, it in ipairs(items) do
    if it.file then
      vim.cmd("badd " .. vim.fn.fnameescape(it.file))
      n = n + 1
    end
  end
  vim.notify(("Opened %d notes in the background — :bnext to iterate"):format(n), vim.log.levels.INFO)
end

-- ── new note with parent MOC(s) ──────────────────────────────────────────────

local function create_note(dir, name, template_name, moc_links)
  local Note = require("obsidian.note")
  local note = Note.create({ id = name, dir = dir, template = template_name })
  note:write({}) -- clones the template into the file; frontmatter left as-is
  if #moc_links > 0 then
    local ok, reason = write_parents(tostring(note.path), moc_links)
    if not ok then
      vim.notify("Created note but could not set parents: " .. tostring(reason), vim.log.levels.WARN)
    end
  end
  note:open({ sync = true })
end

local function new_note_with_parents(dir)
  local templates = template_items()
  if #templates == 0 then
    vim.notify("No templates found in templates/", vim.log.levels.ERROR)
    return
  end
  pick({
    source = "obs_new_template",
    title = "Template",
    items = templates,
    multi = false,
    on_choice = function(sel)
      local tmpl = sel[1]
      if not tmpl then
        return
      end
      vim.ui.input({ prompt = "Note name: " }, function(name)
        if not name or vim.trim(name) == "" then
          return
        end
        name = vim.trim(name)
        pick({
          source = "obs_new_parents",
          title = "Parent MOC(s) — Enter = highlighted, Tab = multi-select",
          items = moc_items(collect_mocs()),
          multi = true,
          on_choice = function(psel)
            local links = {}
            for _, it in ipairs(psel) do
              if it.moc then
                links[#links + 1] = it.moc.link
              end
            end
            create_note(dir, name, tmpl.text, links)
          end,
        })
      end)
    end,
  })
end

-- ── re-parenting (MOC swap / add) ────────────────────────────────────────────

-- For each selected note: drop any parent whose target is in `remove_refids`
-- (pass nil to remove nothing), then append `add_links`, skipping duplicates.
---@return integer applied, integer skipped
local function reparent_notes(items, remove_refids, add_links)
  local applied, skipped = 0, 0
  for _, it in ipairs(items) do
    local p = it.file
    local fm = read_file(p)
    if not fm or not fm.ok then
      skipped = skipped + 1
    else
      local parents = (type(fm.data.parents) == "table") and fm.data.parents or {}
      local kept, present = {}, {}
      for _, entry in ipairs(parents) do
        if type(entry) == "string" then
          local tgt = link_target(entry)
          if not (remove_refids and tgt and remove_refids[tgt]) and tgt ~= "" then
            kept[#kept + 1] = entry
            if tgt then
              present[tgt] = true
            end
          end
        end
      end
      for _, link in ipairs(add_links) do
        local tgt = link_target(link)
        if not (tgt and present[tgt]) then
          kept[#kept + 1] = link
          if tgt then
            present[tgt] = true
          end
        end
      end
      if write_parents(p, kept) then
        applied = applied + 1
      else
        skipped = skipped + 1
      end
    end
  end
  return applied, skipped
end

-- Pick target MOC(s), then apply. `verb`/`remove_refids` differ for swap vs add.
local function pick_targets_and_apply(notes, remove_refids, verb)
  pick({
    source = "obs_moc_targets",
    title = (verb == "swap" and "New parent MOC(s)" or "Parent MOC(s) to add")
      .. " — Enter = highlighted, Tab = multi-select",
    items = moc_items(collect_mocs()),
    multi = true,
    on_choice = function(msel)
      local add_links = {}
      for _, it in ipairs(msel) do
        if it.moc then
          add_links[#add_links + 1] = it.moc.link
        end
      end
      if #add_links == 0 then
        vim.notify("No MOC selected — aborted", vim.log.levels.WARN)
        return
      end
      local applied, skipped = reparent_notes(notes, remove_refids, add_links)
      vim.notify(
        ("%s %d note(s)%s"):format(
          verb == "swap" and "Re-parented" or "Added parent to",
          applied,
          skipped > 0 and (", skipped " .. skipped .. " (malformed frontmatter)") or ""
        ),
        vim.log.levels.INFO
      )
    end,
  })
end

-- <leader>op — only valid on a `type/moc` buffer. Re-parent the notes that
-- declare THIS moc as a parent onto one or more other MOCs (i.e. promote a
-- cohering cluster into its own child MOC).
local function moc_swap()
  local path = vim.api.nvim_buf_get_name(0)
  local fm = read_file(path)
  if not fm or not fm.ok or type(fm.data.tags) ~= "table" or not vim.tbl_contains(fm.data.tags, "type/moc") then
    vim.notify("Not a type/moc note — MOC swap only runs from a MOC buffer", vim.log.levels.WARN)
    return
  end
  local stem = vim.fn.fnamemodify(path, ":t:r")
  local refids = note_ref_ids(path, fm.data)

  local children = collect_children({ path = path, stem = stem })
  if #children == 0 then
    vim.notify("No notes declare [[" .. stem .. "]] as a parent", vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, c in ipairs(children) do
    items[#items + 1] = { text = relpath(c.path), file = c.path }
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)

  pick({
    source = "obs_moc_children",
    title = "Notes to re-parent off [[" .. stem .. "]] — Enter = highlighted, Tab = multi-select",
    items = items,
    multi = true,
    on_choice = function(csel)
      if #csel == 0 then
        return
      end
      pick_targets_and_apply(csel, refids, "swap")
    end,
  })
end

-- <leader>oP — works anywhere. Pick any notes, then add one or more MOCs to
-- their `parents:` (nothing is removed).
local function moc_add()
  pick({
    source = "obs_all_notes",
    title = "Notes to add a parent to — Enter = highlighted, Tab = multi-select",
    items = all_note_items(),
    multi = true,
    on_choice = function(nsel)
      if #nsel == 0 then
        return
      end
      pick_targets_and_apply(nsel, nil, "add")
    end,
  })
end

-- <leader>oc — pick root MOC(s), then browse every note in their parents-subtree
-- (direct or recursive children), ranked by how many roots reach a note (desc)
-- then by depth (shallowest first).
local function moc_tree()
  pick({
    source = "obs_moctree_roots",
    title = "Root MOC(s) — Enter = highlighted, Tab = multi-select",
    items = moc_items(collect_mocs()),
    multi = true,
    on_choice = function(rsel)
      local roots = {}
      for _, it in ipairs(rsel) do
        if it.moc then
          roots[#roots + 1] = it.moc.path
        end
      end
      if #roots == 0 then
        return
      end
      local t0 = uv.hrtime()
      local items = moc_tree_items(expand_descendants(roots, build_index()))
      local ms = (uv.hrtime() - t0) / 1e6
      if #items == 0 then
        vim.notify("No descendant notes found", vim.log.levels.INFO)
        return
      end
      pick({
        source = "obs_moctree_notes",
        title = ("Subtree of %d MOC(s) · %d notes · %.0fms"):format(#roots, #items, ms),
        items = items,
        multi = true,
        on_choice = open_notes,
      })
    end,
  })
end

-- ── lint ─────────────────────────────────────────────────────────────────────

-- Scan the vault once and bucket notes into hygiene categories. `broken` entries
-- carry the offending parent strings; the rest are plain path lists.
---@return { orphans: string[], untyped: string[], no_desc: string[], broken: {path:string,bad:string[]}[], malformed: string[] }, integer
local function lint_scan()
  local report_abs = VAULT .. "/" .. LINT_REPORT
  local files = vim.tbl_filter(function(p)
    return p ~= report_abs
  end, vault_md_files())

  local parsed, refset, path_of, is_moc = {}, {}, {}, {}
  for _, p in ipairs(files) do
    local fm = read_fm(p)
    parsed[p] = fm
    if fm then
      if type(fm.data.tags) == "table" and vim.tbl_contains(fm.data.tags, "type/moc") then
        is_moc[p] = true
      end
      for id in pairs(note_ref_ids(p, fm.data)) do
        refset[id] = true
        path_of[id] = path_of[id] or p
      end
    end
  end

  local cats = { orphans = {}, untyped = {}, no_desc = {}, broken = {}, malformed = {} }
  for _, p in ipairs(files) do
    local fm = parsed[p]
    if not fm or not fm.ok then
      cats.malformed[#cats.malformed + 1] = p
    else
      local d = fm.data

      -- "orphan" = a non-MOC note with no parent that resolves to a type/moc note.
      local has_moc_parent = false
      if type(d.parents) == "table" then
        for _, e in ipairs(d.parents) do
          local tgt = link_target(e)
          local pp = (tgt and tgt ~= "") and path_of[tgt] or nil
          if pp and is_moc[pp] then
            has_moc_parent = true
          end
        end
      end
      if not is_moc[p] and not has_moc_parent then
        cats.orphans[#cats.orphans + 1] = p
      end

      local typed = false
      if type(d.tags) == "table" then
        for _, t in ipairs(d.tags) do
          if type(t) == "string" and t:match("^type/") then
            typed = true
          end
        end
      end
      if not typed then
        cats.untyped[#cats.untyped + 1] = p
      end

      local desc = d.description
      if
        desc == nil
        or (type(desc) == "string" and (vim.trim(desc) == "" or BOILERPLATE_DESC[vim.trim(desc):lower()]))
      then
        cats.no_desc[#cats.no_desc + 1] = p
      end

      local bad = {}
      if type(d.parents) == "table" then
        for _, e in ipairs(d.parents) do
          local tgt = link_target(e)
          if tgt and tgt ~= "" and not refset[tgt] then
            bad[#bad + 1] = tostring(e)
          end
        end
      end
      if #bad > 0 then
        cats.broken[#cats.broken + 1] = { path = p, bad = bad }
      end
    end
  end
  return cats, #files
end

-- <leader>org / :ObsLint — write the hygiene report and open it.
local function obs_lint()
  vim.notify("Linting vault…", vim.log.levels.INFO)
  local cats, scanned = lint_scan()

  local function linkify(p)
    return "[[" .. relpath(p):gsub("%.md$", "") .. "|" .. vim.fn.fnamemodify(p, ":t:r") .. "]]"
  end
  local function section(title, list, fmt)
    local out = { ("## %s (%d)"):format(title, #list), "" }
    if #list == 0 then
      out[#out + 1] = "_none_"
    else
      for _, it in ipairs(list) do
        out[#out + 1] = "- " .. fmt(it)
      end
    end
    out[#out + 1] = ""
    return out
  end

  local lines = {
    "---",
    "tags:",
    "  - type/note",
    "description: Generated vault hygiene report",
    "---",
    "",
    "# Lint Report",
    "",
    ("Scanned %d notes."):format(scanned),
    "",
  }
  vim.list_extend(lines, section("Orphans (no MOC parent)", cats.orphans, linkify))
  vim.list_extend(lines, section("Untyped (no type/*)", cats.untyped, linkify))
  vim.list_extend(lines, section("Missing / boilerplate description", cats.no_desc, linkify))
  vim.list_extend(lines, section("Broken parent links", cats.broken, function(it)
    return linkify(it.path) .. " → `" .. table.concat(it.bad, ", ") .. "`"
  end))
  vim.list_extend(lines, section("Malformed frontmatter", cats.malformed, linkify))

  local report_abs = VAULT .. "/" .. LINT_REPORT
  vim.fn.writefile(lines, report_abs)
  vim.notify(
    ("Lint: %d orphan · %d untyped · %d desc · %d broken · %d malformed → %s"):format(
      #cats.orphans, #cats.untyped, #cats.no_desc, #cats.broken, #cats.malformed, LINT_REPORT
    ),
    vim.log.levels.INFO
  )
  vim.cmd.edit(vim.fn.fnameescape(report_abs))
end

local function broken_paths(cats)
  local ps = {}
  for _, e in ipairs(cats.broken) do
    ps[#ps + 1] = e.path
  end
  return ps
end

local function path_items(paths)
  local items = {}
  for _, p in ipairs(paths) do
    items[#items + 1] = { text = relpath(p), file = p }
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  return items
end

-- Lowercase keys: browse a category's notes; Enter opens the note.
local function lint_pick(paths, title)
  if #paths == 0 then
    vim.notify("No notes in this category 🎉", vim.log.levels.INFO)
    return
  end
  pick({
    source = "obs_lint_pick",
    title = title .. " — Enter opens; Tab marks several to open in background",
    items = path_items(paths),
    multi = true,
    on_choice = open_notes,
  })
end

-- Capital keys: multi-select a category's notes, then hand the chosen items
-- (each with `.file`) to `resolve`.
local function lint_resolve(paths, title, resolve)
  if #paths == 0 then
    vim.notify("Nothing to resolve 🎉", vim.log.levels.INFO)
    return
  end
  pick({
    source = "obs_lint_resolve",
    title = title,
    items = path_items(paths),
    multi = true,
    on_choice = function(sel)
      if #sel > 0 then
        resolve(sel)
      end
    end,
  })
end

local TYPE_CHOICES = {
  "type/note", "type/moc", "type/article", "type/list",
  "type/log", "type/person", "type/tasks", "type/reference", "type/ticket",
}

-- Sequentially prompt a description for each selected note and set it.
local function set_descriptions(notes, i)
  i = i or 1
  if i > #notes then
    vim.notify(("Done setting descriptions (%d note(s))"):format(#notes), vim.log.levels.INFO)
    return
  end
  local path = notes[i].file
  vim.ui.input({ prompt = ("[%d/%d] Description for %s: "):format(i, #notes, relpath(path)) }, function(input)
    if input and vim.trim(input) ~= "" then
      set_description_on(path, vim.trim(input))
    end
    set_descriptions(notes, i + 1)
  end)
end

-- ── lint group: pickers (lowercase) + resolvers (capital) ────────────────────

local function lint_orphans()
  lint_pick((lint_scan()).orphans, "Orphans (no MOC parent)")
end
local function lint_orphans_fix()
  lint_resolve((lint_scan()).orphans, "Orphans (no MOC parent) → pick notes (Tab=multi), then add parent MOC(s)", function(notes)
    pick_targets_and_apply(notes, nil, "add")
  end)
end

local function lint_untyped()
  lint_pick((lint_scan()).untyped, "Untyped (no type/*)")
end
local function lint_untyped_fix()
  lint_resolve((lint_scan()).untyped, "Untyped → pick notes, then choose a type", function(notes)
    local titems = {}
    for _, t in ipairs(TYPE_CHOICES) do
      titems[#titems + 1] = { text = t, type_tag = t }
    end
    pick({
      source = "obs_lint_type",
      title = "Type to apply — Enter",
      items = titems,
      multi = false,
      preview = "none",
      on_choice = function(tsel)
        local t = tsel[1] and tsel[1].type_tag
        if not t then
          return
        end
        local n = 0
        for _, it in ipairs(notes) do
          if add_tag_on(it.file, t) then
            n = n + 1
          end
        end
        vim.notify(("Tagged %d note(s) %s"):format(n, t), vim.log.levels.INFO)
      end,
    })
  end)
end

local function lint_no_desc()
  lint_pick((lint_scan()).no_desc, "Missing / boilerplate description")
end
local function lint_no_desc_fix()
  lint_resolve((lint_scan()).no_desc, "Description → pick notes, then type one for each", function(notes)
    set_descriptions(notes)
  end)
end

local function lint_broken()
  lint_pick(broken_paths(lint_scan()), "Broken parent links")
end
local function lint_broken_fix()
  lint_resolve(broken_paths(lint_scan()), "Broken → pick notes, then pick replacement parent MOC(s)", function(notes)
    pick({
      source = "obs_lint_broken_targets",
      title = "Replacement parent MOC(s) — Enter = highlighted, Tab = multi-select",
      items = moc_items(collect_mocs()),
      multi = true,
      on_choice = function(msel)
        local links = {}
        for _, it in ipairs(msel) do
          if it.moc then
            links[#links + 1] = it.moc.link
          end
        end
        if #links == 0 then
          vim.notify("No MOC selected — aborted", vim.log.levels.WARN)
          return
        end
        local n = 0
        for _, it in ipairs(notes) do
          if write_parents(it.file, links) then -- replaces the broken parents
            n = n + 1
          end
        end
        vim.notify(("Re-parented %d note(s)"):format(n), vim.log.levels.INFO)
      end,
    })
  end)
end

local function lint_malformed()
  lint_pick((lint_scan()).malformed, "Malformed frontmatter")
end
-- No safe auto-fix for malformed YAML; the resolver just opens the picked notes
-- (as buffers) so you can fix the frontmatter by hand and :bnext through them.
local function lint_malformed_fix()
  lint_resolve((lint_scan()).malformed, "Malformed → pick notes to open for hand-fixing", function(notes)
    open_notes(notes)
  end)
end

-- ── weedy queue ───────────────────────────────────────────────────────────────

local function obs_weedy()
  local items = {}
  for _, p in ipairs(rg_files_matching("weedy")) do
    local fm = read_file(p)
    if fm and fm.ok and type(fm.data.tags) == "table" and vim.tbl_contains(fm.data.tags, "weedy") then
      local st = uv.fs_stat(p)
      local mtime = (st and st.mtime and st.mtime.sec) or 0

      local typ = "—"
      for _, t in ipairs(fm.data.tags) do
        if type(t) == "string" and t:match("^type/") then
          typ = t
        end
      end

      local par = "—"
      if type(fm.data.parents) == "table" then
        local ts = {}
        for _, e in ipairs(fm.data.parents) do
          local tgt = link_target(e)
          if tgt and tgt ~= "" then
            ts[#ts + 1] = tgt
          end
        end
        if #ts > 0 then
          par = table.concat(ts, ",")
        end
      end

      local desc = (type(fm.data.description) == "string" and vim.trim(fm.data.description) ~= "")
          and fm.data.description
        or ""

      items[#items + 1] = {
        text = ("%-46s  [%s]  ⇧ %s   %s"):format(relpath(p), typ, par, desc),
        file = p,
        mtime = mtime,
      }
    end
  end

  if #items == 0 then
    vim.notify("No weedy notes 🎉", vim.log.levels.INFO)
    return
  end
  table.sort(items, function(a, b)
    return a.mtime < b.mtime -- oldest first
  end)

  pick({
    source = "obs_weedy",
    title = ("Weedy queue (%d) — oldest first; Tab marks several to open in background"):format(#items),
    items = items,
    multi = true,
    on_choice = open_notes,
  })
end

-- ── plugin spec ────────────────────────────────────────────────────────────────

-- ── move files to a directory ────────────────────────────────────────────────

-- All directories in the vault (absolute), excluding .git/.obsidian/.trash.
local function vault_dirs()
  local dirs = nonempty(vim.fn.systemlist({
    "find", VAULT, "-type", "d",
    "(", "-name", ".git", "-o", "-name", ".obsidian", "-o", "-name", ".trash", ")", "-prune",
    "-o", "-type", "d", "-print",
  }))
  table.sort(dirs)
  return dirs
end

local function dir_items()
  local items = {}
  for _, d in ipairs(vault_dirs()) do
    local r = relpath(d)
    items[#items + 1] = { text = (r == d) and "/ (vault root)" or r, dir = d, file = d }
  end
  return items
end

-- Every file in the vault (not just notes), for the multi-file move picker.
local function vault_all_file_items()
  local items = {}
  for _, p in ipairs(nonempty(vim.fn.systemlist({ "rg", "--files", "--no-ignore", "--color=never", VAULT }))) do
    items[#items + 1] = { text = relpath(p), file = p }
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  return items
end

-- Move one file into dst_dir, preferring `git mv` to preserve history, and
-- re-point any open buffer at the new path. Returns (ok, dst_or_error).
local function move_file(src, dst_dir)
  local dst = dst_dir .. "/" .. vim.fn.fnamemodify(src, ":t")
  if vim.fn.fnamemodify(src, ":p") == vim.fn.fnamemodify(dst, ":p") then
    return true, dst
  end
  if vim.fn.filereadable(dst) == 1 then
    return false, "target exists: " .. relpath(dst)
  end
  vim.fn.mkdir(dst_dir, "p")
  vim.fn.system({ "git", "-C", VAULT, "mv", "-f", src, dst })
  if vim.v.shell_error ~= 0 then
    local ok, err = os.rename(src, dst)
    if not ok then
      return false, tostring(err)
    end
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == src then
      vim.api.nvim_buf_set_name(b, dst)
      vim.api.nvim_buf_call(b, function()
        vim.cmd("silent! edit!")
      end)
    end
  end
  return true, dst
end

-- <leader>om — move the current file into a directory chosen from a picker.
local function move_current_file()
  local src = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
  if src == "" or vim.fn.filereadable(src) == 0 then
    vim.notify("No file in the current buffer", vim.log.levels.ERROR)
    return
  end
  pick({
    source = "obs_move_dir",
    title = "Move " .. relpath(src) .. " to — Enter to confirm",
    items = dir_items(),
    preview = "directory",
    multi = false,
    on_choice = function(sel)
      local it = sel[1]
      if not it then
        return
      end
      local ok, dst = move_file(src, it.dir)
      vim.notify(
        ok and ("Moved to " .. relpath(dst)) or ("Move failed: " .. tostring(dst)),
        ok and vim.log.levels.INFO or vim.log.levels.ERROR
      )
    end,
  })
end

-- <leader>oM — pick multiple files, then a directory, and move them all there.
local function move_files()
  pick({
    source = "obs_move_files",
    title = "Files to move — Enter = highlighted, Tab = multi-select",
    items = vault_all_file_items(),
    multi = true,
    on_choice = function(fsel)
      if #fsel == 0 then
        return
      end
      pick({
        source = "obs_move_files_dir",
        title = ("Move %d file(s) to — Enter to confirm"):format(#fsel),
        items = dir_items(),
        preview = "directory",
        multi = false,
        on_choice = function(dsel)
          local it = dsel[1]
          if not it then
            return
          end
          local moved, failed = 0, 0
          for _, f in ipairs(fsel) do
            if (move_file(f.file, it.dir)) then
              moved = moved + 1
            else
              failed = failed + 1
            end
          end
          vim.notify(("Moved %d file(s)%s to %s"):format(
            moved, failed > 0 and (", " .. failed .. " failed") or "", relpath(it.dir)))
        end,
      })
    end,
  })
end

-- <leader>od / <leader>oD — open (creating if needed) today's daily log, under
-- work/daily or daily, foldered by year / abbreviated month
-- (e.g. daily/2026/Jun/2026-06-25.md). Work logs use the "Work Log" template,
-- personal logs use "Log"; the template's {{date}} fills in.
local function open_daily(work)
  local dir = (work and "work/daily" or "daily") .. "/" .. os.date("%Y") .. "/" .. os.date("%b")
  local id = os.date("%Y-%m-%d")
  local abs = VAULT .. "/" .. dir .. "/" .. id .. ".md"
  if vim.fn.filereadable(abs) == 1 then
    vim.cmd.edit(vim.fn.fnameescape(abs))
    return
  end
  local note = require("obsidian.note").create({ id = id, dir = dir, template = (work and "Work Log" or "Log") })
  note:write({})
  note:open({ sync = true })
end

-- ── tags ──────────────────────────────────────────────────────────────────────

-- Collect every tag used in the vault (frontmatter + inline, code blocks excluded)
-- via obsidian.nvim's own tag search, then call on_tags(sorted_unique_bare_tags).
local function with_vault_tags(on_tags)
  local search = require("obsidian.search")
  local api = require("obsidian.api")
  search.find_tags_async("", function(locs)
    local seen, tags = {}, {}
    for _, loc in ipairs(locs) do
      if loc.tag and not seen[loc.tag] then
        seen[loc.tag] = true
        tags[#tags + 1] = loc.tag
      end
    end
    table.sort(tags)
    on_tags(tags) -- find_tags_async already schedule-wraps this callback
  end, { dir = api.resolve_workspace_dir() })
end

-- Picker over all vault tags; on_choice gets the chosen bare tag list.
local function tag_picker(title, on_choice)
  with_vault_tags(function(tags)
    if #tags == 0 then
      vim.notify("No tags found in the vault", vim.log.levels.WARN)
      return
    end
    local items = {}
    for _, t in ipairs(tags) do
      items[#items + 1] = { text = t, tag = t }
    end
    pick({
      source = "obs_tags",
      title = title,
      items = items,
      multi = true,
      preview = "none",
      on_choice = function(sel)
        local chosen = {}
        for _, it in ipairs(sel) do
          if it.tag then
            chosen[#chosen + 1] = it.tag
          end
        end
        if #chosen > 0 then
          on_choice(chosen)
        end
      end,
    })
  end)
end

-- Like edit_frontmatter, but on a live buffer (preserves unsaved edits; the user saves).
local function edit_frontmatter_buf(bufnr, mutate, ensure_keys)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local function fence(l)
    return l ~= nil and l:match("^%-%-%-+%s*$") ~= nil
  end
  local has_fm = fence(lines[1])
  local fm_end, data, order = nil, {}, {}
  if has_fm then
    for i = 2, #lines do
      if fence(lines[i]) then
        fm_end = i
        break
      end
    end
    if not fm_end then
      return false, "malformed frontmatter (unclosed)"
    end
    local body = {}
    for i = 2, fm_end - 1 do
      body[#body + 1] = lines[i]
    end
    local ok, d, o = pcall(require("obsidian.yaml").loads, table.concat(body, "\n"))
    if not ok or type(d) ~= "table" then
      return false, "malformed frontmatter"
    end
    data, order = d, o or {}
  end
  mutate(data)
  for _, k in ipairs(ensure_keys or {}) do
    if not vim.tbl_contains(order, k) then
      table.insert(order, 1, k)
    end
  end
  local fm_lines = require("obsidian.frontmatter").dump(data, order)
  vim.api.nvim_buf_set_lines(bufnr, 0, has_fm and fm_end or 0, false, fm_lines)
  return true
end

-- <leader>oa — pick tag(s), insert at the cursor as `#tag` (comma-separated).
local function insert_tags_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local cur = vim.api.nvim_win_get_cursor(win)
  tag_picker("Insert #tag(s) at cursor — Enter = highlighted, Tab = multi-select", function(tags)
    local parts = {}
    for _, t in ipairs(tags) do
      parts[#parts + 1] = "#" .. t
    end
    local text = table.concat(parts, ", ")
    local row, col = cur[1] - 1, cur[2]
    vim.api.nvim_buf_set_text(buf, row, col, row, col, { text })
    pcall(vim.api.nvim_win_set_cursor, win, { cur[1], col + #text })
  end)
end

-- <leader>oA — pick tag(s), add them to the current buffer's frontmatter `tags`.
local function add_tags_to_frontmatter()
  local buf = vim.api.nvim_get_current_buf()
  tag_picker("Add tag(s) to frontmatter — Enter = highlighted, Tab = multi-select", function(tags)
    local ok, err = edit_frontmatter_buf(buf, function(d)
      local t = (type(d.tags) == "table") and d.tags or {}
      for _, tag in ipairs(tags) do
        if not vim.tbl_contains(t, tag) then
          t[#t + 1] = tag
        end
      end
      d.tags = t
    end, { "tags" })
    vim.notify(
      ok and ("Added %d tag(s) to frontmatter"):format(#tags) or ("Couldn't update frontmatter: " .. tostring(err)),
      ok and vim.log.levels.INFO or vim.log.levels.ERROR
    )
  end)
end

-- <leader>op — add parent MOC(s) to the CURRENT note (no note picker; operates on
-- the focused buffer, live, so unsaved edits are kept). Like <leader>oP scoped to
-- this one note: keeps existing real parents, drops empty placeholders, dedupes.
local function moc_add_current()
  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buf) == "" then
    vim.notify("No file in the current buffer", vim.log.levels.WARN)
    return
  end
  pick({
    source = "obs_moc_add_current",
    title = "Parent MOC(s) to add to this note — Enter = highlighted, Tab = multi-select",
    items = moc_items(collect_mocs()),
    multi = true,
    on_choice = function(msel)
      local links = {}
      for _, it in ipairs(msel) do
        if it.moc then
          links[#links + 1] = it.moc.link
        end
      end
      if #links == 0 then
        return
      end
      local ok, err = edit_frontmatter_buf(buf, function(d)
        local kept, present = {}, {}
        if type(d.parents) == "table" then
          for _, e in ipairs(d.parents) do
            local t = link_target(e)
            if type(e) == "string" and t and t ~= "" then
              kept[#kept + 1] = e
              present[t] = true
            end
          end
        end
        for _, link in ipairs(links) do
          local t = link_target(link)
          if not (t and present[t]) then
            kept[#kept + 1] = link
            if t then
              present[t] = true
            end
          end
        end
        d.parents = kept
      end, { "parents" })
      vim.notify(
        ok and ("Added %d parent MOC(s)"):format(#links) or ("Couldn't update parents: " .. tostring(err)),
        ok and vim.log.levels.INFO or vim.log.levels.ERROR
      )
    end,
  })
end

-- ── note pickers that replace obsidian.nvim built-ins ────────────────────────
-- These wrap quick-switch / backlinks / links so multi-select opens the chosen
-- notes in the background (via open_notes), instead of opening just one.

-- <leader>oq — quick-switch over every note in the vault.
local function obs_quick_switch()
  pick({
    source = "obs_quick_switch",
    title = "Notes — Enter opens; Tab marks several to open in background",
    items = all_note_items(),
    multi = true,
    on_choice = open_notes,
  })
end

-- <leader>ob — notes that link TO the current note (backlinks).
local function obs_backlinks()
  local note = require("obsidian.api").current_note(0)
  if not note then
    vim.notify("Not in a note", vim.log.levels.WARN)
    return
  end
  note:backlinks_async({}, function(matches)
    local seen, items = {}, {}
    for _, m in ipairs(matches) do
      local p = tostring(m.path)
      if not seen[p] then
        seen[p] = true
        items[#items + 1] = { text = relpath(p), file = p }
      end
    end
    if #items == 0 then
      vim.notify("No backlinks", vim.log.levels.INFO)
      return
    end
    table.sort(items, function(a, b)
      return a.text < b.text
    end)
    vim.schedule(function()
      pick({
        source = "obs_backlinks",
        title = "Backlinks — Enter opens; Tab marks several to open in background",
        items = items,
        multi = true,
        on_choice = open_notes,
      })
    end)
  end)
end

-- refid → path map for the whole vault (filename stems, relpaths, and aliases all
-- lower-cased), so wiki-links — including alias links like [[home]] — resolve right.
local function vault_path_index()
  local path_of = {}
  for _, p in ipairs(vault_md_files()) do
    local fm = read_fm(p)
    if fm then
      for id in pairs(note_ref_ids(p, fm.data)) do
        path_of[id] = path_of[id] or p
      end
    end
  end
  return path_of
end

-- <leader>ol — open the notes the current note links to. Wiki-links are resolved
-- through the vault index (alias-aware), so [[home]] → mocs/home moc.md, etc.
local function obs_links()
  local note = require("obsidian.api").current_note(0)
  if not note then
    vim.notify("Not in a note", vim.log.levels.WARN)
    return
  end
  local path_of = vault_path_index()
  local seen, items = {}, {}
  for _, m in ipairs(note:links()) do
    local tgt = link_target(m.link)
    local p = (tgt and tgt ~= "") and path_of[tgt] or nil
    if p and not seen[p] then
      seen[p] = true
      items[#items + 1] = { text = m.link .. "  →  " .. relpath(p), file = p }
    end
  end
  if #items == 0 then
    vim.notify("No resolvable wiki-links to notes here", vim.log.levels.INFO)
    return
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  pick({
    source = "obs_links",
    title = "Outgoing links — Enter opens; Tab marks several to open in background",
    items = items,
    multi = true,
    on_choice = open_notes,
  })
end

-- <leader>om / <leader>oQ — quick-switch over MOCs (breadcrumb picker; typing a
-- MOC name keeps its whole subtree). Multi-select opens them in the background.
local function obs_moc_switch()
  pick({
    source = "obs_moc_switch",
    title = "MOCs — Enter opens; Tab marks several to open in background",
    items = moc_items(collect_mocs()),
    multi = true,
    on_choice = open_notes,
  })
end

-- <leader>oB — notes that declare the CURRENT note as a parent (i.e. backlinks
-- via the `parents:` frontmatter only, not generic body links).
local function obs_parent_backlinks()
  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
  if path == "" or vim.fn.filereadable(path) == 0 then
    vim.notify("No file in the current buffer", vim.log.levels.WARN)
    return
  end
  local children = collect_children({ path = path, stem = vim.fn.fnamemodify(path, ":t:r") })
  if #children == 0 then
    vim.notify("No notes declare this note as a parent", vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, c in ipairs(children) do
    items[#items + 1] = { text = relpath(c.path), file = c.path }
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  pick({
    source = "obs_parent_backlinks",
    title = "Parent-backlinks (notes parented here) — Enter opens; Tab marks several",
    items = items,
    multi = true,
    on_choice = open_notes,
  })
end

-- <leader>of / <leader>oF — pick notes whose vault path contains `needle`
-- (e.g. "fleeting" or "in_progress", which match across all the mirrored trees).
local function obs_notes_in(needle, label)
  local items = {}
  for _, p in ipairs(vault_md_files()) do
    local rel = relpath(p)
    if rel:find(needle, 1, true) then
      items[#items + 1] = { text = rel, file = p }
    end
  end
  if #items == 0 then
    vim.notify("No notes with '" .. needle .. "' in their path", vim.log.levels.INFO)
    return
  end
  table.sort(items, function(a, b)
    return a.text < b.text
  end)
  pick({
    source = "obs_path_" .. needle,
    title = label .. " — Enter opens; Tab marks several to open in background",
    items = items,
    multi = true,
    on_choice = open_notes,
  })
end

-- ── plugin spec ────────────────────────────────────────────────────────────────

return {
  "obsidian-nvim/obsidian.nvim",
  version = "*", -- recommended, use latest release instead of latest commit
  ft = "markdown",

  ---@module 'obsidian'
  ---@type obsidian.config

  dependencies = {
    'folke/snacks.nvim',
    'nvim-treesitter/nvim-treesitter',
  },

  keys = {
    {
      "<leader>on",
      function()
        new_note_with_parents("work/fleeting")
      end,
      desc = "Obsidian new note (+ parent MOC picker)",
    },
    {
      "<leader>oN",
      function()
        new_note_with_parents("nosync/fleeting")
      end,
      desc = "Obsidian new note in nosync (+ parent MOC picker)",
    },
    {
      "<leader>op",
      moc_add_current,
      desc = "Obsidian add parent MOC(s) to this note",
    },
    {
      "<leader>oS",
      moc_swap,
      desc = "Obsidian MOC swap (re-parent notes off this MOC)",
    },
    {
      "<leader>oP",
      moc_add,
      desc = "Obsidian add parent MOC to notes (anywhere)",
    },
    { "<leader>org", obs_lint, desc = "Lint: generate report" },
    { "<leader>oro", lint_orphans, desc = "Lint: orphans (no parent)" },
    { "<leader>orO", lint_orphans_fix, desc = "Lint: orphans → assign parent MOC(s)" },
    { "<leader>oru", lint_untyped, desc = "Lint: untyped notes" },
    { "<leader>orU", lint_untyped_fix, desc = "Lint: untyped → assign type/*" },
    { "<leader>ord", lint_no_desc, desc = "Lint: missing/boilerplate description" },
    { "<leader>orD", lint_no_desc_fix, desc = "Lint: → set descriptions" },
    { "<leader>orb", lint_broken, desc = "Lint: broken parent links" },
    { "<leader>orB", lint_broken_fix, desc = "Lint: → fix broken parents" },
    { "<leader>orm", lint_malformed, desc = "Lint: malformed frontmatter" },
    { "<leader>orM", lint_malformed_fix, desc = "Lint: → open malformed to hand-fix" },
    {
      "<leader>ow",
      obs_weedy,
      desc = "Obsidian weedy triage queue",
    },
    {
      "<leader>oc",
      moc_tree,
      desc = "Obsidian MOC subtree (descendants picker)",
    },
    {
      "<leader>om",
      obs_moc_switch,
      desc = "Obsidian MOC quick-switch",
    },
    {
      "<leader>oQ",
      obs_moc_switch,
      desc = "Obsidian MOC quick-switch",
    },
    {
      "<leader>ov",
      move_current_file,
      desc = "Obsidian move current file to a directory",
    },
    {
      "<leader>oV",
      move_files,
      desc = "Obsidian move selected files to a directory",
    },
    {
      "<leader>od",
      function()
        open_daily(true)
      end,
      desc = "Obsidian work daily note (create if needed)",
    },
    {
      "<leader>oD",
      function()
        open_daily(false)
      end,
      desc = "Obsidian daily note (create if needed)",
    },
    {
      "<leader>oa",
      insert_tags_at_cursor,
      desc = "Obsidian insert #tag(s) at cursor",
    },
    {
      "<leader>oA",
      add_tags_to_frontmatter,
      desc = "Obsidian add tag(s) to frontmatter",
    },
    {
      "<leader>oq",
      obs_quick_switch,
      desc = "Obsidian quick switch (multi → open in background)",
    },
    {
      "<leader>ob",
      obs_backlinks,
      desc = "Obsidian backlinks (multi → open in background)",
    },
    {
      "<leader>oB",
      obs_parent_backlinks,
      desc = "Obsidian parent-backlinks (notes parented here)",
    },
    {
      "<leader>of",
      function()
        obs_notes_in("fleeting", "Fleeting notes")
      end,
      desc = "Obsidian notes with 'fleeting' in path",
    },
    {
      "<leader>oF",
      function()
        obs_notes_in("in_progress", "In-progress notes")
      end,
      desc = "Obsidian notes with 'in_progress' in path",
    },
    {
      "<leader>ol",
      obs_links,
      desc = "Obsidian links (multi → open in background)",
    },
  },

  config = function(_, opts)
    require("obsidian").setup(opts)
    -- Command aliases for the custom tooling (keybinds above are the primary UI).
    vim.api.nvim_create_user_command("ObsNew", function()
      new_note_with_parents("work/fleeting")
    end, { desc = "New note with parent MOC picker" })
    vim.api.nvim_create_user_command("ObsMocSwap", moc_swap, { desc = "Re-parent notes off this MOC" })
    vim.api.nvim_create_user_command("ObsMocAdd", moc_add, { desc = "Add a parent MOC to notes" })
    vim.api.nvim_create_user_command("ObsLint", obs_lint, { desc = "Vault hygiene lint report" })
    vim.api.nvim_create_user_command("ObsWeedy", obs_weedy, { desc = "Weedy triage queue" })
    vim.api.nvim_create_user_command("ObsMocTree", moc_tree, { desc = "Browse the subtree of selected MOCs" })
    vim.api.nvim_create_user_command("ObsMove", move_current_file, { desc = "Move the current file to a directory" })
    vim.api.nvim_create_user_command("ObsMoveFiles", move_files, { desc = "Move selected files to a directory" })
    vim.api.nvim_create_user_command("ObsDaily", function() open_daily(false) end, { desc = "Open today's daily note" })
    vim.api.nvim_create_user_command("ObsWorkDaily", function() open_daily(true) end, { desc = "Open today's work daily note" })
    vim.api.nvim_create_user_command("ObsTagInsert", insert_tags_at_cursor, { desc = "Insert #tag(s) at cursor" })
    vim.api.nvim_create_user_command("ObsTagAdd", add_tags_to_frontmatter, { desc = "Add tag(s) to frontmatter" })
    vim.api.nvim_create_user_command("ObsMocSwitch", obs_moc_switch, { desc = "Quick-switch over MOCs" })
    vim.api.nvim_create_user_command("ObsParentBacklinks", obs_parent_backlinks, { desc = "Notes that declare this note a parent" })
    vim.api.nvim_create_user_command("ObsFleeting", function() obs_notes_in("fleeting", "Fleeting notes") end, { desc = "Notes with 'fleeting' in the path" })
    vim.api.nvim_create_user_command("ObsInProgress", function() obs_notes_in("in_progress", "In-progress notes") end, { desc = "Notes with 'in_progress' in the path" })
  end,

  opts = {
    ui = { enable = false }, -- use render-markdown instead
    picker = {
      name = "snacks.pick",
    },

    -- Disable backup files when editing vault files to prevent sync conflicts
    callbacks = {
      ---@param note obsidian.Note
      enter_note = function(note)
        vim.opt_local.backup = false
        vim.opt_local.writebackup = false
        vim.opt_local.swapfile = false

        -- Add fold settings
        vim.opt_local.foldmethod = "expr"
        vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.opt.foldlevelstart = 99
        vim.opt.foldtext = "" -- can look into nvim-ufo if we want more complicated rendering that preserves syntax highlighting
        vim.cmd('normal! zx')
      end,
    },

    workspaces = {
      {
        name = "Main",
        path = "~/vaults/Main",
      },
    },
    legacy_commands = false,
    templates = {
      folder = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
      -- A map for custom variables, the key should be the variable and the value a function
      substitutions = {},
    },
    notes_subdir="fleeting",
    new_notes_location = "notes_subdir",

    -- Optional, customize how note IDs are generated given an optional title.
    ---@param title string|?
    ---@return string
    note_id_func = function(title)
      return title or tostring(os.time())  -- fallback if nil
    end,

    -- Optional, customize how note file names are generated given the ID, target directory, and title.
    ---@param spec { id: string, dir: obsidian.Path, title: string|? }
    ---@return string|obsidian.Path The full path to the new note.
    note_path_func = function(spec)
      local path = spec.dir / tostring(spec.id)
      return path:with_suffix(".md")
    end,
    ---This was set to allow obsidian to be open in the background for obsidian sync.
    ---It likely makes not_id_func do nothing
    frontmatter = {
      enabled = false
    },

  ---Order of checkbox state chars, e.g. { " ", "x" }
  ---@field order? string[]
  checkbox = {
    order = { " ", "x" },
  },

    -- see below for full list of options 👇
  },

}
