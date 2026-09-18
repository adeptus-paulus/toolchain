set clipboard+=unnamedplus
set number
set termguicolors
set ruler
set nowrap
set noshowmode
vmap <S-Tab> <gv
vmap <Tab> >gv
nmap <silent> cvi :TSHighlightCapturesUnderCursor<CR>
nmap <silent> = :horizontal split<CR>
nmap <silent> + :vertical split<CR>
nmap <silent> <M-Left> :tabprevious<CR>
nmap <silent> <M-Right> :tabnext<CR>

nmap <silent> <C-F8> :DapToggleBreakpoint<CR>

nmap <silent> <F7> :DapStepInto<CR>
nmap <silent> <F8> :DapStepOver<CR>
nmap <silent> <F9> :DapContinue<CR>
nmap <silent> <C-F9> :RustRun<CR>
nmap <silent> псс gcc

call plug#begin()

Plug 'uga-rosa/translate.nvim'

Plug 'LunarVim/bigfile.nvim'

" uncomment to enable scala lsp
" Plug 'scalameta/nvim-metals'

Plug 'f-person/auto-dark-mode.nvim'

Plug 'aveplen/ruscmd.nvim'

"Shorthand notation; fetches https://github.com/junegunn/vim-easy-align
Plug 'junegunn/vim-easy-align'

Plug 'kshenoy/vim-signature'

Plug 'lewis6991/gitsigns.nvim'
Plug 'neovim/nvim-lspconfig'
"Completion plugin 
Plug 'hrsh7th/nvim-cmp'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'saadparwaiz1/cmp_luasnip'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/cmp-buffer'

Plug 'L3MON4D3/LuaSnip'

Plug 'mrcjkb/rustaceanvim', { 'tag': 'v8.0.5' }

Plug 'windwp/nvim-autopairs'

Plug 'nvim-lua/plenary.nvim'

" Plug 'github/copilot.vim'

Plug 'rmagatti/auto-session'

Plug 'folke/snacks.nvim'

Plug 'https://gitlab.com/itaranto/plantuml.nvim'
Plug 'tpope/vim-fugitive'
Plug 'rbong/vim-flog'
Plug 'briones-gabriel/darcula-solid.nvim'
Plug 'rktjmp/lush.nvim'
" Plug 'pocco81/AutoSave.nvim'

Plug 'williamboman/mason.nvim'
Plug 'williamboman/mason-lspconfig.nvim'

" Database management plugins
Plug 'tpope/vim-dadbod'
Plug 'kristijanhusak/vim-dadbod-ui'
Plug 'kristijanhusak/vim-dadbod-completion' "Optional

Plug 'MunifTanjim/prettier.nvim'

Plug 'kevinhwang91/promise-async'
Plug 'kevinhwang91/nvim-ufo'
Plug 'tpope/vim-sleuth'

Plug 'ray-x/go.nvim'
Plug 'ray-x/guihua.lua'

Plug 'f-person/git-blame.nvim'
" Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && npx --yes yarn install' }
Plug 'nvim-tree/nvim-tree.lua'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'nvim-telescope/telescope-ui-select.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'nvim-treesitter/nvim-treesitter', { 'do' : ':TSUpdate', 'branch': 'master' }
Plug 'nvim-treesitter/playground'

Plug 'HiPhish/rainbow-delimiters.nvim'

Plug 'mfussenegger/nvim-dap'
Plug 'nvim-neotest/nvim-nio'
Plug 'rcarriga/nvim-dap-ui'
Plug 'sindrets/diffview.nvim'

Plug 'numToStr/Comment.nvim'

Plug 'folke/todo-comments.nvim'

" Plug 'saecki/crates.nvim'
Plug 'paval-shlyk/crates.nvim', { 'branch': 'feat/add-workspace-support' }
Plug 'https://github.com/ThePrimeagen/harpoon', { 'branch': 'harpoon2' }
Plug 'https://github.com/MeanderingProgrammer/render-markdown.nvim'

Plug 'rust-sailfish/sailfish', { 'rtp': 'syntax/vim' }

Plug 'kenn7/vim-arsync'

" vim-arsync depedencies
Plug 'prabirshrestha/async.vim'


Plug 'nvim-treesitter/nvim-treesitter-context' 

Plug 'nvim-lualine/lualine.nvim'
Plug 'folke/snacks.nvim'

Plug 'tigion/nvim-asciidoc-preview'

" Plug 'paval-shlyk/session-todo.nvim'

" they both use same bindings
Plug 'coder/claudecode.nvim'
" Plug 'NickvanDyke/opencode.nvim'

call plug#end()

set termguicolors
highlight rustLifetime guifg=#20999d

autocmd FileType sql,mysql,plsql lua require('cmp').setup.buffer({ sources = {{ name = 'vim-dadbod-completion' }} })

lua require('sharelink').setup()
