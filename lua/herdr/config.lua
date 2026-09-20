---@mod herdr.config Configuration for herdr.nvim
local M = {}

--- @class herdr.Keymaps
--- @field file string|false|nil
--- @field line string|false|nil
--- @field list string|false|nil
--- @field prompt string|false|nil
--- @field send string|false|nil -- flush stacked comments to an agent
--- @field ask string|false|nil -- alias of send
--- @field select string|false|nil -- alias of send

--- @class herdr.Config
--- @field herdr_bin string
--- @field remember_target boolean
--- @field submit_default boolean
--- @field timeout_ms integer
--- @field roles table<string, string>
--- @field prompts table[]|nil
--- @field keymaps herdr.Keymaps|false

M.default_config = {
  herdr_bin = "herdr",
  remember_target = true,
  submit_default = true,
  timeout_ms = 5000,
  roles = {
    review = "review",
    tests = "tests",
    audit = "audit",
    impl = "impl",
  },
  prompts = nil,
  -- Off by default so we do not steal grok-code's <leader>a / <leader>l.
  keymaps = {
    file = false,
    line = false,
    list = false,
    prompt = false,
    send = false,
  },
}

--- @type herdr.Config
M.current = vim.deepcopy(M.default_config)

local function validate(cfg)
  if type(cfg.herdr_bin) ~= "string" or cfg.herdr_bin == "" then
    return false, "herdr_bin must be a non-empty string"
  end
  if type(cfg.remember_target) ~= "boolean" then
    return false, "remember_target must be boolean"
  end
  if type(cfg.submit_default) ~= "boolean" then
    return false, "submit_default must be boolean"
  end
  if type(cfg.timeout_ms) ~= "number" or cfg.timeout_ms <= 0 then
    return false, "timeout_ms must be a positive number"
  end
  if type(cfg.roles) ~= "table" then
    return false, "roles must be a table"
  end
  if cfg.prompts ~= nil and type(cfg.prompts) ~= "table" then
    return false, "prompts must be a table or nil"
  end
  if cfg.keymaps ~= false and type(cfg.keymaps) ~= "table" then
    return false, "keymaps must be a table or false"
  end
  return true
end

--- @param user_config table|nil
--- @param silent boolean|nil
--- @return herdr.Config
function M.parse_config(user_config, silent)
  local cfg = vim.tbl_deep_extend("force", {}, M.default_config, user_config or {})
  -- tbl_deep_extend merges keymaps; false should fully disable.
  if user_config and user_config.keymaps == false then
    cfg.keymaps = false
  end
  local ok, err = validate(cfg)
  if not ok then
    if not silent then
      vim.notify("herdr: " .. err, vim.log.levels.ERROR)
    end
    return vim.deepcopy(M.default_config)
  end
  return cfg
end

--- @param cfg herdr.Config
function M.set(cfg)
  M.current = cfg
end

--- @return herdr.Config
function M.get()
  return M.current
end

function M.reset()
  M.current = vim.deepcopy(M.default_config)
end

return M
