-- Tests for herdr.nvim. Run via tests/herdr/minimal_init.lua + plenary.
local herd = require("herdr")
local herdr = require("herdr.cli")
local context = require("herdr.context")
local prompts = require("herdr.prompts")
local target = require("herdr.target")
local commands = require("herdr.commands")
local config = require("herdr.config")
local comments = require("herdr.comments")

local notes = {}
local last_cmd = nil
local mocks = {}

local SAMPLE_AGENTS = {
  {
    name = "impl",
    agent = "grok",
    agent_status = "idle",
    pane_id = "wM:p3",
    cwd = "/tmp/proj",
    tab_id = "wM:t1",
  },
  {
    name = "review",
    agent = "grok",
    agent_status = "idle",
    pane_id = "wM:p2",
    cwd = "/tmp/proj",
    tab_id = "wM:t1",
  },
  {
    name = nil,
    agent = "grok",
    agent_status = "working",
    pane_id = "wM:p4",
    cwd = "/tmp/other",
    tab_id = "wM:t1",
  },
}

local function classify(cmd)
  if cmd[2] == "status" then
    return "status"
  end
  if cmd[2] == "agent" and cmd[3] == "list" then
    return "agent_list"
  end
  if cmd[2] == "agent" and cmd[3] == "prompt" then
    return "agent_prompt"
  end
  if cmd[2] == "agent" and cmd[3] == "focus" then
    return "agent_focus"
  end
  if cmd[2] == "agent" and cmd[3] == "get" then
    return "agent_get"
  end
  if cmd[2] == "pane" and cmd[3] == "send-text" then
    return "send_text"
  end
  return "other"
end

local function json_ok(result)
  return {
    code = 0,
    stdout = vim.json.encode({ id = "cli", result = result }),
    stderr = "",
  }
end

local function json_err(code, message)
  return {
    code = 1,
    stdout = vim.json.encode({
      id = "cli",
      error = { code = code, message = message },
    }),
    stderr = "",
  }
end

local function install_mocks()
  notes = {}
  last_cmd = nil
  mocks = {
    status = {
      code = 0,
      stdout = vim.json.encode({
        server = {
          status = "running",
          running = true,
          socket = "/tmp/herdr.sock",
        },
      }),
      stderr = "",
    },
    agent_list = json_ok({ type = "agent_list", agents = SAMPLE_AGENTS }),
    agent_prompt = json_ok({ type = "ok" }),
    agent_focus = json_ok({ type = "ok" }),
    send_text = json_ok({ type = "ok" }),
    agent_get = json_ok({ type = "ok" }),
  }
  herdr._system = function(cmd, _)
    last_cmd = cmd
    local kind = classify(cmd)
    local payload = mocks[kind] or { code = 1, stdout = "", stderr = "unmocked " .. kind }
    return {
      wait = function()
        return payload
      end,
    }
  end
  vim.notify = function(msg, level)
    table.insert(notes, { msg = tostring(msg), level = level })
  end
end

local function note_join()
  local parts = {}
  for _, n in ipairs(notes) do
    table.insert(parts, n.msg)
  end
  return table.concat(parts, "\n")
end

describe("herdr.nvim", function()
  before_each(function()
    config.reset()
    herd._setup_done = false
    target.clear_memory()
    install_mocks()
    herd.setup({ keymaps = false, herdr_bin = "herdr" })
    pcall(vim.api.nvim_del_user_command, "HerdHealth")
    comments.clear_all()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.cmd("enew!")
  end)

  it("can be required and set up", function()
    assert.is_not_nil(herd)
    assert.is_function(herd.setup)
    assert.is_function(herd.send)
    assert.equals("herdr", herd.config.herdr_bin)
  end)

  it("registers :Herdr and no legacy :Herd* commands", function()
    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds.Herdr)
    assert.is_nil(cmds.HerdHealth)
    assert.is_nil(cmds.HerdAgents)
    assert.is_nil(cmds.HerdFile)
    assert.is_nil(cmds.HerdLine)
    assert.is_nil(cmds.HerdRange)
    assert.is_nil(cmds.HerdPrompt)
  end)

  it("completes subcommands", function()
    local all = commands.complete("", "Herdr ", 7)
    assert.is_true(vim.tbl_contains(all, "health"))
    assert.is_true(vim.tbl_contains(all, "prompt"))
    assert.is_true(vim.tbl_contains(all, "list"))
    local h = commands.complete("he", "Herdr he", 9)
    assert.same({ "health" }, h)
    local none = commands.complete("", "Herdr health ", 14)
    assert.same({}, none)
  end)

  it("health reports binary, env, socket, agents", function()
    herd.health()
    local msg = note_join()
    assert.is_truthy(msg:find("Herdr health", 1, true))
    assert.is_truthy(msg:find("binary:", 1, true))
    assert.is_truthy(msg:find("socket: /tmp/herdr.sock", 1, true))
    assert.is_truthy(msg:find("agents: 3", 1, true))
    assert.is_truthy(msg:find("HERDR_ENV:", 1, true))
  end)

  it("agents notifies list and state", function()
    herd.agents()
    local msg = note_join()
    assert.is_truthy(msg:find("Herdr agents (3)", 1, true))
    assert.is_truthy(msg:find("review", 1, true))
    assert.is_truthy(msg:find("working", 1, true))
  end)

  it("empty agent list is success", function()
    mocks.agent_list = json_ok({ type = "agent_list", agents = {} })
    herd.agents()
    local msg = note_join()
    assert.is_truthy(msg:find("Herdr agents (0)", 1, true))
  end)

  it("parses CLI JSON errors", function()
    mocks.agent_list = json_err("agent_blocked", "agent is blocked")
    local agents, err = herdr.agent_list()
    assert.equals(0, #agents)
    assert.equals("agent_blocked", err.code)
    assert.equals("agent is blocked", err.message)
  end)

  it("labels agents by Herdr name or pane title", function()
    assert.equals(
      "review · idle · grok · /tmp/proj",
      target.label(SAMPLE_AGENTS[2])
    )
    assert.equals(
      "Fix counter in main.rs · idle · grok · ~/qt-journey",
      target.label({
        agent = "grok",
        agent_status = "idle",
        cwd = vim.fn.expand("~/qt-journey"),
        pane_id = "w1:p2",
        terminal_title_stripped = "Fix counter in main.rs",
      })
    )
  end)

  it("sorts named roles ahead of pane ids", function()
    local sorted = target.sort(SAMPLE_AGENTS)
    assert.equals("review", sorted[1].name)
    assert.equals("impl", sorted[2].name)
    assert.equals("wM:p4", sorted[3].pane_id)
  end)

  it("asks which agent when several are live, even if one is remembered", function()
    target.remember(SAMPLE_AGENTS[2])
    local agent, err, need_pick = target.try_resolve()
    assert.is_nil(err)
    assert.is_nil(agent)
    assert.is_true(need_pick)
  end)

  it("sorts remembered agent first in the picker list", function()
    target.remember(SAMPLE_AGENTS[1]) -- impl, otherwise review wins by role
    local sorted = target.sort(SAMPLE_AGENTS)
    assert.equals("impl", sorted[1].name)
  end)

  it("stale memory falls through to pick when several remain", function()
    target.remember({ name = "audit", pane_id = "gone" })
    local agent, err, need_pick = target.try_resolve()
    assert.is_nil(agent)
    assert.is_nil(err)
    assert.is_true(need_pick)
    assert.is_truthy(note_join():find("remembered target is gone", 1, true))
  end)

  it("auto-uses a single live agent", function()
    mocks.agent_list = json_ok({
      type = "agent_list",
      agents = { SAMPLE_AGENTS[2] },
    })
    local agent, err, need_pick = target.try_resolve()
    assert.is_nil(err)
    assert.is_false(need_pick)
    assert.equals("review", agent.name)
  end)

  it("formats @file / :line / :range refs", function()
    assert.equals("@src/foo.lua", context.format_ref("src/foo.lua"))
    assert.equals("@src/foo.lua:42", context.format_ref("src/foo.lua", 42))
    assert.equals("@src/foo.lua:42", context.format_ref("src/foo.lua", 42, 42))
    assert.equals("@src/foo.lua:10-25", context.format_ref("src/foo.lua", 10, 25))
    assert.equals("@src/foo.lua:10-25", context.format_ref("src/foo.lua", 25, 10))
  end)

  it("relative_file strips git root", function()
    local orig = context.git_root
    context.git_root = function()
      return "/tmp/proj"
    end
    vim.cmd("enew")
    vim.api.nvim_buf_set_name(0, "/tmp/proj/lua/foo.lua")
    assert.equals("lua/foo.lua", context.relative_file())
    context.git_root = orig
  end)

  it("renders prompt then ref, and skips duplicate @", function()
    assert.equals("Explain\n\n@src/foo.lua", prompts.render("Explain", "@src/foo.lua"))
    assert.equals("Explain @src/foo.lua", prompts.render("Explain @src/foo.lua", "@src/foo.lua"))
    assert.equals("Explain", prompts.render("Explain", nil))
  end)

  it("paste send uses pane send-text", function()
    local ok = herd.send("@src/foo.lua", { submit = false, target = "review" })
    assert.is_true(ok)
    assert.equals("pane", last_cmd[2])
    assert.equals("send-text", last_cmd[3])
    assert.equals("wM:p2", last_cmd[4])
    assert.equals("@src/foo.lua", last_cmd[5])
  end)

  it("send focuses the agent view and pastes without submitting", function()
    local ok = herd.send("Explain\n\n@src/foo.lua", { target = "review" })
    assert.is_true(ok)
    assert.equals("pane", last_cmd[2])
    assert.equals("send-text", last_cmd[3])
    assert.equals("wM:p2", last_cmd[4])
    assert.equals("Explain\n\n@src/foo.lua", last_cmd[5])
    assert.is_truthy(note_join():find("not submitted", 1, true))
  end)

  it("warns and still sends when agent is working", function()
    mocks.agent_list = json_ok({
      type = "agent_list",
      agents = {
        {
          name = "review",
          agent = "grok",
          agent_status = "working",
          pane_id = "wM:p2",
        },
      },
    })
    local ok = herd.send("hi", { target = "review" })
    assert.is_true(ok)
    assert.equals("send-text", last_cmd[3])
    assert.is_truthy(note_join():find("working", 1, true))
  end)

  it("unknown subcommand notifies the valid list", function()
    commands.dispatch(herd, { fargs = { "nope" }, range = 0 })
    local msg = note_join()
    assert.is_truthy(msg:find("unknown command", 1, true))
    assert.is_truthy(msg:find("health", 1, true))
  end)

  it(":Herdr prompt with args submits rendered text", function()
    mocks.agent_list = json_ok({ type = "agent_list", agents = { SAMPLE_AGENTS[2] } })
    commands.dispatch(herd, {
      fargs = { "prompt", "fix", "this" },
      range = 0,
    })
    assert.equals("pane", last_cmd[2])
    assert.equals("send-text", last_cmd[3])
    assert.equals("wM:p2", last_cmd[4])
    assert.equals("fix this", last_cmd[5])
  end)

  it(":Herdr prompt without args uses vim.ui.input", function()
    mocks.agent_list = json_ok({ type = "agent_list", agents = { SAMPLE_AGENTS[2] } })
    local asked
    vim.ui.input = function(opts, cb)
      asked = opts.prompt
      cb("please review")
    end
    commands.dispatch(herd, { fargs = { "prompt" }, range = 0 })
    assert.equals("Herdr prompt: ", asked)
    assert.equals("please review", last_cmd[5])
  end)

  it("bare :Herdr picker submits the chosen prompt", function()
    mocks.agent_list = json_ok({ type = "agent_list", agents = { SAMPLE_AGENTS[2] } })
    vim.ui.select = function(items, _, cb)
      cb(items[1])
    end
    commands.dispatch(herd, { fargs = {}, range = 0 })
    assert.equals("send-text", last_cmd[3])
    assert.is_truthy(last_cmd[5]:find("Explain this code", 1, true))
  end)

  it("ask prompt opens vim.ui.input", function()
    mocks.agent_list = json_ok({ type = "agent_list", agents = { SAMPLE_AGENTS[2] } })
    vim.ui.select = function(items, _, cb)
      cb(items[#items])
    end
    vim.ui.input = function(_, cb)
      cb("custom hello")
    end
    herd.ask()
    assert.equals("custom hello", last_cmd[5])
  end)

  it("send asks which agent when several are live", function()
    local prompts_seen = {}
    vim.ui.select = function(items, opts, cb)
      table.insert(prompts_seen, opts.prompt)
      for _, it in ipairs(items) do
        if it.name == "review" then
          cb(it)
          return
        end
      end
      cb(items[1])
    end
    local ok = herd.send("hello", { submit = true })
    assert.is_true(ok)
    assert.is_truthy(prompts_seen[1]:find("agent", 1, true))
    assert.equals("send-text", last_cmd[3])
    assert.equals("wM:p2", last_cmd[4])
    assert.equals("hello", last_cmd[5])
  end)

  it("paste error does not look like success", function()
    mocks.send_text = json_err("error", "pane gone")
    local ok = herd.send("hi", { target = "review" })
    assert.is_false(ok)
    assert.is_truthy(note_join():find("pane gone", 1, true))
  end)

  it(":Herdr file sends @file with the typed comment", function()
    local orig = context.git_root
    context.git_root = function()
      return "/tmp/proj"
    end
    vim.api.nvim_buf_set_name(0, "/tmp/proj/src/foo.lua")
    mocks.agent_list = json_ok({ type = "agent_list", agents = { SAMPLE_AGENTS[2] } })
    vim.ui.input = function(opts, cb)
      assert.equals("Herdr comment: ", opts.prompt)
      cb("look here")
    end
    commands.dispatch(herd, { fargs = { "file" }, range = 0 })
    assert.equals("send-text", last_cmd[3])
    assert.equals("look here\n\n@src/foo.lua", last_cmd[5])
    context.git_root = orig
  end)

  it(":Herdr line stacks a visible comment and does not send yet", function()
    local orig = context.git_root
    context.git_root = function()
      return "/tmp/proj"
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
    vim.api.nvim_buf_set_name(0, "/tmp/proj/src/foo.lua")
    vim.ui.input = function(_, cb)
      cb("this is wrong")
    end
    last_cmd = nil
    commands.dispatch(herd, { fargs = { "line" }, line1 = 2, line2 = 2, range = 0 })
    assert.is_nil(last_cmd)
    local items = comments.list(0)
    assert.equals(1, #items)
    assert.equals("this is wrong", items[1].text)
    assert.equals(2, items[1].start_line)
    local marks = vim.api.nvim_buf_get_extmarks(0, comments.ns, 0, -1, { details = true })
    assert.equals(1, #marks)
    local chunks = marks[1][4].virt_lines[1]
    local shown = ""
    for _, chunk in ipairs(chunks) do
      shown = shown .. chunk[1]
    end
    assert.is_truthy(shown:find("💬", 1, true))
    assert.is_truthy(shown:find("this is wrong", 1, true))
    assert.is_truthy(vim.trim(marks[1][4].sign_text or ""):find("▌", 1, true))
    context.git_root = orig
  end)

  it(":Herdr send flushes stacked comments to the chosen agent", function()
    local orig = context.git_root
    context.git_root = function()
      return "/tmp/proj"
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
    vim.api.nvim_buf_set_name(0, "/tmp/proj/src/foo.lua")
    comments.add(0, { path = "src/foo.lua", start_line = 1, end_line = 1, text = "first" })
    comments.add(0, { path = "src/foo.lua", start_line = 3, end_line = 4, text = "range note" })
    vim.ui.select = function(items, opts, cb)
      assert.is_truthy(opts.prompt:find("agent", 1, true))
      for _, it in ipairs(items) do
        if it.name == "review" then
          cb(it)
          return
        end
      end
      cb(items[1])
    end
    commands.dispatch(herd, { fargs = { "send" }, range = 0 })
    assert.equals("send-text", last_cmd[3])
    assert.equals("wM:p2", last_cmd[4])
    local body = last_cmd[5]
    assert.is_truthy(body:find("@src/foo.lua:1", 1, true))
    assert.is_truthy(body:find("first", 1, true))
    assert.is_truthy(body:find("@src/foo.lua:3-4", 1, true))
    assert.is_truthy(body:find("range note", 1, true))
    assert.equals(0, #comments.list(0))
    context.git_root = orig
  end)

  it("updates a stacked comment in place", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
    local uid = comments.add(0, { path = "src/foo.lua", start_line = 1, end_line = 1, text = "old" })
    assert.is_true(comments.update({ uid = uid }, "new text"))
    local items = comments.list(0)
    assert.equals("new text", items[1].text)
    local marks = vim.api.nvim_buf_get_extmarks(0, comments.ns, 0, -1, { details = true })
    local shown = ""
    for _, chunk in ipairs(marks[1][4].virt_lines[1]) do
      shown = shown .. chunk[1]
    end
    assert.is_truthy(shown:find("new text", 1, true))
  end)

  it("deletes a single stacked comment", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
    comments.add(0, { path = "src/foo.lua", start_line = 1, end_line = 1, text = "first" })
    comments.add(0, { path = "src/foo.lua", start_line = 2, end_line = 2, text = "second" })
    local items = comments.list(0)
    assert.equals(2, #items)
    comments.delete(0, items[1].id)
    local left = comments.list(0)
    assert.equals(1, #left)
    assert.equals("second", left[1].text)
  end)

  local function find_list_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "herdr-comments" then
        return win, buf
      end
    end
    return nil, nil
  end

  it(":Herdr list opens a widget and dd deletes that comment", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
    local src = vim.api.nvim_get_current_buf()
    comments.add(src, { path = "src/foo.lua", start_line = 1, end_line = 1, text = "first" })
    comments.add(src, { path = "src/foo.lua", start_line = 2, end_line = 2, text = "second" })
    commands.dispatch(herd, { fargs = { "list" }, range = 0 })
    local win, buf = find_list_win()
    assert.is_not_nil(win)
    assert.equals(2, vim.api.nvim_buf_line_count(buf))
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal dd")
    end)
    local left = comments.list(src)
    assert.equals(1, #left)
    assert.equals("second", left[1].text)
  end)

  it(":Herdr list with no comments notifies", function()
    commands.dispatch(herd, { fargs = { "list" }, range = 0 })
    assert.is_truthy(note_join():find("no comments", 1, true))
  end)

  it("stores comments globally across files", function()
    local orig = context.git_root
    context.git_root = function()
      return "/tmp/proj"
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a1", "a2" })
    vim.api.nvim_buf_set_name(0, "/tmp/proj/a.lua")
    local buf_a = vim.api.nvim_get_current_buf()
    comments.add(buf_a, { path = "a.lua", start_line = 1, end_line = 1, text = "in a" })

    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "b1" })
    vim.api.nvim_buf_set_name(0, "/tmp/proj/b.lua")
    local buf_b = vim.api.nvim_get_current_buf()
    comments.add(buf_b, { path = "b.lua", start_line = 1, end_line = 1, text = "in b" })

    local all = comments.list()
    assert.equals(2, #all)
    local rendered = comments.render()
    assert.is_truthy(rendered:find("@a.lua:1", 1, true))
    assert.is_truthy(rendered:find("in a", 1, true))
    assert.is_truthy(rendered:find("@b.lua:1", 1, true))
    assert.is_truthy(rendered:find("in b", 1, true))
    assert.equals(1, #comments.list(buf_a))
    assert.equals("a.lua:1  in a", comments.label(all[1]))
    context.git_root = orig
  end)

  it(":Herdr send with no comments notifies", function()
    commands.dispatch(herd, { fargs = { "send" }, range = 0 })
    assert.is_truthy(note_join():find("no comments to send", 1, true))
  end)

  it("registers suggested keymaps", function()
    herd.setup({
      keymaps = {
        file = "<leader>f",
        line = "<leader>l",
        list = "<leader>al",
        send = "<leader>as",
      },
    })
    local function has_map(mode, rhs_desc)
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        if m.desc and m.desc:find(rhs_desc, 1, true) then
          return true
        end
      end
      return false
    end
    assert.is_true(has_map("n", "Herdr: send @file with comment"))
    assert.is_true(has_map("n", "Herdr: stack comment on line"))
    assert.is_true(has_map("x", "Herdr: stack comment on range"))
    assert.is_true(has_map("n", "Herdr: list comments"))
    assert.is_true(has_map("n", "Herdr: send comments"))
  end)
end)
