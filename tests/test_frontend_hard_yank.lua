package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local T = pvm.context()
require("moonlift.asdl").Define(T)

local Parse = require("moonlift.parse").Define(T)
local SurfaceResolve = require("moonlift.surface_resolve").Define(T)

local Ty = T.MoonType
local Tr = T.MoonTree
local O = T.MoonOpen
local S = T.MoonSyntax

local function assert_no_parse(result)
    if #result.issues ~= 0 then
        error(result.issues[1].message, 2)
    end
end

do
    local parsed = Parse.parse_module([[
struct Box value: i32 end
func id_box(x: Box): Box
    return x
end
]])
    assert_no_parse(parsed)
    local func = parsed.module.items[2].func
    assert(pvm.classof(func.params[1].ty) == Ty.TNamed)
    assert(pvm.classof(func.params[1].ty.ref) == Ty.TypeRefPath)

    local resolved = SurfaceResolve.module(parsed.module)
    local resolved_func = resolved.items[2].func
    assert(pvm.classof(resolved_func.params[1].ty) == Ty.TNamed)
    assert(pvm.classof(resolved_func.params[1].ty.ref) == Ty.TypeRefGlobal)
end

do
    local region = Parse.parse_region([[
region sink(x: i32; ok)
entry start()
    jump ok()
end
end
]])
    assert_no_parse(region)

    local func = Parse.parse_func([[
func use_sink(x: i32): void
    emit sink(x; ok = done)
block done()
    return
end
end
]])
    assert_no_parse(func)
    local stmt = func.value.body[1]
    assert(pvm.classof(stmt) == Tr.StmtUseRegionFrag)
    assert(pvm.classof(stmt.frag) == O.RegionFragRefName)
end

do
    local func = Parse.parse_func([[
func use_spliced(x: i32): void
    emit @{sink}(x; ok = done)
block done()
    return
end
end
]])
    assert_no_parse(func)
    local stmt = func.value.body[1]
    assert(pvm.classof(stmt) == Tr.StmtUseRegionFrag)
    assert(pvm.classof(stmt.frag) == O.RegionFragRefSlot)
end

do
    local parsed = Parse.parse_func("func bad(@{params...}): i32 return 0 end")
    assert_no_parse(parsed)
    assert(pvm.classof(parsed.value) == S.SyntaxFuncLocal)
    assert(pvm.classof(parsed.value.params[1]) == S.SyntaxParamItemSpread)
end

print("moonlift frontend hard yank ok")
