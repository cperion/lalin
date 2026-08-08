local Coverage = {}

local function sorted(values)
  table.sort(values)
  return values
end

local function find_files(command)
  local out = {}
  local pipe = io.popen(command)
  if not pipe then return out end
  for path in pipe:lines() do out[#out + 1] = path end
  pipe:close()
  return sorted(out)
end

local function array_values(tbl)
  local out = {}
  for index, value in ipairs(tbl or {}) do
    out[index] = value
  end
  return out
end

local function excluded_entries(excluded)
  local out = {}
  for key, value in pairs(excluded or {}) do
    if type(key) == "number" then
      out[#out + 1] = { leaf = value, reason = true }
    else
      out[#out + 1] = { leaf = key, reason = value }
    end
  end
  table.sort(out, function(a, b) return a.leaf < b.leaf end)
  return out
end

local function assert_type(value, expected, message)
  assert(type(value) == expected, message .. ": expected " .. expected .. ", got " .. type(value))
end

function Coverage.assert_leaf_exists(Compiler, path)
  assert_type(path, "string", "leaf path")
  local parts = {}
  for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
  assert(#parts == 3, "leaf path must be Module.Sum.Leaf: " .. path)

  local module_name, sum_name, leaf_name = parts[1], parts[2], parts[3]
  local namespace = assert(Compiler[module_name], "unknown schema module in leaf path: " .. path)
  local parent = assert(namespace[sum_name], "unknown schema sum in leaf path: " .. path)
  local leaf = assert(namespace[leaf_name], "unknown schema leaf in leaf path: " .. path)
  assert(parent.members and parent.members[leaf], "leaf is not a member of sum: " .. path)
  assert(leaf.kind == leaf_name, "leaf kind mismatch for path: " .. path)
  return leaf
end
local function class_at(Compiler, path)
  assert_type(path, "string", "class path")
  local node = Compiler
  for part in path:gmatch("[^.]+") do
    node = node and node[part]
  end
  assert(node, "unknown schema class path: " .. path)
  return node
end

function Coverage.assert_class_exists(Compiler, path)
  return class_at(Compiler, path)
end

local function spec_key(cfg)
  return cfg.key or cfg.phase
end

function Coverage.load_phase_specs(dir)
  local specs = {}
  for _, path in ipairs(find_files("find " .. dir .. " -type f -name '*_spec.lua' 2>/dev/null")) do
    if not path:match("/_") then
      local cfg = assert(dofile(path), "compiler spec did not return a table: " .. path)
      assert_type(cfg, "table", "compiler spec " .. path)
      local key = spec_key(cfg)
      assert_type(key, "string", "compiler spec key in " .. path)
      assert(not specs[key], "duplicate compiler spec for " .. key)
      cfg.key = key
      cfg.__file = path
      cfg.modules = cfg.modules or {}
      cfg.leaves = cfg.leaves or {}
      cfg.excluded = cfg.excluded or {}
      specs[key] = cfg
    end
  end
  return specs
end

function Coverage.scan_fixture_dirs(root)
  local fixtures = {}
  local prefix = root .. "/"
  for _, path in ipairs(find_files("find " .. root .. " -type f -name '*.lua' 2>/dev/null")) do
    if path:sub(1, #prefix) == prefix then
      local rest = path:sub(#prefix + 1)
      local key = rest:match("^([^/]+)/")
      if key then
        fixtures[key] = fixtures[key] or {}
        fixtures[key][#fixtures[key] + 1] = path
      end
    end
  end
  return fixtures
end

function Coverage.validate_phase_spec(Compiler, cfg)
  assert_type(cfg.key, "string", "compiler spec key in " .. cfg.__file)
  assert_type(cfg.boundary, "string", "compiler spec boundary in " .. cfg.__file)
  assert_type(cfg.status, "string", "compiler spec status in " .. cfg.__file)
  assert(cfg.status == "planned" or cfg.status == "in-progress" or cfg.status == "green",
    "invalid compiler spec status in " .. cfg.__file .. ": " .. tostring(cfg.status))
  assert_type(cfg.fixtures, "string", "compiler spec fixtures path in " .. cfg.__file)
  assert_type(cfg.golden, "string", "compiler spec golden path in " .. cfg.__file)
  for _, module_name in ipairs(array_values(cfg.modules)) do
    assert(Compiler[module_name], "unknown schema module " .. module_name .. " in " .. cfg.__file)
  end
  for _, leaf in ipairs(array_values(cfg.leaves)) do
    Coverage.assert_leaf_exists(Compiler, leaf)
  end
  for _, contract in ipairs(array_values(cfg.methods)) do
    assert_type(contract.owner, "string", "method contract owner in " .. cfg.__file)
    assert_type(contract.method, "string", "method contract method in " .. cfg.__file)
    Coverage.assert_class_exists(Compiler, contract.owner)
    assert(contract.method:match("^[%a_][%a_%d]*$"),
      "invalid method name in " .. cfg.__file .. ": " .. contract.method)
  end
  for _, key in ipairs(array_values(cfg.implementation_order)) do
    assert_type(key, "string", "implementation order key in " .. cfg.__file)
  end
  for _, entry in ipairs(excluded_entries(cfg.excluded)) do
    Coverage.assert_leaf_exists(Compiler, entry.leaf)
    assert(entry.reason and entry.reason ~= "", "excluded leaf lacks reason in " .. cfg.__file .. ": " .. entry.leaf)
  end
end

local function load_fixture(path)
  local value = dofile(path)
  assert(type(value) == "table", "fixture did not return a table: " .. path)
  return value
end

local function collect_fixture_leaves(Compiler, fixture_dir)
  local covered = {}
  for _, path in ipairs(find_files("find " .. fixture_dir .. " -type f -name '*.lua' 2>/dev/null")) do
    local fixture = load_fixture(path)
    local leaves = fixture.leaves or (fixture.leaf and { fixture.leaf }) or {}
    for _, leaf in ipairs(leaves) do
      Coverage.assert_leaf_exists(Compiler, leaf)
      covered[leaf] = true
    end
  end
  return covered
end

function Coverage.assert_phase_coverage(Compiler, cfg, fixture_dir)
  local covered = collect_fixture_leaves(Compiler, fixture_dir)
  local missing = {}
  for _, leaf in ipairs(array_values(cfg.leaves)) do
    if not covered[leaf] then missing[#missing + 1] = leaf end
  end
  table.sort(missing)
  assert(#missing == 0, "missing fixture coverage for " .. cfg.key .. ": " .. table.concat(missing, ", "))
end

function Coverage.report(spec_dir, fixture_root)
  local specs = Coverage.load_phase_specs(spec_dir)
  local fixtures = Coverage.scan_fixture_dirs(fixture_root)
  local names = {}
  for key in pairs(specs) do names[#names + 1] = key end
  table.sort(names)
  print("# compiler specs: " .. tostring(#names))
  for _, key in ipairs(names) do
    local cfg = specs[key]
    print(key .. " " .. cfg.status .. " leaves=" .. tostring(#(cfg.leaves or {})))
  end
  local fixture_names = {}
  for key in pairs(fixtures) do fixture_names[#fixture_names + 1] = key end
  table.sort(fixture_names)
  print("# fixture keys: " .. tostring(#fixture_names))
  for _, key in ipairs(fixture_names) do
    print(key .. " fixtures=" .. tostring(#fixtures[key]))
  end
end

return Coverage
