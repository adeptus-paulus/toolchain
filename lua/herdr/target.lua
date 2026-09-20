---@mod herdr.target List, resolve, and remember a Herdr agent
local M = {}

local ROLE_ORDER = { "review", "tests", "audit", "impl" }

local function herdr()
  return require("herdr.cli")
end

local function cfg()
  return require("herdr.config").get()
end

--- @param agent table
--- @return string
function M.cli_target(agent)
  if type(agent.name) == "string" and agent.name ~= "" then
    return agent.name
  end
  return agent.pane_id
end

--- Visible name: Herdr `name`, else the pane title (the view you see in Herdr).
--- @param agent table
--- @return string
function M.display_name(agent)
  if type(agent.name) == "string" and agent.name ~= "" then
    return agent.name
  end
  local title = agent.title or agent.terminal_title_stripped or agent.terminal_title
  if type(title) == "string" then
    title = vim.trim(title)
    if title ~= "" then
      return title
    end
  end
  return agent.agent or agent.display_agent or agent.pane_id or "agent"
end

--- @param agent table
--- @return string
function M.label(agent)
  local name = M.display_name(agent)
  local status = agent.agent_status or "unknown"
  local kind = agent.agent or agent.display_agent
  local cwd = agent.cwd or agent.foreground_cwd or ""
  local short = cwd ~= "" and vim.fn.fnamemodify(cwd, ":~") or ""
  local parts = { name, status }
  if kind and kind ~= "" and not name:find(kind, 1, true) then
    parts[#parts + 1] = kind
  end
  if short ~= "" then
    parts[#parts + 1] = short
  end
  return table.concat(parts, " · ")
end

--- @return table[]
--- @return table|nil
function M.list()
  return herdr().agent_list()
end

--- @param agents table[]
--- @return table[]
function M.sort(agents)
  local roles = cfg().roles or {}
  local rank = {}
  local i = 1
  for _, key in ipairs(ROLE_ORDER) do
    if roles[key] then
      rank[roles[key]] = i
      i = i + 1
    end
  end
  for key, value in pairs(roles) do
    if not rank[value] then
      rank[value] = i
      i = i + 1
    end
    -- also rank by role key in case the alias equals the key
    if not rank[key] then
      rank[key] = i
      i = i + 1
    end
  end

  local spec = M.remembered_spec()
  local copy = vim.list_slice(agents, 1, #agents)
  table.sort(copy, function(a, b)
    if spec then
      local a_mem = (spec.name and a.name == spec.name)
        or (spec.pane_id and a.pane_id == spec.pane_id)
        or false
      local b_mem = (spec.name and b.name == spec.name)
        or (spec.pane_id and b.pane_id == spec.pane_id)
        or false
      if a_mem ~= b_mem then
        return a_mem
      end
    end
    local ra = (a.name and rank[a.name]) or 1000
    local rb = (b.name and rank[b.name]) or 1000
    if ra ~= rb then
      return ra < rb
    end
    local na = (type(a.name) == "string" and a.name ~= "") and 0 or 1
    local nb = (type(b.name) == "string" and b.name ~= "") and 0 or 1
    if na ~= nb then
      return na < nb
    end
    return (a.pane_id or "") < (b.pane_id or "")
  end)
  return copy
end

local function memory_key()
  return vim.fn.getcwd()
end

--- @param agent table
function M.remember(agent)
  if not cfg().remember_target then
    return
  end
  local slot = vim.t.herdr_target
  if type(slot) ~= "table" then
    slot = {}
  end
  slot[memory_key()] = {
    name = agent.name,
    pane_id = agent.pane_id,
  }
  vim.t.herdr_target = slot
end

function M.clear_memory()
  vim.t.herdr_target = {}
end

--- @return { name?: string, pane_id?: string }|nil
function M.remembered_spec()
  if not cfg().remember_target then
    return nil
  end
  local slot = vim.t.herdr_target
  if type(slot) ~= "table" then
    return nil
  end
  return slot[memory_key()]
end

--- @param agents table[]
--- @param spec { name?: string, pane_id?: string, target?: string }|string
--- @return table|nil
function M.find_in(agents, spec)
  if type(spec) == "string" then
    spec = { target = spec }
  end
  if spec.name and spec.name ~= "" then
    for _, agent in ipairs(agents) do
      if agent.name == spec.name then
        return agent
      end
    end
  end
  local needle = spec.target or spec.pane_id
  if needle and needle ~= "" then
    for _, agent in ipairs(agents) do
      if agent.pane_id == needle or agent.name == needle then
        return agent
      end
    end
  end
  return nil
end

--- @param target string
--- @return table|nil
--- @return table|string|nil
function M.find(target)
  local agents, err = M.list()
  if err then
    return nil, err
  end
  local agent = M.find_in(agents, target)
  if not agent then
    return nil, { code = "agent_not_found", message = "agent target " .. target .. " not found" }
  end
  return agent, nil
end

--- Resolve without UI when possible.
--- @return table|nil agent
--- @return table|string|nil err
--- @return boolean need_pick
function M.try_resolve()
  local agents, err = M.list()
  if err then
    return nil, err, false
  end
  if #agents == 0 then
    return nil, "no_agents", false
  end

  if #agents == 1 then
    M.remember(agents[1])
    return agents[1], nil, false
  end

  -- Several agents: always ask, even if one is remembered.
  local spec = M.remembered_spec()
  if spec and not M.find_in(agents, spec) then
    vim.notify("Herdr: remembered target is gone", vim.log.levels.WARN)
  end

  return nil, nil, true
end

--- @param callback fun(agent: table|nil, err?: string)
--- @param opts? { force_select?: boolean }
function M.pick(callback, opts)
  opts = opts or {}
  local agents, err = M.list()
  if err then
    vim.notify("Herdr: " .. herdr().err_message(err), vim.log.levels.ERROR)
    if callback then
      callback(nil, herdr().err_message(err))
    end
    return
  end
  if #agents == 0 then
    vim.notify("Herdr: no agents. Start one with your herd-roles script.", vim.log.levels.WARN)
    if callback then
      callback(nil, "no_agents")
    end
    return
  end

  agents = M.sort(agents)

  if #agents == 1 and not opts.force_select then
    M.remember(agents[1])
    vim.notify("Herdr target: " .. M.label(agents[1]), vim.log.levels.INFO)
    if callback then
      callback(agents[1])
    end
    return
  end

  local RENAME = { _rename = true }
  local choices = vim.list_slice(agents, 1, #agents)
  table.insert(choices, RENAME)

  vim.ui.select(choices, {
    prompt = "Send to agent:",
    format_item = function(item)
      if item._rename then
        return "Rename agent…"
      end
      return M.label(item)
    end,
  }, function(choice)
    if not choice then
      if callback then
        callback(nil)
      end
      return
    end
    if choice._rename then
      vim.ui.select(agents, {
        prompt = "Rename which agent?",
        format_item = function(item)
          return M.label(item)
        end,
      }, function(agent)
        if not agent then
          M.pick(callback, opts)
          return
        end
        vim.ui.input({
          prompt = "Agent name: ",
          default = agent.name or "",
        }, function(name)
          if not name or name == "" then
            M.pick(callback, opts)
            return
          end
          local _, err = herdr().agent_rename(M.cli_target(agent), name)
          if err then
            vim.notify("Herdr: " .. herdr().err_message(err), vim.log.levels.ERROR)
          else
            vim.notify("Herdr: renamed to " .. name, vim.log.levels.INFO)
          end
          M.pick(callback, opts)
        end)
      end)
      return
    end
    M.remember(choice)
    if callback then
      callback(choice)
    end
  end)
end

--- Resolve a target, opening a picker when several agents are live.
--- @param callback fun(agent: table|nil, err?: string|table)
function M.resolve(callback)
  local agent, err, need_pick = M.try_resolve()
  if need_pick then
    M.pick(callback, { force_select = true })
    return
  end
  if err == "no_agents" then
    vim.notify("Herdr: no agents. Start one with your herd-roles script.", vim.log.levels.WARN)
    callback(nil, err)
    return
  end
  if err then
    vim.notify("Herdr: " .. herdr().err_message(err), vim.log.levels.ERROR)
    callback(nil, err)
    return
  end
  callback(agent)
end

return M
