---@mod herdr.comments Stacked notes, global across files, shown as extmarks
local M = {}

local context = require("herdr.context")

M.ns = vim.api.nvim_create_namespace("herdr_comments")

--- @class herdr.Comment
--- @field uid integer
--- @field bufnr integer
--- @field mark_id integer
--- @field rails integer[]
--- @field path string
--- @field abs string
--- @field text string
--- @field start_line integer
--- @field end_line integer

--- @type herdr.Comment[]
local entries = {}
local next_uid = 0

local function buf_id(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function new_uid()
  next_uid = next_uid + 1
  return next_uid
end

function M.ensure_highlights()
  -- Amber rail/callout, same idea as herdr-nvim (not DiagnosticWarn).
  vim.api.nvim_set_hl(0, "HerdrCommentSign", { default = true, fg = "#d7a65f", bold = true })
  vim.api.nvim_set_hl(0, "HerdrComment", { default = true, fg = "#d7a65f" })
  vim.api.nvim_set_hl(0, "HerdrCommentLine", { default = true, link = "CursorLine" })
end

--- Callout drawn ABOVE the first annotated line: ╭─ 💬 text
--- @param text string
--- @return table
local function callout(text)
  local one = vim.trim((text or ""):gsub("%s+", " "))
  if vim.fn.strdisplaywidth(one) > 80 then
    one = vim.fn.strcharpart(one, 0, 77) .. "..."
  end
  local label = one == "" and "💬" or ("💬 " .. one)
  return { { { "╭─ ", "HerdrCommentSign" }, { label, "HerdrComment" } } }
end

local function refresh_rec(rec)
  if not vim.api.nvim_buf_is_valid(rec.bufnr) then
    return rec
  end
  local mark = vim.api.nvim_buf_get_extmark_by_id(rec.bufnr, M.ns, rec.mark_id, { details = true })
  if not mark or mark[1] == nil then
    rec.invalid = true
    return rec
  end
  local details = mark[3] or {}
  if details.invalid then
    rec.invalid = true
    return rec
  end
  rec.invalid = false
  rec.start_line = mark[1] + 1
  rec.end_line = rec.start_line
  if details.end_row then
    rec.end_line = details.end_row + 1
  end
  return rec
end

local function as_item(rec)
  return {
    id = rec.uid,
    uid = rec.uid,
    mark_id = rec.mark_id,
    bufnr = rec.bufnr,
    path = rec.path,
    abs = rec.abs,
    text = rec.text or "",
    start_line = rec.start_line,
    end_line = rec.end_line,
  }
end

--- @param bufnr integer|nil
--- @param item { path: string, start_line: integer, end_line: integer, text: string }
--- @return integer uid
function M.add(bufnr, item)
  M.ensure_highlights()
  bufnr = buf_id(bufnr)
  local start_line = item.start_line or 1
  local end_line = item.end_line or start_line
  if end_line < start_line then
    start_line, end_line = end_line, start_line
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if start_line < 1 then
    start_line = 1
  end
  if start_line > line_count then
    start_line = line_count
  end
  if end_line > line_count then
    end_line = line_count
  end

  local function decorate(row, erow, text, extmark_id)
    local opts = {
      end_row = erow,
      end_col = 0,
      virt_lines = callout(text),
      virt_lines_above = true,
      sign_text = "▌",
      sign_hl_group = "HerdrCommentSign",
      line_hl_group = "HerdrCommentLine",
      hl_mode = "combine",
      invalidate = true,
      right_gravity = false,
    }
    if extmark_id then
      opts.id = extmark_id
    end
    return vim.api.nvim_buf_set_extmark(bufnr, M.ns, row, 0, opts)
  end

  -- Primary mark: 💬 callout above the first line + ▌ rail (herdr-nvim style).
  local mark_id = decorate(start_line - 1, end_line - 1, item.text)

  local rails = {}
  for line = start_line + 1, end_line do
    rails[#rails + 1] = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line - 1, 0, {
      sign_text = "▌",
      sign_hl_group = "HerdrCommentSign",
      line_hl_group = "HerdrCommentLine",
      invalidate = true,
      right_gravity = false,
    })
  end

  local abs = vim.api.nvim_buf_get_name(bufnr)
  local rec = {
    uid = new_uid(),
    bufnr = bufnr,
    mark_id = mark_id,
    rails = rails,
    path = item.path or context.relative_file(bufnr) or vim.fn.fnamemodify(abs, ":."),
    abs = abs,
    text = item.text or "",
    start_line = start_line,
    end_line = end_line,
  }
  entries[#entries + 1] = rec
  return rec.uid
end

--- Replace the text of an existing comment and refresh its callout.
--- @param item { uid?: integer, id?: integer }
--- @param text string
--- @return boolean
function M.update(item, text)
  if type(item) ~= "table" then
    return false
  end
  local uid = item.uid or item.id
  text = text or ""
  for _, rec in ipairs(entries) do
    if rec.uid == uid then
      rec.text = text
      refresh_rec(rec)
      if vim.api.nvim_buf_is_valid(rec.bufnr) and not rec.invalid then
        vim.api.nvim_buf_set_extmark(rec.bufnr, M.ns, rec.start_line - 1, 0, {
          id = rec.mark_id,
          end_row = rec.end_line - 1,
          end_col = 0,
          virt_lines = callout(text),
          virt_lines_above = true,
          sign_text = "▌",
          sign_hl_group = "HerdrCommentSign",
          line_hl_group = "HerdrCommentLine",
          hl_mode = "combine",
          invalidate = true,
          right_gravity = false,
        })
      end
      return true
    end
  end
  return false
end

--- List comments. Omit bufnr (or pass nil) for every file; a bufnr filters to that buffer.
--- @param bufnr integer|nil
--- @return table[]
function M.list(bufnr)
  local filter = nil
  if bufnr ~= nil then
    filter = buf_id(bufnr)
  end
  local items = {}
  for _, rec in ipairs(entries) do
    refresh_rec(rec)
    if rec.invalid then
      goto continue
    end
    if filter and rec.bufnr ~= filter then
      goto continue
    end
    items[#items + 1] = as_item(rec)
    ::continue::
  end
  table.sort(items, function(a, b)
    local pa, pb = a.path or "", b.path or ""
    if pa ~= pb then
      return pa < pb
    end
    if a.start_line == b.start_line then
      return a.end_line < b.end_line
    end
    return a.start_line < b.start_line
  end)
  return items
end

--- @param item { path?: string, start_line: integer, end_line: integer, text?: string }
--- @return string
function M.label(item)
  local path = item.path or "?"
  local loc
  if not item.end_line or item.end_line == item.start_line then
    loc = string.format("%s:%d", path, item.start_line)
  else
    loc = string.format("%s:%d-%d", path, item.start_line, item.end_line)
  end
  local text = vim.trim((item.text or ""):gsub("%s+", " "))
  if text == "" then
    return loc
  end
  return loc .. "  " .. text
end

local function drop_marks(rec)
  if vim.api.nvim_buf_is_valid(rec.bufnr) then
    for _, rid in ipairs(rec.rails or {}) do
      pcall(vim.api.nvim_buf_del_extmark, rec.bufnr, M.ns, rid)
    end
    pcall(vim.api.nvim_buf_del_extmark, rec.bufnr, M.ns, rec.mark_id)
  end
end

--- Delete by uid (preferred) or by (bufnr, extmark id).
--- @param bufnr integer|table|nil
--- @param id integer|nil
--- @return boolean
function M.delete(bufnr, id)
  if type(bufnr) == "table" then
    id = bufnr.uid or bufnr.id
    bufnr = bufnr.bufnr
  end
  if not id then
    return false
  end
  local filter_buf = bufnr ~= nil and buf_id(bufnr) or nil
  for i, rec in ipairs(entries) do
    local match_uid = rec.uid == id
    local match_mark = rec.mark_id == id and (not filter_buf or rec.bufnr == filter_buf)
    if match_uid or match_mark then
      drop_marks(rec)
      table.remove(entries, i)
      return true
    end
  end
  return false
end

--- @param bufnr integer|nil nil → every file
--- @return string|nil
function M.render(bufnr)
  local items = M.list(bufnr)
  if #items == 0 then
    return nil
  end
  local parts = {}
  for _, item in ipairs(items) do
    local path = item.path or "?"
    local ref = context.format_ref(path, item.start_line, item.end_line)
    if item.text and item.text ~= "" then
      table.insert(parts, ref .. "\n" .. item.text)
    else
      table.insert(parts, ref)
    end
  end
  return table.concat(parts, "\n\n")
end

--- @param bufnr integer|nil
function M.clear(bufnr)
  if bufnr == nil then
    M.clear_all()
    return
  end
  bufnr = buf_id(bufnr)
  local kept = {}
  for _, rec in ipairs(entries) do
    if rec.bufnr == bufnr then
      drop_marks(rec)
    else
      kept[#kept + 1] = rec
    end
  end
  entries = kept
end

function M.clear_all()
  for _, rec in ipairs(entries) do
    drop_marks(rec)
  end
  entries = {}
end

local function ensure_buf(item, code_win)
  if item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
    return item.bufnr
  end
  local name = item.abs or item.path
  if not name or name == "" then
    return nil
  end
  if vim.api.nvim_win_is_valid(code_win) then
    local ok = pcall(vim.api.nvim_win_call, code_win, function()
      vim.cmd.edit(vim.fn.fnameescape(name))
    end)
    if ok then
      return vim.api.nvim_win_get_buf(code_win)
    end
  end
  return nil
end

--- Floating list of every stacked comment. `dd` deletes that row; `<CR>` jumps.
--- @param bufnr integer|nil unused; comments are global
--- @param opts? { code_win?: integer }
function M.open_list(bufnr, opts)
  if type(bufnr) == "table" then
    opts = bufnr
  end
  opts = opts or {}
  local code_win = opts.code_win or vim.api.nvim_get_current_win()

  local items = M.list()
  if #items == 0 then
    vim.notify("Herdr: no comments", vim.log.levels.WARN)
    return
  end

  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].buftype = "nofile"
  vim.bo[list_buf].bufhidden = "wipe"
  vim.bo[list_buf].swapfile = false
  vim.bo[list_buf].filetype = "herdr-comments"
  vim.bo[list_buf].modifiable = false

  local function lines_for(rows)
    local lines = {}
    for _, item in ipairs(rows) do
      lines[#lines + 1] = M.label(item)
    end
    return lines
  end

  local function win_config(rows)
    local labels = lines_for(rows)
    local width = 24
    for _, line in ipairs(labels) do
      width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
    end
    width = math.min(width, math.max(24, vim.o.columns - 6))
    local height = math.max(1, math.min(#rows, 12))
    return {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(0, vim.o.lines - height - 4),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      style = "minimal",
      border = "rounded",
      title = { { " Comments ", "HerdrComment" } },
      title_pos = "center",
    }
  end

  local win = vim.api.nvim_open_win(list_buf, true, win_config(items))
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false

  local function render()
    items = M.list()
    if #items == 0 then
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      return false
    end
    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines_for(items))
    vim.bo[list_buf].modifiable = false
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, win_config(items))
    end
    return true
  end

  local function current()
    if not vim.api.nvim_win_is_valid(win) then
      return nil
    end
    return items[vim.api.nvim_win_get_cursor(win)[1]]
  end

  local function jump(item)
    item = item or current()
    if not item or not vim.api.nvim_win_is_valid(code_win) then
      return
    end
    local target = ensure_buf(item, code_win)
    if not target then
      return
    end
    if not pcall(vim.api.nvim_win_set_buf, code_win, target) then
      return
    end
    local line = math.min(item.start_line, math.max(1, vim.api.nvim_buf_line_count(target)))
    vim.api.nvim_win_set_cursor(code_win, { line, 0 })
    vim.api.nvim_win_call(code_win, function()
      vim.cmd("normal! zz")
    end)
  end

  local function delete_at_cursor()
    local item = current()
    if not item then
      return
    end
    M.delete(item)
    render()
  end

  render()
  jump()

  local grp = vim.api.nvim_create_augroup("HerdrCommentList" .. list_buf, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = grp,
    buffer = list_buf,
    callback = function()
      jump()
    end,
  })

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = list_buf, nowait = true, silent = true, noremap = true })
  end

  map("q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)
  map("<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)
  map("<CR>", function()
    jump()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)
  map("dd", delete_at_cursor)
  map("x", delete_at_cursor)
  map("<Del>", delete_at_cursor)
  map("e", function()
    local item = current()
    if not item then
      return
    end
    vim.ui.input({ prompt = "Herdr comment: ", default = item.text }, function(text)
      if text == nil then
        return
      end
      M.update(item, text)
      render()
    end)
  end)
end

return M
