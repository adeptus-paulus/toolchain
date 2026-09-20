local M = {}

M.subcommands = {
  "agents",
  "file",
  "health",
  "line",
  "list",
  "prompt",
  "range",
  "send",
  "target",
}

local SUB_SET = {}
for _, name in ipairs(M.subcommands) do
  SUB_SET[name] = true
end

--- @param arglead string
--- @param cmdline string
--- @param _cursorpos integer
--- @return string[]
function M.complete(arglead, cmdline, _cursorpos)
  local after = cmdline:match("Herdr%s*(.*)$") or ""
  if after:match("%s") and not cmdline:match("%s$") and arglead ~= "" then
    -- still completing the first word (partial)
  elseif after:match("%S%s+") then
    return {}
  end
  local out = {}
  for _, name in ipairs(M.subcommands) do
    if arglead == "" or name:sub(1, #arglead) == arglead then
      table.insert(out, name)
    end
  end
  return out
end

--- @param herd table
--- @param opts table
function M.dispatch(herd, opts)
  local sub = opts.fargs[1]
  local range_opts = {
    line1 = opts.line1,
    line2 = opts.line2,
    range = opts.range or 0,
  }

  if not sub then
    herd.ask(range_opts)
    return
  end

  if not SUB_SET[sub] then
    vim.notify(
      "Herdr: unknown command '" .. sub .. "'. Try: " .. table.concat(M.subcommands, ", "),
      vim.log.levels.ERROR
    )
    return
  end

  if sub == "health" then
    herd.health()
  elseif sub == "agents" then
    herd.agents()
  elseif sub == "target" then
    herd.pick_target()
  elseif sub == "file" then
    herd.send_file_ref()
  elseif sub == "line" then
    if (range_opts.range or 0) > 0 and range_opts.line1 ~= range_opts.line2 then
      herd.add_comment(range_opts.line1, range_opts.line2)
    else
      herd.add_comment(range_opts.line1, range_opts.line1)
    end
  elseif sub == "range" then
    herd.add_comment(range_opts.line1, range_opts.line2)
  elseif sub == "send" then
    herd.send_comments()
  elseif sub == "list" then
    herd.list_comments()
  elseif sub == "prompt" then
    local text = table.concat(vim.list_slice(opts.fargs, 2), " ")
    if text == "" then
      text = nil
    end
    herd.prompt(text, range_opts)
  end
end

return M
