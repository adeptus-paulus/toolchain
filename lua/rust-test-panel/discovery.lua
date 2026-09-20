local M = {}

local function is_test_attr(text)
  if text:match("^#%[test[%]%(]") then return true end
  if text:match("^#%[actix_test]") then return true end
  if text:match("::%s*test[%]%(]") then return true end
  if text:match("^#%[rstest[%]%(]") then return true end
  return false
end

-- Returns the raw attribute text (e.g. "#[tokio::test]") or nil if not a test fn.
-- Checks fn_node children first (current tree-sitter-rust) then falls back to
-- preceding named siblings (older grammar layout).
local function find_test_attr(fn_node, bufnr)
  for i = 0, fn_node:named_child_count() - 1 do
    local child = fn_node:named_child(i)
    if child:type() == "attribute_item" then
      local text = vim.treesitter.get_node_text(child, bufnr)
      if is_test_attr(text) then return text end
    end
  end

  local parent = fn_node:parent()
  if not parent then return nil end

  local fn_idx = nil
  for i = 0, parent:named_child_count() - 1 do
    if parent:named_child(i) == fn_node then fn_idx = i; break end
  end
  if not fn_idx then return nil end

  for i = fn_idx - 1, 0, -1 do
    local sib = parent:named_child(i)
    if sib:type() == "attribute_item" then
      local text = vim.treesitter.get_node_text(sib, bufnr)
      if is_test_attr(text) then return text end
    else
      break
    end
  end
  return nil
end

local function is_fn_async(fn_node, bufnr)
  for i = 0, fn_node:named_child_count() - 1 do
    local child = fn_node:named_child(i)
    if child:type() == "function_modifiers" then
      return vim.treesitter.get_node_text(child, bufnr):match("async") ~= nil
    end
  end
  return false
end

function M.collect(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype == "python" then
    return require("rust-test-panel.discovery_python").collect(bufnr)
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "rust")
  if not ok or not parser then return {} end

  local tree = parser:parse()[1]
  if not tree then return {} end

  local formatter = require("rust-test-panel.formatter")
  local query = vim.treesitter.query.parse("rust", "(function_item) @fn")
  local results = {}

  for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    local name_fields = node:field("name")
    local name_node   = name_fields and name_fields[1]
    if name_node then
      local attr = find_test_attr(node, bufnr)
      if attr then
        local row, col = name_node:start()
        local end_row  = node:end_()
        local name = vim.treesitter.get_node_text(name_node, bufnr)
        table.insert(results, {
          name     = name,
          display  = formatter.format(name),
          bufnr    = bufnr,
          lnum     = row + 1,
          col      = col,
          end_lnum = end_row + 1,  -- 1-indexed last line of the function body
          attr     = attr,
          is_async = is_fn_async(node, bufnr),
        })
      end
    end
  end

  table.sort(results, function(a, b) return a.lnum < b.lnum end)
  return results
end

return M
