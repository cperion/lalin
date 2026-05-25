-- Moonlift Lua VM JIT — product-level regions.
--
-- These regions establish the control protocols for the real JIT pipeline.
-- They are intentionally small structural boundaries; later implementation
-- fills in allocation/recording details behind the same continuations.

local moon = require("moonlift")
local host = require("moonlift.host")
local C = require("experiments.lua_interpreter_vm.src.jit.constants")
require("experiments.lua_interpreter_vm.src.jit.products")

local V = {}
for k, v in pairs(C.Effect) do V["EFF_" .. k] = moon.int(v) end
for k, v in pairs(C.ProjectionReq) do V["PROJ_" .. k] = moon.int(v) end
for k, v in pairs(C.BoundaryReq) do V["BOUND_" .. k] = moon.int(v) end
for k, v in pairs(C.TraceStatus) do V["TRACE_STATUS_" .. k] = moon.int(v) end

local R = host.region(V)

local classify_effect = R [[
region classify_effect(e: Effect;
                       pure: cont(), needs_boundary: cont(flags: u64),
                       needs_projection: cont(flags: u64))
entry start()
    var proj: u64 = 0
    var bound: u64 = 0

    if (e.flags & as(u64, @{EFF_MAY_ALLOC})) ~= 0 then
        proj = proj | as(u64, @{PROJ_ROOTS})
        bound = bound | as(u64, @{BOUND_ALLOCATOR})
    end
    if (e.flags & as(u64, @{EFF_MAY_GC})) ~= 0 then
        proj = proj | as(u64, @{PROJ_ROOTS})
        bound = bound | as(u64, @{BOUND_GC_SAFEPOINT})
    end
    if (e.flags & as(u64, @{EFF_MAY_CALL_LUA})) ~= 0 then
        proj = proj | as(u64, @{PROJ_ROOTS}) | as(u64, @{PROJ_RESUME})
        bound = bound | as(u64, @{BOUND_LUA_CALL})
    end
    if (e.flags & as(u64, @{EFF_MAY_YIELD})) ~= 0 then
        proj = proj | as(u64, @{PROJ_RESUME})
        bound = bound | as(u64, @{BOUND_LUA_CALL})
    end
    if (e.flags & as(u64, @{EFF_MAY_RUN_HOOK})) ~= 0 then
        proj = proj | as(u64, @{PROJ_ROOTS}) | as(u64, @{PROJ_RESUME}) | as(u64, @{PROJ_DEBUG})
        bound = bound | as(u64, @{BOUND_LUA_CALL})
    end
    if (e.flags & as(u64, @{EFF_MAY_CALL_METAMETHOD})) ~= 0 then
        proj = proj | as(u64, @{PROJ_ROOTS}) | as(u64, @{PROJ_RESUME})
        bound = bound | as(u64, @{BOUND_METAMETHOD})
    end
    if (e.flags & as(u64, @{EFF_MAY_THROW})) ~= 0 then
        proj = proj | as(u64, @{PROJ_ERROR})
        bound = bound | as(u64, @{BOUND_VM_RETURN})
    end
    if (e.flags & as(u64, @{EFF_MAY_OBSERVE_STACK})) ~= 0 then
        proj = proj | as(u64, @{PROJ_INTERPRETER})
        bound = bound | as(u64, @{BOUND_VM_RETURN})
    end
    if (e.flags & as(u64, @{EFF_MAY_NEED_BARRIER})) ~= 0 then
        proj = proj | as(u64, @{PROJ_BARRIER})
    end
    if (e.flags & as(u64, @{EFF_MAY_BRANCH})) ~= 0 then
        proj = proj | as(u64, @{PROJ_TARGET})
    end

    if bound ~= 0 then jump needs_boundary(flags = bound) end
    if proj ~= 0 then jump needs_projection(flags = proj) end
    jump pure()
end
end
]]

local validate_stencil_plan = R [[
region validate_stencil_plan(plan: ptr(StencilPlan);
                             ok: cont(), empty: cont(), invalid: cont(code: i32))
entry start()
    if plan == nil then jump invalid(code = 1) end
    if plan.node_count == 0 then jump empty() end
    if plan.estimated_size == 0 then jump invalid(code = 2) end
    jump ok()
end
end
]]

local require_projection_for_effect = R [[
region require_projection_for_effect(e: Effect;
                                     none: cont(), required: cont(flags: u64))
entry start()
    var flags: u64 = 0
    if (e.flags & as(u64, @{EFF_MAY_ALLOC})) ~= 0 or (e.flags & as(u64, @{EFF_MAY_GC})) ~= 0 then
        flags = flags | as(u64, @{PROJ_ROOTS})
    end
    if (e.flags & as(u64, @{EFF_MAY_CALL_LUA})) ~= 0 or (e.flags & as(u64, @{EFF_MAY_CALL_METAMETHOD})) ~= 0 then
        flags = flags | as(u64, @{PROJ_ROOTS}) | as(u64, @{PROJ_RESUME})
    end
    if (e.flags & as(u64, @{EFF_MAY_YIELD})) ~= 0 then
        flags = flags | as(u64, @{PROJ_RESUME})
    end
    if (e.flags & as(u64, @{EFF_MAY_RUN_HOOK})) ~= 0 then
        flags = flags | as(u64, @{PROJ_ROOTS}) | as(u64, @{PROJ_RESUME}) | as(u64, @{PROJ_DEBUG})
    end
    if (e.flags & as(u64, @{EFF_MAY_THROW})) ~= 0 then
        flags = flags | as(u64, @{PROJ_ERROR})
    end
    if (e.flags & as(u64, @{EFF_MAY_OBSERVE_STACK})) ~= 0 then
        flags = flags | as(u64, @{PROJ_INTERPRETER})
    end
    if (e.flags & as(u64, @{EFF_MAY_NEED_BARRIER})) ~= 0 then
        flags = flags | as(u64, @{PROJ_BARRIER})
    end
    if (e.flags & as(u64, @{EFF_MAY_BRANCH})) ~= 0 then
        flags = flags | as(u64, @{PROJ_TARGET})
    end
    if flags == 0 then jump none() end
    jump required(flags = flags)
end
end
]]

local try_enter_jit = R [[
region try_enter_jit(ent: ptr(EntryCell), L: ptr(LuaThread), frame: ptr(Frame);
                     entered_jit: cont(nres: i32, pc: index),
                     use_interpreter: cont())
block start()
    if ent == nil then jump use_interpreter() end
    let code: ptr(u8) = ent.target
    if code == nil then jump use_interpreter() end
    -- Code is available: attempt JIT entry
    -- The actual call to code happens in native implementation
    -- For MVP: pass control to entered_jit with result
    -- Real implementation will invoke code and handle outcome
    jump entered_jit(nres = 0, pc = frame.pc)
end
end
]]

local record_trace_ops = R [[
region record_trace_ops(rec: ptr(TraceRecord), anchor: ptr(TraceAnchor);
                        recording: cont(),
                        no_capacity: cont())
block start()
    if rec == nil or anchor == nil then jump no_capacity() end
    if rec.op_count == 0 then jump no_capacity() end
    anchor.status = as(u8, @{TRACE_STATUS_RECORDING})
    jump recording()
end
end
]]

local trace_record_guard_check = R [[
region trace_record_guard_check(rec: ptr(TraceRecord);
                                has_guards: cont(),
                                no_guards: cont())
block start()
    if rec == nil then jump no_guards() end
    if rec.guard_count == 0 then jump no_guards() end
    if rec.snapshot_count == 0 then jump no_guards() end
    jump has_guards()
end
end
]]

local materialize_stencil_plan = R [[
region materialize_stencil_plan(plan: ptr(StencilPlan), slab: ptr(CodeSlab);
                                materialized: cont(code: ptr(u8)),
                                no_space: cont(),
                                invalid_plan: cont())
block start()
    if plan == nil or slab == nil then jump invalid_plan() end
    if plan.node_count == 0 then jump invalid_plan() end
    if plan.estimated_size == 0 then jump invalid_plan() end
    if slab.used + plan.estimated_size > slab.size then jump no_space() end
    let code: ptr(u8) = slab.rw + slab.used
    jump materialized(code = code)
end
end
]]

local link_executable_unit = R [[
region link_executable_unit(unit: ptr(ExecutableUnit), ent: ptr(EntryCell),
                            code: ptr(u8);
                            linked: cont(),
                            invalid: cont())
block start()
    if unit == nil or ent == nil or code == nil then jump invalid() end
    unit.code = code
    ent.target = code
    ent.unit = as(ptr(u8), unit)
    jump linked()
end
end
]]

return {
    classify_effect = classify_effect,
    validate_stencil_plan = validate_stencil_plan,
    require_projection_for_effect = require_projection_for_effect,
    try_enter_jit = try_enter_jit,
    record_trace_ops = record_trace_ops,
    trace_record_guard_check = trace_record_guard_check,
    materialize_stencil_plan = materialize_stencil_plan,
    link_executable_unit = link_executable_unit,
}
