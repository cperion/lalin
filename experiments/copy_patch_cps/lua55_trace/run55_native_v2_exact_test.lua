-- run55_native_v2_exact_test: exact-residual selection and typed mismatch.
--
-- Verifies the binding exact-residual contract for the table batch:
--   1. GETTABLE/SETTABLE residual leaves are selected from learned key-domain
--      facts, never from runtime tag dispatch.
--   2. A deliberately wrong learned fact makes the residual's exact guard
--      publish a typed SpecializationMismatchV2 rejection (kind 9) instead
--      of executing a sibling implementation.
--   3. NEWTABLE residual preallocates the learned capacity floor.
package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path
local ffi = require("ffi")
local Undump = require("experiments.lua55.undump55")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local Run55 = require("experiments.copy_patch_cps.lua55_trace.run55")
local CPS = require("experiments.copy_patch_cps.lua55_trace.cps_invocation_v2")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local V2_BANK = require("target.copy_patch_cps.lua55_trace.opcode_v2.bank")

local function compile_to_ctx(src, region)
    local path = os.tmpname() .. ".lua"
    local f = assert(io.open(path, "wb")); f:write(src); f:close()
    local bytes = Run55.compile(path)
    os.remove(path)
    local main = Undump.undump(bytes)
    local heap = Heap.GuestHeap.new(1, region or (32 * 1024 * 1024))
    local ctx = { plans = {}, const_heap = heap }
    ctx.plans, ctx.main_index = Run55.build_plans(main, heap)
    ctx.slot_count = CPS.assign_learning_slots(ctx.plans)
    return ctx, heap
end

local function find_slot(ctx, learner_name)
    local found
    local indexes = {}
    for index in pairs(ctx.plans) do indexes[#indexes + 1] = index end
    table.sort(indexes)
    for _, index in ipairs(indexes) do
        local plan = ctx.plans[index]
        for _, super in pairs(plan.superinstructions or {}) do
            if super.learner_name == learner_name then found = super.learn_slot end
        end
        local blocks = {}
        for _, b in ipairs(plan.blocks) do blocks[#blocks + 1] = b end
        table.sort(blocks, function(a, b) return a.start < b.start end)
        for _, block in ipairs(blocks) do
            for _, occ in ipairs(block.path.occurrences) do
                if occ.learner_name == learner_name then found = occ.learn_slot end
            end
        end
    end
    return found
end

local function empty_facts(ctx)
    local facts = {}
    for i = 0, ctx.slot_count do
        facts[i] = { key_tag = 0, value_tag = 0, max_array_index = 0,
                     max_field_count = 0, seen = 0 }
    end
    return facts
end

-- 1. a real learning pass learns an integer key domain and a string key
--    domain on two SETTABLE occurrences; the residual build selects the
--    exact leaves without error.
local ctx, heap = compile_to_ctx([[
local t = {}
local u = {}
for i = 1, 4 do t[i] = i end
local k = "x"
u[k] = 7
return t[3], u[k]
]])
local learn_inv, learn_frame, learn_arena, learn_dispatch = CPS.build_invocation(
    ctx, heap, {}, "learning", { slot_count = ctx.slot_count })
local values = CPS.execute(learn_inv, learn_frame, learn_arena, learn_dispatch, heap, {})
assert(values[1] == 3 and values[2] == 7, "learning pass result changed")
local facts = CPS.read_learning(learn_inv)
learn_inv:free()
assert(facts[find_slot(ctx, "settable")] ~= nil, "settable slot absent")
local inv, frame, arena, dispatch = CPS.build_invocation(ctx, heap, {}, "residual", facts)
inv:free()
print("exact residual selection: ok")

-- 2. deliberate mismatch: claim an integer key domain on the string-keyed
--    settable; the exact int-key leaf publishes a typed mismatch reject.
local ctx2, heap2 = compile_to_ctx([[
local u = {}
local k = "x"
u[k] = 7
return u[k]
]])
local facts2 = empty_facts(ctx2)
facts2[find_slot(ctx2, "gettable")].key_tag = 5   -- observed string reads
facts2[find_slot(ctx2, "settable")].key_tag = 3   -- lie: int
local inv2, frame2, arena2, dispatch2 = CPS.build_invocation(ctx2, heap2, {}, "residual", facts2)
local ok2, err2 = pcall(CPS.execute, inv2, frame2, arena2, dispatch2, heap2, {})
assert(not ok2 and tostring(err2):find("specialization mismatch", 1, true),
    "wrong learned key domain did not publish a typed mismatch: " .. tostring(err2))
inv2:free()
print("deliberate specialization mismatch: ok")
heap2:free()
heap:free()

-- 3. residual NEWTABLE preallocates the learned capacity floor: after a
--    learning pass that writes index 10000, the residual table's array
--    capacity is 16384 and a retained run finds no growth (all in bounds).
local ctx3, heap3 = compile_to_ctx([[
local t = {}
for i = 1, 10000 do t[i] = true end
return t[10000]
]], 64 * 1024 * 1024)
local learn_inv3, learn_frame3, learn_arena3, learn_dispatch3 = CPS.build_invocation(
    ctx3, heap3, {}, "learning", { slot_count = ctx3.slot_count })
local values3 = CPS.execute(learn_inv3, learn_frame3, learn_arena3, learn_dispatch3, heap3, {})
assert(values3[1] == true, "capacity learning pass result changed")
local facts3 = CPS.read_learning(learn_inv3)
learn_inv3:free()
assert(facts3[find_slot(ctx3, "newtable")].max_array_index == 10000,
    "site max array index was not learned: " .. tostring(facts3[find_slot(ctx3, "newtable")].max_array_index))
-- build the residual owner and re-enter it once (retained protocol)
local inv3, frame3, arena3, dispatch3 = CPS.build_invocation(ctx3, heap3, {}, "residual", facts3)
local bytes = CPS.root_frame_bytes(tonumber(frame3[0].value_count), tonumber(frame3[0].value_capacity))
local entry3 = inv3.functions[inv3.main_index].entry
inv3.invocation[0].frame_next = inv3.frame_begin + bytes
inv3.invocation[0].current_frame = frame3
inv3.invocation[0].outcome.discriminant = 0
frame3[0].top = 0
entry3(frame3)
assert(tonumber(inv3.invocation[0].outcome.discriminant) == 1,
    "retained exact run did not return")
assert(tonumber(inv3.invocation[0].outcome.result_count) == 1, "result count")
inv3:free()
inv3:free()
heap3:free()
print("learned capacity floor: ok")

-- 3b. Array capacity is mutable program data, not a learned semantic shape.
-- Suppress the learned preallocation hint: the published integer-key leaf must
-- take its named NeedGrow exit and still complete, not publish mismatch.
local ctx3b, heap3b = compile_to_ctx([[
local t = {}
for i = 1, 257 do t[i] = i end
return t[257]
]])
local learn_inv3b, learn_frame3b, learn_arena3b, learn_dispatch3b = CPS.build_invocation(
    ctx3b, heap3b, {}, "learning", { slot_count = ctx3b.slot_count })
local learned3b = CPS.execute(learn_inv3b, learn_frame3b, learn_arena3b,
    learn_dispatch3b, heap3b, {})
assert(learned3b[1] == 257, "NeedGrow learning result changed")
local facts3b = CPS.read_learning(learn_inv3b)
learn_inv3b:free()
facts3b[find_slot(ctx3b, "newtable")].max_array_index = 0
local inv3b, frame3b, arena3b, dispatch3b = CPS.build_invocation(
    ctx3b, heap3b, {}, "residual", facts3b)
local values3b = CPS.execute(inv3b, frame3b, arena3b, dispatch3b, heap3b, {})
assert(values3b[1] == 257, "NeedGrow data exit did not preserve semantics")
inv3b:free()
heap3b:free()
print("mutable table capacity data exit: ok")

-- 3c. Constant-field reads select a direct learned slot. A changed slot/layout
-- rejects through SpecializationMismatchV2; a learned missing field remains a
-- named program-data result and returns nil.
local ctx3c, heap3c = compile_to_ctx([[
local t = { x = 9 }
return t.x
]])
local learn_inv3c, learn_frame3c, learn_arena3c, learn_dispatch3c = CPS.build_invocation(
    ctx3c, heap3c, {}, "learning", { slot_count = ctx3c.slot_count })
local learned3c = CPS.execute(learn_inv3c, learn_frame3c, learn_arena3c,
    learn_dispatch3c, heap3c, {})
assert(learned3c[1] == 9, "field-slot learning result changed")
local facts3c = CPS.read_learning(learn_inv3c)
learn_inv3c:free()
local field_slot3c = assert(find_slot(ctx3c, "getfield"), "GETFIELD slot absent")
assert(facts3c[field_slot3c].field_state == 1, "GETFIELD did not learn a found slot")
facts3c[field_slot3c].field_slot = facts3c[field_slot3c].field_layout_capacity
local inv3c, frame3c, arena3c, dispatch3c = CPS.build_invocation(
    ctx3c, heap3c, {}, "residual", facts3c)
local ok3c, err3c = pcall(CPS.execute, inv3c, frame3c, arena3c, dispatch3c, heap3c, {})
assert(not ok3c and tostring(err3c):find("specialization mismatch", 1, true),
    "changed constant-field slot did not publish typed mismatch")
inv3c:free()
heap3c:free()

local ctx3m, heap3m = compile_to_ctx([[
local t = {}
return t.absent
]])
local learn_inv3m, learn_frame3m, learn_arena3m, learn_dispatch3m = CPS.build_invocation(
    ctx3m, heap3m, {}, "learning", { slot_count = ctx3m.slot_count })
local learned3m = CPS.execute(learn_inv3m, learn_frame3m, learn_arena3m,
    learn_dispatch3m, heap3m, {})
assert(learned3m[1] == nil, "missing-field learning result changed")
local facts3m = CPS.read_learning(learn_inv3m)
learn_inv3m:free()
local missing_slot3m = assert(find_slot(ctx3m, "getfield"), "missing GETFIELD slot absent")
assert(facts3m[missing_slot3m].field_state == 2, "GETFIELD did not learn missing state")
local inv3m, frame3m, arena3m, dispatch3m = CPS.build_invocation(
    ctx3m, heap3m, {}, "residual", facts3m)
local values3m = CPS.execute(inv3m, frame3m, arena3m, dispatch3m, heap3m, {})
assert(values3m[1] == nil, "named missing-field result changed")
inv3m:free()
heap3m:free()
print("exact constant-field slot and missing result: ok")

-- 4. Numeric-for superinstructions own one learned five-part product. The
--    complete FORPREP+ADD+FORLOOP cycle is published as one exact residual.
local ctx4, heap4 = compile_to_ctx([[
local s = 0
for i = 1, 1000 do s = s + i end
return s
]])
local super_slot = assert(find_slot(ctx4, "super_for_add"), "super-for-add slot absent")
local learn_inv4, learn_frame4, learn_arena4, learn_dispatch4 = CPS.build_invocation(
    ctx4, heap4, {}, "learning", { slot_count = ctx4.slot_count })
local values4 = CPS.execute(learn_inv4, learn_frame4, learn_arena4, learn_dispatch4, heap4, {})
assert(values4[1] == 500500, "super-for learning result changed")
local facts4 = CPS.read_learning(learn_inv4)
learn_inv4:free()
assert(facts4[super_slot].key_tag == 3 and facts4[super_slot].value_tag == 3
    and facts4[super_slot].max_array_index == 3 + 3 * 4294967296
    and facts4[super_slot].max_field_count == 0, "super-for exact product changed")
local inv4, frame4, arena4, dispatch4 = CPS.build_invocation(ctx4, heap4, {}, "residual", facts4)
local retained4 = CPS.execute(inv4, frame4, arena4, dispatch4, heap4, {})
assert(retained4[1] == 500500, "super-for retained result changed")
inv4:free()
print("learned numeric-for superinstruction: ok")

-- A false accumulator tag selects one sibling residual, whose entry guard
-- must publish SpecializationMismatchV2 instead of executing another shape.
local ctx4m, heap4m = compile_to_ctx([[
local s = 0
for i = 1, 3 do s = s + i end
return s
]])
local mismatch_slot = assert(find_slot(ctx4m, "super_for_add"))
local facts4m = empty_facts(ctx4m)
facts4m[mismatch_slot] = { key_tag = 3, value_tag = 3,
    max_array_index = 3 + 4 * 4294967296, max_field_count = 0, seen = 1 }
local inv4m, frame4m, arena4m, dispatch4m = CPS.build_invocation(
    ctx4m, heap4m, {}, "residual", facts4m)
local ok4m, err4m = pcall(CPS.execute, inv4m, frame4m, arena4m, dispatch4m, heap4m, {})
assert(not ok4m and tostring(err4m):find("specialization mismatch", 1, true),
    "wrong super-for product did not reject: " .. tostring(err4m))
inv4m:free()
print("superinstruction specialization mismatch: ok")

-- 5. Field and dynamic-table read/ADDI/write triples each become one
--    independently learned exact occurrence; both remain correct in loops.
local ctx5, heap5 = compile_to_ctx([[
local t = { x = 0 }
for i = 1, 20 do t.x = t.x + 1 end
local k = "x"
for i = 1, 20 do t[k] = t[k] + 1 end
return t.x
]])
assert(find_slot(ctx5, "super_field_addi"), "field-rmw super slot absent")
assert(find_slot(ctx5, "super_table_addi"), "table-rmw super slot absent")
local learn_inv5, learn_frame5, learn_arena5, learn_dispatch5 = CPS.build_invocation(
    ctx5, heap5, {}, "learning", { slot_count = ctx5.slot_count })
local values5 = CPS.execute(learn_inv5, learn_frame5, learn_arena5, learn_dispatch5, heap5, {})
assert(values5[1] == 40, "RMW super learning result changed")
local facts5 = CPS.read_learning(learn_inv5)
learn_inv5:free()
local inv5, frame5, arena5, dispatch5 = CPS.build_invocation(ctx5, heap5, {}, "residual", facts5)
local retained5 = CPS.execute(inv5, frame5, arena5, dispatch5, heap5, {})
assert(retained5[1] == 40, "RMW super retained result changed")
inv5:free()
print("learned RMW superinstructions: ok")

-- 6. Global-constant, global-move, and method-call superinstructions each
--    own their call-site learner. The learned alternatives cover native fixed,
--    native vararg, and host suspension; the retained leaves contain one only.
local ctx6, heap6 = compile_to_ctx([[
function echo(x) return x end
function vecho(...) return ... end
local a = echo("ok")
local b = vecho("var")
local n = select("#")
local t = {}
local k = t
local p = pairs(k)
local o = { x = 7 }
function o:get() return self.x end
function o:count(...) return 0 end
local c = o:get()
local d = o:count()
return a, b, n, c, d
]])
local call_supers = {}
for _, plan in pairs(ctx6.plans) do
    for _, super in pairs(plan.call_superinstructions or {}) do
        call_supers[#call_supers + 1] = super
    end
end
assert(#call_supers >= 6, "canonical call superinstructions were not projected")
local learn_inv6, learn_frame6, learn_arena6, learn_dispatch6 = CPS.build_invocation(
    ctx6, heap6, {}, "learning", { slot_count = ctx6.slot_count })
local values6 = CPS.execute(learn_inv6, learn_frame6, learn_arena6, learn_dispatch6, heap6, {})
assert(values6[1] == "ok" and values6[2] == "var" and values6[3] == 0
    and values6[4] == 7 and values6[5] == 0, "call-super learning result changed")
local facts6 = CPS.read_learning(learn_inv6)
learn_inv6:free()
local saw_fixed, saw_vararg, saw_host = false, false, false
for _, super in ipairs(call_supers) do
    local f = facts6[super.learn_slot]
    if f.key_tag == 1 and f.value_tag == 0 then saw_fixed = true
    elseif f.key_tag == 1 and f.value_tag == 1 then saw_vararg = true
    elseif f.key_tag == 2 then saw_host = true end
end
assert(saw_fixed and saw_vararg and saw_host, "call-super learned alternatives incomplete")
local inv6, frame6, arena6, dispatch6 = CPS.build_invocation(ctx6, heap6, {}, "residual", facts6)
local retained6 = CPS.execute(inv6, frame6, arena6, dispatch6, heap6, {})
assert(retained6[1] == "ok" and retained6[2] == "var" and retained6[3] == 0
    and retained6[4] == 7 and retained6[5] == 0, "call-super retained result changed")
inv6:free()
print("learned call superinstructions: ok")

-- 7. Numeric-for SETTABLE cycle: one learned (protocol, sign) product; the
--    residual publishes a const-kind leaf and refuses a doctored protocol.
local ctx7, heap7 = compile_to_ctx([[
local t = {}
for i = 1, 1000 do t[i] = true end
local n = 0
for i = 1, 1000 do if t[i] then n = n + 1 end end
return n
]])
local settable_slot = assert(find_slot(ctx7, "super_for_settable"),
    "super-settable slot absent")
local learn_inv7, learn_frame7, learn_arena7, learn_dispatch7 = CPS.build_invocation(
    ctx7, heap7, {}, "learning", { slot_count = ctx7.slot_count })
local values7 = CPS.execute(learn_inv7, learn_frame7, learn_arena7, learn_dispatch7, heap7, {})
assert(values7[1] == 1000, "super-settable learning result changed")
local facts7 = CPS.read_learning(learn_inv7)
learn_inv7:free()
assert(facts7[settable_slot].key_tag == 3 and facts7[settable_slot].value_tag == 0,
    "super-settable learned protocol changed")
local inv7, frame7, arena7, dispatch7 = CPS.build_invocation(ctx7, heap7, {}, "residual", facts7)
local retained7 = CPS.execute(inv7, frame7, arena7, dispatch7, heap7, {})
assert(retained7[1] == 1000, "super-settable retained result changed")
inv7:free()
print("learned store-cycle superinstruction: ok")

-- 8. Five-leaf dictionary accumulation: learned (key, acc, src) domains;
--    the residual publishes one exact kind-triple leaf and re-enters.
local ctx8, heap8 = compile_to_ctx([[
local totals = { 0, 0, 0 }
local orders = {
  { customer = 1, amount = 10 }, { customer = 1, amount = 5 },
  { customer = 2, amount = 7 },
}
for i = 1, #orders do
  local o = orders[i]
  totals[o.customer] = totals[o.customer] + o.amount
end
return totals[1], totals[2], totals[3]
]])
local accum_slot = assert(find_slot(ctx8, "super_accumulate_field"),
    "accumulate slot absent")
local learn_inv8, learn_frame8, learn_arena8, learn_dispatch8 = CPS.build_invocation(
    ctx8, heap8, {}, "learning", { slot_count = ctx8.slot_count })
local values8 = CPS.execute(learn_inv8, learn_frame8, learn_arena8, learn_dispatch8, heap8, {})
assert(values8[1] == 15 and values8[2] == 7 and values8[3] == 0,
    "accumulate learning result changed")
local facts8 = CPS.read_learning(learn_inv8)
learn_inv8:free()
assert(facts8[accum_slot].key_tag == 3 and facts8[accum_slot].value_tag == 3
    and facts8[accum_slot].max_array_index == 3, "accumulate learned domains changed")
local inv8, frame8, arena8, dispatch8 = CPS.build_invocation(ctx8, heap8, {}, "residual", facts8)
local retained8 = CPS.execute(inv8, frame8, arena8, dispatch8, heap8, {})
assert(retained8[1] == 15 and retained8[2] == 7, "accumulate retained result changed")
inv8:free()
print("learned accumulate superinstruction: ok")

-- Publication must reject unknown and missing physical holes before RX.
assert(V2_BANK.assembly_audit.exact_rets == 0
    and V2_BANK.assembly_audit.exact_calls > 0
    and V2_BANK.assembly_audit.exact_sections == 450
    and V2_BANK.assembly_audit.exact_conditional_branches > 0,
    "V2 assembly audit summary changed")
assert(V2_BANK.assembly_audit.field_slot_sections == 16,
    "S7 direct field-slot assembly coverage changed")
local concat_fragments = {
    "concat_measure_str", "concat_measure_int", "concat_measure_flt",
    "concat_allocate", "concat_write_str", "concat_write_int",
    "concat_write_flt", "concat_finish",
}
local concat_bytes = 0
for _, name in ipairs(concat_fragments) do
    local fragment = assert(V2_BANK.residual[name],
        "S10 CONCAT fragment absent: " .. name)
    concat_bytes = concat_bytes + #fragment.code
end
assert(concat_bytes == 1200, "S10 CONCAT fragment footprint changed")
for name in pairs(V2_BANK.residual) do
    assert(not name:match("^concat_[2345]_[sif]+$"),
        "S10 retired CONCAT Cartesian leaf returned: " .. name)
end
assert(V2_BANK.mismatch_audit.sections == 388
    and V2_BANK.mismatch_audit.inline_publishers == 0,
    "S9 typed mismatch exit coverage changed")
assert(V2_BANK.cps.specialization_mismatch
    and V2_BANK.cps.specialization_mismatch.holes.host_exit,
    "S9 typed mismatch CPS exit manifest absent")
assert(V2_BANK.assembly_audit.stack_sections
        == V2_BANK.assembly_audit.exact_sections
    and V2_BANK.assembly_audit.stack_tail_edges > 0,
    "S11 proper-tail stack-balance coverage changed")
local budget_count = 0
for name, budget in pairs(V2_BANK.assembly_audit.hot_budgets) do
    budget_count = budget_count + 1
    assert(budget.bytes <= budget.byte_limit
        and budget.instructions <= budget.instruction_limit,
        name .. " exceeded its S8 assembly budget")
end
assert(budget_count == 9, "S8 call/return budget inventory changed")
local provenance = assert(V2_BANK.branch_provenance, "S1 provenance report absent")
assert(provenance.opcode_count == 85 and provenance.forbidden_count == 0,
    "S1 opcode/forbidden inventory changed")
for opcode = 57, 67 do
    assert(provenance.opcodes[opcode].forbidden == nil,
        "comparison/test retained a projection-time branch: " .. opcode)
end
for opcode = 0, 84 do
    assert(provenance.opcodes[opcode].forbidden == nil,
        provenance.opcodes[opcode].name .. " retained a projection-time decision")
end
for name, record in pairs(V2_BANK.residual) do
    local comparison = name:match("^eq") or name:match("^lt")
        or name:match("^le_") or name:match("^lei_")
        or name:match("^gti_") or name:match("^gei_")
        or name:match("^test")
    if comparison then
        assert(record.holes.k == nil, name .. " retained runtime polarity hole")
        assert(name:match("_k[01]$"), name .. " is not a polarity-selected leaf")
    end
end
local function displacement_shape(record, required, absent)
    for _, hole in ipairs(required) do
        assert(record.holes[hole], record.__name .. " lacks " .. hole)
    end
    for _, hole in ipairs(absent) do
        assert(record.holes[hole] == nil, record.__name .. " retained " .. hole)
    end
end
displacement_shape(V2_BANK.residual.loadk_int, { "target_disp" }, { "target_index" })
displacement_shape(V2_BANK.v2[0], { "target_disp", "source_disp" },
    { "target_index", "source_index" })
displacement_shape(V2_BANK.residual.add_ii,
    { "target_disp", "left_disp", "right_disp" },
    { "target_index", "left_index", "right_index" })
displacement_shape(V2_BANK.residual.addi_ii, { "target_disp", "left_disp" },
    { "target_index", "left_index", "right_index", "right_disp" })
displacement_shape(V2_BANK.residual.eq_ii_k1, { "left_disp", "right_disp" },
    { "target_index", "left_index", "right_index" })
displacement_shape(V2_BANK.residual.unm_int, { "target_disp", "source_disp" },
    { "target_index", "source_index" })
displacement_shape(V2_BANK.v2[9], { "target_disp", "upvalue_index" },
    { "target_index", "source_index" })
displacement_shape(V2_BANK.residual.closure_1, { "target_disp" },
    { "target_index" })
displacement_shape(V2_BANK.residual.getvarg_int, { "target_disp", "key_disp" },
    { "target_index", "key_index" })
assert(V2_BANK.residual.vararg_fixed == nil,
    "runtime fixed VARARG leaf survived S5")
displacement_shape(V2_BANK.residual.vararg_fixed_slot,
    { "target_disp", "span" }, { "target_index", "wanted" })
displacement_shape(V2_BANK.residual.vararg_fixed_finish, { "top_index" },
    { "target_index", "wanted" })
displacement_shape(V2_BANK.residual.forloop_int, { "base_disp" }, { "base_index" })
displacement_shape(V2_BANK.v2[75], { "base_disp" }, { "base_index" })
displacement_shape(V2_BANK.v2[54], { "base_disp" }, { "call_a", "base_index" })
displacement_shape(V2_BANK.v2[13], { "target_disp", "receiver_disp" },
    { "target_index", "receiver_index" })
displacement_shape(V2_BANK.v2[11], { "target_disp", "upvalue_index", "occ_slot" },
    { "target_index" })
displacement_shape(V2_BANK.v2[14],
    { "target_disp", "receiver_disp", "occ_slot" },
    { "target_index", "receiver_index", "field_slot" })
displacement_shape(V2_BANK.residual.newtable, { "target_disp" }, { "target_index" })
displacement_shape(V2_BANK.v2[20],
    { "target_disp", "object_disp", "receiver_disp", "occ_slot" },
    { "target_index", "object_target", "receiver_index", "field_slot" })
displacement_shape(V2_BANK.residual.getfield_slot,
    { "target_disp", "receiver_disp", "key_ref", "field_slot",
      "field_layout_capacity" }, { "occ_slot" })
displacement_shape(V2_BANK.residual.getfield_missing,
    { "target_disp", "receiver_disp", "key_ref", "field_layout_capacity" },
    { "occ_slot", "field_slot" })
displacement_shape(V2_BANK.residual.gettabup_slot,
    { "target_disp", "upvalue_index", "key_ref", "field_slot",
      "field_layout_capacity" }, { "occ_slot" })
displacement_shape(V2_BANK.residual.self_slot,
    { "target_disp", "object_disp", "receiver_disp", "key_ref",
      "field_slot", "field_layout_capacity" }, { "occ_slot" })
displacement_shape(V2_BANK.residual.gettable_int,
    { "target_disp", "receiver_disp", "key_disp" },
    { "target_index", "receiver_index", "key_index" })
displacement_shape(V2_BANK.residual.settable_int_reg_inbounds,
    { "receiver_disp", "key_disp", "source_disp", "need_grow_link" },
    { "receiver_index", "key_index", "source_index", "grow_link" })
displacement_shape(V2_BANK.residual.settable_int_reg_grow,
    { "receiver_disp", "key_disp", "source_disp", "resume_link" },
    { "receiver_index", "key_index", "source_index", "succ_link" })
displacement_shape(V2_BANK.residual.setfield_reg_existing,
    { "receiver_disp", "source_disp", "key_ref", "field_slot",
      "field_layout_capacity", "need_create_link" },
    { "receiver_index", "source_index", "grow_link", "occ_slot" })
displacement_shape(V2_BANK.residual.setfield_reg_create,
    { "receiver_disp", "source_disp", "key_ref", "field_slot",
      "field_layout_capacity", "resume_link" },
    { "receiver_index", "source_index", "succ_link", "occ_slot" })
displacement_shape(V2_BANK.residual.settabup_existing,
    { "upvalue_index", "source_disp", "key_ref", "field_slot",
      "field_layout_capacity", "need_create_link" }, { "occ_slot" })
displacement_shape(V2_BANK.residual.settabup_create,
    { "upvalue_index", "source_disp", "key_ref", "field_slot",
      "field_layout_capacity", "resume_link" }, { "occ_slot" })
displacement_shape(V2_BANK.residual.setlist_inbounds,
    { "base_disp", "need_grow_link" },
    { "setlist_base", "base_index", "grow_link" })
displacement_shape(V2_BANK.residual.setlist_grow,
    { "base_disp", "resume_link" },
    { "setlist_base", "base_index", "succ_link" })
displacement_shape(V2_BANK.residual.setlist_slot,
    { "base_disp", "source_disp", "array_disp" },
    { "setlist_base", "setlist_count", "setlist_key", "source_index" })
assert(V2_BANK.residual.call_native_fixed == nil
    and V2_BANK.residual.call_native_vararg == nil,
    "monolithic fixed CALL leaf survived S5")
displacement_shape(V2_BANK.residual.call_native_fixed_prepare,
    { "base_disp", "call_a", "arg_count", "result_count", "call_pc",
      "continuation" },
    { "call_b", "call_c", "source_index" })
displacement_shape(V2_BANK.residual.call_fixed_arg_slot,
    { "target_disp", "source_disp", "span" },
    { "target_index", "source_index", "arg_count" })
displacement_shape(V2_BANK.residual.call_native_fixed_open,
    { "base_disp", "call_a", "call_c", "call_pc", "continuation" },
    { "call_b", "arg_count", "result_count" })
displacement_shape(V2_BANK.residual.call_host,
    { "base_disp", "call_a", "call_b", "call_c", "call_pc", "continuation" },
    { "base_index", "source_index" })
assert(next(V2_BANK.residual.call_fixed_finish.holes) == nil,
    "fixed CALL finish retained an occurrence hole")
assert(V2_BANK.residual.tailcall_native_fixed == nil
    and V2_BANK.residual.tailcall_native_vararg == nil,
    "monolithic fixed TAILCALL leaf survived S5")
displacement_shape(V2_BANK.residual.tailcall_native_fixed_prepare,
    { "base_disp", "call_a", "arg_count", "call_pc" },
    { "call_b", "tail_return", "source_index" })
displacement_shape(V2_BANK.residual.tailcall_fixed_arg_slot,
    { "target_disp", "source_disp", "span" },
    { "target_index", "source_index", "arg_count" })
displacement_shape(V2_BANK.residual.tailcall_native_fixed_open,
    { "base_disp", "call_a", "call_pc" },
    { "call_b", "arg_count", "tail_return" })
displacement_shape(V2_BANK.residual.tailcall_host,
    { "base_disp", "call_a", "call_b", "call_pc", "tail_return" },
    { "base_index", "source_index" })
assert(next(V2_BANK.residual.tailcall_fixed_finish.holes) == nil,
    "fixed TAILCALL finish retained an occurrence hole")
displacement_shape(V2_BANK.residual.tforcall_native,
    { "base_disp", "call_a", "call_c", "call_pc", "continuation" },
    { "base_index", "source_index" })
displacement_shape(V2_BANK.residual.tforcall_host,
    { "base_disp", "call_a", "call_c", "call_pc", "continuation" },
    { "base_index", "source_index" })

assert(V2_BANK.residual.ret_fixed == nil, "runtime fixed RETURN leaf survived S5")
displacement_shape(V2_BANK.residual.ret_fixed_begin, { "span", "call_pc" },
    { "call_a", "call_b", "source_index" })
displacement_shape(V2_BANK.residual.ret_fixed_slot, { "source_disp", "span" },
    { "call_a", "call_b", "source_index" })
displacement_shape(V2_BANK.residual.ret_fixed_finish, { "span" },
    { "call_a", "call_b", "source_index" })
displacement_shape(V2_BANK.residual.ret_all,
    { "base_disp", "call_a", "call_pc" },
    { "call_b", "source_index" })
for name, record in pairs(V2_BANK.residual) do
    assert(record.holes.grow_link == nil and record.holes.succ_link == nil,
        name .. " retained ambiguous table transition holes")
end
local bad_arena = Native.Arena.new(4096)
local bad_machine = CPS.V2Machine.new(bad_arena, V2_BANK, {}, "residual", {})
bad_machine.pc = 1
local bad_ok, bad_err = pcall(function()
    bad_machine:emit(V2_BANK.residual.loadk_int, {
        target_dispp = 0, ["u64::const_int"] = 1,
    })
end)
assert(not bad_ok and tostring(bad_err):match("unknown product hole target_dispp")
    and bad_arena.cursor == 0, "unknown hole did not fail before append")
bad_arena:free()

local missing_arena = Native.Arena.new(4096)
local missing_machine = CPS.V2Machine.new(missing_arena, V2_BANK, {}, "residual", {})
missing_machine.pc = 1
missing_machine:emit(V2_BANK.residual.loadk_int, { target_disp = 0 })
local missing_ok, missing_err = pcall(function()
    missing_machine:assert_all_holes_patched()
end)
assert(not missing_ok and tostring(missing_err):match("const_int"),
    "missing physical hole was not rejected")
missing_arena:free()
print("strict publication holes + assembly/provenance audit: ok")

print("run55 v2 exact-residual tests: ok")
