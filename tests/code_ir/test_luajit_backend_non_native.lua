package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local lalin = require("lalin")

local T = asdl.context()
Schema(T)
assert(T.LalinNative ~= nil, "schema should expose LalinNative")
assert(T.LalinResidual == nil, "LuaJIT backend must not require LalinResidual")

local Backend = require("lalin.luajit_backend")(T)
require("lalin.luajit_emit")(T)
assert(T._lalin_api_cache.native == nil, "LuaJIT backend/emitter must not load lalin.native")
assert(T._lalin_api_cache.native_mc == nil, "LuaJIT backend/emitter must not load lalin.native_mc")
assert(Backend.build_mc_bank == nil, "LuaJIT backend must not expose the removed MC bank API")

local realized, realize_err = Backend.realize_artifacts({}, { native_bank = {} })
assert(realized == nil, "LuaJIT realization should not consume native_bank options")
assert(tostring(realize_err):match("explicit LuaJIT bytecode"), tostring(realize_err))
assert(tostring(realize_err):match("lalin.native_backend"), tostring(realize_err))

local decl = lalin.dsl.load([=[
return fn. id_i32 { x [i32] } [i32] {
  ret (x),
}
]=], "test_luajit_backend_non_native.lua")

local ok_native_bank, native_bank_err = pcall(function()
    lalin.emit_luajit_artifact(decl, {
        name = "test_luajit_reject_native_bank",
        native_bank = {},
    })
end)
assert(not ok_native_bank, "LuaJIT artifact facade must reject NativeTemplateBank inputs")
assert(tostring(native_bank_err):match("native banks are not accepted"), tostring(native_bank_err))

local ok_mc_bank, mc_bank_err = pcall(function()
    lalin.emit_luajit_artifact(decl, {
        name = "test_luajit_reject_mc_bank",
        mc_bank = {},
    })
end)
assert(not ok_mc_bank, "LuaJIT artifact facade must reject removed mc_bank inputs")
assert(tostring(mc_bank_err):match("removed LuaJIT machine%-code path"), tostring(mc_bank_err))

io.write("lalin luajit_backend non-native boundary ok\n")
