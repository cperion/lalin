package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local session = lalin.use { scope = "env" }
local asdl = require("lalin.asdl")

local src = [[
return {
    fn. add
        { a [i32], b [i32] }
        [i32]
        {
            ret (a + b),
        },
}
]]

local decls = session:loadstring(src, "compiler_driver_test.lua")()
local decl = lalin.unit("DriverSmoke", decls)

local lowered = decl:lower()
assert(asdl.classof(lowered))
assert(tostring(asdl.classof(lowered)):match("LalinC%.CBackendUnit"))

local artifact = decl:emit_c_artifact()
assert(artifact.unit)
assert(artifact.kind == "LuaJITCSourceArtifact")
assert(tostring(asdl.classof(artifact.unit)):match("LalinLuaJIT%.LJModule"))
assert(type(artifact.source) == "string")

local bytecode = lalin.compile_luajit("DriverSmoke", decls, { bytecode = true })
assert(bytecode.add(3, 4) == 7)

local ok, err = pcall(function()
    lalin.compile("DriverSmokeNativeRequiresBank", decls)
end)
assert(not ok and tostring(err):match("NativeTemplateBank"), "default native compile should require a native bank")

io.write("lalin compiler_driver ok\n")
