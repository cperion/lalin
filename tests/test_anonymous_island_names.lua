package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local add = Host.eval [[
local add = func(a: i32, b: i32) -> i32
    return a + b
end
return add
]]
assert(add.name == "add")
local c_add = add:compile()
assert(c_add(20, 22) == 42)
c_add:free()

local pass, ident, User, Result = Host.eval [[
local pass = region(p: ptr(u8); ok: cont(next: i32))
entry start()
    jump ok(next = 0)
end
end

local ident = expr(x: i32) -> i32
    x
end

local User = struct
    id: i32
end

local Result = union ok(value: i32) | err(code: i32) end

return pass, ident, User, Result
]]

assert(pass.name == "pass")
assert(ident.name == "ident")
assert(User.source_hint == "User")
assert(Result.source_hint == "Result")

local Inline = Host.eval [[
local Inline = struct value: i32 end
return Inline
]]
assert(Inline.source_hint == "Inline")

print("moonlift anonymous_island_names ok")
