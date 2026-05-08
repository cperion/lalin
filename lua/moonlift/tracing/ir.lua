-- moonlift/tracing/ir.lua -- IR definition for the tracing JIT
-- This is pure Moonlift — no C, no LuaJIT dependency.
--
-- The IR is a flat SSA array: [consts...][instructions...].
-- References < nconsts are constants, >= nconsts are instructions.

local A = require("moonlift.asdl")

function Define(T)
    local M = {}

    M.IRType = A.Enum("IRType"):define(T, {
        {INT = 0, ty = T.u8},
        {NUM = 1, ty = T.u8},
        {PTR = 2, ty = T.u8},
        {NIL = 3, ty = T.u8},
        {BOOL= 4, ty = T.u8},
    })

    M.IROp = A.Enum("IROp"):define(T, {
        -- constants (these go in consts[], refs < nconsts)
        {KINT  = 0,  ty = T.u16},
        {KNULL = 1,  ty = T.u16},
        {KPRI  = 2,  ty = T.u16},
        -- frame
        {BASE  = 10, ty = T.u16},
        {LOOP  = 11, ty = T.u16},
        -- memory
        {SLOAD = 20, ty = T.u16},
        {SSTORE= 21, ty = T.u16},
        -- arithmetic
        {ADD   = 30, ty = T.u16},
        {SUB   = 31, ty = T.u16},
        {MUL   = 32, ty = T.u16},
        {NEG   = 35, ty = T.u16},
        -- comparison
        {LT    = 40, ty = T.u16},
        {GT    = 42, ty = T.u16},
        {EQ    = 44, ty = T.u16},
        {NE    = 45, ty = T.u16},
        -- guards
        {GUARD = 50, ty = T.u16},
        -- control flow
        {RET   = 62, ty = T.u16},
    })

    -- A single IR instruction (flat, no pointers — like LuaJIT's IRIns)
    M.IRIns = A.Record("IRIns"):define(T, {
        {op   = M.IROp},
        {ty   = M.IRType},
        {lhs  = T.u16},
        {rhs  = T.u16},
        {aux  = T.i32},
    })

    -- A compiled trace
    M.Trace = A.Record("Trace"):define(T, {
        {nconsts = T.u16},
        {ninsns  = T.u16},
        {consts  = A.Vec(M.IRIns)},  -- index 0..nconsts-1
        {insns   = A.Vec(M.IRIns)},  -- index nconsts..nconsts+ninsns-1
        {snaps   = A.Vec(A.Record("Snap", {
            {iref  = T.u16},
            {slots = A.Vec(T.u16)},  -- stack slot → IR ref pairs
        }))},
    })

    -- Builder for incrementally constructing IR
    M.IRBuilder = A.Record("IRBuilder"):define(T, {
        {consts     = A.Vec(M.IRIns)},
        {insns      = A.Vec(M.IRIns)},
        {slot_map   = A.Vec(T.u16)},   -- stack slot → IR ref
        {base_ref   = T.u16},
    })

    return M
end

return { Define = Define }
