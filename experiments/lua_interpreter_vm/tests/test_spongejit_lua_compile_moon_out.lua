#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local C = require("lua_compile")
local Validate = require("lua_compile.moon_cfg_validate")
local Emit = require("lua_compile.moon_cfg_emit")
local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local CFG, NF, LC = T.MoonCFG, T.LuaNF, T.LuaContract

local function kernel_from(events, evidence)
  local r = C.compile_to_moon_kernel(C.unit_from_events(events, evidence or {}))
  assert(r.kind == "Ok", "compile_to_moon_kernel rejected fixture: " .. tostring(r.rejection and r.rejection.reason and r.rejection.reason.kind))
  return r.product.kernel
end

local function contains_class(v, target, seen)
  if type(v) ~= "table" then return false end
  seen = seen or {}; if seen[v] then return false end; seen[v] = true
  if pvm.classof(v) == target then return true end
  local cls = pvm.classof(v)
  if cls and cls.__fields then
    for _, f in ipairs(cls.__fields) do if contains_class(v[f.name], target, seen) then return true end end
  elseif not cls then
    for _, x in pairs(v) do if contains_class(x, target, seen) then return true end end
  end
  return false
end

local function assert_validate_ok(kernel)
  local ok, errs = Validate.validate(kernel)
  assert(ok, table.concat(errs, "\n"))
end

local function assert_no_protocol_source(src)
  assert(not src:match("out_tag"), "emitted source must not contain out_tag")
  assert(not src:match("out_event_kind"), "emitted source must not contain out_event_kind")
  assert(not src:match("generic_for"), "emitted source must not contain generic_for protocol tag")
  assert(not src:match("getvarg"), "emitted source must not contain getvarg protocol tag")
  assert(not src:match("setlist"), "emitted source must not contain setlist protocol tag")
end

-- Positive structural slice: LOADI + RETURN1 becomes a one-block MoonCFG kernel.
local kernel = kernel_from({ {op="LOADI",pc=1,a=1,b=42}, {op="RETURN1",pc=2,a=1} }, {})
assert(pvm.classof(kernel) == CFG.Kernel)
assert(kernel.normal_form == nil, "MoonCFG kernel must not carry executable LuaNF.Program")
assert(not contains_class(kernel, NF.Program), "accepted MoonCFG kernel must not contain LuaNF.Program")
assert(kernel.body and kernel.body.blocks and #kernel.body.blocks == 1)
assert(kernel.body.blocks[1].terminator.kind == "Return")
assert_validate_ok(kernel)
local src = Emit.emit(kernel, { name = "test_moon_cfg_loadi" })
assert(src:match("local test_moon_cfg_loadi = func"))
assert_no_protocol_source(src)
assert(src == Emit.emit(kernel, { name = "test_moon_cfg_loadi" }), "MoonCFG emission must be deterministic")
local fn = assert(moon.loadstring(src, "=(test_moon_cfg_loadi)"))()
local native = assert(fn:compile())
assert(native() == 42)
native:free()

-- ADDI scalar return uses a typed value parameter, not an output protocol.
local addk = kernel_from({ {op="ADDI",pc=1,a=1,b=1,c=128,sc=1}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_i64"} })
assert_validate_ok(addk)
assert(#addk.params == 1 and addk.params[1].name.text == "slot_1_i64")
local add_src = Emit.emit(addk, { name = "test_moon_cfg_addi" })
assert_no_protocol_source(add_src)
local add_fn = assert(moon.loadstring(add_src, "=(test_moon_cfg_addi)"))()
local add_native = assert(add_fn:compile())
assert(add_native(41) == 42)
add_native:free()

-- Protocol operations must not compile as success. This is a forbidden-success
-- gate only; it is not a claim that these valid Lua operations are implemented.
local function sample_event(op)
  return { op=op, name=op, pc=1, a=1, b=2, c=3, offset=1, k=false, bx=1, sbx=1, ax=1, binop="ADD" }
end
for _, op in ipairs({ "CALL", "TAILCALL", "CLOSE", "TBC", "TFORPREP", "TFORCALL", "TFORLOOP", "SETLIST", "GETVARG" }) do
  local r = C.compile_to_moon_kernel(C.unit_from_events({ sample_event(op) }, {}))
  assert(r.kind == "Reject", op .. " must not compile as protocol success")
end

-- Direct validator negatives for tag ABI and quarantined protocol exits.
local empty_contract = LC.Contract(LC.Transfer({}, {}), {}, {})
local kid = CFG.KernelId(CFG.Name("bad"))
local rid = CFG.RegionId(CFG.Name("body"))
local bid = CFG.BlockId(CFG.Name("entry"))
local block = CFG.Block(bid, {}, {}, CFG.Return({ CFG.ConstValue(CFG.I64Const(0)) }))
local region = CFG.Region(rid, {}, {}, bid, { block })
local bad_param = CFG.Kernel(kid, CFG.InlineSpan, { CFG.Param(CFG.Name("out_tag"), CFG.TypeRef("ptr(i32)"), CFG.ValueParam) }, { CFG.TypeRef("i64") }, region, empty_contract)
local ok, errs = Validate.validate(bad_param)
assert(not ok and table.concat(errs, "\n"):match("forbidden_param:out_tag"), "validator must reject out_tag params")

local proto_exit = NF.CallProtocolExit(NF.ExitId(1), T.LuaSrc.Pc(1), T.LuaSrc.Slot(1), T.LuaSrc.Count(0), T.LuaSrc.Count(0), false, {})
local bad_contract = LC.Contract(LC.Transfer({}, {}), { LC.ProjectionObligation(proto_exit, {}) }, {})
local bad_proto = CFG.Kernel(kid, CFG.InlineSpan, {}, { CFG.TypeRef("i64") }, region, bad_contract)
ok, errs = Validate.validate(bad_proto)
assert(not ok and table.concat(errs, "\n"):match("forbidden_protocol_exit:CallProtocolExit"), "validator must reject protocol exits inside accepted kernels")

print("ok - SpongeJIT LuaCompile MoonCFG honest slice")
