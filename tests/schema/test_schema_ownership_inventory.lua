package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local expected_names = {
  "c", "c_materialize", "code", "compiler", "effect", "flow", "graph",
  "init", "kernel", "lower", "mem", "schedule", "stencil", "stencil_machine", "value",
}
table.sort(expected_names)

local ownership = {
  c = { namespace = "LalinC", owner = "lua/lalin/schema_v2/c.lua" },
  c_materialize = { namespace = "LalinCMat", owner = "lua/lalin/schema_v2/c_materialize.lua" },
  code = { namespace = "LalinCode", owner = "lua/lalin/schema_v2/code.lua" },
  compiler = { namespace = "LalinCompiler", owner = "lua/lalin/schema_v2/compiler.lua" },
  effect = { namespace = "LalinEffect", owner = "lua/lalin/schema_v2/effect.lua" },
  flow = { namespace = "LalinFlow", owner = "lua/lalin/schema_v2/flow.lua" },
  graph = { namespace = "LalinGraph", owner = "lua/lalin/schema_v2/graph.lua" },
  init = { namespace = "bootstrap", owner = "lua/lalin/schema_v2/init.lua" },
  kernel = { namespace = "LalinKernel", owner = "lua/lalin/schema_v2/kernel.lua" },
  lower = { namespace = "LalinLower", owner = "lua/lalin/schema_v2/lower.lua" },
  mem = { namespace = "LalinMem", owner = "lua/lalin/schema_v2/mem.lua" },
  schedule = { namespace = "LalinSchedule", owner = "lua/lalin/schema_v2/schedule.lua" },
  stencil = { namespace = "LalinStencil", owner = "lua/lalin/schema_v2/stencil.lua" },
  stencil_machine = { namespace = "LalinStencilMachine", owner = "lua/lalin/schema_v2/stencil_machine.lua" },
  value = { namespace = "LalinValue", owner = "lua/lalin/schema_v2/value.lua" },
}

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local text = assert(file:read("*a"))
  assert(file:close())
  return text
end

local function module_names(dir)
  local out = {}
  local pipe = assert(io.popen("find " .. dir .. " -maxdepth 1 -type f -name '*.lua' -printf '%f\\n' | sort", "r"))
  for filename in pipe:lines() do out[filename:gsub("%.lua$", "")] = true end
  assert(pipe:close())
  return out
end

local old_names = module_names("lua/lalin/schema")
local v2_names = module_names("lua/lalin/schema_v2")
local duplicates = {}
for name in pairs(old_names) do
  if v2_names[name] then duplicates[#duplicates + 1] = name end
end
table.sort(duplicates)

assert(#duplicates == 15, "schema ownership inventory must contain exactly 15 duplicate names, got " .. tostring(#duplicates))
assert(#expected_names == 15)
for i = 1, #expected_names do
  assert(duplicates[i] == expected_names[i], "schema ambiguity changed at slot " .. tostring(i) .. ": expected " .. expected_names[i] .. ", got " .. tostring(duplicates[i]))
end

local namespace_owners = {}
for i = 1, #duplicates do
  local name = duplicates[i]
  local entry = assert(ownership[name], "duplicate has no intended owner: " .. name)
  assert(read_file(entry.owner) ~= "", "intended owner is missing or empty: " .. entry.owner)
  assert(namespace_owners[entry.namespace] == nil, "namespace has more than one intended owner: " .. entry.namespace)
  namespace_owners[entry.namespace] = entry.owner

  if name ~= "init" then
    local old_text = read_file("lua/lalin/schema/" .. name .. ".lua")
    local v2_text = read_file("lua/lalin/schema_v2/" .. name .. ".lua")
    local old_namespace = old_text:match("return%s+schema%.%s*([%w_]+)")
    local v2_namespace = v2_text:match("return%s+schema%.%s*([%w_]+)")
    assert(old_namespace == entry.namespace, "old schema namespace mismatch for " .. name)
    assert(v2_namespace == entry.namespace, "schema-v2 namespace mismatch for " .. name)
  end
end
for name in pairs(ownership) do
  assert(old_names[name] and v2_names[name], "ownership metadata names a non-duplicate module: " .. name)
end

local canonicalized = {
  bind = { owner = "lua/lalin/schema_v2/bind.lua", removed = "lua/lalin/schema/bind.lua" },
  check = { owner = "lua/lalin/schema_v2/check.lua", removed = "lua/lalin/schema/check.lua" },
  core = { owner = "lua/lalin/schema_v2/core.lua", removed = "lua/lalin/schema/core.lua" },
  parse = { owner = "lua/lalin/schema_v2/parse.lua", removed = "lua/lalin/schema/parse.lua" },
  sem = { owner = "lua/lalin/schema_v2/sem.lua", removed = "lua/lalin/schema/sem.lua" },
  source = { owner = "lua/lalin/schema_v2/source.lua", removed = "lua/lalin/schema/source.lua" },
  tree = { owner = "lua/lalin/schema_v2/tree.lua", removed = "lua/lalin/schema/tree.lua" },
  type = { owner = "lua/lalin/schema_v2/type.lua", removed = "lua/lalin/schema/type.lua" },
  exec = { owner = "lua/lalin/schema_v2/exec.lua", removed = "lua/lalin/schema/exec.lua" },
  phase = { owner = "lua/lalin/schema/phase.lua", removed = "lua/lalin/schema_v2/phase.lua" },
  project = { owner = "lua/lalin/schema_v2/project.lua", removed = "lua/lalin/schema/project.lua" },
}
assert(v2_names.tree_code and not old_names.tree_code, "tree_code must remain schema-v2-only")
for name, entry in pairs(canonicalized) do
  assert(read_file(entry.owner) ~= "", "canonical owner missing: " .. entry.owner)
  assert(not old_names[name] or entry.owner:find("/schema/", 1, true), "removed old declaration returned: " .. name)
  assert(not v2_names[name] or entry.owner:find("/schema_v2/", 1, true), "removed schema-v2 declaration returned: " .. name)
end

local v2_init = read_file("lua/lalin/schema_v2/init.lua")
assert(old_names.host, "canonical Host boundary declaration is missing")
assert(not v2_names.host, "Host boundary must not be duplicated in schema-v2")
assert(v2_init:find('require("lalin.schema.host")', 1, true), "schema-v2 bootstrap must consume the canonical Host boundary")
assert(namespace_owners.LalinHost == nil, "Host must not be recorded as an ambiguous namespace")

local excluded_backends = {
  luajit = "LalinLuaJIT",
  luatrace = "LalinLuaTrace",
  native = "LalinNative",
}
for name, namespace in pairs(excluded_backends) do
  assert(old_names[name], "excluded backend schema is missing: " .. name)
  assert(not v2_names[name], "excluded backend must not gain a schema-v2 duplicate: " .. name)
  local text = read_file("lua/lalin/schema/" .. name .. ".lua")
  assert(text:match("return%s+schema%.%s*" .. namespace), "excluded backend namespace mismatch: " .. name)
end
assert(v2_init:find('require("lalin.schema.luajit")', 1, true), "legacy stencil-machine LuaJIT boundary must remain explicit")
assert(not v2_init:find('require("lalin.schema.luatrace")', 1, true), "LuaTrace must remain excluded from schema-v2")
assert(not v2_init:find('require("lalin.schema.native")', 1, true), "native copy-patch must remain excluded from schema-v2")

io.write("schema ownership inventory ok: 15 duplicate names; frontend and meta canonicalized\n")

