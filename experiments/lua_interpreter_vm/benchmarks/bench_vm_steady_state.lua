-- Steady-state VM benchmarks.
--
-- This benchmark avoids the misleading "one vm_resume per two bytecodes" shape.
-- It builds Proto objects with many cheap bytecodes followed by one RETURN, so
-- vm_resume/RETURN teardown is amortized across a long dispatch run.
--
-- Run from repo root:
--   luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
--
-- Optional knobs:
--   MOONLIFT_VM_STEPS=10000 MOONLIFT_VM_RUNS=1000 luajit ...

local ffi = require("ffi")

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local vm = require("experiments.lua_interpreter_vm.src.init")
local const = vm.const

ffi.cdef [[
    void* moonlift_scratch_raw(int slot, int elem_size, int count);
]]

local function load_moonlift_lib()
    for _, name in ipairs({ "./target/release/libmoonlift.so", "./target/debug/libmoonlift.so", "libmoonlift" }) do
        local ok, lib = pcall(ffi.load, name)
        if ok then return lib end
    end
    error("could not load libmoonlift; build with: cargo build --release")
end

local libmoon = load_moonlift_lib()
local scratch_raw = libmoon.moonlift_scratch_raw

-- Must match experiments/lua_interpreter_vm/src/products.lua exactly.
ffi.cdef [[
    typedef struct { void* next; uint8_t tt; uint8_t marked; } GCHeader;
    typedef struct { uint32_t tag; uint32_t aux; uint64_t bits; } Value;
    typedef struct { uint16_t op; uint16_t a; uint16_t b; uint16_t c; uint32_t bx; int32_t sbx; } Instr;
    typedef struct {
        GCHeader gc;
        void* code; uint64_t code_len;
        void* constants; uint64_t constants_len;
        void** children; uint64_t children_len;
        int32_t* lineinfo; uint64_t lineinfo_len;
        void* locvars; uint64_t locvars_len;
        void* upvals; uint64_t upvals_len;
        void* source;
        int32_t linedefined; int32_t lastlinedefined;
        uint8_t numparams; uint8_t is_vararg; uint16_t maxstack;
    } Proto;
    typedef struct {
        GCHeader gc;
        void* env; Proto* proto;
        void** upvals; uint8_t nupvals;
    } LClosure;
    typedef struct {
        Value closure; uint64_t base; uint64_t top; uint64_t pc;
        int32_t wanted; int32_t tailcalls;
        uint16_t resume_mode;
        uint16_t resume_a; uint16_t resume_b; uint16_t resume_c;
        uint64_t resume_pc; uint64_t resume_base; Value resume_value;
    } Frame;
    typedef struct {
        GCHeader gc; uint8_t status;
        Value* stack; uint64_t stack_size; uint64_t top;
        Frame* frames; uint64_t frame_count; uint64_t frame_cap;
        void* open_upvals; void* protected_top;
        void* global; Value err_value;
        uint8_t hookmask; uint8_t allowhook;
        int32_t hookcount; int32_t basehookcount; Value hook;
    } LuaThread;
    typedef struct { void* allocator; Value registry; void* mainthread; } GlobalState;
]]

local function scratch(slot, elem_size, count, ctype)
    return ffi.cast(ctype or "uint8_t*", scratch_raw(slot, elem_size, count))
end

local function double_bits(x)
    local u = ffi.new("union { double d; uint64_t u; }")
    u.d = x
    return u.u
end

local function bits_double(x)
    local u = ffi.new("union { double d; uint64_t u; }")
    u.u = x
    return u.d
end

local BITS_42 = double_bits(42.0)
local BITS_99 = double_bits(99.0)

local STACK_N = 64
local NEXT_SLOT = 20

local function fresh_slots(n)
    local base = NEXT_SLOT
    NEXT_SLOT = NEXT_SLOT + n
    return base
end

local function clear_stack(stack)
    for i = 0, STACK_N - 1 do
        stack[i].tag = const.Tag.NIL
        stack[i].aux = 0
        stack[i].bits = 0
    end
end

local function make_thread(name, steps, fill_code, maxstack)
    local slot = fresh_slots(8)
    local consts = scratch(slot + 0, 16, 2, "Value*")
    consts[0].tag = const.Tag.NUM; consts[0].aux = 0; consts[0].bits = BITS_42
    consts[1].tag = const.Tag.NUM; consts[1].aux = 0; consts[1].bits = BITS_99

    local code = scratch(slot + 1, 16, steps + 1, "Instr*")
    for i = 0, steps do
        code[i].op = 0; code[i].a = 0; code[i].b = 0; code[i].c = 0; code[i].bx = 0; code[i].sbx = 0
    end
    fill_code(code, steps)

    local proto = scratch(slot + 2, 1, 256, "Proto*")
    proto.code = ffi.cast("void*", code); proto.code_len = steps + 1
    proto.constants = ffi.cast("void*", consts); proto.constants_len = 2
    proto.children = nil; proto.children_len = 0
    proto.lineinfo = nil; proto.lineinfo_len = 0
    proto.locvars = nil; proto.locvars_len = 0
    proto.upvals = nil; proto.upvals_len = 0
    proto.source = nil
    proto.linedefined = -1; proto.lastlinedefined = -1
    proto.numparams = 0; proto.is_vararg = 0; proto.maxstack = maxstack or 2

    local closure = scratch(slot + 3, 1, 64, "LClosure*")
    closure.env = nil; closure.proto = proto; closure.upvals = nil; closure.nupvals = 0

    local stack = scratch(slot + 4, 16, STACK_N, "Value*")
    clear_stack(stack)
    stack[0].tag = const.Tag.LCLOSURE; stack[0].aux = 0; stack[0].bits = ffi.cast("uint64_t", closure)
    stack[1].tag = const.Tag.NUM; stack[1].aux = 0; stack[1].bits = BITS_42
    stack[2].tag = const.Tag.NUM; stack[2].aux = 0; stack[2].bits = BITS_42

    local frames = scratch(slot + 5, 1, 512, "Frame*")
    frames[0].closure.tag = const.Tag.LCLOSURE
    frames[0].closure.aux = 0
    frames[0].closure.bits = ffi.cast("uint64_t", closure)
    frames[0].base = 1; frames[0].top = 1; frames[0].pc = 0
    frames[0].wanted = 1; frames[0].tailcalls = 0
    frames[0].resume_mode = const.Resume.NORMAL
    frames[0].resume_a = 0; frames[0].resume_b = 0; frames[0].resume_c = 0
    frames[0].resume_pc = 0; frames[0].resume_base = 0
    frames[0].resume_value.tag = const.Tag.NIL; frames[0].resume_value.aux = 0; frames[0].resume_value.bits = 0

    local gstate = scratch(slot + 6, 1, 64, "GlobalState*")
    gstate.allocator = nil; gstate.registry.tag = const.Tag.NIL; gstate.registry.aux = 0; gstate.registry.bits = 0

    local thread = scratch(slot + 7, 1, 256, "LuaThread*")
    thread.status = const.Status.OK
    thread.stack = stack; thread.stack_size = STACK_N; thread.top = 1
    thread.frames = frames; thread.frame_count = 1; thread.frame_cap = 8
    thread.open_upvals = nil; thread.protected_top = nil; thread.global = gstate
    thread.err_value.tag = const.Tag.NIL; thread.err_value.aux = 0; thread.err_value.bits = 0
    thread.hookmask = 0; thread.allowhook = 0; thread.hookcount = 0; thread.basehookcount = 0
    thread.hook.tag = const.Tag.NIL; thread.hook.aux = 0; thread.hook.bits = 0
    gstate.mainthread = thread

    return { name = name, steps = steps, dispatches = steps + 1, thread = thread, stack = stack, frames = frames }
end

local function reset(case)
    local thread, stack, frames = case.thread, case.stack, case.frames
    thread.status = const.Status.OK
    thread.top = 1
    thread.frame_count = 1
    frames[0].base = 1
    frames[0].top = 1
    frames[0].pc = 0
    frames[0].wanted = 1
    frames[0].resume_mode = const.Resume.NORMAL
    stack[1].tag = const.Tag.NUM
    stack[1].aux = 0
    stack[1].bits = BITS_42
    stack[2].tag = const.Tag.NUM
    stack[2].aux = 0
    stack[2].bits = BITS_42
end

local function fill_return_only(code, _steps)
    code[0].op = const.Op.RETURN
    code[0].a = 0
    code[0].b = 2
end

local function fill_loadk(code, steps)
    for i = 0, steps - 1 do
        code[i].op = const.Op.LOADK
        code[i].a = 0
        code[i].bx = 0
    end
    code[steps].op = const.Op.RETURN
    code[steps].a = 0
    code[steps].b = 2
end

local function fill_move_self(code, steps)
    for i = 0, steps - 1 do
        code[i].op = const.Op.MOVE
        code[i].a = 0
        code[i].b = 0
    end
    code[steps].op = const.Op.RETURN
    code[steps].a = 0
    code[steps].b = 2
end

print("Compiling vm_resume runner...")
local runner = moon.func { vm_resume = vm.vm_loop.vm_resume } [[
run(L: ptr(LuaThread), nargs: i32) -> i32
    return region -> i32
    entry start()
        emit @{vm_resume}(L, nargs;
            ok = done,
            yielded = did_yield,
            runtime_error = did_error,
            oom = did_oom)
    end
    block done(nres: i32) return nres end
    block did_yield(nres: i32) return -100 - nres end
    block did_error(code: i32) return -200 - code end
    block did_oom() return -999 end
    end
end
]]
local run = runner:compile()

local STEPS = tonumber(os.getenv("MOONLIFT_VM_STEPS")) or 10000
local RUNS = tonumber(os.getenv("MOONLIFT_VM_RUNS")) or 1000
local RETURN_RUNS = tonumber(os.getenv("MOONLIFT_VM_RETURN_RUNS")) or math.max(RUNS, 100000)

local cases = {
    make_thread("RETURN only", 0, fill_return_only, 2),
    make_thread("LOADK x" .. STEPS .. " + RETURN", STEPS, fill_loadk, 2),
    make_thread("MOVE R0,R0 x" .. STEPS .. " + RETURN", STEPS, fill_move_self, 2),
}

local function verify(case)
    reset(case)
    local nres = run(case.thread, 0)
    assert(nres == 1, case.name .. ": expected nres=1, got " .. tostring(nres))
    assert(case.stack[1].tag == const.Tag.NUM or case.stack[1].tag == const.Tag.TRUE,
        case.name .. ": unexpected result tag " .. tostring(case.stack[1].tag))
    if case.stack[1].tag == const.Tag.NUM then
        local v = bits_double(case.stack[1].bits)
        assert(math.abs(v - 42.0) < 0.001, case.name .. ": expected numeric 42, got " .. tostring(v))
    end
    reset(case)
end

local function bench(case, runs)
    verify(case)
    local t0 = os.clock()
    for _ = 1, runs do
        run(case.thread, 0)
        reset(case)
    end
    local elapsed = os.clock() - t0
    return elapsed
end

print(string.format("\nConfig: STEPS=%d RUNS=%d RETURN_RUNS=%d", STEPS, RUNS, RETURN_RUNS))
print("Each long case executes STEPS cheap bytecodes plus one RETURN per vm_resume.\n")

local return_elapsed = bench(cases[1], RETURN_RUNS)
local return_ns_per_resume = (return_elapsed / RETURN_RUNS) * 1e9
print(string.format("%-34s %10d runs  %8.4fs  %8.2f ns/resume",
    cases[1].name, RETURN_RUNS, return_elapsed, return_ns_per_resume))

for i = 2, #cases do
    local case = cases[i]
    local elapsed = bench(case, RUNS)
    local total_dispatches = RUNS * case.dispatches
    local naive_ns = (elapsed / total_dispatches) * 1e9
    local ns_per_resume = (elapsed / RUNS) * 1e9
    local adjusted_hot_ns = math.max(0, (ns_per_resume - return_ns_per_resume) / case.steps)
    print(string.format("%-34s %10d runs  %8.4fs", case.name, RUNS, elapsed))
    print(string.format("  total dispatches: %-12d naive: %8.2f ns/dispatch", total_dispatches, naive_ns))
    print(string.format("  resume cost:      %8.2f ns/run", ns_per_resume))
    print(string.format("  adjusted hot op:  %8.2f ns/op  (subtracts RETURN-only resume/teardown)", adjusted_hot_ns))
end

runner:free()
