if vim.g.loaded_herdr then
  return
end
vim.g.loaded_herdr = true

vim.api.nvim_create_user_command("Herdr", function(opts)
  require("herdr")._ensure_setup()
  require("herdr.commands").dispatch(require("herdr"), opts)
end, {
  nargs = "*",
  range = true,
  desc = "Talk to a Herdr agent",
  complete = function(arglead, cmdline, cursorpos)
    return require("herdr.commands").complete(arglead, cmdline, cursorpos)
  end,
})
