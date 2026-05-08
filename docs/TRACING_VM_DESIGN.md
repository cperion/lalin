-- Tracing JIT Architecture — NO LUA IN THE HOT PATH
-- ==================================================
--
-- Two execution tiers:
--   TIER 0 (compile-time, Lua):    ASDL types, schema, splice helpers
--   TIER 1 (runtime, Moonlift→C):  VM interpreter, tracer, optimizers, codegen
--
-- Lua runs ONLY during metaprogramming/build. The compiled binary is
-- pure C — no lua_State, no GC, no interpreted dispatch.

-- === TIER 0: Lua metaprogramming ===
-- These run once during compilation to define types and generate code.
-- They produce MoonTree values (ASDL constructors), never Lua tables.

asdl IR :: {
    IRType :: u8  { INT=0, NUM=1, PTR=2, NIL=3, BOOL=4 }
    IROp   :: u16 {
        KINT=0, KNULL=1, KPRI=2,
        BASE=10, LOOP=11,
        SLOAD=20, SSTORE=21, ALOAD=22, ASTORE=23, HLOAD=24, HSTORE=25,
        ADD=30, SUB=31, MUL=32, DIV=33, MOD=34, NEG=35,
        LT=40, LE=41, GT=42, GE=43, EQ=44, NE=45,
        GUARD=50, GREF=51, GINT=52, GNUM=53,
        RET=62, CALL=70,
    }
    IRIns :: { op:IROp, ty:IRType, lhs:u16, rhs:u16, aux:i32 }
    Snapshot :: { iref:u16, slots:[]u16 }
    Trace :: { nconsts:u16, consts:[]IRIns, insns:[]IRIns, snaps:[]Snapshot }
}

-- === TIER 1: Moonlit VM (compiled to C, zero Lua at runtime) ===

-- Value representation: tagged union, no GC pointers at this level.
-- We use NaN-boxing in the C backend.
asdl Value :: {
    Int  : i64,
    Num  : f64,
    Bool : bool,
    Nil  : {},
    -- skip strings/tables for now — they need GC, scope later
}

-- The bytecode is a flat array of packed u32. Opcode in top 8 bits.
-- This is the ONLY data structure the hot loop touches.
type BC = u32
const BC_ADD  = 0x01
const BC_SUB  = 0x02
const BC_MUL  = 0x03
const BC_LT   = 0x10
const BC_GT   = 0x11
const BC_EQ   = 0x12
const BC_JMP  = 0x20
const BC_JT   = 0x21
const BC_JF   = 0x22
const BC_RET  = 0x30
const BC_LOOP = 0x40   -- back-edge marker
fun bc_op(bc:BC) -> u8 = (bc >> 24) & 0xFF
fun bc_a(bc:BC)  -> u8 = (bc >> 16) & 0xFF
fun bc_b(bc:BC)  -> u8 = (bc >> 8)  & 0xFF
fun bc_c(bc:BC)  -> u8 = bc & 0xFF

-- The VM state: everything is a fixed-size inline array. No heap allocs.
const STACK_SIZE = 256
const MAX_TRACES = 64
const HOT_THRESHOLD = 3

asdl VM :: {
    stack    : [256]Value,
    sp       : u16,           -- stack pointer
    bc       : []BC,          -- current bytecode (borrowed from Func)
    pc       : u16,           -- instruction pointer
    hotcount : [256]u16,      -- per-back-edge counters
    ntraces  : u16,           -- number of compiled traces
    traces   : [64]*Trace,    -- trace table
}

-- === TRACER (Moonlift, compiled to C) ===

-- The tracer has exactly two modes. No virtual dispatch, no closures.
-- When recording, it appends to a flat IR buffer (like LuaJIT's J->cur).

const MAX_IR = 512

asdl Tracer :: {
    -- IR buffer: flat array. [0..nconsts) = consts, [nconsts..ninsns) = insns
    ir_buf   : [512]IRIns,
    nconsts  : u16,
    ninsns   : u16,
    -- Stack slot → IR reference. slot_map[0] = ref of SLOAD for slot 0.
    slot_map : [32]u16,
    base_ref : u16,
}

-- Append a constant and return its ref (index into consts).
fun emit_const(tr:&Tracer, op:IROp, ty:IRType, aux:i32) -> u16
    slot tr.ir_buf[tr.nconsts] = IRIns{op=op, ty=ty, lhs=0, rhs=0, aux=aux}
    tr.nconsts = tr.nconsts + 1
    return tr.nconsts - 1
end

-- Append an instruction and return its ref (nconsts + index into insns).
fun emit_insn(tr:&Tracer, op:IROp, ty:IRType, lhs:u16, rhs:u16, aux:i32) -> u16
    let idx = tr.nconsts + tr.ninsns
    slot tr.ir_buf[idx] = IRIns{op=op, ty=ty, lhs=lhs, rhs=rhs, aux=aux}
    tr.ninsns = tr.ninsns + 1
    return idx
end

-- Peek at a Value from the executing VM state. If recording, emit SLOAD.
fun peek_stack(tr:&Tracer, vm:&VM, slot:u16, expected_ty:IRType) -> u16
    if tr.is_recording then
        let mapped = tr.slot_map[slot]
        if mapped != 0 then
            return mapped
        end
        -- Emit SLOAD for this slot
        let ref = emit_insn(tr, IR::IROp.SLOAD, expected_ty, slot, 0, 0)
        tr.slot_map[slot] = ref
        return ref
    end
    return 0   -- not used when not recording
end

-- === THE HOT LOOP (Moonlift, compiled to C) ===

-- This is the interpreter. Every instruction is a branch in a tight loop.
-- When a back-edge gets hot, we switch to recording mode, produce a trace,
-- optimize it, and insert it into the trace table.

fun vm_run(vm: &VM) -> Value
    loop
        let bc = vm.bc[vm.pc]
        let op = bc_op(bc)
        let a  = bc_a(bc)
        let b  = bc_b(bc)
        let c  = bc_c(bc)

        if vm.tracer.is_recording then
            -- RECORDING: append IR, advance pc
            vm.pc = vm.pc + 1
            case op of
                BC_ADD =>
                    let lhs_ref = peek_stack(vm.tracer, vm, b, IR::IRType.INT)
                    let rhs_ref = peek_stack(vm.tracer, vm, c, IR::IRType.INT)
                    let res_ref = emit_insn(vm.tracer, IR::IROp.ADD, IR::IRType.INT, lhs_ref, rhs_ref, 0)
                    vm.tracer.slot_map[a] = res_ref

                BC_LOOP =>
                    -- Loop back-edge: end recording
                    let trace = trace_finalize(vm.tracer)
                    let trace = fold_constants(trace)
                    let trace = cse(trace)
                    let trace = dce(trace)
                    let n = vm.ntraces
                    slot vm.traces[n] = trace
                    vm.ntraces = n + 1
                    -- Re-enter via compiled trace (or fall back to interpreter)
                    return trace_execute(trace, vm)
            end

        else
            -- INTERPRETING: execute directly
            vm.pc = vm.pc + 1
            case op of
                BC_ADD =>
                    slot vm.stack[a] = Value::Int{vm.stack[b].Int + vm.stack[c].Int}

                BC_SUB =>
                    slot vm.stack[a] = Value::Int{vm.stack[b].Int - vm.stack[c].Int}

                BC_LT =>
                    slot vm.stack[a] = Value::Bool{vm.stack[b].Int < vm.stack[c].Int}

                BC_JT =>
                    if vm.stack[a].Bool then vm.pc = pc_ofs(pc) end

                BC_RET =>
                    return vm.stack[a]

                BC_LOOP =>
                    -- Back-edge: check hotness
                    let count = vm.hotcount[vm.pc] + 1
                    slot vm.hotcount[vm.pc] = count
                    if count >= HOT_THRESHOLD then
                        -- Start recording from this point
                        vm.tracer.is_recording = true
                        vm.tracer.nconsts = 0
                        vm.tracer.ninsns  = 0
                        -- Emit BASE instruction
                        vm.tracer.base_ref = emit_const(vm.tracer, IR::IROp.BASE, IR::IRType.PTR, 0)
                    end
            end
        end
    end
end

-- === OPTIMIZATION PASSES (Moonlift, compiled to C) ===

-- Each pass is a pure function: Trace → Trace.
-- No allocation: operate on a temporary IR buffer.

fun fold_constants(tr: &Trace) -> &Trace
    -- Walk insns. If ADD(lhs=KINT, rhs=KINT), replace with KINT.
    for i in 0..tr.ninsns
        let insn = tr.insns[i]
        let nk   = tr.nconsts
        if insn.op == IR::IROp.ADD
            && insn.lhs < nk && insn.rhs < nk
            && tr.consts[insn.lhs].op == IR::IROp.KINT
            && tr.consts[insn.rhs].op == IR::IROp.KINT
        then
            -- Fold: emit a new constant
            let val = tr.consts[insn.lhs].aux + tr.consts[insn.rhs].aux
            let new_ref = emit_const_during_fold(tr, IR::IROp.KINT, IR::IRType.INT, val)
            -- Replace all uses of this insn with new_ref
            replace_all_uses(tr, nk + i, new_ref)
            -- Mark insn as NOP (will be removed by DCE)
            slot tr.insns[i].op = IR::IROp.KNULL  -- NOP sentinel
        end
    end
    return tr
end
