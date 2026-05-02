-- code-block-listing.lua
-- Convert fenced code blocks into LaTeX `lstlisting` environments when the
-- output target is LaTeX / PDF. For non-LaTeX targets the block is passed
-- through unchanged so DOCX / GFM stay clean.
--
-- Example markdown:
--   ```python
--   def hello(): ...
--   ```
--
-- Becomes (LaTeX):
--   \begin{lstlisting}[language=Python,caption={...},label={lst:abc}]
--   def hello(): ...
--   \end{lstlisting}
--
-- Languages without a built-in `listings` driver fall back to the generic
-- `language=` slot or are dropped entirely (which `listings` accepts).

local LANG_MAP = {
  python   = "Python",
  py       = "Python",
  bash     = "bash",
  sh       = "bash",
  zsh      = "bash",
  shell    = "bash",
  c        = "C",
  cpp      = "C++",
  ["c++"]  = "C++",
  java     = "Java",
  js       = "Java", -- listings has no JS driver; reuse Java
  javascript = "Java",
  ts       = "Java", -- listings has no TS driver; reuse Java
  typescript = "Java",
  jsx      = "Java",
  tsx      = "Java",
  rust     = "C",    -- nearest neighbour in stock listings
  go       = "C",
  yaml     = "",     -- listings has no YAML; leave empty
  json     = "",
  toml     = "",
  sql      = "SQL",
  html     = "HTML",
  xml      = "XML",
  tex      = "[LaTeX]TeX",
  latex    = "[LaTeX]TeX",
  make     = "make",
  makefile = "make",
  dockerfile = "bash",
}

local function listings_lang(classes)
  for _, c in ipairs(classes or {}) do
    local mapped = LANG_MAP[c:lower()]
    if mapped ~= nil then return mapped end
    -- Unknown class: drop the language= option entirely; listings will not
    -- error and the block is rendered as plain verbatim.
    return ""
  end
  return ""
end

local function escape_caption(s)
  if not s then return nil end
  -- Caption text is brace-wrapped; escape only the showstoppers.
  s = s:gsub("\\", "\\textbackslash{}")
  s = s:gsub("([%%&$#_{}])", "\\%1")
  return s
end

function CodeBlock(el)
  if not (FORMAT and (FORMAT:match("latex") or FORMAT == "beamer")) then
    return nil
  end

  local lang = listings_lang(el.classes)
  local opts = {}
  if lang and lang ~= "" then
    table.insert(opts, "language=" .. lang)
  end

  local caption = el.attributes and el.attributes.caption
  local label   = el.attributes and el.attributes.label
  if caption then
    table.insert(opts, "caption={" .. escape_caption(caption) .. "}")
  end
  if label then
    table.insert(opts, "label={" .. label .. "}")
  end

  local opt_str = ""
  if #opts > 0 then opt_str = "[" .. table.concat(opts, ",") .. "]" end

  local body = el.text
  -- Trim a single trailing newline so \end{lstlisting} sits on its own line.
  body = body:gsub("\n$", "")

  local tex = string.format(
    "\\begin{lstlisting}%s\n%s\n\\end{lstlisting}",
    opt_str, body)
  return pandoc.RawBlock("latex", tex)
end

return { { CodeBlock = CodeBlock } }
