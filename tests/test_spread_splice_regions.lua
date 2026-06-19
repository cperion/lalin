package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")
local pvm = require("moonlift.pvm")
local moon = require("moonlift")

local scan = Host.eval([[
local params = moon.params {
    {name="p", type=moon.ptr(moon.u8)},
    {name="n", type=moon.i32},
}
local conts = {
    {name="ok", params=moon.params{ {name="pos", type=moon.i32} }},
    {name="fail", params=moon.params{ {name="code", type=moon.i32} }},
}
return region scan(@{params...}; @{conts...})
entry start()
    if n >= 0 then jump ok(pos = n) end
    jump fail(code = 1)
end
end
]])
assert(scan.kind == "region_frag")
assert(#scan.frag.params == 2)
assert(scan.frag.params[1].name == "p")
assert(scan.frag.params[2].name == "n")
assert(#scan.frag.conts == 2)
assert(scan.frag.conts[1].pretty_name == "ok")
assert(scan.frag.conts[2].pretty_name == "fail")
local Tr = scan.session.T.MoonTree
local if_stmt = scan.frag.entry.body[1]
assert(pvm.classof(if_stmt.then_body[1]) == Tr.StmtJumpCont)
assert(if_stmt.then_body[1].slot.pretty_name == "ok")
assert(pvm.classof(scan.frag.entry.body[2]) == Tr.StmtJumpCont)
assert(scan.frag.entry.body[2].slot.pretty_name == "fail")

local with_params = Host.eval([[
local eparams = moon.entry_params {
    {name="i", type=moon.i32, init=moon.int(0)}
}
return region with_params()
entry start(@{eparams...})
    return
end
end
]])
assert(#with_params.frag.entry.params == 1)
assert(with_params.frag.entry.params[1].name == "i")

local with_blocks = Host.eval([[
local blocks = moon.blocks { {label="extra", params={}, body={}} }
return region with_blocks()
entry start()
    return
end
@{blocks...}
end
]])
assert(#with_blocks.frag.blocks == 1)
assert(with_blocks.frag.blocks[1].label.name == "extra")

local control_blocks = moon.blocks { {label="extra", params={}, body={}} }
local control_expr = moon.expr { blocks = control_blocks } [[
region: i32
entry start()
    yield 1
end
@{blocks...}
end
]]
local ExprTr = moon.default_session.T.MoonTree
assert(pvm.classof(control_expr.expr) == ExprTr.ExprControl)
assert(#control_expr.expr.region.blocks == 1)
assert(control_expr.expr.region.blocks[1].label.name == "extra")

print("moonlift spread splice regions ok")
