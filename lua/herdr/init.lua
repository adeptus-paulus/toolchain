---@mod herdr Neovim → Herdr agent send
local config_mod = require("herdr.config")
local herdr = require("herdr.cli")
local context = require("herdr.context")
local prompts = require("herdr.prompts")
local target = require("herdr.target")
local comments = require("herdr.comments")
local commands = require("herdr.commands")
local keymaps = require("herdr.keymaps")

local M = {}

M.config = config_mod.current

function M._ensure_setup()
  if M._setup_done then
    return
  end
  M.setup()
end

--- @param user_config table|nil
function M.setup(user_config)
  M.config = config_mod.parse_config(user_config, false)
  config_mod.set(M.config)
  M._setup_done = true
  comments.ensure_highlights()
  keymaps.register(M, M.config)
end

local function no_file()
  vim.notify("Herdr: no current file", vim.log.levels.WARN)
end

--- @param agent table
--- @param text string
--- @param opts { submit?: boolean }
--- @return boolean
function M._send_to(agent, text, opts)
  opts = opts or {}
  local submit = opts.submit
  if submit == nil then
    submit = M.config.submit_default
  end

  if submit then
    if agent.agent_status == "blocked" then
      vim.notify("Herdr: agent is blocked; not submitting", vim.log.levels.WARN)
      return false
    end
    if agent.agent_status == "working" then
      vim.notify("Herdr: agent is working; sending anyway", vim.log.levels.WARN)
    end
    local dest = target.cli_target(agent)
    if not dest then
      vim.notify("Herdr: agent has no name or pane id. Start one with your herd-roles script.", vim.log.levels.WARN)
      return false
    end
    local _, err = herdr.agent_prompt(dest, text)
    if err then
      if err.code == "agent_blocked" then
        vim.notify("Herdr: agent is blocked; not submitting", vim.log.levels.WARN)
      elseif err.code == "agent_not_found" then
        vim.notify("Herdr: named agent is missing. Run your herd-roles script.", vim.log.levels.WARN)
      else
        vim.notify("Herdr: " .. herdr.err_message(err), vim.log.levels.ERROR)
      end
      return false
    end
    vim.notify("Herdr: submitted to " .. target.label(agent), vim.log.levels.INFO)
    return true
  end

  local pane = agent.pane_id
  if not pane or pane == "" then
    vim.notify("Herdr: agent has no pane id", vim.log.levels.ERROR)
    return false
  end
  local _, err = herdr.pane_send_text(pane, text)
  if err then
    vim.notify("Herdr: " .. herdr.err_message(err), vim.log.levels.ERROR)
    return false
  end
  vim.notify("Herdr: pasted into " .. pane, vim.log.levels.INFO)
  return true
end

--- Send arbitrary text to a Herdr agent.
--- Several live agents → always ask which one (remembered is sorted first).
--- @param text string
--- @param opts? { submit?: boolean, target?: string|table, after?: fun() }
--- @return boolean|nil
function M.send(text, opts)
  opts = opts or {}
  if not text or text == "" then
    vim.notify("Herdr: nothing to send", vim.log.levels.WARN)
    return false
  end

  local function with_agent(agent, err)
    if not agent then
      return false
    end
    local ok = M._send_to(agent, text, opts)
    if ok and opts.after then
      opts.after()
    end
    return ok
  end

  if opts.target then
    if type(opts.target) == "table" then
      return with_agent(opts.target)
    end
    local agent, err = target.find(opts.target)
    if not agent then
      vim.notify("Herdr: named agent is missing. Run your herd-roles script.", vim.log.levels.WARN)
      return false
    end
    return with_agent(agent, err)
  end

  local pending
  target.resolve(function(agent, err)
    pending = with_agent(agent, err)
  end)
  return pending
end

--- Immediate send: typed comment + @file. Asks which agent when several are live.
function M.send_file_ref()
  local ref = context.file_ref()
  if not ref then
    no_file()
    return false
  end
  vim.ui.input({ prompt = "Herdr comment: " }, function(input)
    if not input or input == "" then
      return
    end
    M.send(prompts.render(input, ref), { submit = true })
  end)
end

--- Stack a comment on the current line or range. Shown as 💬 callout; not sent yet.
--- @param start_line integer|nil
--- @param end_line integer|nil
function M.add_comment(start_line, end_line)
  local path = context.relative_file()
  if not path then
    no_file()
    return false
  end
  start_line = start_line or vim.fn.line(".")
  end_line = end_line or start_line
  vim.ui.input({ prompt = "Herdr comment: " }, function(input)
    if input == nil then
      return
    end
    comments.add(0, {
      path = path,
      start_line = start_line,
      end_line = end_line,
      text = input,
    })
  end)
end

--- @param line integer|nil
function M.send_line_ref(line)
  return M.add_comment(line, line)
end

--- @param start_line integer|nil
--- @param end_line integer|nil
function M.send_range_ref(start_line, end_line)
  return M.add_comment(start_line, end_line)
end

--- Show stacked comments in a list widget. `dd` deletes that comment.
function M.list_comments()
  comments.open_list({ code_win = vim.api.nvim_get_current_win() })
end

--- Flush stacked comments (every file) to a chosen agent.
function M.send_comments()
  local text = comments.render()
  if not text then
    vim.notify("Herdr: no comments to send", vim.log.levels.WARN)
    return false
  end
  return M.send(text, {
    submit = true,
    after = function()
      comments.clear_all()
    end,
  })
end

--- @param range_opts? { line1?: integer, line2?: integer, range?: integer }
function M.send_current_ref(range_opts)
  if range_opts and (range_opts.range or 0) > 0 then
    return M.add_comment(range_opts.line1, range_opts.line2)
  end
  return M.send_comments()
end

--- @param range_opts? { line1?: integer, line2?: integer, range?: integer }
function M.ask(range_opts)
  local ref = context.current_ref(range_opts)
  local items = prompts.list()

  vim.ui.select(items, {
    prompt = "Herdr prompt:",
    format_item = function(item)
      return item.label or item.id or "?"
    end,
  }, function(choice)
    if not choice then
      return
    end
    local function submit_text(text)
      if not text or text == "" then
        return
      end
      M.send(prompts.render(text, ref), { submit = true })
    end
    if choice.input then
      vim.ui.input({ prompt = "Herdr prompt: " }, function(input)
        submit_text(input)
      end)
      return
    end
    submit_text(choice.text)
  end)
end

M.select = M.ask

--- Custom prompt. Empty/nil opens vim.ui.input.
--- @param text string|nil
--- @param range_opts? { line1?: integer, line2?: integer, range?: integer }
function M.prompt(text, range_opts)
  local ref = context.current_ref(range_opts)

  local function submit_text(value)
    if not value or value == "" then
      return
    end
    M.send(prompts.render(value, ref), { submit = true })
  end

  if not text or text == "" then
    vim.ui.input({ prompt = "Herdr prompt: " }, function(input)
      submit_text(input)
    end)
    return
  end
  submit_text(text)
end

function M.health()
  local lines = { "Herdr health" }
  local bin = herdr.exepath()
  local present = herdr.executable()
  table.insert(lines, string.format("  binary: %s (%s)", bin, present and "ok" or "missing"))
  table.insert(lines, "  HERDR_ENV: " .. (vim.env.HERDR_ENV or "unset"))
  table.insert(lines, "  HERDR_SOCKET_PATH: " .. (vim.env.HERDR_SOCKET_PATH or "unset"))
  table.insert(lines, "  HERDR_BIN_PATH: " .. (vim.env.HERDR_BIN_PATH or "unset"))

  if not present then
    table.insert(lines, "  server: unreachable (herdr not on PATH)")
    vim.notify(table.concat(lines, "\n"), vim.log.levels.ERROR)
    return false
  end

  local status, err = herdr.status()
  if err then
    table.insert(lines, "  server: " .. herdr.err_message(err))
    vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
    return false
  end

  local server = status.server or {}
  local running = server.running or server.status == "running"
  table.insert(lines, "  server: " .. (running and "running" or (server.status or "unknown")))
  table.insert(lines, "  socket: " .. (server.socket or vim.env.HERDR_SOCKET_PATH or "default"))

  local agents, agents_err = herdr.agent_list()
  if agents_err then
    table.insert(lines, "  agents: " .. herdr.err_message(agents_err))
    vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
    return false
  end
  table.insert(lines, "  agents: " .. tostring(#agents))
  vim.notify(table.concat(lines, "\n"), running and vim.log.levels.INFO or vim.log.levels.WARN)
  return running
end

function M.agents()
  local agents, err = herdr.agent_list()
  if err then
    vim.notify("Herdr: " .. herdr.err_message(err), vim.log.levels.ERROR)
    return
  end
  if #agents == 0 then
    vim.notify("Herdr agents (0)\n  (none)", vim.log.levels.INFO)
    return
  end
  local lines = { string.format("Herdr agents (%d)", #agents) }
  for _, agent in ipairs(target.sort(agents)) do
    table.insert(lines, "  " .. target.label(agent))
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.pick_target()
  target.pick(function() end)
end

function M._dispatch(opts)
  commands.dispatch(M, opts)
end

return M
