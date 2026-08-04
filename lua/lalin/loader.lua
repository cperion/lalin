-- lalin.loader
--
-- First-class .lln document loading.  A .lln file is a Lalin declaration
-- document rooted at Lalin.decls, not a Lua value chunk.  Loading returns the
-- typed schema document: the ordered ParsedDecl body array plus the
-- LalinParse.ParsedDocument ASDL value that owns it, and .lln require caches
-- that typed decl array.
--
-- The public loader uses lalin.syntax exclusively.  Parsing produces
-- schema Parsed ASDL (LalinParse.ParsedDocument / ParsedDecl leaves, with
-- bracket host evals already role-adapted into LalinType.Type and
-- LalinTree.Expr values).  There is no dual parser, no fallback to the old
-- lalin.syntax AST, and no adapter surface.

local Loader = {}

local Document = require("lalin.syntax.document")

Loader.path = os.getenv("LALIN_PATH") or "./?.lln;./?/init.lln;lua/?.lln;lua/?/init.lln"

local function copy_opts(opts)
  local out = {}
  if opts then for k, v in pairs(opts) do out[k] = v end end
  return out
end

local function readable(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function path_value(path_or_fn)
  if type(path_or_fn) == "function" then return path_or_fn() end
  return path_or_fn or Loader.path
end

-- Parsed documents take their host environment from opts.env; syntax merges
-- the bracket type vocabulary (i32, ptr, view, ...) beneath caller values.
local function document_opts(opts)
  local out = copy_opts(opts)
  out.root_role = out.root_role or "decls"
  return out
end

function Loader.loadstring(source, chunkname, opts)
  local ok, doc = pcall(Document.parse, source, chunkname or "=(lalin .lln)", document_opts(opts))
  if not ok then return nil, doc end
  return doc.body, doc
end

function Loader.loadfile(path, opts)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local source = f:read("*a") or ""
  f:close()
  return Loader.loadstring(source, "@" .. path, opts)
end

function Loader.dofile(path, opts)
  local decls, doc_or_err = Loader.loadfile(path, opts)
  if not decls then error(doc_or_err, 2) end
  return decls, doc_or_err
end

local function escape_pattern(s)
  return (tostring(s):gsub("([^%w])", "%%%1"))
end

function Loader.searchpath(name, path, sep, rep)
  path = path_value(path)
  sep = sep or "."
  rep = rep or "/"
  local mod_path = tostring(name):gsub(escape_pattern(sep), rep)
  local tried = {}
  for template in tostring(path or ""):gmatch("[^;]+") do
    if template ~= "" then
      local candidate = template:gsub("%?", mod_path)
      if readable(candidate) then return candidate end
      tried[#tried + 1] = candidate
    end
  end
  return nil, "\n\tno .lln file found (tried: " .. table.concat(tried, ", ") .. ")"
end

function Loader.loadmodule(name, opts)
  opts = opts or {}
  local path, err = Loader.searchpath(name, opts.path or Loader.path, opts.sep, opts.rep)
  if not path then return nil, err end
  local load_opts = opts.load_opts or opts
  local decls, doc_or_err = Loader.loadfile(path, load_opts)
  if not decls then return nil, doc_or_err end
  return decls, path, doc_or_err
end

function Loader.require(name, opts)
  if package.loaded[name] then return package.loaded[name] end
  local decls, path_or_err = Loader.loadmodule(name, opts)
  if not decls then error("module '" .. tostring(name) .. "' not found:" .. tostring(path_or_err), 2) end
  package.loaded[name] = decls
  return decls
end

function Loader.searcher(name, opts)
  local decls, path_or_err = Loader.loadmodule(name, opts)
  if not decls then return path_or_err end
  return function()
    return decls
  end, path_or_err
end

function Loader.install_searcher(opts)
  opts = copy_opts(opts)
  local searchers = package.searchers or package.loaders
  if not searchers then return false end
  if Loader._searcher then
    for _, searcher in ipairs(searchers) do
      if searcher == Loader._searcher then return true end
    end
  end
  local function searcher(name)
    return Loader.searcher(name, opts)
  end
  Loader._searcher = searcher
  local index = tonumber(opts.index)
  if index and index >= 1 and index <= #searchers + 1 then
    table.insert(searchers, index, searcher)
  else
    table.insert(searchers, searcher)
  end
  return true
end

function Loader.remove_searcher()
  local searchers = package.searchers or package.loaders
  if not searchers or not Loader._searcher then return false end
  for i = #searchers, 1, -1 do
    if searchers[i] == Loader._searcher then
      table.remove(searchers, i)
      return true
    end
  end
  return false
end

return Loader
