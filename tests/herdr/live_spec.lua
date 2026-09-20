-- Live read-only checks against a running Herdr server.
-- Never calls `herdr agent prompt` or `pane send-text`.
local herd = require("herdr")
local herdr = require("herdr.cli")

local function server_up()
  if vim.fn.executable("herdr") ~= 1 then
    return false
  end
  -- Use the real vim.system, not the unit-test mock.
  herdr._system = vim.system
  local status, err = herdr.status()
  if err or not status or not status.server then
    return false
  end
  return status.server.running or status.server.status == "running"
end

describe("herd live herdr", function()
  if not server_up() then
    it("skips when herdr server is not running", function()
      assert.is_true(true)
    end)
    return
  end

  before_each(function()
    herdr._system = vim.system
    herd.setup({ keymaps = false })
  end)

  it(":Herdr health talks to the live server", function()
    local notes = {}
    vim.notify = function(msg)
      table.insert(notes, tostring(msg))
    end
    local ok = herd.health()
    assert.is_true(ok)
    local msg = table.concat(notes, "\n")
    assert.is_truthy(msg:find("Herdr health", 1, true))
    assert.is_truthy(msg:find("server: running", 1, true))
    assert.is_truthy(msg:find("socket:", 1, true))
    assert.is_truthy(msg:find("agents:", 1, true))
  end)

  it(":Herdr agents lists live agents", function()
    local notes = {}
    vim.notify = function(msg)
      table.insert(notes, tostring(msg))
    end
    herd.agents()
    local msg = table.concat(notes, "\n")
    assert.is_truthy(msg:find("Herdr agents", 1, true))
  end)
end)
