local M = {}

-- "given_a_valid_cert_chain_when_running_filter_then_tls_config_is_set"
-- → "Given a valid cert chain | When running filter | Then tls config is set"
--
-- given/when/then are all optional and independent (Python GWT-style test
-- names in the wild frequently drop "given_", or drop "when_" and go
-- straight to "..._then_...").
function M.format_body(body)
  local lower = body:lower()

  if lower:match("^given_") then
    local rest = body:sub(7) -- skip "given_"

    local ws, we = rest:lower():find("_when_")
    if ws then
      local given_part = rest:sub(1, ws - 1):gsub("_", " ")
      rest = rest:sub(we + 1)

      local ts, te = rest:lower():find("_then_")
      if ts then
        local when_part = rest:sub(1, ts - 1):gsub("_", " ")
        local then_part = rest:sub(te + 1):gsub("_", " ")
        return "Given " .. given_part .. " | When " .. when_part .. " | Then " .. then_part
      end

      return "Given " .. given_part .. " | When " .. rest:gsub("_", " ")
    end

    return "Given " .. rest:gsub("_", " ")
  end

  if lower:match("^when_") then
    local rest = body:sub(6) -- skip "when_"

    local ts, te = rest:lower():find("_then_")
    if ts then
      local when_part = rest:sub(1, ts - 1):gsub("_", " ")
      local then_part = rest:sub(te + 1):gsub("_", " ")
      return "When " .. when_part .. " | Then " .. then_part
    end

    return "When " .. rest:gsub("_", " ")
  end

  local ts, te = lower:find("_then_")
  if ts then
    local lead = body:sub(1, ts - 1):gsub("_", " ")
    local then_part = body:sub(te + 1):gsub("_", " ")
    lead = lead:sub(1, 1):upper() .. lead:sub(2)
    return lead .. " | Then " .. then_part
  end

  -- Non-GWT: replace underscores, capitalize first letter
  local s = body:gsub("_", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
end

function M.format(name)
  return M.format_body(name)
end

-- Python test names carry a "test_" prefix that isn't part of the GWT body.
function M.format_python(name)
  local body = name:gsub("^test_", "")
  return M.format_body(body)
end

-- Returns lines for the indented preview pane
function M.preview_lines(name)
  local display = M.format(name)
  if not display:find("^Given ") then
    return { display }
  end

  local parts = {}
  for part in display:gmatch("([^|]+)") do
    table.insert(parts, vim.trim(part))
  end

  local lines = {}
  if parts[1] then table.insert(lines, parts[1]) end
  if parts[2] then table.insert(lines, "  " .. parts[2]) end
  if parts[3] then table.insert(lines, "    " .. parts[3]) end
  return lines
end

-- Converts a (possibly edited) GWT display string back to a snake_case identifier body.
-- Handles the same optional given/when/then shapes M.format_body produces.
function M.to_snake(display)
  local parts = {}
  for part in display:gmatch("([^|]+)") do
    table.insert(parts, vim.trim(part))
  end

  local is_gwt = false
  for _, p in ipairs(parts) do
    if p:find("^Given ") or p:find("^When ") or p:find("^Then ") then
      is_gwt = true
      break
    end
  end

  if not is_gwt then
    return display:gsub(" +", "_"):lower()
  end

  local segments = {}
  for _, p in ipairs(parts) do
    local given = p:match("^Given (.*)$")
    local when  = p:match("^When (.*)$")
    local then_ = p:match("^Then (.*)$")
    local keyword, text = nil, p
    if given then keyword, text = "given_", given
    elseif when then keyword, text = "when_", when
    elseif then_ then keyword, text = "then_", then_ end
    table.insert(segments, (keyword or "") .. text:gsub(" +", "_"):lower())
  end

  return table.concat(segments, "_")
end

-- Same as M.to_snake but re-adds the "test_" prefix Python test names carry.
function M.to_snake_python(display)
  return "test_" .. M.to_snake(display)
end

return M
