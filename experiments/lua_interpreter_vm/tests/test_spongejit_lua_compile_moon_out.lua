#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")
local C = require("lua_compile")
local Validate = require("lua_compile.moon_out_validate")
local Emit = require("lua_compile.moon_out_emit")
local Lower = require("lua_compile.lua_src_to_lua_sem_lower")
local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()

local function protocol_buffers()
  return {
    tag = ffi.new("int32_t[1]"),
    value_kind = ffi.new("int32_t[1]"),
    pc = ffi.new("int64_t[1]"),
    offset = ffi.new("int64_t[1]"),
    slot = ffi.new("int64_t[1]"),
    i64 = ffi.new("int64_t[1]"),
    f64 = ffi.new("double[1]"),
    bool = ffi.new("bool[1]"),
    reason = ffi.new("int32_t[1]"),
    projection_count = ffi.new("int32_t[1]"),
    event_kind = ffi.new("int32_t[1]"),
    address_kind = ffi.new("int32_t[1]"),
    key = ffi.new("int64_t[1]"),
    array_hint = ffi.new("int64_t[1]"),
    hash_hint = ffi.new("int64_t[1]"),
    narray = ffi.new("int64_t[1]"),
    start = ffi.new("int64_t[1]"),
    upvalue = ffi.new("int64_t[1]"),
    table_slot = ffi.new("int64_t[1]"),
    index_i64 = ffi.new("int64_t[1]"),
    payload_kind = ffi.new("int32_t[1]"),
    payload_pc = ffi.new("int64_t[1]"),
    event_count = ffi.new("int32_t[1]"),
  }
end

local OUT_ARG = {
  out_tag = function(b) return b.tag end,
  out_value_kind = function(b) return b.value_kind end,
  out_pc = function(b) return b.pc end,
  out_offset = function(b) return b.offset end,
  out_slot = function(b) return b.slot end,
  out_i64 = function(b) return b.i64 end,
  out_f64 = function(b) return b.f64 end,
  out_bool = function(b) return b.bool end,
  out_boundary_reason = function(b) return b.reason end,
  out_projection_count = function(b) return b.projection_count end,
  out_event_kind = function(b) return b.event_kind end,
  out_address_kind = function(b) return b.address_kind end,
  out_key = function(b) return b.key end,
  out_array_hint = function(b) return b.array_hint end,
  out_hash_hint = function(b) return b.hash_hint end,
  out_narray = function(b) return b.narray end,
  out_start = function(b) return b.start end,
  out_upvalue = function(b) return b.upvalue end,
  out_table_slot = function(b) return b.table_slot end,
  out_index_i64 = function(b) return b.index_i64 end,
  out_payload_kind = function(b) return b.payload_kind end,
  out_payload_pc = function(b) return b.payload_pc end,
  out_event_count = function(b) return b.event_count end,
}

local function default_arg(ty)
  if ty == "bool" then return false end
  if ty == "f64" then return 0.0 end
  return 0
end

local function call_kernel(compiled, kernel, bufs, args)
  args = args or {}
  local argv = {}
  for _, p in ipairs(kernel.params or {}) do
    if OUT_ARG[p.name] then argv[#argv + 1] = OUT_ARG[p.name](bufs)
    else argv[#argv + 1] = args[p.name] ~= nil and args[p.name] or default_arg(p.moon_type) end
  end
  return compiled(unpack(argv))
end

local function kernel_from(events, evidence)
  local r = C.compile_to_moon_kernel(C.unit_from_events(events, evidence or {}))
  assert(r.kind == "Ok", "compile_to_moon_kernel rejected fixture")
  return r.product.kernel
end

local function validate_ok(kernel)
  local ok, errs = Validate.validate(kernel)
  assert(ok, table.concat(errs, "\n"))
  return true
end

local function compile_kernel(kernel, name)
  validate_ok(kernel)
  local src = Emit.emit(kernel, { name = name or "lua_compile_kernel" })
  assert(src:match("local "), "MoonOut must emit Moonlift source")
  assert(not src:match("MoonOut kernel"), "scaffold comment emission must be gone")
  assert(not src:match("Spon") and not src:match("stencil") and not src:match("bank"), "emitted source must not use retired backend ABI names")
  local chunk = assert(moon.loadstring(src, "=(" .. (name or "moon_out") .. ")"))
  local fn = chunk()
  return assert(fn:compile()), src
end

local function contains_src_op(v, seen)
  if type(v) ~= "table" then return false end
  seen = seen or {}; if seen[v] then return false end; seen[v] = true
  local cls = pvm.classof(v)
  if T.LuaSrc.Op.members[cls] then return true end
  if cls and cls.__fields then for _, f in ipairs(cls.__fields) do if contains_src_op(v[f.name], seen) then return true end end end
  for k, x in pairs(v) do if k ~= "kind" and k ~= "__slot" and contains_src_op(x, seen) then return true end end
  return false
end

local function field_obs(slot, pc, key, barrier)
  local obs = {
    { slot=slot, predicate="is_table" }, { slot=slot, predicate="shape_eq", shape_key="s" .. slot },
    { slot=slot, predicate="metatable_absent", shape_key="s" .. slot }, { slot=slot, predicate="field_offset", shape_key="s" .. slot, key=key },
    { slot=slot, payload="shape", pc=pc, shape_key="s" .. slot }, { slot=slot, payload="field", key=key, pc=pc, shape_key="s" .. slot },
  }
  if barrier then obs[#obs + 1] = { slot=slot, predicate="barrier_clean" }; obs[#obs + 1] = { payload="barrier", pc=pc } end
  return obs
end

local function up_field_obs(up, pc, key, barrier)
  local obs = {
    { up=up, predicate="is_table" }, { up=up, predicate="shape_eq", shape_key="u" .. up },
    { up=up, predicate="metatable_absent", shape_key="u" .. up }, { up=up, predicate="field_offset", shape_key="u" .. up, key=key },
    { up=up, payload="shape", pc=pc, shape_key="u" .. up }, { up=up, payload="field", key=key, pc=pc, shape_key="u" .. up },
  }
  if barrier then obs[#obs + 1] = { up=up, predicate="barrier_clean" }; obs[#obs + 1] = { payload="barrier", pc=pc } end
  return obs
end

local function array_obs(slot, pc, barrier)
  local obs = {
    { slot=slot, predicate="is_table" }, { slot=slot, predicate="array_hit" },
    { slot=slot, predicate="bounds_ok" }, { slot=slot, predicate="array_base_offset" },
    { slot=slot, payload="array", pc=pc },
  }
  if barrier then obs[#obs + 1] = { slot=slot, predicate="barrier_clean" }; obs[#obs + 1] = { payload="barrier", pc=pc } end
  return obs
end

local function append(dst, src) for _, x in ipairs(src or {}) do dst[#dst + 1] = x end; return dst end

local keepalive_callbacks = {}
local function pow_f64_callback()
  local cb = ffi.cast("double (*)(double, double)", function(a, b) return a ^ b end)
  keepalive_callbacks[#keepalive_callbacks + 1] = cb
  return cb
end

local function concat_string_callback()
  local cb = ffi.cast("int64_t (*)(int64_t, int64_t)", function(a, b) return tonumber(a) * 1000 + tonumber(b) end)
  keepalive_callbacks[#keepalive_callbacks + 1] = cb
  return cb
end

-- Arithmetic + return: validate, emit, compile, execute.
local kernel = kernel_from({ {op="ADDI",pc=1,a=1,b=1,c=128,sc=1}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_i64"} })
validate_ok(kernel)
assert(kernel.kind == T.MoonOut.InlineSpan)
assert(#kernel.params >= 19 and kernel.params[1].name == "out_tag")
assert(kernel.params[1].moon_type == "ptr(i32)")
assert(not contains_src_op(kernel), "MoonOut must not receive PUC opcode-shaped code")
local compiled = compile_kernel(kernel, "test_moon_out_addi")
local bufs = protocol_buffers()
local tag = call_kernel(compiled, kernel, bufs, { slot_1_i64 = 41 })
assert(tag == Emit.TAGS.return_ and bufs.tag[0] == Emit.TAGS.return_)
assert(bufs.value_kind[0] == Emit.VALUE_KIND.i64)
assert(bufs.i64[0] == 42)
assert(bufs.pc[0] == 2)
compiled:free()

-- A non-terminal slot write is emitted through the same typed output protocol.
local wr = kernel_from({ {op="ADDI",pc=1,a=1,b=1,c=132,sc=5} }, { {slot=1,predicate="is_i64"} })
local wc = compile_kernel(wr, "test_moon_out_write")
bufs = protocol_buffers()
tag = call_kernel(wc, wr, bufs, { slot_1_i64 = 37 })
assert(tag == Emit.TAGS.ok and bufs.slot[0] == 1 and bufs.i64[0] == 42)
assert(bufs.event_kind[0] == Emit.EVENT_KIND.slot_write and bufs.event_count[0] == 1)
wc:free()

-- Fixed-count VARARG/GETVARG lower to typed vararg values; variable count still rejects.
local va = kernel_from({ {op="VARARGPREP",pc=1,a=2}, {op="VARARG",pc=2,a=1,c=2}, {op="RETURN1",pc=3,a=1} }, {})
local vac = compile_kernel(va, "test_moon_out_vararg")
bufs = protocol_buffers()
tag = call_kernel(vac, va, bufs)
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.vararg_tvalue and bufs.table_slot[0] == 0 and bufs.start[0] == 1)
vac:free()
local gv = kernel_from({ {op="GETVARG",pc=2,a=1,b=5,c=2}, {op="RETURN1",pc=3,a=1} }, {})
local gvc = compile_kernel(gv, "test_moon_out_getvarg")
bufs = protocol_buffers()
tag = call_kernel(gvc, gv, bufs)
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.vararg_tvalue and bufs.table_slot[0] == 5 and bufs.start[0] == 1)
gvc:free()
local bad_va = C.compile_to_moon_kernel(C.unit_from_events({ {op="VARARG",pc=2,a=1,c=0} }, {}))
assert(bad_va.kind == "Reject", "VARARG variable count needs explicit multi-result ABI")

-- SETLIST lowers to a typed bulk table write event carrying source range metadata.
local sl = kernel_from({ {op="SETLIST",pc=2,a=1,b=3,c=8} }, {})
local slc = compile_kernel(sl, "test_moon_out_setlist")
bufs = protocol_buffers()
tag = call_kernel(slc, sl, bufs)
assert(tag == Emit.TAGS.ok and bufs.event_kind[0] == Emit.EVENT_KIND.setlist and bufs.table_slot[0] == 1 and bufs.narray[0] == 3 and bufs.start[0] == 8)
slc:free()

-- NEWTABLE and CLOSURE lower to typed allocation/object outputs with metadata.
local nt = kernel_from({ {op="NEWTABLE",pc=2,a=1,b=4,c=7}, {op="RETURN1",pc=3,a=1} }, {})
local ntc = compile_kernel(nt, "test_moon_out_newtable")
bufs = protocol_buffers()
tag = call_kernel(ntc, nt, bufs)
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.table_tvalue and bufs.array_hint[0] == 4 and bufs.hash_hint[0] == 7)
ntc:free()
local ck = kernel_from({ {op="CLOSURE",pc=2,a=1,bx=9}, {op="RETURN1",pc=3,a=1} }, {})
local ckc = compile_kernel(ck, "test_moon_out_closure")
bufs = protocol_buffers()
tag = call_kernel(ckc, ck, bufs)
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.closure_tvalue and bufs.key[0] == 9)
ckc:free()

-- RETURN with concrete PUC counts lowers B=1 as zero values and B=2 as one value.
local rg = kernel_from({ {op="RETURN",pc=3,a=1,b=2} }, {})
local rgc = compile_kernel(rg, "test_moon_out_return_general_one")
bufs = protocol_buffers()
tag = call_kernel(rgc, rg, bufs)
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.tvalue_slot and bufs.table_slot[0] == 1 and bufs.pc[0] == 3)
rgc:free()
local bad_ret = C.compile_to_moon_kernel(C.unit_from_events({ {op="RETURN",pc=3,a=1,b=0} }, {}))
assert(bad_ret.kind == "Reject", "RETURN multret/variable count needs explicit multi-return ABI before lowering")

-- RETURN0 is an explicit zero-value return, not a fake nil return.
local r0 = kernel_from({ {op="RETURN0",pc=4} }, {})
local r0c = compile_kernel(r0, "test_moon_out_return0")
bufs = protocol_buffers()
tag = call_kernel(r0c, r0, bufs)
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.none and bufs.pc[0] == 4)
r0c:free()

-- LOADKX consumes its following EXTRAARG as extended constant index.
local lkx = kernel_from({ {op="LOADKX",pc=5,a=1}, {op="EXTRAARG",pc=6,ax=44}, {op="RETURN1",pc=7,a=1} }, {})
local lkxc = compile_kernel(lkx, "test_moon_out_loadkx")
bufs = protocol_buffers()
tag = call_kernel(lkxc, lkx, bufs)
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.const_tvalue and bufs.key[0] == 44)
lkxc:free()
local bad_lkx = C.compile_to_moon_kernel(C.unit_from_events({ {op="LOADKX",pc=5,a=1} }, {}))
assert(bad_lkx.kind == "Reject", "LOADKX without following EXTRAARG is malformed and must reject")

-- MMBIN* companion markers have no native effect only after immediately
-- preceding typed arithmetic succeeds; standalone markers are metamethod calls
-- and must reject instead of becoming no-op coverage.
local mmb = kernel_from({ {op="ADDI",pc=4,a=1,b=1,c=128,sc=1}, {op="MMBINI",pc=5,a=1,sb=1,binop="ADD"}, {op="RETURN1",pc=6,a=1} }, { {slot=1,predicate="is_i64"} })
local mmbc = compile_kernel(mmb, "test_moon_out_mmbini_marker")
bufs = protocol_buffers()
tag = call_kernel(mmbc, mmb, bufs, { slot_1_i64 = 9 })
assert(tag == Emit.TAGS.return_ and bufs.i64[0] == 10)
mmbc:free()
local bad_mmb = C.compile_to_moon_kernel(C.unit_from_events({ {op="MMBINI",pc=5,a=1,sb=1,binop="ADD"} }, {}))
assert(bad_mmb.kind == "Reject", "MMBIN* without preceding typed arithmetic is a metamethod call, not a no-op")
local bad_mmb_gap = C.compile_to_moon_kernel(C.unit_from_events({ {op="LOADTRUE",pc=4,a=1}, {op="MMBINI",pc=5,a=1,sb=1,binop="ADD"} }, {}))
assert(bad_mmb_gap.kind == "Reject", "MMBIN* must be immediately paired with lowered arithmetic")

-- LEN lowers when table/no-metamethod/length facts prove the fast path.
local len_obs = {
  { slot=2, predicate="is_table" }, { slot=2, payload="shape", pc=5, shape_key="s2" },
  { slot=2, predicate="shape_eq", shape_key="s2" }, { slot=2, predicate="metatable_absent", shape_key="s2" },
  { slot=2, predicate="array_len_offset", shape_key="s2" },
}
local lnk = kernel_from({ {op="LEN",pc=5,a=1,b=2}, {op="RETURN1",pc=6,a=1} }, len_obs)
local lnc = compile_kernel(lnk, "test_moon_out_len")
bufs = protocol_buffers()
tag = call_kernel(lnc, lnk, bufs, { slot_2_len = 12 })
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.i64 and bufs.i64[0] == 12)
lnc:free()
local bad_len = C.compile_to_moon_kernel(C.unit_from_events({ {op="LEN",pc=5,a=1,b=2} }, {}))
assert(bad_len.kind == "Reject", "LEN requires table/no-metamethod/length facts until generic length lowering exists")

-- CONCAT lowers only when every source slot is proven string and uses an
-- explicit primitive function pointer to produce the concatenated string handle.
local cat = kernel_from({ {op="CONCAT",pc=5,a=1,b=2,c=3}, {op="RETURN1",pc=6,a=1} }, { {slot=2,predicate="is_string"}, {slot=3,predicate="is_string"} })
local stripped_cat_params = {}
for _, p in ipairs(cat.params or {}) do if p.name ~= "lua_compile_prim_concat_string" then stripped_cat_params[#stripped_cat_params + 1] = p end end
local stripped_cat = T.MoonOut.Kernel(cat.kind, stripped_cat_params, cat.normal_form, cat.contract, cat.projections)
local stripped_cat_ok, stripped_cat_errs = Validate.validate(stripped_cat)
assert(not stripped_cat_ok and table.concat(stripped_cat_errs, "\n"):match("missing:primitive_param.lua_compile_prim_concat_string"), "CONCAT must require explicit concat primitive parameter")
local catc = compile_kernel(cat, "test_moon_out_concat")
bufs = protocol_buffers()
tag = call_kernel(catc, cat, bufs, { slot_2_string = 12, slot_3_string = 34, lua_compile_prim_concat_string = concat_string_callback() })
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.string_tvalue and bufs.i64[0] == 12034)
catc:free()
local bad_cat = C.compile_to_moon_kernel(C.unit_from_events({ {op="CONCAT",pc=5,a=1,b=2,c=3} }, { {slot=2,predicate="is_string"} }))
assert(bad_cat.kind == "Reject", "CONCAT requires string proof for every concatenated slot")

-- FORPREP subtracts the step from the internal index, then jumps to loop body.
local fp = kernel_from({ {op="FORPREP",pc=5,a=1,offset=4} }, { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"}, {slot=3,predicate="is_i64"} })
local fpc = compile_kernel(fp, "test_moon_out_forprep")
bufs = protocol_buffers()
tag = call_kernel(fpc, fp, bufs, { slot_1_i64 = 10, slot_2_i64 = 20, slot_3_i64 = 2 })
assert(tag == Emit.TAGS.jump and bufs.pc[0] == 5 and bufs.offset[0] == 4)
assert(bufs.projection_count[0] > 0 and bufs.slot[0] == 1 and bufs.i64[0] == 8)
fpc:free()
local fl = kernel_from({ {op="FORLOOP",pc=6,a=1,offset=-3} }, { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"}, {slot=3,predicate="is_i64"} })
local flc = compile_kernel(fl, "test_moon_out_forloop")
bufs = protocol_buffers()
tag = call_kernel(flc, fl, bufs, { slot_1_i64 = 9, slot_2_i64 = 12, slot_3_i64 = 1 })
assert(tag == Emit.TAGS.branch and bufs.pc[0] == 6 and bufs.offset[0] == -3 and bufs.bool[0] == true)
assert(bufs.projection_count[0] > 0 and (bufs.slot[0] == 1 or bufs.slot[0] == 4) and bufs.i64[0] == 10)
bufs = protocol_buffers()
tag = call_kernel(flc, fl, bufs, { slot_1_i64 = 12, slot_2_i64 = 12, slot_3_i64 = 1 })
assert(tag == Emit.TAGS.branch and bufs.bool[0] == false)
flc:free()

-- ERRNNIL lowers only when facts prove the checked slot is non-nil.
local enn = kernel_from({ {op="ERRNNIL",pc=5,a=1}, {op="RETURN0",pc=6} }, { {slot=1,predicate="is_i64"} })
local ennc = compile_kernel(enn, "test_moon_out_errnnil")
bufs = protocol_buffers()
tag = call_kernel(ennc, enn, bufs, { slot_1_i64 = 1 })
assert(tag == Emit.TAGS.return_)
ennc:free()
local bad_enn = C.compile_to_moon_kernel(C.unit_from_events({ {op="ERRNNIL",pc=5,a=1} }, {}))
assert(bad_enn.kind == "Reject", "ERRNNIL requires non-nil proof until error ABI exists")

-- Integer comparison opcodes lower to conditional branch exits.
local eqi = kernel_from({ {op="EQI",pc=6,a=1,sb=5,k=true} }, { {slot=1,predicate="is_i64"} })
local eqic = compile_kernel(eqi, "test_moon_out_eqi_branch")
bufs = protocol_buffers()
tag = call_kernel(eqic, eqi, bufs, { slot_1_i64 = 5 })
assert(tag == Emit.TAGS.branch and bufs.pc[0] == 6 and bufs.offset[0] == 1 and bufs.bool[0] == true)
bufs = protocol_buffers()
tag = call_kernel(eqic, eqi, bufs, { slot_1_i64 = 4 })
assert(tag == Emit.TAGS.branch and bufs.bool[0] == false)
eqic:free()
local testk = kernel_from({ {op="TEST",pc=6,a=2,k=true} }, {})
local testc = compile_kernel(testk, "test_moon_out_test_branch")
bufs = protocol_buffers()
tag = call_kernel(testc, testk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.nil_, slot_2_bool = false })
assert(tag == Emit.TAGS.branch and bufs.bool[0] == false)
bufs = protocol_buffers()
tag = call_kernel(testc, testk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.i64, slot_2_bool = false })
assert(tag == Emit.TAGS.branch and bufs.bool[0] == true)
testc:free()

-- TESTSET branches on R[B] truthiness and projects R[A] := R[B] only on the
-- branch-taken side.
local tsk = kernel_from({ {op="TESTSET",pc=6,a=1,b=2,k=true} }, {})
local tsc = compile_kernel(tsk, "test_moon_out_testset_branch")
bufs = protocol_buffers()
tag = call_kernel(tsc, tsk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.i64, slot_2_bool = false })
assert(tag == Emit.TAGS.branch and bufs.pc[0] == 6 and bufs.offset[0] == 1 and bufs.bool[0] == true)
assert(bufs.projection_count[0] > 0 and bufs.slot[0] == 1 and bufs.value_kind[0] == Emit.VALUE_KIND.tvalue_slot and bufs.table_slot[0] == 2)
bufs = protocol_buffers()
tag = call_kernel(tsc, tsk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.nil_, slot_2_bool = false })
assert(tag == Emit.TAGS.branch and bufs.bool[0] == false and bufs.projection_count[0] == 0)
tsc:free()
local tsfk = kernel_from({ {op="TESTSET",pc=7,a=1,b=2,k=false} }, {})
local tsfc = compile_kernel(tsfk, "test_moon_out_testset_false_branch")
bufs = protocol_buffers()
tag = call_kernel(tsfc, tsfk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.bool, slot_2_bool = false })
assert(tag == Emit.TAGS.branch and bufs.pc[0] == 7 and bufs.bool[0] == true and bufs.projection_count[0] > 0 and bufs.slot[0] == 1)
bufs = protocol_buffers()
tag = call_kernel(tsfc, tsfk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.i64, slot_2_bool = false })
assert(tag == Emit.TAGS.branch and bufs.bool[0] == false and bufs.projection_count[0] == 0)
tsfc:free()

-- LFALSESKIP writes false into the projected state and jumps over the next op.
local lfs = kernel_from({ {op="LFALSESKIP",pc=6,a=1} }, {})
local lfsc = compile_kernel(lfs, "test_moon_out_lfalseskip")
bufs = protocol_buffers()
tag = call_kernel(lfsc, lfs, bufs)
assert(tag == Emit.TAGS.jump and bufs.pc[0] == 6 and bufs.offset[0] == 1)
assert(bufs.projection_count[0] > 0, "LFALSESKIP jump must project the false slot write")
lfsc:free()

-- JMP lowers to an explicit typed jump exit carrying its signed target offset.
local jr = kernel_from({ {op="JMP",pc=7,sj=-3} }, {})
local jc = compile_kernel(jr, "test_moon_out_jmp")
bufs = protocol_buffers()
tag = call_kernel(jc, jr, bufs)
assert(tag == Emit.TAGS.jump and bufs.tag[0] == Emit.TAGS.jump)
assert(bufs.pc[0] == 7 and bufs.offset[0] == -3)
jc:free()

-- Protocol operations lower to explicit typed protocol exits with operands preserved.
local callk = kernel_from({ {op="CALL",pc=7,a=2,b=3,c=4} }, {})
local callc = compile_kernel(callk, "test_moon_out_call_protocol")
bufs = protocol_buffers()
tag = call_kernel(callc, callk, bufs)
assert(tag == Emit.TAGS.call and bufs.pc[0] == 7 and bufs.slot[0] == 2 and bufs.narray[0] == 3 and bufs.start[0] == 4 and bufs.bool[0] == false)
callc:free()
local tailk = kernel_from({ {op="TAILCALL",pc=8,a=2,b=3,c=4} }, {})
local tailc = compile_kernel(tailk, "test_moon_out_tailcall_protocol")
bufs = protocol_buffers()
tag = call_kernel(tailc, tailk, bufs)
assert(tag == Emit.TAGS.call and bufs.bool[0] == true)
tailc:free()
local closek = kernel_from({ {op="TBC",pc=9,a=5} }, {})
local closec = compile_kernel(closek, "test_moon_out_tbc_protocol")
bufs = protocol_buffers()
tag = call_kernel(closec, closek, bufs)
assert(tag == Emit.TAGS.close and bufs.pc[0] == 9 and bufs.slot[0] == 5 and bufs.bool[0] == true)
closec:free()
local tfk = kernel_from({ {op="TFORCALL",pc=10,a=3,c=2} }, {})
local tfc = compile_kernel(tfk, "test_moon_out_tforcall_protocol")
bufs = protocol_buffers()
tag = call_kernel(tfc, tfk, bufs)
assert(tag == Emit.TAGS.generic_for and bufs.pc[0] == 10 and bufs.slot[0] == 3 and bufs.narray[0] == 2 and bufs.event_kind[0] == 2)
tfc:free()

-- F64 division is supported by Moonlift source emission.
local dr = kernel_from({ {op="DIV",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_f64"}, {slot=2,predicate="is_f64"} })
local dc = compile_kernel(dr, "test_moon_out_div")
bufs = protocol_buffers()
tag = call_kernel(dc, dr, bufs, { slot_1_f64 = 21.0, slot_2_f64 = 2.0 })
assert(tag == Emit.TAGS.return_ and math.abs(bufs.f64[0] - 10.5) < 0.0001)
dc:free()

-- Integer IDIV/MOD zero-divisor exits are real MoonOut guard exits, not
-- hidden helpers or VM fallback stubs.
local igr = kernel_from({ {op="LOADI",pc=0,a=3,b=5}, {op="IDIV",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"} })
local igc = compile_kernel(igr, "test_moon_out_idiv_guard")
bufs = protocol_buffers()
tag = call_kernel(igc, igr, bufs, { slot_1_i64 = 21, slot_2_i64 = 0 })
assert(tag == Emit.TAGS.guard and bufs.tag[0] == Emit.TAGS.guard and bufs.pc[0] == 1)
assert(bufs.projection_count[0] > 0, "guard exit must carry projection obligations")
bufs = protocol_buffers()
tag = call_kernel(igc, igr, bufs, { slot_1_i64 = 21, slot_2_i64 = 3 })
assert(tag == Emit.TAGS.return_ and bufs.i64[0] == 7)
igc:free()

-- Dynamic TValue truthiness/NOT is now represented by typed MoonOut input
-- parameters, not by a hidden helper or fake boundary.
local nr = kernel_from({ {op="NOT",pc=1,a=1,b=2}, {op="RETURN1",pc=2,a=1} }, {})
local nc = compile_kernel(nr, "test_moon_out_not")
bufs = protocol_buffers()
tag = call_kernel(nc, nr, bufs, { slot_2_value_kind = Emit.VALUE_KIND.nil_, slot_2_bool = false })
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.bool and bufs.bool[0] == true)
bufs = protocol_buffers()
tag = call_kernel(nc, nr, bufs, { slot_2_value_kind = Emit.VALUE_KIND.bool, slot_2_bool = false })
assert(tag == Emit.TAGS.return_ and bufs.bool[0] == true)
bufs = protocol_buffers()
tag = call_kernel(nc, nr, bufs, { slot_2_value_kind = Emit.VALUE_KIND.i64, slot_2_bool = false })
assert(tag == Emit.TAGS.return_ and bufs.bool[0] == false)
nc:free()

-- Representative field/array/upvalue reads/writes and barriers compile through
-- Moonlift as typed protocol events when adequate evidence exists.
local gfk = kernel_from({ {op="GETFIELD",pc=10,a=1,b=2,c=3}, {op="RETURN1",pc=11,a=1} }, field_obs(2, 10, 3))
local gfc = compile_kernel(gfk, "test_moon_out_getfield")
bufs = protocol_buffers(); tag = call_kernel(gfc, gfk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.table_tvalue })
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.field_tvalue and bufs.address_kind[0] == Emit.ADDRESS_KIND.field and bufs.key[0] == 3)
gfc:free()

local gik = kernel_from({ {op="GETI",pc=12,a=1,b=2,c=5}, {op="RETURN1",pc=13,a=1} }, array_obs(2, 12))
local gic = compile_kernel(gik, "test_moon_out_geti")
bufs = protocol_buffers(); tag = call_kernel(gic, gik, bufs, { slot_2_value_kind = Emit.VALUE_KIND.table_tvalue })
assert(tag == Emit.TAGS.return_ and bufs.value_kind[0] == Emit.VALUE_KIND.array_tvalue and bufs.address_kind[0] == Emit.ADDRESS_KIND.array and bufs.index_i64[0] == 5)
gic:free()

local sfk = kernel_from({ {op="SETFIELD",pc=14,a=2,b=3,c=1,k=false} }, append({ {slot=1,predicate="is_i64"} }, field_obs(2, 14, 3, true)))
local sfc = compile_kernel(sfk, "test_moon_out_setfield")
bufs = protocol_buffers(); tag = call_kernel(sfc, sfk, bufs, { slot_1_i64 = 99, slot_2_value_kind = Emit.VALUE_KIND.table_tvalue })
assert(tag == Emit.TAGS.ok and bufs.event_kind[0] == Emit.EVENT_KIND.barrier and bufs.event_count[0] == 2 and bufs.payload_kind[0] == Emit.PAYLOAD_KIND.barrier)
sfc:free()

local sik = kernel_from({ {op="SETI",pc=15,a=2,b=5,c=1,k=false} }, append({ {slot=1,predicate="is_i64"} }, array_obs(2, 15, true)))
local sic = compile_kernel(sik, "test_moon_out_seti")
bufs = protocol_buffers(); tag = call_kernel(sic, sik, bufs, { slot_1_i64 = 77, slot_2_value_kind = Emit.VALUE_KIND.table_tvalue })
assert(tag == Emit.TAGS.ok and bufs.event_kind[0] == Emit.EVENT_KIND.barrier and bufs.event_count[0] == 2)
sic:free()

local suk = kernel_from({ {op="SETUPVAL",pc=16,a=1,b=0} }, { {slot=1,predicate="is_i64"} })
local suc = compile_kernel(suk, "test_moon_out_setupval")
bufs = protocol_buffers(); tag = call_kernel(suc, suk, bufs, { slot_1_i64 = 55 })
assert(tag == Emit.TAGS.ok and bufs.event_kind[0] == Emit.EVENT_KIND.upvalue_write and bufs.upvalue[0] == 0)
suc:free()

local selfk = kernel_from({ {op="SELF",pc=17,a=1,b=2,c=3} }, field_obs(2, 17, 3))
local selfc = compile_kernel(selfk, "test_moon_out_self")
bufs = protocol_buffers(); tag = call_kernel(selfc, selfk, bufs, { slot_2_value_kind = Emit.VALUE_KIND.table_tvalue })
assert(tag == Emit.TAGS.ok and bufs.event_count[0] == 2 and bufs.event_kind[0] == Emit.EVENT_KIND.slot_write)
selfc:free()

-- F64 pow is supported only through an explicit MoonOut primitive function
-- pointer parameter.  There is no hidden extern, helper, or fake boundary.
local pr = kernel_from({ {op="POW",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_f64"}, {slot=2,predicate="is_f64"} })
local stripped_params = {}
for _, p in ipairs(pr.params or {}) do if p.name ~= "lua_compile_prim_pow_f64" then stripped_params[#stripped_params + 1] = p end end
local stripped = T.MoonOut.Kernel(pr.kind, stripped_params, pr.normal_form, pr.contract, pr.projections)
local stripped_ok, stripped_errs = Validate.validate(stripped)
assert(not stripped_ok and table.concat(stripped_errs, "\n"):match("missing:primitive_param.lua_compile_prim_pow_f64"), "PowF64 must require explicit primitive parameter")
local pc = compile_kernel(pr, "test_moon_out_pow")
bufs = protocol_buffers()
tag = call_kernel(pc, pr, bufs, { slot_1_f64 = 2.0, slot_2_f64 = 5.0, lua_compile_prim_pow_f64 = pow_f64_callback() })
assert(tag == Emit.TAGS.return_ and math.abs(bufs.f64[0] - 32.0) < 0.0001)
pc:free()

local pkr = kernel_from({ {op="POWK",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_f64"}, {const=2,predicate="const_f64",value=3.0} })
local pkc = compile_kernel(pkr, "test_moon_out_powk")
bufs = protocol_buffers()
tag = call_kernel(pkc, pkr, bufs, { slot_1_f64 = 2.0, const_2_f64 = 3.0, lua_compile_prim_pow_f64 = pow_f64_callback() })
assert(tag == Emit.TAGS.return_ and math.abs(bufs.f64[0] - 8.0) < 0.0001)
pkc:free()

-- Backend support ledger over all 47 semantic opcode families.  Every current
-- NF family validates, emits, and Moonlift-compiles.
local semantic_cases = {
  {"MOVE", {{op="MOVE",pc=1,a=1,b=2}}, {}},
  {"LOADI", {{op="LOADI",pc=1,a=1,b=4}}, {}},
  {"LOADF", {{op="LOADF",pc=1,a=1,b=4}}, {}},
  {"LOADK", {{op="LOADK",pc=1,a=1,b=2}}, {}},
  {"LOADFALSE", {{op="LOADFALSE",pc=1,a=1}}, {}},
  {"LOADTRUE", {{op="LOADTRUE",pc=1,a=1}}, {}},
  {"LOADNIL", {{op="LOADNIL",pc=1,a=1,b=2}}, {}},
  {"ADDI", {{op="ADDI",pc=1,a=1,b=1,c=129,sc=2}}, {{slot=1,predicate="is_i64"}}},
  {"ADDK", {{op="ADDK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"SUBK", {{op="SUBK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"MULK", {{op="MULK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"MODK", {{op="MODK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"IDIVK", {{op="IDIVK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"BANDK", {{op="BANDK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"BORK", {{op="BORK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"BXORK", {{op="BXORK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{const=2,predicate="const_i64",value=2}}},
  {"SHLI", {{op="SHLI",pc=1,a=1,b=2,c=129,sc=2}}, {{slot=2,predicate="is_i64"}}},
  {"SHRI", {{op="SHRI",pc=1,a=1,b=1,c=129,sc=2}}, {{slot=1,predicate="is_i64"}}},
  {"ADD", {{op="ADD",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"SUB", {{op="SUB",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"MUL", {{op="MUL",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"MOD", {{op="MOD",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"IDIV", {{op="IDIV",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"BAND", {{op="BAND",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"BOR", {{op="BOR",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"BXOR", {{op="BXOR",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"SHL", {{op="SHL",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"SHR", {{op="SHR",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_i64"},{slot=2,predicate="is_i64"}}},
  {"UNM", {{op="UNM",pc=1,a=1,b=1}}, {{slot=1,predicate="is_i64"}}},
  {"BNOT", {{op="BNOT",pc=1,a=1,b=1}}, {{slot=1,predicate="is_i64"}}},
  {"DIVK", {{op="DIVK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_f64"},{const=2,predicate="const_f64",value=2.0}}},
  {"POWK", {{op="POWK",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_f64"},{const=2,predicate="const_f64",value=2.0}}},
  {"DIV", {{op="DIV",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_f64"},{slot=2,predicate="is_f64"}}},
  {"POW", {{op="POW",pc=1,a=1,b=1,c=2}}, {{slot=1,predicate="is_f64"},{slot=2,predicate="is_f64"}}},
  {"RETURN1", {{op="RETURN1",pc=1,a=1}}, {}},
  {"GETUPVAL", {{op="GETUPVAL",pc=1,a=1,b=0}}, {}},
  {"SETUPVAL", {{op="SETUPVAL",pc=1,a=1,b=0}}, {{slot=1,predicate="is_i64"}}},
  {"NOT", {{op="NOT",pc=1,a=1,b=2}}, {}},
  {"CONCAT", {{op="CONCAT",pc=1,a=1,b=2,c=3}}, {{slot=2,predicate="is_string"},{slot=3,predicate="is_string"}}},
  {"GETFIELD", {{op="GETFIELD",pc=1,a=1,b=2,c=3}}, field_obs(2, 1, 3)},
  {"GETTABUP", {{op="GETTABUP",pc=1,a=1,b=0,c=3}}, up_field_obs(0, 1, 3)},
  {"SETFIELD", {{op="SETFIELD",pc=1,a=2,b=3,c=1,k=false}}, append({{slot=1,predicate="is_i64"}}, field_obs(2, 1, 3, true))},
  {"SETTABUP", {{op="SETTABUP",pc=1,a=0,b=3,c=1,k=false}}, append({{slot=1,predicate="is_i64"}}, up_field_obs(0, 1, 3, true))},
  {"GETI", {{op="GETI",pc=1,a=1,b=2,c=5}}, array_obs(2, 1)},
  {"SETI", {{op="SETI",pc=1,a=2,b=5,c=1,k=false}}, append({{slot=1,predicate="is_i64"}}, array_obs(2, 1, true))},
  {"GETTABLE", {{op="GETTABLE",pc=1,a=1,b=2,c=3}}, append({{slot=3,predicate="is_i64"}}, array_obs(2, 1))},
  {"SETTABLE", {{op="SETTABLE",pc=1,a=2,b=3,c=1,k=false}}, append({{slot=1,predicate="is_i64"},{slot=3,predicate="is_i64"}}, array_obs(2, 1, true))},
  {"SELF", {{op="SELF",pc=1,a=1,b=2,c=3}}, field_obs(2, 1, 3)},
  {"TESTSET", {{op="TESTSET",pc=1,a=1,b=2,k=true}}, {}},
}

local ledger = { total = 0, validated = 0, emitted = 0, compiled = 0, structured_blocked = 0 }
for _, case in ipairs(semantic_cases) do
  local name, events, evidence, blocker = case[1], case[2], case[3], case[4]
  assert(Lower.decision_for(name) == "semantic", "ledger case is not semantic: " .. name)
  local k = kernel_from(events, evidence)
  ledger.total = ledger.total + 1
  local vok, verrs = Validate.validate(k)
  if blocker then
    assert(not vok and table.concat(verrs, "\n"):match(blocker), "expected structured blocker for " .. name)
    ledger.structured_blocked = ledger.structured_blocked + 1
  else
    assert(vok, name .. " failed MoonOut validation: " .. table.concat(verrs, "\n"))
    ledger.validated = ledger.validated + 1
    local comp = compile_kernel(k, "ledger_" .. name:lower())
    ledger.emitted = ledger.emitted + 1
    ledger.compiled = ledger.compiled + 1
    comp:free()
  end
end
assert(ledger.total == #semantic_cases, "MoonOut semantic ledger total mismatch: " .. tostring(ledger.total))
assert(ledger.compiled == #semantic_cases and ledger.structured_blocked == 0, "MoonOut ledger changed: compiled=" .. ledger.compiled .. " blocked=" .. ledger.structured_blocked)

print("ok - SpongeJIT LuaCompile MoonOut (semantic backend ledger " .. ledger.compiled .. "/" .. ledger.total .. " compiled, " .. ledger.structured_blocked .. " structured blockers)")
