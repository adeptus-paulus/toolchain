local M = {}

-- Generic post-install/update hooks (vim.pack equivalent of vim-plug's `do`).
vim.api.nvim_create_autocmd('PackChanged', {
  group = vim.api.nvim_create_augroup('UserPackHooks', { clear = true }),
  callback = function(ev)
    local spec = ev.data and ev.data.spec
    local kind = ev.data and ev.data.kind
    local path = ev.data and ev.data.path
    if not spec or not kind or (kind ~= 'install' and kind ~= 'update') then return end

    local build = spec.data and spec.data.build
    if not build then return end

    vim.schedule(function()
      if type(build) == 'string' then
        vim.notify('Building ' .. spec.name .. '...', vim.log.levels.INFO)
        vim.system({ 'sh', '-c', build }, { cwd = path }, function(res)
          vim.schedule(function()
            if res.code == 0 then
              vim.notify(spec.name .. ' build complete', vim.log.levels.INFO)
            else
              vim.notify(spec.name .. ' build failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
            end
          end)
        end)
      elseif type(build) == 'function' then
        build(path)
      end
    end)
  end,
})

local plugins = {
  -- Core utilities
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/nvim-neotest/nvim-nio',

  -- UI / appearance
  {
    src = 'https://github.com/briones-gabriel/darcula-solid.nvim',
    version = 'd950b9ca20096313c435a93e57af7815766f3d3d',
  },
  'https://github.com/rktjmp/lush.nvim',
  'https://github.com/nvim-lualine/lualine.nvim',
  'https://github.com/nvim-tree/nvim-web-devicons',

  -- File explorer
  'https://github.com/nvim-tree/nvim-tree.lua',

  -- Treesitter (core + context + rainbow)
  {
    src = 'https://github.com/nvim-treesitter/nvim-treesitter',
    version = 'main',
    build = function()
      vim.schedule(function() pcall(vim.cmd, 'TSUpdate') end)
    end,
  },
  'https://github.com/nvim-treesitter/nvim-treesitter-context',
  'https://github.com/HiPhish/rainbow-delimiters.nvim',

  -- Telescope + extensions
  { src = 'https://github.com/nvim-telescope/telescope.nvim', version = 'main' },
  'https://github.com/nvim-telescope/telescope-ui-select.nvim',
  'https://github.com/smartpde/telescope-recent-files',

  -- LSP + completion + snippets
  'https://github.com/neovim/nvim-lspconfig',
  'https://github.com/hrsh7th/nvim-cmp',
  'https://github.com/hrsh7th/cmp-nvim-lsp',
  'https://github.com/hrsh7th/cmp-buffer',
  'https://github.com/hrsh7th/cmp-path',
  'https://github.com/saadparwaiz1/cmp_luasnip',
  'https://github.com/L3MON4D3/LuaSnip',

  -- Mason (LSP/DAP/linter management)
  'https://github.com/williamboman/mason.nvim',
  'https://github.com/williamboman/mason-lspconfig.nvim',

  -- Language specific / heavy plugins
  'https://github.com/mrcjkb/rustaceanvim',
  'https://github.com/ray-x/go.nvim',
  'https://github.com/ray-x/guihua.lua',
  { src = 'https://github.com/paval-shlyk/crates.nvim',       version = 'feat/add-workspace-support' },
  'https://github.com/elixir-tools/elixir-tools.nvim',

  -- DAP
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/rcarriga/nvim-dap-ui',

  -- Git
  'https://github.com/tpope/vim-fugitive',
  'https://github.com/rbong/vim-flog',
  'https://github.com/sindrets/diffview.nvim',
  'https://github.com/lewis6991/gitsigns.nvim',
  'https://github.com/f-person/git-blame.nvim',

  -- Editing / productivity
  'https://github.com/numToStr/Comment.nvim',
  'https://github.com/windwp/nvim-autopairs',
  'https://github.com/kshenoy/vim-signature',
  'https://github.com/rmagatti/auto-session',
  'https://github.com/LunarVim/bigfile.nvim',
  'https://github.com/uga-rosa/translate.nvim',
  'https://github.com/tpope/vim-sleuth',
  {
    src = 'https://github.com/ThePrimeagen/harpoon',
    version = 'harpoon2',
  },

  -- Database
  'https://github.com/tpope/vim-dadbod',
  'https://github.com/kristijanhusak/vim-dadbod-ui',
  'https://github.com/kristijanhusak/vim-dadbod-completion',

  -- Folding
  'https://github.com/kevinhwang91/nvim-ufo',
  'https://github.com/kevinhwang91/promise-async',

  -- Other tools
  'https://github.com/f-person/auto-dark-mode.nvim',
  'https://github.com/aveplen/ruscmd.nvim',
  'https://github.com/folke/snacks.nvim',
  'https://gitlab.com/itaranto/plantuml.nvim',
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
  { src = 'https://github.com/paval-shlyk/grok-code.nvim', version = 'feature/send-notifications' },
  {
    src = 'https://github.com/rust-sailfish/sailfish',
    build = function(path)
      local rtp_path = vim.fs.joinpath(path, 'syntax', 'vim')
      if vim.uv.fs_stat(rtp_path) then
        vim.opt.rtp:append(rtp_path)
      end
    end,
  },
  'https://github.com/kenn7/vim-arsync',
  'https://github.com/prabirshrestha/async.vim',
}

-- Normalize plugin list into vim.pack specs.
-- Supported forms (vim-plug style):
--   'https://github.com/user/repo'
--   { src = '...', version = 'main' }
--   { src = '...', build = 'make' }                    -- string command
--   { src = '...', build = function(path) ... end }     -- lua function
local specs = {}
for _, p in ipairs(plugins) do
  if type(p) == 'string' then
    table.insert(specs, { src = p })
  else
    if p.build then
      p.data = p.data or {}
      p.data.build = p.build
      p.build = nil
    end
    table.insert(specs, p)
  end
end

-- Perform the actual plugin installation / registration.
-- This replaces the entire old vim-plug block.
vim.pack.add(specs)

-- Convenience command for updating plugins (including grok-code.nvim)
vim.api.nvim_create_user_command('PackUpdate', function(opts)
  local plugins = opts.fargs
  if #plugins == 0 then
    vim.pack.update(nil, { force = true })
  else
    vim.pack.update(plugins, { force = true })
  end
end, {
  nargs = '*',
  desc = 'Update one or more plugins (or all if no arguments) using vim.pack',
  complete = function()
    -- Basic completion from lock file names
    local lock = vim.fn.readfile(vim.fn.stdpath('config') .. '/nvim-pack-lock.json')
    local names = {}
    for _, line in ipairs(lock) do
      local name = line:match('"([^"]+)":')
      if name then table.insert(names, name) end
    end
    return names
  end,
})

pcall(function()
  local devicons = require('nvim-web-devicons')
  devicons.setup({ default = true })

  -- Explicit yaml/yml support (in case default set is incomplete)
  devicons.set_icon {
    yml = { icon = "", color = "#6d8086", cterm_color = "66", name = "Yml" },
    yaml = { icon = "", color = "#6d8086", cterm_color = "66", name = "Yaml" },
  }

  vim.g.have_nerd_font = true
end)

M.specs = specs
return M
