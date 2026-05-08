-- === Moonlift-native Tracing JIT Architecture ===
--
-- Core idea: a hot-loop tracer that records operations into SSA IR,
-- optimizes the IR, then lowers to Moonlift itself (or C/mcode later).
--
-- The VM interpreter runs in a loop. When a back-edge (loop) hits a
-- threshold, the tracer kicks in: it switches from interpretation to
-- recording mode. Every bytecode handler now records an IR instruction
-- instead of executing. When the loop back-edge is hit again, the
-- recording stops, we optimize the IR, lower it, and patch the
-- bytecode to call the compiled trace next time.

-- === 1. IR Definition (the IR language) ===

asdl IR :: {

    IRType :: u8 {
        INT  = 0,
        NUM  = 1,
        PTR  = 2,
        NIL  = 3,
        BOOL = 4,
    }

    IROp :: u16 {
        -- constants
        KINT   = 0,   -- integer literal
        KNULL  = 1,   -- null/nil
        KPRI   = 2,   -- primitive (true/false/nil)
        -- control flow
        BASE   = 10,  -- frame base
        LOOP   = 11,  -- loop marker / back-edge
        -- memory
        SLOAD  = 20,  -- load from stack slot
        SSTORE = 21,  -- store to stack slot
        ALOAD  = 22,  -- load from array
        ASTORE = 23,  -- store to array
        HLOAD  = 24,  -- load from table field
        HSTORE = 25,  -- store to table field
        -- arithmetic
        ADD    = 30,
        SUB    = 31,
        MUL    = 32,
        DIV    = 33,
        MOD    = 34,
        NEG    = 35,
        -- comparison
        LT     = 40,
        LE     = 41,
        GT     = 42,
        GE     = 43,
        EQ     = 44,
        NE     = 45,
        -- guards (side exits)
        GUARD  = 50,  -- generic guard
        GREF   = 51,  -- type guard (reference)
        GINT   = 52,  -- type guard (integer)
        GNUM   = 53,  -- type guard (number)
        -- control flow within trace
        JF     = 60,  -- jump-if-false
        JMP    = 61,  -- unconditional jump
        RET    = 62,  -- return from trace
        -- calls
        CALL   = 70,  -- call other function/trace
    }

    -- A single IR instruction
    IRIns :: {
        op   : IROp,
        type : IRType,
        lhs  : u16,    -- left operand (ref into insns[])
        rhs  : u16,    -- right operand (ref into insns[])
        aux  : i32,    -- auxiliary data (literal value, slot#, flags)
    }

    -- A compiled trace
    Trace :: {
        id        : u16,
        consts    : []IRIns,    -- constants (refs 0..nconsts-1)
        insns     : []IRIns,    -- instructions (refs nconsts..)
        snapshots : []Snapshot, -- side-exit checkpoints
    }

    -- A snapshot records live state at a guard point
    Snapshot :: {
        ins_ref  : u16,          -- which instruction is guarded
        slots    : []{slot : u16, ref : u16},  -- stack slot → IR ref
    }
}

-- === 2. VM State ===

asdl VM :: {

    -- The Lua value tagged union
    Value :: {
        Int  : { i : i64 },
        Num  : { n : f64 },
        Bool : { b : bool },
        Nil  : {},
        Str  : { s : []u8 },
        Tab  : { t : &Table },
        Fun  : { f : &Func },
    }

    -- Stack frame
    Frame :: {
        prev     : &Frame,
        func     : &Func,
        base     : u16,      -- index into stack where frame starts
        top      : u16,      -- index past last used slot
        pc       : u16,      -- instruction pointer
        varargs  : bool,
    }

    -- Bytecode instruction
    BC :: u32  -- packed: op(8) | A(8) | B(8) | C(8)

    -- Lua function prototype
    Func :: {
        bc       : []BC,
        k        : []Value,  -- constants
        upvalues : []{name : []u8, slot : u16},
        params   : u8,
        maxstack : u8,
        name     : []u8,
    }

    -- The VM itself
    VMState :: {
        stack    : [256]Value,   -- value stack (fixed capacity for now)
        frames   : &Frame,       -- linked list of frames
        hotcount : [256]u16,     -- back-edge counters per bc index
        traces   : [64]&Trace,   -- compiled traces table
    }
}

-- === 3. The Tracer ===

-- The tracer records IR instructions as it "walks" the bytecode.
-- It's a state machine: {Normal, Recording{ir_buf, slot_map}}.

asdl Tracer :: {
    TracerMode :: {
        Normal   : {},
        Recording : {
            ir       : &IRBuilder,
            slot_map : [256]u16,  -- stack slot → IR ref mapping
            frame    : &Frame,
            start_pc : u16,
        },
    }
}

-- === 4. Optimization Passes (pure functions over IR) ===

-- Each pass takes a Trace and returns an optimized Trace.
-- These are clean, recursive, typed transformations.

-- Constant folding: if both operands of ADD are KINTs, replace with KINT
func fold_constants(t: Trace) -> Trace
    -- walk t.insns, for each op:
    --   if op == ADD and lhs == KINT and rhs == KINT:
    --     replace with KINT(lhs.aux + rhs.aux), update refs
end

-- Dead code elimination: remove instructions whose result is never read
func dce(t: Trace) -> Trace
    -- start from snapshot refs + trace result, mark reachable
    -- keep only marked instructions
end

-- Common subexpression elimination
func cse(t: Trace) -> Trace
    -- hash cons: if two insns have same op + lhs + rhs, reuse first
end

-- Sinking: move stores past side-exits when safe
func sink(t: Trace) -> Trace
    -- if a store's result is only needed along one path, delay it
end

-- === 5. Code Generation (IR → Moonlift function) ===

-- The beautiful thing: we can lower optimized IR back INTO Moonlift
-- code using the splice pipeline. Compile a trace into a Moonlift
-- function that executes the compiled path directly.

func lower_trace(t: Trace) -> ItemFunc
    -- For each IR instruction, generate a slot in a Moonlift function:
    --
    --    t0 := 5       (KINT)
    --    t1 := x        (SLOAD slot 0)
    --    t2 := y        (SLOAD slot 1)
    --    t3 := t1 + t2  (ADD)
    --
    -- Guard instructions become assertions/checks.
    -- The function signature comes from the frame's parameter slots.
end

-- === 6. Putting It Together ===

func vm_run(vm: &VMState, func: &Func) -> []Value
    -- main interpreter loop
    loop
        insn := func.bc[vm.frames.pc]
        op   := insn >> 24
        case op of
            ADD => stack[B] := stack[A] + stack[C]; pc++
            LT  => ...
            ...
            LOOP =>  -- back-edge
                hotcount[pc]++
                if hotcount[pc] > HOT_THRESHOLD then
                    trace := record_trace(vm, func, pc)
                    trace := fold_constants(trace)
                    trace := dce(trace)
                    trace := cse(trace)
                    trace := sink(trace)
                    compiled := lower_trace(trace)
                    vm.traces[func.id] := compiled
                    -- jump to compiled trace
                    jump compiled(vm)
                end
        end
    end
end
