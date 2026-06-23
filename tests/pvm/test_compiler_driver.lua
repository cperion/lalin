package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local session = require("moonlift").use { scope = "env" }
local pvm = require("moonlift.pvm")

local src = [[
return module "DriverSmoke" {
    fn. add
        { a [i32], b [i32] }
        [i32]
        {
            ret (a + b),
        },
}
]]

local decl = session:loadstring(src, "compiler_driver_test.lua")()

local lowered = decl:lower()
assert(pvm.classof(lowered))
assert(tostring(pvm.classof(lowered)):match("MoonBack%.BackProgram"))

local artifact = decl:emit_c_artifact()
assert(artifact.unit)
assert(tostring(pvm.classof(artifact.unit)):match("MoonC%.CBackendUnit"))
assert(type(artifact.source) == "string")

io.write("moonlift compiler_driver ok\n")
