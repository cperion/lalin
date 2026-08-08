local DiagnosticOrigin = {}

local function class_reaches_origin(Compiler, cls, memo, visiting)
  if cls == Compiler.Source.Origin then return true end
  if Compiler.Source.Origin.members and Compiler.Source.Origin.members[cls] then return true end
  if memo[cls] ~= nil then return memo[cls] end
  if visiting[cls] then return false end
  visiting[cls] = true

  local reaches = false
  local sum_members = {}
  if cls.members and not cls.kind then
    for member in pairs(cls.members) do
      if member.kind then sum_members[#sum_members + 1] = member end
    end
  end

  if #sum_members > 0 then
    reaches = true
    for _, member in ipairs(sum_members) do
      if not class_reaches_origin(Compiler, member, memo, visiting) then
        reaches = false
        break
      end
    end
  else
    for _, field in ipairs(cls.__fields or {}) do
      local field_class = Compiler.definitions[field.type]
      if field_class and class_reaches_origin(Compiler, field_class, memo, visiting) then
        reaches = true
        break
      end
    end
  end

  visiting[cls] = nil
  memo[cls] = reaches
  return reaches
end

local function diagnostic_leaf_rows(Compiler)
  local rows = {}
  for parent_name, parent in pairs(Compiler.definitions) do
    if parent_name:match("^Diagnostic%.") and parent.members and not parent.kind then
      for leaf in pairs(parent.members) do
        if leaf.kind then rows[#rows + 1] = { name = parent_name .. "." .. leaf.kind, class = leaf } end
      end
    end
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

function DiagnosticOrigin.classification(Compiler)
  local memo = {}
  local rows = {}
  for _, row in ipairs(diagnostic_leaf_rows(Compiler)) do
    local status = class_reaches_origin(Compiler, row.class, memo, {}) and "origin" or "originless"
    rows[#rows + 1] = status .. " " .. row.name
  end
  return table.concat(rows, "\n") .. "\n"
end

function DiagnosticOrigin.read_file(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("*a")
  file:close()
  return text
end

function DiagnosticOrigin.write_file(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

return DiagnosticOrigin
