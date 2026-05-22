-- Lua Interpreter VM — Opcode handler aggregator
-- All handlers live in src/op/ submodules. This file merges them.

local load_mod = require("experiments.lua_interpreter_vm.src.op.load")
local arith_mod = require("experiments.lua_interpreter_vm.src.op.arithmetic")
local table_mod = require("experiments.lua_interpreter_vm.src.op.table")
local compare_mod = require("experiments.lua_interpreter_vm.src.op.compare")
local call_mod = require("experiments.lua_interpreter_vm.src.op.call")
local loop_mod = require("experiments.lua_interpreter_vm.src.op.loop")
local closure_mod = require("experiments.lua_interpreter_vm.src.op.closure")
local misc_mod = require("experiments.lua_interpreter_vm.src.op.misc")

local handlers = {}
for _, mod in ipairs({ load_mod, arith_mod, table_mod, compare_mod,
                        call_mod, loop_mod, closure_mod, misc_mod }) do
    for k, v in pairs(mod) do
        handlers[k] = v
    end
end

return handlers
