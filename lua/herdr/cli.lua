---@mod herdr.cli vim.system wrapper around the herdr CLI
local M = {}

--- Injectable for tests. Must match vim.system's return shape (`:wait()`).
M._system = vim.system

local function cfg()
  return require("herdr.config").get()
end

--- @class herdr.CliError
--- @field code string
--- @field message string

--- @param args string[]
--- @param opts? { timeout?: integer }
--- @return table|nil result
--- @return herdr.CliError|nil err
function M.run(args, opts)
  opts = opts or {}
  local bin = cfg().herdr_bin or "herdr"
  local cmd = { bin }
  vim.list_extend(cmd, args)
  local timeout = opts.timeout or cfg().timeout_ms or 5000

  local ok, obj = pcall(M._system, cmd, { text = true, timeout = timeout })
  if not ok then
    return nil, { code = "spawn_failed", message = tostring(obj) }
  end

  local res = obj:wait()
  local stdout = (res.stdout or ""):gsub("%s+$", "")
  local stderr = (res.stderr or ""):gsub("%s+$", "")

  local decoded
  if stdout ~= "" then
    local json_ok, data = pcall(vim.json.decode, stdout)
    if json_ok then
      decoded = data
    end
  end

  if decoded then
    if decoded.error then
      local err = decoded.error
      if type(err) == "string" then
        return nil, { code = "error", message = err }
      end
      return nil, {
        code = err.code or "error",
        message = err.message or stdout,
      }
    end
    if decoded.result ~= nil then
      return decoded.result, nil
    end
    -- `herdr status --json` is a bare object (no {id,result} envelope).
    return decoded, nil
  end

  if res.code ~= 0 then
    local msg = stderr ~= "" and stderr or (stdout ~= "" and stdout or ("herdr exited " .. tostring(res.code)))
    return nil, { code = "exit_" .. tostring(res.code), message = msg }
  end

  if stdout == "" then
    return {}, nil
  end
  return nil, { code = "invalid_json", message = stdout }
end

--- @return boolean
function M.executable()
  return vim.fn.executable(cfg().herdr_bin or "herdr") == 1
end

--- @return string
function M.exepath()
  local path = vim.fn.exepath(cfg().herdr_bin or "herdr")
  if path ~= "" then
    return path
  end
  return cfg().herdr_bin or "herdr"
end

--- @return table|nil
--- @return herdr.CliError|nil
function M.status()
  return M.run({ "status", "--json" })
end

--- @return table[]
--- @return herdr.CliError|nil
function M.agent_list()
  local result, err = M.run({ "agent", "list" })
  if err then
    return {}, err
  end
  if type(result) == "table" and type(result.agents) == "table" then
    return result.agents, nil
  end
  return {}, nil
end

--- @param target string
--- @return table|nil
--- @return herdr.CliError|nil
function M.agent_get(target)
  return M.run({ "agent", "get", target })
end

--- @param target string
--- @param text string
--- @return table|nil
--- @return herdr.CliError|nil
function M.agent_prompt(target, text)
  return M.run({ "agent", "prompt", target, text })
end

--- @param pane_id string
--- @param text string
--- @return table|nil
--- @return herdr.CliError|nil
function M.pane_send_text(pane_id, text)
  return M.run({ "pane", "send-text", pane_id, text })
end

--- @param err herd.CliError|string|nil
--- @return string
function M.err_message(err)
  if err == nil then
    return "unknown error"
  end
  if type(err) == "string" then
    return err
  end
  if err.message and err.code then
    return err.code .. ": " .. err.message
  end
  return err.message or err.code or "unknown error"
end

return M
