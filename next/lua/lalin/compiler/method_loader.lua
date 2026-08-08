local MethodLoader = {}

local function apply_module(Compiler, module_name, loaded)
  local module = require(module_name)
  if type(module) == "function" then
    module(Compiler)
  elseif type(module) == "table" and module.load then
    module.load(Compiler)
  else
    error("compiler method module must return a function or table with load(): " .. module_name, 2)
  end
  loaded[module_name] = true
end

function MethodLoader.load_modules(Compiler, module_names, loaded)
  loaded = loaded or {}
  for _, module_name in ipairs(module_names or {}) do
    if not loaded[module_name] then
      apply_module(Compiler, module_name, loaded)
    end
  end
  return Compiler
end

return MethodLoader
