-- Add additional capabilities supported by nvim-cmp
-- local capabilities = require("cmp_nvim_lsp").default_capabilities()

require 'nvim-treesitter.configs'.setup {
  -- A list of parser names, or "all"
  ensure_installed = { "c", "cpp", "lua", "rust", "java", "toml", "xml", "helm" },

  -- Install parsers synchronously (only applied to `ensure_installed`)
  sync_install = false,

  -- Automatically install missing parsers when entering buffer
  -- Recommendation: set to false if you don't have `tree-sitter` CLI installed locally
  auto_install = true,
  -- ignore_install = { "html", "xml"},

  highlight = {
    -- `false` will disable the whole extension
    enable = true,
    disable = { "" },

    -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
    -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
    -- Using this option may slow down your editor, and you may see some duplicate highlights.
    -- Instead of true it can also be a list of languages
    additional_vim_regex_highlighting = false,
  },

  ident = {
    enable = true,
  },

  -- autotag = {
  --   enable = true,
  --   -- enable_rename = true,
  --   -- enable_close = true,
  --   -- enable_close_on_slash = true,
  --   -- filetypes = { "xml", "html" },
  -- }
}

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'sh',
  callback = function()
    vim.lsp.start({
      name = 'bash-language-server',
      cmd = { 'bash-language-server', 'start' },
    })
  end
})

require('mason').setup()
require('mason-lspconfig').setup {
  automatic_enable = false,
  ensure_installed = { 'lua_ls', 'taplo', 'yamlls', 'html', 'pyright', 'ts_ls', 'codebook', 'just', 'asm_lsp', 'buf_ls', 'harper_ls', 'helm_ls'}
}

vim.filetype.add({
  pattern = {
    ['.*/templates/.*%.ya?ml'] = 'helm',
    ['.*/templates/.*%.tpl'] = 'helm',
    ['.*/templates/NOTES%.txt'] = 'helm',
  },
})

-- Enable some language servers with the additional completion capabilities offered by nvim-cmp
local servers = { 'clangd', 'pyright', 'ts_ls', 'lua_ls',
  'yamlls', 'digestif', 'taplo', 'buf_ls', 'sqlls',
  'html', 'codebook-lsp', 'just',
  'asm_lsp', 'systemd_lsp', 'jdtls', 'terraformls', 'gopls', 'csharp_ls',
  'harper_ls', 'helm_ls'
}

local is_first_delete = true

local function on_attach(client, buffer)
  -- Example usage
  if is_first_delete then
    vim.keymap.del('n', '.', { buffer = nil })
    is_first_delete = false
  end

  if client.name == "rust-analyzer" then
    -- override lsp semantic tokens by treesitter
    client.server_capabilities.semanticTokensProvider = nil
  end
  -- client.server_capabilities.semanticTokensProvider = nil
  -- This callback is called when the LSP is atttached/enabled for this buffer
  -- we could set keymaps related to LSP, etc here.
end

for _, lsp in ipairs(servers) do
  if lsp == 'omnisharp' then
    local config = {
      handlers = {
        ["textDocument/definition"] = require('omnisharp_extended').definition_handler,
        ["textDocument/typeDefinition"] = require('omnisharp_extended').type_definition_handler,
        ["textDocument/references"] = require('omnisharp_extended').referenes_handler,
        ["textDocument/implementation"] = require('omnisharp_extended').implementation_handler,
      },
    }
    vim.lsp.config(lsp, config)
    vim.lsp.enable({ lsp })
  elseif lsp == 'ink-ls' then
    local config = {
      cmd = { 'ink-lsp-server' },
      filetypes = { 'ink' },
      root_markers = { '.git', 'package.json', 'ink.toml' },
    }

    vim.lsp.config(lsp, config)
    vim.lsp.enable({ lsp })
  elseif lsp == 'codebook-lsp' then
    local config = {
      cmd = { 'codebook-lsp', 'serve' },
      filetypes = {
        'c',
        'css',
        'gitcommit',
        'go',
        'haskell',
        'html',
        'java',
        'javascript',
        'javascriptreact',
        'lua',
        'markdown',
        'php',
        'python',
        'ruby',
        'rust',
        'toml',
        'text',
        'typescript',
        'typescriptreact',
      },

      root_markers = { '.git', 'codebook.toml', '.codebook.toml' },
    }

    vim.lsp.config(lsp, config)
    vim.lsp.enable({ lsp })
  elseif lsp == 'metals' then
    local metals_config = require('metals').bare_config()
    metals_config.on_attach = on_attach
    metals_config.init_options.statusBarProvider = "on"
    metals_config.settings = {
      showImplicitArguments = true,
      showInferredType = true,
      superMethodLensesEnabled = true,
      showImplicitConversionsAndClasses = true,
      enableSemanticHighlighting = true,
      inlayHints = true
    }

    vim.lsp.config(lsp, metals_config)
    vim.lsp.enable({ lsp })
  elseif lsp == 'tact' then
    local util = require 'lspconfig.util'
    vim.lsp.config(lsp, {
      cmd = { 'tact-language-server', '--stdio' },
      on_attach = on_attach,
      filetypes = { 'tact' },
      -- If you installed the language server via NPM, use the following command:
      root_dir = util.root_pattern('package.json', '.git'),
      docs = {
        description = [[
        Tact Language Server
        https://github.com/tact-lang/tact-language-server
      ]],
        default_config = {
          root_dir = [[root_pattern("package.json", ".git")]],
        },
      }
    })
    vim.lsp.enable({ lsp })
  elseif lsp == 'helm_ls' then
    vim.lsp.config(lsp, {
      cmd = { 'helm_ls', 'serve' },
      filetypes = { 'helm' },
      on_attach = on_attach,
    })
    vim.lsp.enable({ lsp })
  elseif lsp == 'yamlls' then
    vim.lsp.config(lsp, {
      filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab', 'json' },
      settings = {
        yaml = {
          validate = true,
          format = {
            enable = true,
            insertFinalNewline = true,
          },
          schemas = {
            kubernetes = "*.yaml",
            ["http://json.schemastore.org/github-workflow.json"] = ".github/workflows/*",
            ["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
            ["http://json.schemastore.org/ansible-stable-2.9"] = "roles/tasks/*.{yml,yaml}",
            ["http://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
            ["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
            ["http://json.schemastore.org/ansible-playbook"] = "*play*.{yml,yaml}",
            ["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
            ["https://json.schemastore.org/dependabot-v2"] = ".github/dependabot.{yml,yaml}",
            ["https://json.schemastore.org/gitlab-ci"] = "*gitlab-ci*.{yml,yaml}",
            ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json"] =
            "*api*.{yml,yaml}",
            ["https://json.schemastore.org/package.json"] = "package.json",
            ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] =
            "*docker-compose*.{yml,yaml}",
            ["https://raw.githubusercontent.com/argoproj/argo-workflows/master/api/jsonschema/schema.json"] =
            "*flow*.{yml,yaml}",
            ["https://golangci-lint.run/jsonschema/golangci.jsonschema.json"] = "*.golangci.{yml,yaml}",
          }
        }
      },
      on_attach = function(client, buffer)
        if vim.api.nvim_buf_get_name(buffer):match('/templates/') then
          vim.schedule(function()
            vim.lsp.buf_detach_client(buffer, client.id)
          end)
          return
        end
        on_attach(client, buffer)
      end,
      -- capabilities = capabilities,
    })
    vim.lsp.enable({ lsp })
  elseif lsp == 'clangd' then
    vim.lsp.config(lsp, {
      cmd = { 'clangd',
        '--clang-tidy',
        '--background-index',
      },
      on_attach = on_attach,
      -- capabilities = capabilities,
    })
    vim.lsp.enable({ lsp })
  else
    vim.lsp.config(lsp, {
      on_attach = on_attach,
      -- capabilities = capabilities,
    })
    vim.lsp.enable({ lsp })
  end
end

local opts         = {
  tools = {
    inlay_hints = {
      auto = true,
      show_parameter_hints = true,
      parameter_hints_prefix = "",
      other_hints_prefix = "",
    },
  },
  -- all the opts to send to nvim-lspconfig
  -- these override the defaults set by rust-tools.nvim
  -- see https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#rust_analyzer
  server = {
    -- on_attach is a callback called when the language server attachs to the buffer
    on_attach = on_attach,
    default_settings = {
      -- to enable rust-analyzer settings visit:
      -- https://github.com/rust-analyzer/rust-analyzer/blob/master/docs/user/generated_config.adoc
      ["rust-analyzer"] = {
        -- enable clippy on save
        checkOnSave = true,
        cargo = {
          buildScripts = {
            enable = true,
          },
          -- target = "x86_64-pc-windows-msvc",
        },
        check = {
          -- features = "all",
          -- allTargets = true,
          --   target = "riscv32imac-unknown-none-elf"
        },
        workspace = {
          symbol = {
            search = {
              limit = 512
            }
          }
        },
        lru = {
          capacity = 128,
        },

        procMacro = {
          enable = true,
          ignored = {
            tokio       = { "select" },
            o2o         = { "o2o" },
            anchor_lang = { "program" },
          }
        },

        diagnostics = {
          experimental = {
            enable = false,
          },

          disabled = { "unresolved-proc-macro" },
        },
      },
    },
  },
}

vim.g.rustaceanvim = opts;

-- Toggle whether rust-analyzer checks/diagnoses test code (#[cfg(test)], #[test]),
-- by flipping rust-analyzer.check.allTargets on the live client(s), no restart needed.
--
-- Note: nvim's built-in `workspace/configuration` pull handler serves config
-- from the client's `settings` field (see vim.lsp.client), which is distinct
-- from `client.config.settings`. rustaceanvim's own `set_config` API updates
-- the right field and re-sends workspace/didChangeConfiguration to trigger a
-- re-pull, so we use that instead of poking the client object ourselves.
local rust_check_all_targets = true

local function set_rust_check_all_targets(value)
  rust_check_all_targets = value
  local rust_analyzer = require('rustaceanvim.rust_analyzer')
  local clients = rust_analyzer.get_active_rustaceanvim_clients(nil)
  if #clients == 0 then
    vim.notify("rust-analyzer is not running", vim.log.levels.WARN)
    return
  end
  for _, client in ipairs(clients) do
    ---@diagnostic disable-next-line: inject-field
    client.settings = vim.tbl_deep_extend('force', client.settings or {}, {
      ["rust-analyzer"] = { check = { allTargets = value } },
    })
    client:notify('workspace/didChangeConfiguration', { settings = client.settings })
  end
  vim.notify("rust-analyzer: checking test code " .. (value and "enabled" or "disabled"))
end

vim.api.nvim_create_user_command("RustToggleTestChecks", function()
  set_rust_check_all_targets(not rust_check_all_targets)
end, { desc = "Toggle whether rust-analyzer checks/diagnoses test code" })

-- luasnip setup
local luasnip      = require 'luasnip'
-- nvim-cmp setup
local cmp          = require 'cmp'
cmp.setup {
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-u>'] = cmp.mapping.scroll_docs(-4), -- Up
    ['<C-d>'] = cmp.mapping.scroll_docs(4),  -- Down
    -- C-b (back) C-f (forward) for snippet placeholder navigation.
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<Tab>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    }
    --[[
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      else
        fallback()
      end
    end,
    { 'i', 's' }),
    --]]
    --[[
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      elseif luasnip.jumpable(-1) then
        luasnip.jump(-1)
      else
        fallback()
      end
    end, { 'i', 's' }),
    --]]
  }),
  sources = {
    { name = 'nvim_lsp' },
    { name = 'luasnip' },
  },
}
