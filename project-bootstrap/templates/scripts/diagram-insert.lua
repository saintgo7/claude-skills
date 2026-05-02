-- diagram-insert.lua
-- Pandoc Lua filter that resolves diagram-NN placeholders to absolute SVG
-- paths and warns when the SVG has not been built yet.
--
-- Source markdown convention:
--   ![diagram-NN 제목](../../docs/diagrams/diagram-NN.svg)
--
-- The image target must contain the substring `diagram-NN` (NN = 01..40).
-- The filter rewrites the target to the absolute path
--   <repo>/docs/diagrams/svg/diagram-NN.svg
-- and, if that file is missing, replaces the image with a placeholder
-- paragraph carrying a build instruction (so Pandoc never aborts).

local function script_dir()
  -- arg[0] is set when pandoc invokes the filter; fall back to PANDOC_SCRIPT_FILE.
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return src:match("(.*/)")
end

local function repo_root()
  local d = script_dir() or "./"
  -- script lives in <repo>/scripts/pandoc-filters/, climb two levels.
  return d .. "../../"
end

local function file_exists(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

local function normalize(p)
  -- Resolve a path against repo_root() if relative; squash double slashes.
  if p:sub(1, 1) ~= "/" then p = repo_root() .. p end
  -- Collapse `./` and `foo/../` style segments cheaply.
  local prev
  repeat
    prev = p
    p = p:gsub("/%./", "/")
    p = p:gsub("/[^/]+/%.%./", "/")
  until p == prev
  return p
end

local ROOT = normalize("")
local SVG_DIR = ROOT .. "docs/diagrams/svg/"

function Image(el)
  local target = el.src or ""
  local id = target:match("(diagram%-%d%d)")
  if not id then return nil end

  local abs = SVG_DIR .. id .. ".svg"
  if file_exists(abs) then
    el.src = abs
    return el
  end

  -- SVG missing: emit a visible placeholder + caption.
  local msg = string.format(
    "[diagram missing: %s] Run `bash scripts/build-diagrams.sh` to render docs/diagrams/svg/%s.svg",
    id, id)
  io.stderr:write("[diagram-insert.lua] " .. msg .. "\n")

  local cap_inlines = el.caption
  if not cap_inlines or #cap_inlines == 0 then
    cap_inlines = pandoc.Inlines({ pandoc.Str(id) })
  end
  table.insert(cap_inlines, pandoc.Space())
  table.insert(cap_inlines, pandoc.Emph({ pandoc.Str("(missing — run build-diagrams.sh)") }))

  return pandoc.Span(
    { pandoc.Str(msg) },
    pandoc.Attr("", { "diagram-missing" }, { { "data-id", id } })
  )
end

return { { Image = Image } }
