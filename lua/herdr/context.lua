---@mod herdr.context Git-root relative @file / :line / :range refs
local M = {}

--- @return string|nil
function M.git_root()
  local cmd = { "git", "-C", vim.fn.getcwd(), "rev-parse", "--show-toplevel" }
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local root = vim.trim(result.stdout or "")
  if root == "" then
    return nil
  end
  return root
end

--- @param bufnr integer|nil
--- @return string|nil
function M.relative_file(bufnr)
  bufnr = bufnr or 0
  local abs = vim.api.nvim_buf_get_name(bufnr)
  if abs == "" then
    return nil
  end
  abs = vim.fn.fnamemodify(abs, ":p")
  local git_root = M.git_root() or vim.fn.getcwd()
  git_root = vim.fn.fnamemodify(git_root, ":p")
  -- Strip trailing slash for prefix compare; skip root + "/" when slicing.
  git_root = git_root:gsub("/+$", "")
  if abs:sub(1, #git_root) == git_root and abs:sub(#git_root + 1, #git_root + 1) == "/" then
    return abs:sub(#git_root + 2)
  end
  return vim.fn.fnamemodify(abs, ":.")
end

--- @param path string
--- @param start_line integer|nil
--- @param end_line integer|nil
--- @return string
function M.format_ref(path, start_line, end_line)
  if not start_line then
    return "@" .. path
  end
  if not end_line or end_line == start_line then
    return string.format("@%s:%d", path, start_line)
  end
  if end_line < start_line then
    start_line, end_line = end_line, start_line
  end
  if start_line == end_line then
    return string.format("@%s:%d", path, start_line)
  end
  return string.format("@%s:%d-%d", path, start_line, end_line)
end

--- @return string|nil
function M.file_ref()
  local path = M.relative_file()
  if not path then
    return nil
  end
  return M.format_ref(path)
end

--- @param line integer|nil
--- @return string|nil
function M.line_ref(line)
  local path = M.relative_file()
  if not path then
    return nil
  end
  return M.format_ref(path, line or vim.fn.line("."))
end

--- Resolve a visual or explicit range. Collapses to a single line when start == end.
--- @param start_line integer|nil
--- @param end_line integer|nil
--- @return string|nil
function M.range_ref(start_line, end_line)
  local path = M.relative_file()
  if not path then
    return nil
  end

  if not start_line or not end_line then
    local mode = vim.fn.mode()
    if type(mode) == "string" and mode:match("^[vV\22]") then
      start_line = vim.fn.line("v")
      end_line = vim.fn.line(".")
    else
      start_line = vim.fn.line("'<")
      end_line = vim.fn.line("'>")
      if (not start_line or start_line == 0) and (not end_line or end_line == 0) then
        start_line = vim.fn.line(".")
        end_line = start_line
      end
    end
  end

  if not start_line or start_line == 0 then
    start_line = vim.fn.line(".")
    end_line = start_line
  end
  if not end_line or end_line == 0 then
    end_line = start_line
  end

  return M.format_ref(path, start_line, end_line)
end

--- Pick a ref from a :Herdr command's range info.
--- @param opts? { kind?: "file"|"line"|"range"|"auto", line1?: integer, line2?: integer, range?: integer }
--- @return string|nil
function M.current_ref(opts)
  opts = opts or {}
  local kind = opts.kind or "auto"
  if kind == "file" then
    return M.file_ref()
  end
  if kind == "line" then
    return M.line_ref(opts.line1 or vim.fn.line("."))
  end
  if kind == "range" then
    return M.range_ref(opts.line1, opts.line2)
  end
  -- auto: a real command range uses range_ref (collapses single-line); else file.
  if (opts.range or 0) > 0 then
    return M.range_ref(opts.line1, opts.line2)
  end
  return M.file_ref()
end

return M
