---@mod herdr.prompts Builtin prompt table + render
local M = {}

--- @class herdr.Prompt
--- @field id string
--- @field label string
--- @field text string|nil
--- @field input boolean|nil

--- @type herdr.Prompt[]
M.builtin = {
  {
    id = "explain",
    label = "Explain",
    text = "Explain this code and its context. Be thorough about the logic.",
  },
  {
    id = "fix",
    label = "Fix issues",
    text = "Find and fix any bugs or problems in this code. Explain the fix.",
  },
  {
    id = "review",
    label = "Review",
    text = "Review this code for correctness, style, performance, and best practices. Findings only unless I ask for edits.",
  },
  {
    id = "tests",
    label = "Add tests",
    text = "Write unit/integration tests for this code. Do not change production code.",
  },
  {
    id = "audit",
    label = "Security",
    text = "Security audit this range. Cite CWE. No refactors.",
  },
  {
    id = "optimize",
    label = "Optimize",
    text = "Optimize this code for performance and readability. Show before/after.",
  },
  {
    id = "document",
    label = "Document",
    text = "Add clear documentation, comments, and docstrings where missing.",
  },
  {
    id = "refactor",
    label = "Refactor",
    text = "Suggest a clean refactor of this code with explanations.",
  },
  {
    id = "bugs",
    label = "Find bugs",
    text = "Analyze for potential bugs, edge cases, and security issues.",
  },
  {
    id = "implement",
    label = "Implement",
    text = "Implement the requested change. Touch only the cited range.",
  },
  {
    id = "ask",
    label = "Custom…",
    input = true,
  },
}

--- @return herdr.Prompt[]
function M.list()
  local cfg = require("herdr.config").get()
  if cfg.prompts then
    return cfg.prompts
  end
  return M.builtin
end

--- @param text string
--- @param ref string|nil
--- @return string
function M.render(text, ref)
  if not ref or ref == "" then
    return text
  end
  if text:find("@", 1, true) then
    return text
  end
  return text .. "\n\n" .. ref
end

return M
