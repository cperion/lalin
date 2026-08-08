local Inventory = {}

local function field_text(field)
  local suffix = ""
  if field.list then suffix = suffix .. "*" end
  if field.optional then suffix = suffix .. "?" end
  return field.name .. ":" .. tostring(field.type) .. suffix
end

function Inventory.render(Compiler)
  local names = {}
  for name in pairs(Compiler.definitions) do names[#names + 1] = name end
  table.sort(names)

  local lines = {}
  for _, name in ipairs(names) do
    local cls = Compiler.definitions[name]
    local fields = {}
    for _, field in ipairs(cls.__fields or {}) do
      fields[#fields + 1] = field_text(field)
    end
    local kind = cls.kind or ""
    lines[#lines + 1] = name .. " | kind=" .. kind .. " | fields=(" .. table.concat(fields, ", ") .. ")"
  end
  return table.concat(lines, "\n") .. "\n"
end

function Inventory.read_file(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("*a")
  file:close()
  return text
end

function Inventory.write_file(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

return Inventory
