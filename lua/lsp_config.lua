-- Add additional capabilities supported by nvim-cmp
-- local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- Old nvim-treesitter setup removed (new rewrite uses different API).
-- Parser installation is handled in lua/config/setup.lua with a curated list.

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'sh',
  callback = function()
    vim.lsp.start({
      name = 'bash-language-server',
      cmd = { 'bash-language-server', 'start' },
    })
  end
})

-- gopls is owned by go.nvim (see setup.lua). rust-analyzer is owned by rustaceanvim.
-- clangd / digestif / sqlls are enabled if present but not auto-installed.
local servers = {
  'lua_ls', 'taplo', 'yamlls', 'html', 'pyright', 'ts_ls', 'just',
  'asm_lsp', 'buf_ls', 'golangci_lint_ls', 'emmet_language_server', 'harper_ls',
  'clangd', 'digestif', 'sqlls',
}

local mason_skip = {
  clangd = true,
  digestif = true,
  sqlls = true,
}

local ensure_installed = {}
for _, name in ipairs(servers) do
  if not mason_skip[name] then
    table.insert(ensure_installed, name)
  end
end

require('mason').setup({
  ui = {
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗"
    }
  }
})
require('mason-lspconfig').setup {
  automatic_enable = false,
  ensure_installed = ensure_installed,
}

local is_first_delete = true

local function on_attach(client, buffer)
  -- Example usage
  if is_first_delete then
    vim.keymap.del('n', '.', { buffer = nil })
    is_first_delete = false
  end

  if client.name == "rust-analyzer" then
    -- override LSP semantic tokens by Tree-sitter
    client.server_capabilities.semanticTokensProvider = nil
  end
  -- client.server_capabilities.semanticTokensProvider = nil
  -- This callback is called when the LSP is atttached/enabled for this buffer
  -- we could set keymaps related to LSP, etc here.
end

for _, lsp in ipairs(servers) do
  if lsp == 'emmet_language_server' then
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities.textDocument.completion.completionItem.snippetSupport = true

    local config = {
      filetypes = { "css", "eruby", "html", "javascript", "javascriptreact", "less", "sass", "scss", "pug", "typescriptreact", "twig", "sailfish" },
      -- Read more about this options in the [vscode docs](https://code.visualstudio.com/docs/editor/emmet#_emmet-configuration).
      -- **Note:** only the options listed in the table are supported.
      init_options = {
        ---@type table<string, string>
        includeLanguages = {},
        --- @type string[]
        excludeLanguages = {},
        --- @type string[]
        extensionsPath = {},
        --- @type table<string, any> [Emmet Docs](https://docs.emmet.io/customization/preferences/)
        preferences = {},
        --- @type boolean Defaults to `true`
        showAbbreviationSuggestions = true,
        --- @type "always" | "never" Defaults to `"always"`
        showExpandedAbbreviation = "always",
        --- @type boolean Defaults to `false`
        showSuggestionsAsSnippets = false,
        --- @type table<string, any> [Emmet Docs](https://docs.emmet.io/customization/syntax-profiles/)
        syntaxProfiles = {},
        --- @type table<string, string> [Emmet Docs](https://docs.emmet.io/customization/snippets/#variables)
        variables = {},
      },
      capabilities = capabilities,
    }

    vim.lsp.config(lsp, config)
    vim.lsp.enable({ lsp })
  elseif lsp == 'harper_ls' then
    local config = {
      settings = {
        ['harper-ls'] = {
          linters = {
            BoringWords = true,
            SpelledNumbers = true,
          }
        },
      },
    }

    vim.lsp.config(lsp, config)
    vim.lsp.enable({ lsp })
  elseif lsp == 'yamlls' then
    vim.lsp.config(lsp, {
      filetypes = { 'yaml', 'json' },
      settings = {
        yaml = {
          validate = true,
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
    settings = {
      -- to enable rust-analyzer settings visit:
      -- https://github.com/rust-analyzer/rust-analyzer/blob/master/docs/user/generated_config.adoc
      ["rust-analyzer"] = {
        -- enable clippy on save
        checkOnSave = true,
        cargo = {
          buildScripts = {
            enable = true,
          },
          -- target = 'aarch64-linux-android'
          -- targetOs = "android"
          -- target = "x86_64-pc-windows-msvc",
        },
        check = {
          -- features = "all",
          allTargets = true,
          -- target = "riscv32imac-unknown-none-elf"
          -- target = "wasm32-unknown-unknown"
          -- target = "xtensa-esp32-none-elf"
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
    { name = 'buffer' },
    { name = 'path' },
  },
}
