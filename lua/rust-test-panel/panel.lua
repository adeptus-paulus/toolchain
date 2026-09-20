local M = {}

local HEADER = 2   -- non-entry lines at top of the panel buffer
local WIDTH  = 55  -- updated on close; seed from global if set by user config

local state = {
  win          = nil,
  buf          = nil,
  ns           = vim.api.nvim_create_namespace("rust_test_panel"),
  entries      = {},
  marked       = {},    -- { [entry_index] = true }
  source       = nil,   -- source bufnr
  prev_win     = nil,   -- window to focus / split terminals into
  augroup      = nil,
  showing_help = false,
}

-- ── helpers ──────────────────────────────────────────────────────────

local function entry_at(lnum)
  local i = lnum - HEADER
  return (i >= 1 and i <= #state.entries) and state.entries[i] or nil
end

local function source_win()
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    return state.prev_win
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative == ""
        and vim.api.nvim_win_get_buf(w) == state.source then
      return w
    end
  end
end

local function safe_cursor(win, lnum, col)
  if not vim.api.nvim_win_is_valid(win) then return end
  local n   = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  lnum      = math.max(1, math.min(lnum, n))
  local ln  = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), lnum-1, lnum, false)[1] or ""
  col       = math.max(0, math.min(col, math.max(0, #ln - 1)))
  pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
end

-- ── render ───────────────────────────────────────────────────────────

local function render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

  if state.showing_help then
    local lines = {
      " Rust Test Panel — keys",
      " " .. string.rep("-", WIDTH - 1),
      "",
      "  <CR>       jump to test",
      "  <Space>    mark / unmark (anonymous)",
      "  m          bookmark with a name",
      "  r          run marked (or focused)",
      "  R          run all tests",
      "  n          rename via LSP",
      "  g          generate new test below",
      "  q / <Esc>  close panel",
      "  ?          toggle this help",
    }
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
    vim.api.nvim_buf_add_highlight(state.buf, state.ns, "Title", 0, 0, -1)
    return
  end

  local lines = {}
  local fname = vim.fn.fnamemodify(vim.fn.bufname(state.source), ":t")
  local lang  = (state.filetype == "python") and "Python" or "Rust"
  lines[1] = " " .. lang .. " Tests  " .. fname
  lines[2] = " " .. string.rep("-", WIDTH - 1)

  for i, e in ipairs(state.entries) do
    -- marker(2) + lnum(4) + gap(2) + display → fixed offsets for highlighting
    local mv     = state.marked[i]
    local prefix = mv and "* " or "  "
    local suffix = (type(mv) == "string") and ("  @" .. mv) or ""
    lines[HEADER + i] = prefix .. string.format("%4d", e.lnum) .. "  " .. e.display .. suffix
  end

  if #state.entries == 0 then
    lines[HEADER + 1] = "  (no tests found)"
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
  vim.api.nvim_buf_add_highlight(state.buf, state.ns, "Title", 0, 0, -1)

  for i, e in ipairs(state.entries) do
    local row = HEADER + i - 1  -- 0-indexed
    local mv  = state.marked[i]
    if mv then
      vim.api.nvim_buf_add_highlight(state.buf, state.ns, "DiagnosticOk", row, 0, 2)
    end
    -- line-number column (bytes 2–6)
    vim.api.nvim_buf_add_highlight(state.buf, state.ns, "TelescopeResultsLineNr", row, 2, 6)
    -- GWT keywords in the display portion (byte offset 8)
    local off = 8
    for _, kw in ipairs({ "Given", "When", "Then" }) do
      local s = 1
      while true do
        local ks, ke = e.display:find(kw, s, true)
        if not ks then break end
        vim.api.nvim_buf_add_highlight(state.buf, state.ns, "Comment", row, off+ks-1, off+ke)
        s = ke + 1
      end
    end
    -- bookmark name suffix  "  @name"  (byte offset: 8 + #display + 2)
    if type(mv) == "string" then
      vim.api.nvim_buf_add_highlight(state.buf, state.ns, "Special", row, off + #e.display + 2, -1)
    end
  end
end

-- ── terminal helper ──────────────────────────────────────────────────

-- args: list passed directly to termopen (no shell expansion of $ etc.)
local function run_in_terminal(args)
  local w = source_win()
  if not w then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= state.win and vim.api.nvim_win_get_config(win).relative == "" then
        w = win; break
      end
    end
  end
  if w then vim.api.nvim_set_current_win(w) end
  vim.cmd("botright new")
  vim.fn.termopen(args)
end

-- ── close ────────────────────────────────────────────────────────────

local function do_close()
  local w = source_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    WIDTH = vim.api.nvim_win_get_width(state.win)
    vim.g.rust_test_panel_width = WIDTH
    vim.api.nvim_win_close(state.win, true)
  end
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  state.win    = nil
  state.buf    = nil
  state.marked = {}
  if w and vim.api.nvim_win_is_valid(w) then
    vim.api.nvim_set_current_win(w)
  end
end

-- ── actions ──────────────────────────────────────────────────────────

local function toggle_mark()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local i   = row - HEADER
  if i < 1 or i > #state.entries then return end
  if state.marked[i] then state.marked[i] = nil else state.marked[i] = true end
  render()
  pcall(vim.api.nvim_win_set_cursor, state.win, { row, 0 })
end

local function named_mark()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local i   = row - HEADER
  if i < 1 or i > #state.entries then return end
  local current = state.marked[i]
  local default = (type(current) == "string") and current or ""
  vim.ui.input({ prompt = "Bookmark name (empty to clear): ", default = default }, function(input)
    if input == nil then return end  -- cancelled
    local name = vim.trim(input)
    state.marked[i] = (name ~= "") and name or nil
    vim.schedule(function()
      render()
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        pcall(vim.api.nvim_win_set_cursor, state.win, { row, 0 })
      end
    end)
  end)
end

local function jump_to_test()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local e   = entry_at(row)
  if not e then return end
  local w = source_win()
  if not w then
    vim.cmd("leftabove vsplit")
    w = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(w, state.source)
  else
    vim.api.nvim_set_current_win(w)
  end
  safe_cursor(w, e.lnum, e.col)
  vim.cmd("normal! zz")
end

local function run_tests()
  local marked = {}
  for idx in pairs(state.marked) do
    if state.entries[idx] then table.insert(marked, state.entries[idx]) end
  end
  table.sort(marked, function(a, b) return a.lnum < b.lnum end)

  local args
  if state.filetype == "python" then
    local filepath = vim.fn.fnamemodify(vim.fn.bufname(state.source), ":.")
    if #marked == 0 then
      local e = entry_at(vim.api.nvim_win_get_cursor(state.win)[1])
      if not e then return end
      args = { "pytest", filepath, "-k", e.name }
    elseif #marked == 1 then
      args = { "pytest", filepath, "-k", marked[1].name }
    else
      local parts = {}
      for _, e in ipairs(marked) do table.insert(parts, e.name) end
      args = { "pytest", filepath, "-k", table.concat(parts, " or ") }
    end
  else
    if #marked == 0 then
      local e = entry_at(vim.api.nvim_win_get_cursor(state.win)[1])
      if not e then return end
      args = { "cargo", "test", e.name, "--", "--nocapture" }
    elseif #marked == 1 then
      args = { "cargo", "test", marked[1].name, "--", "--nocapture" }
    else
      local parts = {}
      for _, e in ipairs(marked) do table.insert(parts, e.name .. "$") end
      args = { "cargo", "test", "(" .. table.concat(parts, "|") .. ")", "--", "--nocapture" }
    end
  end

  run_in_terminal(args)
end

local function run_all()
  if state.filetype == "python" then
    local filepath = vim.fn.fnamemodify(vim.fn.bufname(state.source), ":.")
    run_in_terminal({ "pytest", filepath })
  else
    run_in_terminal({ "cargo", "test", "--", "--nocapture" })
  end
end

local function rename_test()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local e   = entry_at(row)
  if not e then return end
  local w = source_win()
  if not w then
    vim.notify("rust-test-panel: source buffer not visible", vim.log.levels.WARN)
    return
  end

  local formatter = require("rust-test-panel.formatter")
  local n    = vim.api.nvim_buf_line_count(state.source)
  local lnum = math.min(e.lnum, n)
  local ln   = vim.api.nvim_buf_get_lines(state.source, lnum-1, lnum, false)[1] or ""
  local col  = math.min(e.col, math.max(0, #ln - 1))

  vim.api.nvim_set_current_win(w)
  pcall(vim.api.nvim_win_set_cursor, w, { lnum, col })

  vim.ui.input({ prompt = "Rename test: ", default = e.display }, function(new_display)
    if not new_display or vim.trim(new_display) == "" then return end
    local new_name = (state.filetype == "python")
      and formatter.to_snake_python(new_display)
      or formatter.to_snake(new_display)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(w) then
        vim.api.nvim_set_current_win(w)
        pcall(vim.api.nvim_win_set_cursor, w, { lnum, col })
      end
      vim.lsp.buf.rename(new_name)
    end)
  end)
end

local function generate_test()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local e   = entry_at(row)
  if not e then return end

  local fn_line = vim.api.nvim_buf_get_lines(state.source, e.lnum-1, e.lnum, false)[1] or ""
  local indent  = fn_line:match("^(%s*)") or ""
  local inner   = indent .. "    "
  local attr    = e.attr or "#[test]"
  local fn_kw   = e.is_async and "async fn" or "fn"
  local formatter = require("rust-test-panel.formatter")

  vim.ui.input({ prompt = "New test name: " }, function(input)
    if not input or vim.trim(input) == "" then return end
    local new_name  = formatter.to_snake(input)
    local new_lines = {
      "",
      indent .. attr,
      indent .. fn_kw .. " " .. new_name .. "() {",
      inner .. "// Arrange",
      "",
      inner .. "// Act",
      "",
      inner .. "// Assert",
      indent .. "}",
    }
    vim.schedule(function()
      vim.api.nvim_buf_set_lines(state.source, e.end_lnum, e.end_lnum, false, new_lines)
      state.entries = require("rust-test-panel.discovery").collect(state.source)
      render()
      local w = source_win()
      if w then
        vim.api.nvim_set_current_win(w)
        pcall(vim.api.nvim_win_set_cursor, w, { e.end_lnum + 5, 0 })
        vim.cmd("normal! zz")
      end
    end)
  end)
end

local function show_help()
  state.showing_help = not state.showing_help
  render()
end

-- ── keymaps ──────────────────────────────────────────────────────────

local function setup_keymaps()
  local b = state.buf
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = b, nowait = true, silent = true })
  end
  map("<CR>",    jump_to_test)
  map("<Space>", toggle_mark)
  map("m",       named_mark)
  map("r",       run_tests)
  map("R",       run_all)
  map("n",       rename_test)
  map("g",       generate_test)
  map("q",       do_close)
  map("<Esc>",   do_close)
  map("?",       show_help)
end

-- ── public API ───────────────────────────────────────────────────────

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
    return true
  end
  return false
end

function M.toggle(source_bufnr)
  if M.is_open() then do_close(); return end

  source_bufnr   = source_bufnr or vim.api.nvim_get_current_buf()
  state.source        = source_bufnr
  state.filetype      = vim.bo[source_bufnr].filetype
  state.marked        = {}
  state.showing_help  = false
  state.prev_win      = vim.api.nvim_get_current_win()
  state.entries       = require("rust-test-panel.discovery").collect(source_bufnr)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile  = false
  state.buf = buf

  WIDTH = vim.g.rust_test_panel_width or WIDTH
  vim.cmd("botright " .. WIDTH .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  -- Marks this window so the global <Tab> window-cycler (plugin/init.lua) skips it,
  -- the same way it already skips terminal windows.
  vim.w[win].rust_test_panel = true
  -- Use nvim_win_call + opt_local to set strictly window-local values
  -- (vim.wo[win] in Neovim 0.10 sets the global copy too, which breaks other windows)
  vim.api.nvim_win_call(win, function()
    vim.opt_local.wrap           = false
    vim.opt_local.number         = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn     = "no"
    vim.opt_local.cursorline     = true
    vim.opt_local.winfixwidth    = true
  end)
  state.win = win

  state.augroup = vim.api.nvim_create_augroup("RustTestPanel" .. buf, { clear = true })

  -- Refresh when the current source file is saved
  vim.api.nvim_create_autocmd("BufWritePost", {
    group    = state.augroup,
    callback = function()
      if not M.is_open() then return end
      if vim.api.nvim_get_current_buf() ~= state.source then return end
      state.entries = require("rust-test-panel.discovery").collect(state.source)
      render()
    end,
  })

  -- Switch source when the user enters a different Rust/Python buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    group    = state.augroup,
    callback = function()
      if not M.is_open() then return end
      local bufnr = vim.api.nvim_get_current_buf()
      if bufnr == state.buf or bufnr == state.source then return end
      local ft = vim.bo[bufnr].filetype
      if ft ~= "rust" and ft ~= "python" then return end
      state.source   = bufnr
      state.filetype = ft
      state.marked   = {}
      state.prev_win = vim.api.nvim_get_current_win()
      state.entries  = require("rust-test-panel.discovery").collect(bufnr)
      render()
    end,
  })

  -- Clean up state when the window is closed from outside (e.g. :q)
  vim.api.nvim_create_autocmd("WinClosed", {
    group   = state.augroup,
    pattern = tostring(win),
    once    = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        WIDTH = vim.api.nvim_win_get_width(win)
        vim.g.rust_test_panel_width = WIDTH
      end
      if state.augroup then
        pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
        state.augroup = nil
      end
      state.win = nil
      state.buf = nil
    end,
  })

  render()
  setup_keymaps()
  if #state.entries > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { HEADER + 1, 0 })
  end
end

return M
