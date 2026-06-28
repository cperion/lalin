-- llbl.syntax.constructor
-- Runtime descriptor for parsed-channel islands.  The descriptor is created at
-- parse time and invoked at Lua evaluation time with explicit lexical refs.

local Constructor = {}
Constructor.__index = Constructor

local chunks = {}

local function shallow_copy(t)
  local r = {}
  if t then for k, v in pairs(t) do r[k] = v end end
  return r
end

function Constructor.new(desc)
  assert(type(desc) == "table", "constructor descriptor must be a table")
  assert(type(desc.build) == "function", "constructor descriptor requires build(env, ctx)")
  local self = setmetatable({}, Constructor)
  for k, v in pairs(desc) do self[k] = v end
  self.refs = self.refs or {}
  self.outputs = self.outputs or {}
  self.channel = self.channel or "parsed"
  return self
end

function Constructor:run(env_fn, ctx)
  local env = {}
  if env_fn then
    local ok, value = pcall(env_fn)
    if not ok then error(value, 0) end
    env = value or {}
  end
  ctx = shallow_copy(ctx)
  ctx.constructor = self
  ctx.origin = self.origin
  ctx.owner = self.owner
  return self.build(env, ctx)
end

function Constructor.install_chunk(chunk_id, constructors)
  assert(chunk_id, "chunk id required")
  chunks[chunk_id] = constructors or {}
end

function Constructor.invoke(chunk_id, index, env_fn)
  local chunk = chunks[chunk_id]
  if not chunk then error("LLBL syntax chunk not installed: " .. tostring(chunk_id), 0) end
  local ctor = chunk[index]
  if not ctor then error("LLBL syntax constructor not found: " .. tostring(chunk_id) .. "#" .. tostring(index), 0) end
  if getmetatable(ctor) ~= Constructor then ctor = Constructor.new(ctor) end
  return ctor:run(env_fn, { chunk_id = chunk_id, index = index })
end

function Constructor.env_source(refs)
  refs = refs or {}
  local parts = { "function() return {" }
  for i = 1, #refs do
    local name = refs[i]
    if type(name) == "string" and name:match("^[A-Za-z_][A-Za-z0-9_]*$") then
      parts[#parts + 1] = string.format("[%q]=%s,", name, name)
    end
  end
  parts[#parts + 1] = "} end"
  return table.concat(parts)
end

function Constructor.loaded_chunks()
  return chunks
end

return Constructor
