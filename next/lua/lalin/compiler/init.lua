local Compiler = require("lalin.compiler.schema")
local method_loader = require("lalin.compiler.method_loader")
local impl = require("lalin.compiler.impl")

local M = {
  schema = Compiler,
}

local loaded = false
local loaded_modules = {}

function M.load_methods()
  if loaded then return Compiler end
  method_loader.load_modules(Compiler, impl.modules or {}, loaded_modules)
  if impl.load then impl.load(Compiler) end
  loaded = true
  return Compiler
end

return M
