local M = {}

--- @param herd table
--- @param config table
function M.register(herd, config)
  local km = config.keymaps
  if not km or km == false then
    return
  end

  if km.file and km.file ~= false then
    vim.keymap.set("n", km.file, function()
      herd.send_file_ref()
    end, { desc = "Herdr: send @file with comment", noremap = true, silent = true })
  end

  if km.line and km.line ~= false then
    vim.keymap.set("n", km.line, function()
      herd.add_comment()
    end, { desc = "Herdr: stack comment on line", noremap = true, silent = true })
    vim.keymap.set("x", km.line, function()
      local start_line = vim.fn.line("v")
      local end_line = vim.fn.line(".")
      if start_line > end_line then
        start_line, end_line = end_line, start_line
      end
      herd.add_comment(start_line, end_line)
    end, { desc = "Herdr: stack comment on range", noremap = true, silent = true })
  end

  if km.list and km.list ~= false then
    vim.keymap.set("n", km.list, function()
      herd.list_comments()
    end, { desc = "Herdr: list comments", noremap = true, silent = true })
  end

  if km.prompt and km.prompt ~= false then
    vim.keymap.set("n", km.prompt, function()
      herd.prompt()
    end, { desc = "Herdr: custom prompt", noremap = true, silent = true })
  end

  local send = km.send or km.ask or km.select
  if send and send ~= false then
    vim.keymap.set("n", send, function()
      herd.send_comments()
    end, { desc = "Herdr: send comments", noremap = true, silent = true })
  end
end

return M
