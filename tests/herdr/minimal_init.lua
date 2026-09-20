-- Minimal init for herdr.nvim tests (headless Neovim / plenary).
local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.rtp:prepend(config_root)

local plenary_path = vim.fn.stdpath("data") .. "/site/pack/core/opt/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 0 then
  plenary_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim"
end
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:append(plenary_path)
end

vim.cmd("runtime plugin/herdr.lua")

-- Print notifies so headless runs are inspectable. Tests can still stub this.
vim.notify = function(msg, level)
  local label = ({
    [vim.log.levels.ERROR] = "ERROR",
    [vim.log.levels.WARN] = "WARN",
    [vim.log.levels.INFO] = "INFO",
    [vim.log.levels.DEBUG] = "DEBUG",
  })[level or vim.log.levels.INFO] or "INFO"
  print(string.format("[herdr %s] %s", label, tostring(msg)))
end

pcall(function()
  vim.cmd("runtime plugin/plenary.vim")
end)
