local FixtureCases = {}

local function find_files(dir)
  local out = {}
  local pipe = io.popen("find " .. dir .. " -type f -name '*.lua' 2>/dev/null")
  if not pipe then return out end
  for path in pipe:lines() do out[#out + 1] = path end
  pipe:close()
  table.sort(out)
  return out
end

function FixtureCases.load_dir(dir)
  local cases = {}
  for _, path in ipairs(find_files(dir)) do
    local case = dofile(path)
    assert(type(case) == "table", "fixture must return table: " .. path)
    case.__file = path
    cases[#cases + 1] = case
  end
  return cases
end

function FixtureCases.assert_common(spec, Compiler, case)
  spec.assert_truthy(case.key, "fixture key missing in " .. case.__file)
  spec.assert_truthy(case.boundary, "fixture boundary missing in " .. case.__file)
  if case.input_type then
    spec.assert_truthy(case.input, "fixture input missing in " .. case.__file)
    spec.assert_truthy(case.input_type:isclassof(case.input), "fixture input type mismatch in " .. case.__file)
  end
  for _, leaf in ipairs(case.leaves or {}) do
    local parts = {}
    for part in leaf:gmatch("[^.]+") do parts[#parts + 1] = part end
    spec.assert_equal(#parts, 3, "fixture leaf path shape in " .. case.__file)
    local namespace = Compiler[parts[1]]
    spec.assert_truthy(namespace, "fixture leaf module missing in " .. case.__file .. ": " .. leaf)
    local parent = namespace[parts[2]]
    local child = namespace[parts[3]]
    spec.assert_truthy(parent, "fixture leaf parent missing in " .. case.__file .. ": " .. leaf)
    spec.assert_truthy(child, "fixture leaf child missing in " .. case.__file .. ": " .. leaf)
    spec.assert_truthy(parent.members and parent.members[child], "fixture leaf membership mismatch in " .. case.__file .. ": " .. leaf)
  end
  if case.cases then
    for _, item in ipairs(case.cases) do
      spec.assert_truthy(item.name, "nested fixture case missing name in " .. case.__file)
      if item.input_type then
        spec.assert_truthy(item.input, "nested fixture case missing input in " .. case.__file .. ": " .. item.name)
        spec.assert_truthy(item.input_type:isclassof(item.input),
          "nested fixture input type mismatch in " .. case.__file .. ": " .. item.name)
      end
      spec.assert_truthy(item.expected, "nested fixture case missing expected value in " .. case.__file .. ": " .. item.name)
    end
  end
  if case.decisions then
    local seen = {}
    for _, decision in ipairs(case.decisions) do
      spec.assert_truthy(decision.leaf, "decision missing leaf in " .. case.__file)
      spec.assert_truthy(decision.status == "EMIT" or decision.status == "REJECT",
        "decision status must be EMIT or REJECT in " .. case.__file)
      seen[decision.leaf] = true
    end
    for _, leaf in ipairs(case.leaves or {}) do
      spec.assert_truthy(seen[leaf], "fixture leaf lacks decision in " .. case.__file .. ": " .. leaf)
    end
  end
  if case.expected_c then
    local file = assert(io.open(case.expected_c, "r"), "missing expected C golden: " .. case.expected_c)
    local text = file:read("*a")
    file:close()
    spec.assert_truthy(text, "empty expected C golden read failed: " .. case.expected_c)
  end
end

return FixtureCases
