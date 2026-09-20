local M = {}

local function get_git_root()
  local root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 or not root or root == '' then
    return nil
  end
  return root
end

local function get_remote_url()
  local url = vim.fn.systemlist('git config --get remote.origin.url')[1]
  if vim.v.shell_error ~= 0 or not url or url == '' then
    return nil
  end
  return url
end

local function get_commit()
  local commit = vim.fn.systemlist('git rev-parse HEAD')[1]
  if vim.v.shell_error ~= 0 or not commit or commit == '' then
    return nil
  end
  return commit
end

-- Turns git@host:org/repo.git, ssh://git@host/org/repo.git, or
-- https://host/org/repo.git into https://host/org/repo
local function to_https(url)
  url = url:gsub('%.git$', '')

  local host, path = url:match('^git@([^:]+):(.+)$')
  if host then
    return 'https://' .. host .. '/' .. path
  end

  host, path = url:match('^ssh://git@([^/]+)/(.+)$')
  if host then
    return 'https://' .. host .. '/' .. path
  end

  if url:match('^https?://') then
    return url
  end

  return nil
end

function M.share_link(line1, line2)
  local git_root = get_git_root()
  if not git_root then
    vim.notify('ShareLink: not inside a git repository', vim.log.levels.ERROR)
    return
  end

  local remote = get_remote_url()
  if not remote then
    vim.notify('ShareLink: no "origin" remote configured', vim.log.levels.ERROR)
    return
  end

  local base_url = to_https(remote)
  if not base_url then
    vim.notify('ShareLink: could not parse origin url: ' .. remote, vim.log.levels.ERROR)
    return
  end

  local commit = get_commit()
  if not commit then
    vim.notify('ShareLink: could not resolve HEAD commit', vim.log.levels.ERROR)
    return
  end

  local filepath = vim.fn.expand('%:p')
  local rel_path = filepath:sub(#git_root + 2)

  local line_frag
  if line1 == line2 then
    line_frag = '#L' .. line1
  elseif base_url:match('gitlab') then
    line_frag = '#L' .. line1 .. '-' .. line2
  else
    line_frag = '#L' .. line1 .. '-L' .. line2
  end

  local url = string.format('%s/blob/%s/%s%s', base_url, commit, rel_path, line_frag)

  vim.fn.setreg('+', url)
  vim.fn.setreg('"', url)
  vim.notify('ShareLink copied: ' .. url)
end

function M.setup()
  vim.api.nvim_create_user_command('ShareLink', function(opts)
    M.share_link(opts.line1, opts.line2)
  end, { range = true, desc = 'Copy GitHub/GitLab blob URL' })
end

return M
