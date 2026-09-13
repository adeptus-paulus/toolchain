vim.g.mapleader = ' '

vim.opt.clipboard:append('unnamedplus')
vim.opt.number = true
vim.opt.termguicolors = true
vim.opt.ruler = true
vim.opt.wrap = false
vim.opt.showmode = false

require('config.plugins')
require('config.setup')

vim.cmd('highlight rustLifetime guifg=#20999d')
