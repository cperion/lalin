package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local Protocol = Host.eval [[
local Protocol = union
    ok(value: i32)
  | err(pos: i32, code: i32)
  | empty
end
return Protocol
]]
assert(Protocol.name == "Protocol")
assert(#Protocol.decl.variants == 3)
assert(Protocol.decl.variants[1].name == "ok")
assert(#Protocol.decl.variants[1].fields == 1)
assert(Protocol.decl.variants[3].name == "empty")
assert(#Protocol.decl.variants[3].fields == 0)

local comma_union = Host.eval [[
return union PipeUnion
    one
  | two(x: i32)
  | three
end
]]
assert(comma_union.name == "PipeUnion")
assert(#comma_union.decl.variants == 3)

local use_new_cont_syntax = Host.eval [[
local emit_value = region(x: i32;
    ok(value: i32)
  | err(pos: i32, code: i32)
  | empty
)
entry start()
    if x < 0 then jump err(pos = 0, code = x) end
    if x == 0 then jump empty() end
    jump ok(value = x + 1)
end
end

return func(x: i32): i32
    return region: i32
    entry start()
        emit @{emit_value}(x; ok = good, err = bad, empty = zero)
    end
    block good(value: i32)
        yield value
    end
    block bad(pos: i32, code: i32)
        yield code
    end
    block zero()
        yield 0
    end
    end
end
]]
local c = use_new_cont_syntax:compile()
assert(c(41) == 42)
assert(c(0) == 0)
assert(c(-7) == -7)
c:free()

local old_ok, old_err = pcall(function()
    local removed = "local emit_value = region(x: i32; ok" .. ": con" .. "t(value: i32) | empty" .. ": con" .. "t()) end\nreturn emit_value\n"
    Host.eval(removed)
end)
assert(not old_ok)
assert(tostring(old_err):match("removed continuation syntax"))

local comma_sum_ok, comma_sum_err = pcall(function()
    Host.eval [[local Bad = union ok(i32), err(i32) end return Bad]]
end)
assert(not comma_sum_ok)
assert(tostring(comma_sum_err):match("expected '%|' between union variants"))

local comma_cont_ok, comma_cont_err = pcall(function()
    Host.eval [[local bad = region(x: i32; ok(v: i32), err(code: i32)) end return bad]]
end)
assert(not comma_cont_ok)
assert(tostring(comma_cont_err):match("expected '%|' between continuation alternatives"))

local semicolon_struct_ok, semicolon_struct_err = pcall(function()
    Host.eval [[local Bad = struct x: i32; y: i32 end return Bad]]
end)
assert(not semicolon_struct_ok)
assert(tostring(semicolon_struct_err):match("expected ',' between struct fields"))

print("moonlift mlua protocol variant syntax ok")
