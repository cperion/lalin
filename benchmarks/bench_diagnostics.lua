-- Diagnostics for the benchmark kernels.
-- Prints schedule, backend fact summaries, command counts, and optional disassembly.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Pipeline = require("moonlift.frontend_pipeline")
local BackInspect = require("moonlift.back_inspect")
local BackDiagnostics = require("moonlift.back_diagnostics")

local SRC = [[
func sum_i32(xs: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

func dot_i32(a: ptr(i32), b: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32): i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

func scale_i32(dst: ptr(i32), xs: ptr(i32), k: i32, n: i32): i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end
]]

local T = pvm.context()
A2.Define(T)
local P = Pipeline.Define(T)
local BI = BackInspect.Define(T)
local BD = BackDiagnostics.Define(T)
local B = T.MoonBack
local Kernel = T.MoonKernel

local result = P.parse_and_lower(SRC, { site = "bench_diagnostics" })
local program = result.program
local report = result.back_report
assert(#report.issues == 0)
for _, func_plan in ipairs(result.kernel_plan and result.kernel_plan.funcs or {}) do
    local plan = func_plan.plan
    if pvm.classof(plan) == Kernel.KernelPlanned and pvm.classof(plan.schedule) == Kernel.KernelScheduleVector then
        local sched = plan.schedule
        io.write(string.format("kernel_schedule %s lanes=%d unroll=%d interleave=%d tail=%s\n",
            func_plan.func.text,
            sched.shape.lanes,
            sched.unroll,
            sched.interleave,
            sched.tail.kind))
    end
end

local decisions = {}

local inspection = BI.inspect(program)
for i = 1, #inspection.command_counts do
    local c = inspection.command_counts[i]
    io.write(string.format("cmd %-24s %d\n", c.command_kind, c.count))
end

local align, deref, traps = {}, {}, {}
for i = 1, #inspection.memory do
    local m = inspection.memory[i]
    align[m.alignment.kind] = (align[m.alignment.kind] or 0) + 1
    deref[m.dereference.kind] = (deref[m.dereference.kind] or 0) + 1
    traps[m.trap.kind] = (traps[m.trap.kind] or 0) + 1
end
for k, v in pairs(align) do io.write(string.format("memory_alignment %-20s %d\n", k, v)) end
for k, v in pairs(deref) do io.write(string.format("memory_dereference %-18s %d\n", k, v)) end
for k, v in pairs(traps) do io.write(string.format("memory_trap %-25s %d\n", k, v)) end
io.write(string.format("aliases %d\n", #inspection.aliases))
io.write(string.format("addresses %d\n", #inspection.addresses))
io.write(string.format("pointer_offsets %d\n", #inspection.pointer_offsets))

if os.getenv("MOONLIFT_BENCH_DIAGNOSTICS_DISASM") == "1" then
    local funcs = { B.BackFuncId("sum_i32"), B.BackFuncId("dot_i32"), B.BackFuncId("add_i32"), B.BackFuncId("scale_i32") }
    local diag = BD.diagnostics(program, decisions, funcs, { bytes = tonumber(os.getenv("MOONLIFT_BENCH_DISASM_BYTES") or "220") })
    for i = 1, #diag.disassembly do
        io.write(string.format("disasm %s\n%s\n", diag.disassembly[i].func.text, diag.disassembly[i].text))
    end
end
