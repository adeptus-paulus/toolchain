if vim.g.loaded_sharelink then
  return
end
vim.g.loaded_sharelink = true

require("sharelink").setup()
