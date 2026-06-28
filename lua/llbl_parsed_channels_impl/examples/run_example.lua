-- Run from this directory with a LuaJIT/Lua 5.1-compatible interpreter in a
-- repository that has this bundle's lua/ directory on package.path.
package.path = "../lua/?.lua;../lua/?/init.lua;" .. package.path

local syntax = require("llbl.syntax")
require("lalin.syntax")
local Ast = require("lalin.syntax.ast")

local chunk, compiled_or_err, compiled_if_err = syntax.loadfile("copy_scale.lalin.lua")
if not chunk then
  error(tostring(compiled_or_err) .. "\nGenerated Lua:\n" .. tostring(compiled_if_err and compiled_if_err.lua or "<none>"))
end

local mod = chunk()
print(Ast.dump(mod.copy_scale))
