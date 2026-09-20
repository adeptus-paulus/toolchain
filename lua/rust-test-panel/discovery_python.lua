local M = {}

local function parse_decorators(parent_node, bufnr)
  local marks   = {}
  local qase_id = nil

  for i = 0, parent_node:named_child_count() - 1 do
    local child = parent_node:named_child(i)
    if child:type() == "decorator" then
      local text = vim.treesitter.get_node_text(child, bufnr)
      -- strip leading "@" and any trailing whitespace
      text = text:match("^@(.-)%s*$") or text

      -- @pytest.mark.<name>  or  @pytest.mark.<name>(...)
      local marker = text:match("^pytest%.mark%.([%w_]+)")
      if marker then
        table.insert(marks, marker)
      end

      -- @qase.id(<number>)
      local id = text:match("^qase%.id%((%d+)%)")
      if id then qase_id = id end
    end
  end

  return marks, qase_id
end

function M.collect(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "python")
  if not ok or not parser then return {} end

  local tree = parser:parse()[1]
  if not tree then return {} end

  local query   = vim.treesitter.query.parse("python", "(function_definition) @fn")
  local results = {}

  for _, fn_node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    local name_fields = fn_node:field("name")
    local name_node   = name_fields and name_fields[1]
    if not name_node then goto continue end

    local name = vim.treesitter.get_node_text(name_node, bufnr)
    if name:sub(1, 5) ~= "test_" then goto continue end

    local row, col = name_node:start()
    local end_row  = fn_node:end_()

    -- decorators live on the parent decorated_definition node
    local marks, qase_id = {}, nil
    local parent = fn_node:parent()
    if parent and parent:type() == "decorated_definition" then
      marks, qase_id = parse_decorators(parent, bufnr)
    end

    local formatter = require("rust-test-panel.formatter")
    local display = formatter.format_python(name)
    if #marks > 0 then
      display = display .. "  [" .. table.concat(marks, ", ") .. "]"
    end
    if qase_id then
      display = display .. "  qase:" .. qase_id
    end

    table.insert(results, {
      name     = name,
      display  = display,
      bufnr    = bufnr,
      lnum     = row + 1,
      col      = col,
      end_lnum = end_row + 1,
      marks    = marks,
      qase_id  = qase_id,
    })

    ::continue::
  end

  table.sort(results, function(a, b) return a.lnum < b.lnum end)
  return results
end

return M
