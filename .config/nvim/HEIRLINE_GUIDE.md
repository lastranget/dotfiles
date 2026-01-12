# Complete Guide to heirline.lua

This guide provides an in-depth explanation of every aspect of the `heirline.lua` configuration file. If you're familiar with Neovim but new to heirline.nvim, this document will help you understand how everything works.

## Table of Contents

1. [What is Heirline?](#what-is-heirline)
2. [Core Concepts](#core-concepts)
3. [Component Structure](#component-structure)
4. [The TabLine Configuration](#the-tabline-configuration)
5. [The StatusLine Configuration](#the-statusline-configuration)
6. [Setup and Integration](#setup-and-integration)
7. [Customization Tips](#customization-tips)

---

## What is Heirline?

Heirline.nvim is a Neovim plugin that provides an API for building statuslines, tablines, winbars, and statuscolumns. Unlike other statusline plugins that come with pre-built configurations, heirline gives you complete control by requiring you to build everything from scratch using Lua.

**Key Philosophy:**
- No defaults provided
- Component-based architecture
- Recursive inheritance for code reuse
- Extremely fast and lightweight

Think of heirline as a framework rather than a ready-to-use plugin. You're the architect.

---

## Core Concepts

Before diving into the code, you need to understand how heirline works.

### Components Are Everything

In heirline, everything is a **component**. A component is simply a Lua table with specific fields that define its behavior. Here's the simplest possible component:

```lua
local SimpleComponent = {
  provider = "Hello, World!"
}
```

This component displays the text "Hello, World!" in your statusline.

### Component Fields

Components can have several fields, each serving a specific purpose:

#### 1. `provider` - What to Display

The `provider` field determines what text appears. It can be:

**A string:**
```lua
{ provider = "Hello" }
```

**A function returning a string:**
```lua
{
  provider = function()
    return "Current time: " .. os.date("%H:%M")
  end
}
```

**Vim statusline syntax:**
```lua
{
  provider = " %l:%c "  -- Shows line:column
}
```

Common statusline syntax patterns:
- `%l` - Line number
- `%c` - Column number
- `%p` or `%P` - Percentage through file (`%p` shows 0-100, `%P` shows "Top", "Bot", or percentage)
- `%f` - Filename (relative to current directory)
- `%F` - Full file path
- `%t` - Filename tail (just the filename, no path)
- `%m` - Modified flag (`[+]` if modified, empty otherwise)
- `%r` - Readonly flag (`[RO]` if readonly)
- `%=` - Separation point between left and right aligned items
- `%2(...)%)` - Ensure content is at least 2 characters wide (padding)
- `%T` - Start/end of clickable region for mouse (we don't use this in our config)

#### 2. `hl` - Highlighting/Colors

The `hl` field controls how the component looks. It can be:

**A string referencing an existing highlight group:**
```lua
{
  provider = "Error!",
  hl = "ErrorMsg"
}
```

**A table with color specifications:**
```lua
{
  provider = "Warning",
  hl = { fg = "yellow", bg = "black", bold = true }
}
```

**A function that returns a highlight table:**
```lua
{
  provider = "Dynamic",
  hl = function(self)
    if some_condition then
      return { fg = "green" }
    else
      return { fg = "red" }
    end
  end
}
```

#### 3. `condition` - When to Show

The `condition` field determines whether a component should be evaluated at all:

```lua
{
  condition = function()
    return vim.bo.modified  -- Only show if buffer is modified
  end,
  provider = "[+]"
}
```

If a condition returns `false` or `nil`, the entire component (and all its children) is skipped.

#### 4. `init` - Pre-computation

The `init` function runs **before** the component is displayed, allowing you to compute and cache values:

```lua
{
  init = function(self)
    -- Compute once, use multiple times
    self.filename = vim.api.nvim_buf_get_name(0)
    self.is_modified = vim.bo.modified
  end,
  provider = function(self)
    -- Use the cached values
    return self.filename
  end
}
```

**Why use init?**
- Performance: Compute expensive operations once
- Code organization: Separate computation from display
- Data sharing: Store values that multiple child components need

#### 5. `static` - Shared Constants

The `static` table holds data that doesn't change and is shared across all instances:

```lua
{
  static = {
    icons = {
      error = " ",
      warning = " ",
      info = " "
    }
  },
  provider = function(self)
    return self.icons.error  -- Access static data
  end
}
```

Think of `static` as a component-level constant storage.

#### 6. `update` - When to Refresh

The `update` field controls when a component should re-evaluate:

**Using autocmd events:**
```lua
{
  update = "BufEnter"  -- Re-evaluate when entering a buffer
}
```

**Multiple events:**
```lua
{
  update = { "BufEnter", "BufWritePost" }
}
```

**With patterns and callbacks:**
```lua
{
  update = {
    "ModeChanged",
    pattern = "*:*",
    callback = vim.schedule_wrap(function()
      vim.cmd("redrawstatus")
    end)
  }
}
```

This is crucial for performance—components only refresh when necessary, not on every cursor movement.

### Component Nesting and Inheritance

Components can contain other components, creating a tree structure:

```lua
local ParentComponent = {
  hl = { fg = "blue" },  -- All children inherit this

  -- Child components
  { provider = "Hello " },
  { provider = "World" },
}
```

Children automatically inherit fields from parents unless they override them:

```lua
{
  hl = { fg = "blue" },  -- Parent color

  { provider = "Blue text" },  -- Inherits blue
  { provider = "Red text", hl = { fg = "red" } },  -- Overrides to red
}
```

### The `self` Parameter

In component functions, `self` represents the component instance:

```lua
{
  init = function(self)
    self.custom_data = "some value"
  end,
  provider = function(self)
    return self.custom_data  -- Access data set in init
  end
}
```

`self` also provides access to:
- `self.static` - The static table
- Parent component fields (through inheritance)
- Custom fields you set in `init`

### Component Execution Order

Understanding when each component function runs is crucial for writing efficient configurations:

```
1. condition() - Evaluated first
   ↓ (if true, continue; if false, skip entire component and children)
2. init(self) - Pre-computation, set up self fields
   ↓
3. hl(self) - Determine highlighting (can use data from init)
   ↓
4. provider(self) - Generate display text (can use data from init)
```

**Visual example:**

```lua
{
  condition = function()
    print("1. Checking condition")
    return true
  end,
  init = function(self)
    print("2. Running init")
    self.mode = vim.fn.mode()
  end,
  hl = function(self)
    print("3. Determining highlight")
    return { fg = "green" }
  end,
  provider = function(self)
    print("4. Generating text")
    return self.mode
  end,
}
```

**Key insights:**
- If `condition` returns false, **nothing else runs** (including children)
- `init` runs before `hl` and `provider`, so they can use values set in `init`
- Each child component goes through the same cycle
- The `update` field determines when to **re-run** this entire cycle

---

## The TabLine Configuration

Let's break down the tabline section line by line.

### Overview

The tabline shows tabs at the top of Neovim when you have multiple tabs open. Our configuration displays:
- Tab number
- File icon (matching file type)
- Active filename in the tab
- Different icon when multiple buffers are open
- Separators between tabs

### Required Imports

```lua
local conditions = require("heirline.conditions")
local utils = require("heirline.utils")
```

**`conditions`** - Pre-built condition functions (like `is_git_repo`, `lsp_attached`)
**`utils`** - Utility functions (like `get_highlight`, `make_tablist`)

### The Tabpage Component

This is the component that represents **a single tab**. Here's the complete code from our configuration:

```lua
local Tabpage = {
  provider = function(self)
    -- Get all windows in this tabpage
    local wins = vim.api.nvim_tabpage_list_wins(self.tabpage)

    -- Get unique buffers from those windows (excluding floating windows)
    local buffers = {}
    local buf_set = {}
    for _, win in ipairs(wins) do
      -- Skip floating windows
      local win_config = vim.api.nvim_win_get_config(win)
      if win_config.relative == "" then
        local buf = vim.api.nvim_win_get_buf(win)
        if not buf_set[buf] then
          buf_set[buf] = true
          table.insert(buffers, buf)
        end
      end
    end

    -- Get icon and display text
    local icon = ""
    local display
    local has_devicons, devicons = pcall(require, "nvim-web-devicons")

    -- Get the active buffer in this tabpage
    local active_win = vim.api.nvim_tabpage_get_win(self.tabpage)
    local active_buf = vim.api.nvim_win_get_buf(active_win)
    local bufname = vim.api.nvim_buf_get_name(active_buf)

    if bufname == "" then
      display = "[No Name]"
      icon = "󰈤 "
    else
      local filename = vim.fn.fnamemodify(bufname, ":t")
      local extension = vim.fn.fnamemodify(bufname, ":e")
      display = filename

      -- Get file icon
      if has_devicons then
        local file_icon = devicons.get_icon(filename, extension, { default = true })
        if file_icon then
          icon = file_icon .. " "
        end
      end
    end

    -- Use multi-buffer icon if there are multiple buffers
    if #buffers > 1 then
      icon = "󰓩 "
    end

    return " " .. self.tabnr .. " " .. icon .. display .. " "
  end,
  hl = function(self)
    if not self.is_active then
      return "TabLine"
    else
      return "TabLineSel"
    end
  end,
}
```

This component demonstrates several advanced techniques all working together. Let's break down what it does.

#### Understanding `self` in Tabpage

When used with `utils.make_tablist()`, the `Tabpage` component receives special fields automatically:

- `self.tabpage` - The tabpage handle (integer)
- `self.tabnr` - The tab number (1, 2, 3, etc.)
- `self.is_active` - Boolean indicating if this is the current tab

#### Provider Logic: Step-by-Step

Let's examine the provider function piece by piece:

**Step 1: Get all windows in the tab**

```lua
local wins = vim.api.nvim_tabpage_list_wins(self.tabpage)
```

This gets all window IDs in the current tabpage. Remember, a single tab can have multiple windows (splits).

**Step 2: Filter out floating windows and collect unique buffers**

```lua
local buffers = {}
local buf_set = {}
for _, win in ipairs(wins) do
  -- Skip floating windows
  local win_config = vim.api.nvim_win_get_config(win)
  if win_config.relative == "" then
    local buf = vim.api.nvim_win_get_buf(win)
    if not buf_set[buf] then
      buf_set[buf] = true
      table.insert(buffers, buf)
    end
  end
end
```

This loop:
1. Checks each window's configuration
2. `win_config.relative == ""` means it's a normal window (not floating)
3. Gets the buffer in that window
4. Uses a set (`buf_set`) to track unique buffers (same buffer might be in multiple splits)
5. Stores unique buffers in the `buffers` array

**Why filter floating windows?** Floating windows (like LSP hover docs or completion popups) aren't "real" content windows, so we don't want to count them.

**Step 3: Get the active buffer**

```lua
local active_win = vim.api.nvim_tabpage_get_win(self.tabpage)
local active_buf = vim.api.nvim_win_get_buf(active_win)
local bufname = vim.api.nvim_buf_get_name(active_buf)
```

This gets the buffer in the currently active window of this tab. This is what we'll display as the tab's title.

**Step 4: Determine the filename and icon**

```lua
if bufname == "" then
  display = "[No Name]"
  icon = "󰈤 "
else
  local filename = vim.fn.fnamemodify(bufname, ":t")
  local extension = vim.fn.fnamemodify(bufname, ":e")
  display = filename

  -- Get file icon
  if has_devicons then
    local file_icon = devicons.get_icon(filename, extension, { default = true })
    if file_icon then
      icon = file_icon .. " "
    end
  end
end
```

**File path modifiers explained:**

`vim.fn.fnamemodify(path, modifier)` transforms file paths. Here are the modifiers we use:

- `:t` (tail) - Just the filename without path
  - `/home/user/code/init.lua` → `init.lua`
- `:e` (extension) - Just the file extension
  - `/home/user/code/init.lua` → `lua`
- `:h` (head) - Directory path without filename
  - `/home/user/code/init.lua` → `/home/user/code`
- `:r` (root) - Remove extension
  - `/home/user/code/init.lua` → `/home/user/code/init`
- `:p` (full path) - Expand to full absolute path
  - `./init.lua` → `/home/user/code/init.lua`

You can combine modifiers:
- `:t:r` - Filename without extension
  - `/home/user/code/init.lua` → `init`

**The pcall pattern for optional dependencies:**

Earlier in the provider, you'll see:

```lua
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
```

This is a **protected call** (pcall) pattern:
- **If nvim-web-devicons is installed:** `has_devicons = true`, `devicons = <module>`
- **If not installed:** `has_devicons = false`, `devicons = <error message>`

Later we check `if has_devicons then` before using the module. This makes our config work even if the user doesn't have nvim-web-devicons installed—it just won't show file-type icons.

**Step 5: Override with multi-buffer icon if needed**

```lua
if #buffers > 1 then
  icon = "󰓩 "
end
```

If we found multiple buffers in this tab, use a different icon to indicate splits/multiple files.

**Step 6: Return the formatted string**

```lua
return " " .. self.tabnr .. " " .. icon .. display .. " "
```

Format: ` 1  filename.lua ` or ` 2 󰓩 multiple.txt `

#### Highlighting Logic

```lua
hl = function(self)
  if not self.is_active then
    return "TabLine"
  else
    return "TabLineSel"
  end
end
```

Simple: use Neovim's built-in highlight groups to distinguish active vs inactive tabs.
- `TabLine` - Inactive tabs
- `TabLineSel` - Active tab (usually brighter/more prominent)

### The TabSeparator Component

```lua
local TabSeparator = {
  condition = function(self)
    return self.tabnr ~= #vim.api.nvim_list_tabpages()
  end,
  provider = "│",
  hl = "TabLine",
}
```

This displays a vertical bar (`│`) between tabs, but **not after the last tab**.

**How it works:**
- `self.tabnr` - Current tab number (inherited from parent when used with make_tablist)
- `#vim.api.nvim_list_tabpages()` - Total number of tabs
- Condition returns `true` only if this isn't the last tab
- Result: separators between tabs, but not a trailing separator

### The TabPages Container

```lua
local TabPages = {
  condition = function()
    return #vim.api.nvim_list_tabpages() >= 2
  end,
  utils.make_tablist({ Tabpage, TabSeparator }),
}
```

This is the container that:
1. Only shows when you have 2 or more tabs
2. Uses `utils.make_tablist()` to iterate through all tabs

#### Understanding `make_tablist`

`utils.make_tablist(component)` is a special utility that:
1. Gets all tabpages in Neovim
2. For each tabpage, creates an instance of your component
3. Injects `self.tabpage`, `self.tabnr`, and `self.is_active` into each instance
4. Returns a component that renders all tabs

When you pass `{ Tabpage, TabSeparator }`, it renders both for each tab, giving you:
```
Tab1 Separator Tab2 Separator Tab3
```

But the separator's condition prevents it from showing after Tab3.

### Final TabLine Assembly

```lua
local TabLine = { TabPages }
```

This wraps everything into a single tabline component. We could add more things here (like a close button on the right), but we keep it simple.

---

## The StatusLine Configuration

The statusline appears at the bottom of each window, showing information about the current buffer.

### Color Setup

```lua
local colors = {
  bg0 = utils.get_highlight("Normal").bg,
  fg = utils.get_highlight("Normal").fg,
  green = utils.get_highlight("String").fg,
  yellow = utils.get_highlight("Number").fg,
  red = utils.get_highlight("Error").fg,
  blue = utils.get_highlight("Function").fg,
  gray = utils.get_highlight("Comment").fg,
  orange = utils.get_highlight("Constant").fg,
}
```

**What's happening here?**

We're extracting colors from your colorscheme's existing highlight groups. This ensures the statusline matches your theme automatically.

`utils.get_highlight("GroupName")` returns a table like:
```lua
{ fg = "#a7c080", bg = "#2d353b", bold = true }
```

We pull out the `.fg` (foreground) or `.bg` (background) to get specific color values.

**Why this approach?**
- **Theme consistency**: Colors automatically match your colorscheme
- **Dynamic**: If you change colorschemes, statusline colors adapt
- **Semantic**: We associate colors with meaning (green = String color, red = Error color)

These color names can then be used in component `hl` fields:

```lua
{ hl = { fg = "green" } }  -- Uses the green we extracted
```

### ViMode Component: The Mode Indicator

This is the colorful block on the left showing which mode you're in (Normal, Insert, Visual, etc.)

#### The `init` Function

```lua
init = function(self)
  self.mode = vim.fn.mode(1)
end
```

**What does `vim.fn.mode(1)` do?**
- Returns the current Vim mode as a string
- The `1` argument includes additional information (like pending operators)
- Examples: `"n"` (normal), `"i"` (insert), `"v"` (visual), `"V"` (visual line)

**Why cache it in `self.mode`?**
- The `provider` and `hl` functions both need this value
- Computing it once in `init` is more efficient than calling `vim.fn.mode()` twice
- Ensures consistency (mode can't change between provider and hl execution)

#### The `static` Table

Here's the complete static table from our configuration:

```lua
static = {
  mode_names = {
    n = "N",
    no = "N",
    nov = "N",
    noV = "N",
    ["no\22"] = "N",
    niI = "N",
    niR = "N",
    niV = "N",
    nt = "N",
    v = "V",
    vs = "V",
    V = "V",
    Vs = "V",
    ["\22"] = "V",
    ["\22s"] = "V",
    s = "S",
    S = "S",
    ["\19"] = "S",
    i = "I",
    ic = "I",
    ix = "I",
    R = "R",
    Rc = "R",
    Rx = "R",
    Rv = "R",
    Rvc = "R",
    Rvx = "R",
    c = "C",
    cv = "C",
    r = ".",
    rm = "M",
    ["r?"] = "?",
    ["!"] = "!",
    t = "T",
  },
  mode_colors = {
    n = "green",
    i = "yellow",
    v = "red",
    V = "red",
    ["\22"] = "red",
    c = "blue",
    s = "orange",
    S = "orange",
    ["\19"] = "orange",
    R = "orange",
    r = "orange",
    ["!"] = "red",
    t = "green",
  },
}
```

**Purpose:**
- `mode_names`: Maps Vim's internal mode strings to display strings
- `mode_colors`: Maps mode types to color names

**Why so many mode variants?**

Vim has many subtle mode variations:
- `n` - Normal mode
- `no` - Operator-pending (like after pressing `d` or `y`)
- `niI`, `niR`, `niV` - Normal mode accessed via Ctrl-O from insert/replace/visual
- `nt` - Normal mode in a terminal buffer
- `v`, `V`, `\22` - Visual character, line, and block modes (`\22` is Ctrl-V)
- `vs`, `Vs`, `\22s` - Select mode variants (rare)
- `s`, `S`, `\19` - Select mode (character, line, block)
- `i`, `ic`, `ix` - Insert mode, completion, Ctrl-X submode
- `R`, `Rc`, `Rx`, `Rv`, `Rvc`, `Rvx` - Replace mode variants
- `c`, `cv` - Command-line mode, Vim Ex mode
- `r`, `rm`, `r?` - Prompt/input modes
- `!` - Shell command execution
- `t` - Terminal mode

We map them all to simple display letters (N, I, V, R, C, S, T, etc.) for clarity.

#### The `provider` Function

```lua
provider = function(self)
  return " %2(" .. self.mode_names[self.mode] .. "%) "
end
```

**Breaking it down:**
- `" "` - Leading space for padding
- `%2(...)%)` - Vim statusline syntax: ensure this section is at least 2 characters wide
- `self.mode_names[self.mode]` - Look up the display string (e.g., "N", "I", "V")
- `%)` - Closes the width specification started by `%2(`
- `" "` - Trailing space

**Result:** ` N ` or ` I ` (always centered in a fixed-width space)

#### The `hl` Function

```lua
hl = function(self)
  local mode = self.mode:sub(1, 1)  -- Get first character
  return { fg = "bg0", bg = self.mode_colors[mode], bold = true }
end
```

**How it works:**
1. Extract first character of mode (e.g., `"niI"` becomes `"n"`)
2. Look up color for that mode type in `mode_colors`
3. Return highlight with:
   - Foreground = background color (inverted for color block effect)
   - Background = mode color (green/yellow/red/blue)
   - Bold text

**Visual result:** A colored block with bold text inside

#### The `update` Field

```lua
update = {
  "ModeChanged",
  pattern = "*:*",
  callback = vim.schedule_wrap(function()
    vim.cmd("redrawstatus")
  end),
}
```

**What this does:**
1. Listen for `ModeChanged` autocmd events
2. Pattern `"*:*"` means any mode change
3. When triggered, redraw the statusline

**Why `vim.schedule_wrap`?**
- Ensures the redraw happens in a safe context
- Prevents issues with event handling timing

**Result:** Statusline updates immediately when you change modes, without manual refresh

### Git Component: Branch and Changes

Shows Git information when in a Git repository. Here's the complete component from our configuration:

```lua
local Git = {
  condition = conditions.is_git_repo,
  init = function(self)
    self.status_dict = vim.b.gitsigns_status_dict
  end,
  {
    provider = function(self)
      return "  " .. self.status_dict.head .. " "
    end,
    hl = { fg = "blue", bold = true },
  },
  {
    condition = function(self)
      return self.status_dict.added and self.status_dict.added > 0
    end,
    provider = function(self)
      return "+" .. self.status_dict.added .. " "
    end,
    hl = { fg = "green" },
  },
  {
    condition = function(self)
      return self.status_dict.changed and self.status_dict.changed > 0
    end,
    provider = function(self)
      return "~" .. self.status_dict.changed .. " "
    end,
    hl = { fg = "yellow" },
  },
  {
    condition = function(self)
      return self.status_dict.removed and self.status_dict.removed > 0
    end,
    provider = function(self)
      return "-" .. self.status_dict.removed .. " "
    end,
    hl = { fg = "red" },
  },
}
```

**The condition:**
- `conditions.is_git_repo` - Built-in heirline function
- Returns `true` only if current buffer is in a Git repository
- If `false`, entire Git component (and all children) is skipped

**The init function:**
- `vim.b.gitsigns_status_dict` - Data provided by gitsigns.nvim plugin
- Contains: branch name, added lines, changed lines, removed lines
- Example: `{ head = "main", added = 5, changed = 2, removed = 1 }`

**This is a perfect example of parent-child data sharing:**
1. Parent's `init` sets `self.status_dict`
2. All child components can access `self.status_dict` through inheritance
3. Each child conditionally displays one piece of information

#### Child Component: Branch Name

```lua
{
  provider = function(self)
    return "  " .. self.status_dict.head .. " "
  end,
  hl = { fg = "blue", bold = true },
}
```

- Icon `""` is a Git branch symbol (nerd font)
- `self.status_dict.head` is the branch name
- Blue color, bold text
- Always shows (no condition)

#### Child Component: Added Lines

```lua
{
  condition = function(self)
    return self.status_dict.added and self.status_dict.added > 0
  end,
  provider = function(self)
    return "+" .. self.status_dict.added .. " "
  end,
  hl = { fg = "green" },
}
```

**Only shows when:**
- `added` field exists
- `added` is greater than 0

**Displays:** `+5 ` (number of added lines)

**Color:** Green (additions are positive)

#### Child Components: Changed and Removed

```lua
{
  condition = function(self)
    return self.status_dict.changed and self.status_dict.changed > 0
  end,
  provider = function(self)
    return "~" .. self.status_dict.changed .. " "
  end,
  hl = { fg = "yellow" },
},
{
  condition = function(self)
    return self.status_dict.removed and self.status_dict.removed > 0
  end,
  provider = function(self)
    return "-" .. self.status_dict.removed .. " "
  end,
  hl = { fg = "red" },
}
```

Same pattern:
- Changed lines: `~2 ` in yellow
- Removed lines: `-1 ` in red

**Result when all present:** `  main +5 ~2 -1 `

**Result when no changes:** `  main ` (only branch shows)

### FileName Component: Current File

Displays the current buffer's filename with a modified indicator.

#### Structure

```lua
local FileName = {
  init = function(self)
    self.filename = vim.api.nvim_buf_get_name(0)
  end,
  -- Child components...
}
```

**Init caches the full file path:**
- `vim.api.nvim_buf_get_name(0)` gets the full path of current buffer
- `0` means current buffer
- Stored in `self.filename` for children to use

#### Child: Filename Display

```lua
{
  provider = function(self)
    local filename = vim.fn.fnamemodify(self.filename, ":t")
    if filename == "" then
      return "[No Name] "
    end
    return filename .. " "
  end,
  hl = { fg = "fg", bold = true },
}
```

**Logic:**
1. Extract just the filename (`:t` modifier removes path)
2. If empty (unnamed buffer), show `[No Name]`
3. Otherwise show the filename
4. Bold, in foreground color

**Examples:**
- `/home/user/code/file.lua` becomes `file.lua `
- Unnamed buffer becomes `[No Name] `

#### Child: Modified Indicator

```lua
{
  condition = function()
    return vim.bo.modified
  end,
  provider = "[+] ",
  hl = { fg = "yellow", bold = true },
}
```

**Only shows when buffer is modified:**
- `vim.bo.modified` checks if buffer has unsaved changes
- Displays `[+]` in bold yellow

**Result:** `filename.lua [+] ` when modified, `filename.lua ` when saved

### LSPActive Component: Language Server Status

Simple indicator showing if an LSP is attached.

```lua
local LSPActive = {
  condition = conditions.lsp_attached,
  update = { "LspAttach", "LspDetach" },
  provider = " LSP ",
  hl = { fg = "green", bold = true },
}
```

**Breakdown:**
- **Condition:** Only shows when LSP is attached to buffer
- **Update:** Re-evaluate when LSP attaches or detaches
- **Provider:** Simple text ` LSP `
- **Highlight:** Green (indicating active/good status)

**Result:** Empty when no LSP, ` LSP ` when language server is active

### Diagnostics Component: Errors and Warnings

Shows counts of LSP diagnostic messages.

#### Structure

```lua
local Diagnostics = {
  condition = conditions.has_diagnostics,
  static = {
    error_icon = " ",
    warn_icon = " ",
    info_icon = " ",
    hint_icon = " ",
  },
  init = function(self)
    self.errors = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
    self.warnings = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
    self.hints = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.HINT })
    self.info = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.INFO })
  end,
  update = { "DiagnosticChanged", "BufEnter" },
  -- Children...
}
```

**Condition:** Only shows when diagnostics exist

**Static:** Nerd font icons for each severity level

**Init:**
- `vim.diagnostic.get(0, {...})` gets diagnostics for current buffer
- `#` counts the number of diagnostics
- Stores counts in `self.errors`, `self.warnings`, etc.

**Update:** Refreshes when diagnostics change or when entering buffer

#### Child: Error Count

```lua
{
  condition = function(self)
    return self.errors > 0
  end,
  provider = function(self)
    return self.error_icon .. self.errors .. " "
  end,
  hl = { fg = "red" },
}
```

**Only shows when there are errors:**
- Checks `self.errors > 0`
- Displays icon + count: ` 3 `
- Red color

#### Child: Warning Count

```lua
{
  condition = function(self)
    return self.warnings > 0
  end,
  provider = function(self)
    return self.warn_icon .. self.warnings .. " "
  end,
  hl = { fg = "yellow" },
}
```

Same pattern for warnings, in yellow.

**Result examples:**
- No diagnostics: (nothing shown)
- 2 errors: ` 2 `
- 1 error, 3 warnings: ` 1  3 `

### Simple Components: Position and Progress

These use straightforward Vim statusline syntax.

#### FilePosition

```lua
local FilePosition = {
  provider = " %l:%c ",
  hl = { fg = "fg" },
}
```

- `%l` - Current line number
- `%c` - Current column number
- Result: ` 42:15 ` (line 42, column 15)

#### FileProgress

```lua
local FileProgress = {
  provider = " %P ",
  hl = { fg = "gray" },
}
```

- `%P` - Percentage through file
- Gray color (less prominent)
- Result: ` 45% ` or ` Top ` or ` Bot `

### Layout Components

#### Spacer

```lua
local Spacer = { provider = "%=" }
```

**The magic of `%=`:**
- Everything before `%=` is left-aligned
- Everything after `%=` is right-aligned
- Creates the classic statusline layout:

```
Left content                                            Right content
```

#### Space

```lua
local Space = { provider = " " }
```

Just a single space for breathing room between components.

### StatusLine Assembly

```lua
local StatusLine = {
  ViMode,
  Space,
  Git,
  FileName,
  Spacer,
  LSPActive,
  Diagnostics,
  FilePosition,
  FileProgress,
}
```

**Layout:**
```
[Mode]  git info filename                    LSP  2  1  45:12  50%
└─────┘ └────────┴───────┘                   └────────────────────┘
 Left                                              Right
```

The `Spacer` (`%=`) creates the division between left and right sections.

### Real-World Statusline Examples

Here's what the statusline actually looks like in different scenarios:

**1. Normal mode, in Git repo, clean file with LSP:**
```
 N    main  heirline.lua                                LSP  145:12  45%
└┬┘  └───┬─────┘ └──┬────────┘                           └┬┘  └──┬──┘ └─┬┘
 │       │          │                                     │      │      │
Mode   Branch    Filename                              LSP    Line:Col  %
```

**2. Insert mode, with Git changes, modified file, diagnostics:**
```
 I    main +5 ~2  heirline.lua [+]                   LSP  2  1  89:7  32%
└┬┘  └────┬──────┘ └──────┬───────┘                  └┬┘ └─┬──┘ └┬──┘└─┬┘
 │        │                │                           │    │     │    │
Yellow  Changes      Modified (yellow)                │  Errors Line  %
                                                       │  Warnings
                                                    LSP Active
```

**3. Visual mode, no Git, no diagnostics:**
```
 V    config.lua                                                    78:23  12%
└┬┘  └───┬─────┘                                                    └──┬──┘└─┬┘
 │       │                                                            Line   %
Red   Filename                                                        Col
```

**4. Non-git file, no LSP:**
```
 N    notes.txt                                                      1:1  Top
```

**Notice the dynamic behavior:**
- Mode block changes color based on mode (green/yellow/red/blue)
- Git info only appears in Git repositories
- Change stats only appear when there are changes
- Modified indicator `[+]` only shows when file is unsaved
- LSP indicator only shows when language server is attached
- Diagnostics only appear when there are errors/warnings
- Layout adapts: components gracefully hide when not relevant

---

## Setup and Integration

### The Setup Call

```lua
require("heirline").setup({
  statusline = StatusLine,
  tabline = TabLine,
  opts = {
    colors = colors,
  },
})
```

**What this does:**
1. Registers your statusline configuration
2. Registers your tabline configuration
3. Loads the color definitions
4. Activates heirline

**Other possible fields:**
- `winbar = ...` - Per-window bar at top of each window
- `statuscolumn = ...` - Custom column on left side (like line numbers area)

### TabLine Visibility

```lua
vim.o.showtabline = 1  -- Only show tabline when there are 2+ tabs
```

**Options:**
- `0` - Never show tabline
- `1` - Show only when 2+ tabs exist (our choice)
- `2` - Always show tabline

Since our `TabPages` component already has a condition for 2+ tabs, using `1` creates clean behavior: tabline appears exactly when needed.

---

## Customization Tips

### Adding New Components

To add a new component, follow this pattern:

```lua
local MyComponent = {
  -- Optional: only show under certain conditions
  condition = function()
    return some_check()
  end,

  -- Optional: pre-compute values
  init = function(self)
    self.data = get_some_data()
  end,

  -- Required: what to display
  provider = function(self)
    return " " .. self.data .. " "
  end,

  -- Optional: how to style it
  hl = { fg = "blue", bold = true },

  -- Optional: when to refresh
  update = "SomeEvent",
}
```

Then add it to your StatusLine or TabLine array.

### Modifying Colors

To change colors:

1. **Modify the color extraction:**
```lua
local colors = {
  -- Use different highlight groups
  green = utils.get_highlight("Keyword").fg,
  -- Or hardcode hex values
  red = "#e67e80",
}
```

2. **Change component highlights:**
```lua
hl = { fg = "red", bg = "bg0", bold = true, italic = true }
```

### Adding Separators

For fancy powerline-style separators:

```lua
local LeftSep = {
  provider = "",  -- Nerd font powerline separator
  hl = { fg = "bg0", bg = "green" },
}
```

Use `utils.surround()` for automatic separator generation:

```lua
local Surrounded = utils.surround(
  { "", "" },  -- Left and right separators
  "green",  -- Background color
  { provider = "Content" }  -- Component to surround
)
```

### Debugging Components

To see what's happening:

```lua
provider = function(self)
  print(vim.inspect(self))  -- Print component state
  return "Debug"
end
```

Check `:messages` to see the output.

### Performance Tips

1. **Use conditions wisely:** Skip expensive components when not needed
2. **Cache in init:** Compute once, use many times
3. **Limit updates:** Only update on relevant events
4. **Test performance:** `:profile` can help identify slow components

### Common Patterns

#### Conditional Color

```lua
hl = function(self)
  if self.has_errors then
    return { fg = "red" }
  else
    return { fg = "green" }
  end
end
```

#### Truncation for Small Windows

```lua
{
  condition = function()
    return vim.api.nvim_win_get_width(0) > 80  -- Only show in wide windows
  end,
  provider = "Extra info"
}
```

#### Clickable Components

```lua
{
  provider = " File Explorer ",
  on_click = {
    callback = function()
      vim.cmd("NvimTreeToggle")
    end,
    name = "toggle_file_explorer",
  },
}
```

---

## Understanding Inheritance

One of heirline's most powerful features is recursive inheritance. Here's how it works:

```lua
{
  hl = { fg = "blue" },  -- Parent highlight

  { provider = "A" },  -- Inherits blue

  {
    hl = { bg = "black" },  -- Partially override

    { provider = "B" },  -- Has fg=blue (from grandparent) and bg=black
    { provider = "C", hl = { fg = "red" } },  -- Overrides to red, keeps bg=black
  },
}
```

**Inheritance rules:**
1. Children inherit all parent fields
2. Child fields override parent fields
3. Partial overrides merge (like the `hl` table above)
4. Inheritance is recursive (grandchildren inherit from grandparents)

This allows you to set common properties once and specialize them in children.

---

## Advanced Patterns

### Flexible Components (Responsive Layouts)

Heirline supports `flexible` components that adapt to available space. While not used in our config, this is a powerful feature:

```lua
{
  flexible = 1,  -- Priority level (lower = higher priority to keep)

  -- Try full version first
  { provider = " Git Branch: main +5 ~2 -1 " },

  -- If not enough space, try medium version
  { provider = " main +5 ~2 -1 " },

  -- If still not enough space, use minimal version
  { provider = " main " },
}
```

Heirline will automatically pick the longest version that fits in the available window width.

### Caching Expensive Operations

For operations that are expensive to compute, use the `init` function to cache results:

```lua
{
  init = function(self)
    -- Expensive operation - only runs when component updates
    self.git_blame = vim.fn.systemlist("git blame " .. vim.fn.expand("%"))[vim.fn.line(".")]
  end,
  provider = function(self)
    -- Fast - just uses cached value
    return self.git_blame
  end,
  update = { "BufEnter", "CursorHold" },  -- Only update on these events
}
```

### Multiple Components Sharing Data

When multiple components need the same data, compute it once in a parent:

```lua
{
  init = function(self)
    -- Compute once
    self.diagnostics = vim.diagnostic.get(0)
    self.error_count = #vim.tbl_filter(function(d)
      return d.severity == vim.diagnostic.severity.ERROR
    end, self.diagnostics)
  end,

  -- Multiple children can use self.diagnostics and self.error_count
  { provider = function(self) return " " .. self.error_count end },
  { provider = function(self) return " Total: " .. #self.diagnostics end },
}
```

---

## Troubleshooting

### Common Issues

**1. "Module 'heirline' not found"**
- Ensure heirline.nvim is properly installed via your plugin manager
- Check that lazy.nvim has loaded the plugin: `:Lazy`

**2. Statusline not appearing**
- Check if another plugin is overriding it (like airline or lualine)
- Verify setup is being called: add `print("Heirline loaded")` after setup
- Ensure no errors in `:messages`

**3. Colors not working**
- Run `:lua print(vim.inspect(require("heirline.utils").get_highlight("Normal")))`
- Ensure your colorscheme is loaded before heirline
- Try hardcoding colors to test: `hl = { fg = "#ffffff" }`

**4. Git information not showing**
- Ensure gitsigns.nvim is installed and loaded
- Check buffer is in a Git repository
- Verify: `:lua print(vim.inspect(vim.b.gitsigns_status_dict))`

**5. LSP indicator not appearing**
- Ensure an LSP is actually attached: `:LspInfo`
- Check the condition function: `:lua print(require("heirline.conditions").lsp_attached())`

**6. Diagnostics not displaying**
- Verify diagnostics exist: `:lua print(#vim.diagnostic.get(0))`
- Check update events are triggering: add print statements in init

**7. TabLine not showing**
- Remember it only shows with 2+ tabs: create another tab with `:tabnew`
- Check `vim.o.showtabline` value: `:lua print(vim.o.showtabline)`

### Debug Techniques

**Print component state:**
```lua
init = function(self)
  print("Component init:", vim.inspect(self))
  -- ... rest of init
end
```

**Test condition functions:**
```lua
condition = function(self)
  local result = some_check()
  print("Condition result:", result)
  return result
end
```

**Verify update events are firing:**
```lua
update = {
  "ModeChanged",
  callback = function()
    print("ModeChanged event fired!")
  end,
}
```

---

## Conclusion

You now have a complete understanding of how this heirline configuration works:

- **TabLine:** Smart tab display with file icons, multi-buffer detection, and clean separators
- **StatusLine:** Minimal, informative design with mode indicator, Git status, LSP info, diagnostics, and file position
- **Component Architecture:** Understanding provider, hl, condition, init, static, and update
- **Customization:** Knowledge to modify colors, add components, and optimize performance

Heirline's component-based approach gives you unlimited flexibility. Start with this configuration and customize it to match your workflow.

**Additional Resources:**
- [Heirline Cookbook](https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md) - More component examples
- [Heirline README](https://github.com/rebelot/heirline.nvim) - Official documentation
- `:help statusline` - Vim's statusline syntax reference

Happy customizing!
