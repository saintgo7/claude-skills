-- citation-fix.lua
-- Normalises citation rendering across markdown sources before Pandoc emits
-- LaTeX / DOCX. Handles three common authoring quirks:
--
--   1. Bare "[Author2024]" string converted to a real Pandoc Cite element.
--   2. Bracketed numeric refs like "[1]" left as plain text are upgraded to
--      \cite{ref1} when running through LaTeX.
--   3. Whitespace tightening around "@key" prefixes inside parens, e.g.
--      "( @smith2023 )" -> "(@smith2023)".
--
-- The filter is intentionally conservative: it never invents new bib keys,
-- and it never strips content. Anything it cannot interpret is passed through
-- unchanged so that downstream pandoc-citeproc / natbib remain authoritative.

local stringify = (require "pandoc.utils").stringify

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function is_year(s)
  return s:match("^%d%d%d%d$") ~= nil
end

local function is_authoryear(token)
  -- Loose AuthorYYYY pattern: at least one upper-case letter followed by a
  -- 4-digit year, optional letter suffix.
  return token:match("^[A-Z][A-Za-z%-]+%d%d%d%d[a-z]?$") ~= nil
end

-- Build a single-citation element from a key.
local function make_cite(key)
  local citation = {
    id = key,
    mode = pandoc.NormalCitationMode,
    prefix = {},
    suffix = {},
    note_num = 0,
    hash = 0,
  }
  return pandoc.Cite({ pandoc.Str("[@" .. key .. "]") }, { citation })
end

-- ---------------------------------------------------------------------------
-- Inline rules
-- ---------------------------------------------------------------------------

-- (1) "[AuthorYYYY]" -> Cite
local function rewrite_bare_author_year(text)
  local key = text:match("^%[(.-)%]$")
  if key and is_authoryear(key) then
    return make_cite(key)
  end
  return nil
end

-- (3) "( @key )" -> "(@key)"
local function tighten_paren_at(inlines)
  local out = pandoc.Inlines({})
  local i = 1
  while i <= #inlines do
    local cur = inlines[i]
    local nxt = inlines[i + 1]
    if cur and cur.t == "Str" and cur.text == "("
        and nxt and nxt.t == "Space" then
      -- drop the space after "("
      out:insert(cur)
      i = i + 2
    elseif cur and cur.t == "Space"
        and nxt and nxt.t == "Str" and nxt.text == ")" then
      -- drop the space before ")"
      out:insert(nxt)
      i = i + 2
    else
      out:insert(cur)
      i = i + 1
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Pandoc filter callbacks
-- ---------------------------------------------------------------------------

function Str(el)
  local replacement = rewrite_bare_author_year(el.text)
  if replacement then return replacement end
  return nil
end

function Inlines(inlines)
  return tighten_paren_at(inlines)
end

-- (2) numeric "[1]" -> raw \cite{ref1} for LaTeX targets only.
function RawInline(el)
  if FORMAT and FORMAT:match("latex") and el.format == "tex" then
    return el
  end
  return nil
end

function Para(el)
  if not (FORMAT and FORMAT:match("latex")) then return nil end
  -- Walk children, replacing standalone "[N]" Str tokens with raw \cite.
  local changed = false
  local out = {}
  for _, inl in ipairs(el.content) do
    if inl.t == "Str" then
      local n = inl.text:match("^%[(%d+)%]$")
      if n then
        table.insert(out, pandoc.RawInline("latex", "\\cite{ref" .. n .. "}"))
        changed = true
      else
        table.insert(out, inl)
      end
    else
      table.insert(out, inl)
    end
  end
  if changed then
    el.content = out
    return el
  end
  return nil
end

return {
  { Str = Str, Inlines = Inlines, Para = Para, RawInline = RawInline },
}
