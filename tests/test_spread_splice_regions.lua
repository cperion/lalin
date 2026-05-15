package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local r = Host.eval [[
local params = { moon.param("p", moon.ptr(moon.u8)), moon.param("n", moon.i32) }
local conts = {
    moon.cont_decl("ok", { moon.param("pos", moon.i32) }),
    moon.cont_decl("fail", { moon.param("code", moon.i32) }),
}
return region scan(@{params...}; @{conts...})
entry start()
    if n >= 0 then jump ok(pos = n) end
    jump fail(code = 1)
end
end
]]

assert(#r.frag.params == 2)
assert(r.frag.params[1].name == "p")
assert(r.frag.params[2].name == "n")
assert(#r.frag.conts == 2)
assert(r.frag.conts[1].pretty_name == "ok")
assert(r.frag.conts[1].params[1].name == "pos")
assert(r.frag.conts[2].pretty_name == "fail")
assert(r.frag.conts[2].params[1].name == "code")

local r2 = Host.eval [[
local eparams = { moon.entry_param("i", moon.i32, 0) }
local bparams = { moon.param("acc", moon.i32) }
return region with_params()
entry start(@{eparams...})
end
block done(@{bparams...})
end
end
]]
assert(#r2.frag.entry.params == 1)
assert(r2.frag.entry.params[1].name == "i")
assert(#r2.frag.blocks == 1)
assert(r2.frag.blocks[1].params[1].name == "acc")

local r3 = Host.eval [[
local blocks = { moon.control_block("extra", {}, {}) }
return region with_blocks()
entry start()
end
@{blocks...}
end
]]
assert(#r3.frag.blocks == 1)
assert(r3.frag.blocks[1].label.name == "extra")

print("moonlift spread splice regions ok")
