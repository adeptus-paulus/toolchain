local M = {}

local pickers      = require("telescope.pickers")
local finders      = require("telescope.finders")
local conf         = require("telescope.config").values
local actions      = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers   = require("telescope.previewers")
local sorters      = require("telescope.sorters")

local KEYWORDS = { "Given", "When", "Then" }

-- Sorter that uses lnum as the score so Telescope ranks items by file position.
-- Lower score = shown first; lnum 1 < lnum 100, so declaration order is preserved.
-- Typing still filters by substring on the raw test name.
local function declaration_order_sorter()
  return sorters.Sorter:new({
    scoring_function = function(_, prompt, _, entry)
      local lnum = entry and entry.value and entry.value.lnum or 0
      if not prompt or prompt == "" then return -lnum end
      local target = (entry and entry.ordinal or ""):lower()
      return target:find(prompt:lower(), 1, true) and -lnum or -1
    end,
  })
end

local function make_entry(test)
  return {
    value   = test,
    ordinal = test.name,
    display = function(entry)
      local t    = entry.value
      local lnum = string.format("%4d", t.lnum)
      local text = lnum .. "  " .. t.display
      local off  = #lnum + 2   -- byte offset where display text starts
      local highlights = {
        { { 0, #lnum }, "TelescopeResultsLineNr" },
      }
      for _, kw in ipairs(KEYWORDS) do
        local s = 1
        while true do
          local ks, ke = t.display:find(kw, s, true)
          if not ks then break end
          table.insert(highlights, { { off + ks - 1, off + ke }, "Comment" })
          s = ke + 1
        end
      end
      return text, highlights
    end,
  }
end

-- Find a real (non-floating) window showing bufnr, or hijack the current one.
local function find_or_open_win(bufnr)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative == ""
        and vim.api.nvim_win_get_buf(w) == bufnr then
      return w
    end
  end
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(w, bufnr)
  return w
end

local function safe_set_cursor(win, lnum, col)
  if not vim.api.nvim_win_is_valid(win) then return end
  local n = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  lnum = math.max(1, math.min(lnum, n))
  local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), lnum - 1, lnum, false)[1] or ""
  col = math.max(0, math.min(col, math.max(0, #line - 1)))
  pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
end

local function jump_to(test)
  local win = find_or_open_win(test.bufnr)
  vim.api.nvim_set_current_win(win)
  safe_set_cursor(win, test.lnum, test.col)
end

-- Fresh previewer every open() call so stale state from previous crashes doesn't carry over
local function make_previewer()
  return previewers.new_buffer_previewer({
    title = "Test Source",
    define_preview = function(self, entry)
      local test = entry.value
      local lines = vim.api.nvim_buf_get_lines(test.bufnr, 0, -1, false)
      if #lines == 0 then return end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = "rust"

      local lnum = math.max(1, math.min(test.lnum, #lines))
      vim.api.nvim_buf_add_highlight(
        self.state.bufnr, -1, "TelescopePreviewLine", lnum - 1, 0, -1
      )

      -- Defer cursor set: Telescope wires the window to the buffer asynchronously
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(self.state.winid) then return end
        local n = vim.api.nvim_buf_line_count(self.state.bufnr)
        pcall(vim.api.nvim_win_set_cursor, self.state.winid, { math.min(lnum, n), 0 })
      end)
    end,
  })
end

local function run_in_terminal(cmd)
  vim.cmd("botright split | terminal " .. cmd)
end

local function run_specific(test)
  run_in_terminal("cargo test " .. test.name .. " -- --exact --nocapture")
end

-- Build a libtest regex alternation so all selected names match exactly.
local function run_many(tests)
  local parts = {}
  for _, t in ipairs(tests) do
    -- anchor each name to end of path so module::name doesn't bleed into module::name_suffix
    table.insert(parts, t.name .. "$")
  end
  run_in_terminal("cargo test '(" .. table.concat(parts, "|") .. ")' -- --nocapture")
end

local function do_generate(test)
  local formatter = require("rust-test-panel.formatter")
  -- Mirror the indentation and async style of the focused test
  local fn_line = vim.api.nvim_buf_get_lines(test.bufnr, test.lnum - 1, test.lnum, false)[1] or ""
  local indent  = fn_line:match("^(%s*)") or ""
  local inner   = indent .. "    "
  local attr    = test.attr or "#[test]"
  local fn_kw   = test.is_async and "async fn" or "fn"

  vim.ui.input({ prompt = "New test name: " }, function(input)
    if not input or vim.trim(input) == "" then return end
    local new_name = formatter.to_snake(input)
    local lines = {
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
      -- end_lnum is 1-indexed; as a 0-indexed insert position it falls right after the fn's "}"
      vim.api.nvim_buf_set_lines(test.bufnr, test.end_lnum, test.end_lnum, false, lines)
      local win = find_or_open_win(test.bufnr)
      vim.api.nvim_set_current_win(win)
      -- Land on the blank line after "// Arrange" (5th inserted line, 1-indexed = end_lnum + 5)
      pcall(vim.api.nvim_win_set_cursor, win, { test.end_lnum + 5, 0 })
      vim.cmd("normal! zz")
    end)
  end)
end

local function do_rename(test)
  local formatter = require("rust-test-panel.formatter")
  -- Find the window once; reuse it both before and after the input dialog.
  local win = find_or_open_win(test.bufnr)
  vim.api.nvim_set_current_win(win)
  safe_set_cursor(win, test.lnum, test.col)

  vim.ui.input({
    prompt  = "Rename test: ",
    default = test.display,
  }, function(new_display)
    if not new_display or vim.trim(new_display) == "" then return end
    local new_name = formatter.to_snake(new_display)
    -- vim.ui.input (snacks) may move cursor; put it back on the symbol before rename.
    vim.schedule(function()
      vim.api.nvim_set_current_win(win)
      safe_set_cursor(win, test.lnum, test.col)
      vim.lsp.buf.rename(new_name)
    end)
  end)
end

function M.open(entries)
  if #entries == 0 then
    vim.notify("rust-test-panel: no tests found in buffer", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "Rust Tests  <CR> jump · <Tab> select · <C-r> run · <C-g> new test · <C-n> rename · <C-a> all",
    finder = finders.new_table({
      results     = entries,
      entry_maker = make_entry,
    }),
    sorter    = declaration_order_sorter(),
    previewer = make_previewer(),

    attach_mappings = function(prompt_bufnr, map)
      -- <CR>: jump to definition
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then jump_to(entry.value) end
      end)

      -- <C-r>: run <Tab>-selected tests, or the focused one if none are tagged
      local function run_test()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local multi  = picker:get_multi_selection()
        local single = action_state.get_selected_entry()  -- must capture before close
        actions.close(prompt_bufnr)
        vim.schedule(function()
          if #multi > 1 then
            local tests = {}
            for _, e in ipairs(multi) do table.insert(tests, e.value) end
            run_many(tests)
          else
            local entry = (#multi == 1) and multi[1] or single
            if entry then run_specific(entry.value) end
          end
        end)
      end
      map("i", "<C-r>", run_test)
      map("n", "<C-r>", run_test)

      -- <C-a>: run all file tests via rustaceanvim
      local function run_all()
        actions.close(prompt_bufnr)
        vim.schedule(function() vim.cmd("RustLsp testables") end)
      end
      map("i", "<C-a>", run_all)
      map("n", "<C-a>", run_all)

      -- <C-g>: generate a new test template after the focused test
      local function gen_template()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local test = entry.value
        actions.close(prompt_bufnr)
        vim.schedule(function() do_generate(test) end)
      end
      map("i", "<C-g>", gen_template)
      map("n", "<C-g>", gen_template)

      -- <C-n>: rename test via LSP with GWT-formatted prompt
      local function rename_test()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local test = entry.value
        actions.close(prompt_bufnr)
        -- schedule so Telescope fully relinquishes window focus before we move the cursor
        vim.schedule(function() do_rename(test) end)
      end
      map("i", "<C-n>", rename_test)
      map("n", "<C-n>", rename_test)

      return true
    end,
  }):find()
end

return M
