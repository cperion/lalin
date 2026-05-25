-- L0: 1:1 Translation of Lua 5.5 Bytecode Opcodes to Stencils
-- One stencil family per opcode from lopnames.h

local M = {}

-- Lua 5.5 opcodes (from .vendor/Lua/lopnames.h)
-- Each should have a corresponding primitive stencil
M.opcodes = {
    -- Value loading/movement
    {op = "MOVE",     family = "value.move",     ops = 1},
    {op = "LOADI",    family = "value.load_i64", ops = 1},
    {op = "LOADF",    family = "value.load_f64", ops = 1},
    {op = "LOADK",    family = "value.load_k",   ops = 1},
    {op = "LOADKX",   family = "value.load_kx",  ops = 1},
    {op = "LOADFALSE",family = "value.load_false", ops = 1},
    {op = "LFALSESKIP",family = "value.load_false_skip", ops = 1},
    {op = "LOADTRUE", family = "value.load_true", ops = 1},
    {op = "LOADNIL",  family = "value.load_nil", ops = 1},

    -- Upvalue access
    {op = "GETUPVAL", family = "upval.get",      ops = 1},
    {op = "SETUPVAL", family = "upval.set",      ops = 1},

    -- Table access
    {op = "GETTABUP", family = "table.get_upval", ops = 1},
    {op = "GETTABLE", family = "table.get_generic", ops = 1},
    {op = "GETI",     family = "table.get_i",    ops = 1},
    {op = "GETFIELD", family = "table.get_field", ops = 1},
    {op = "SETTABUP", family = "table.set_upval", ops = 1},
    {op = "SETTABLE", family = "table.set_generic", ops = 1},
    {op = "SETI",     family = "table.set_i",    ops = 1},
    {op = "SETFIELD", family = "table.set_field", ops = 1},

    -- Table construction
    {op = "NEWTABLE", family = "table.new",      ops = 1},
    {op = "SETLIST",  family = "table.setlist",  ops = 1},

    -- Method access
    {op = "SELF",     family = "method.get_self", ops = 1},

    -- Arithmetic: immediate forms
    {op = "ADDI",     family = "arith.add_i",    ops = 1},
    {op = "ADDK",     family = "arith.add_k",    ops = 1},
    {op = "SUBK",     family = "arith.sub_k",    ops = 1},
    {op = "MULK",     family = "arith.mul_k",    ops = 1},
    {op = "MODK",     family = "arith.mod_k",    ops = 1},
    {op = "POWK",     family = "arith.pow_k",    ops = 1},
    {op = "DIVK",     family = "arith.div_k",    ops = 1},
    {op = "IDIVK",    family = "arith.idiv_k",   ops = 1},

    -- Bitwise: immediate forms
    {op = "BANDK",    family = "bitwise.and_k",  ops = 1},
    {op = "BORK",     family = "bitwise.or_k",   ops = 1},
    {op = "BXORK",    family = "bitwise.xor_k",  ops = 1},
    {op = "SHLI",     family = "bitwise.shl_i",  ops = 1},
    {op = "SHRI",     family = "bitwise.shr_i",  ops = 1},

    -- Arithmetic: full forms
    {op = "ADD",      family = "arith.add",      ops = 1},
    {op = "SUB",      family = "arith.sub",      ops = 1},
    {op = "MUL",      family = "arith.mul",      ops = 1},
    {op = "MOD",      family = "arith.mod",      ops = 1},
    {op = "POW",      family = "arith.pow",      ops = 1},
    {op = "DIV",      family = "arith.div",      ops = 1},
    {op = "IDIV",     family = "arith.idiv",     ops = 1},

    -- Bitwise: full forms
    {op = "BAND",     family = "bitwise.and",    ops = 1},
    {op = "BOR",      family = "bitwise.or",     ops = 1},
    {op = "BXOR",     family = "bitwise.xor",    ops = 1},
    {op = "SHL",      family = "bitwise.shl",    ops = 1},
    {op = "SHR",      family = "bitwise.shr",    ops = 1},

    -- Metamethod dispatch
    {op = "MMBIN",    family = "mm.binary",      ops = 1},
    {op = "MMBINI",   family = "mm.binary_i",    ops = 1},
    {op = "MMBINK",   family = "mm.binary_k",    ops = 1},

    -- Unary operations
    {op = "UNM",      family = "arith.neg",      ops = 1},
    {op = "BNOT",     family = "bitwise.not",    ops = 1},
    {op = "NOT",      family = "logic.not",      ops = 1},
    {op = "LEN",      family = "table.len",      ops = 1},
    {op = "CONCAT",   family = "string.concat",  ops = 1},

    -- Control/scope
    {op = "CLOSE",    family = "scope.close",    ops = 1},
    {op = "TBC",      family = "scope.tbc",      ops = 1},

    -- Branching
    {op = "JMP",      family = "branch.jmp",     ops = 1},

    -- Comparisons
    {op = "EQ",       family = "cmp.eq",         ops = 1},
    {op = "LT",       family = "cmp.lt",         ops = 1},
    {op = "LE",       family = "cmp.le",         ops = 1},
    {op = "EQK",      family = "cmp.eq_k",       ops = 1},
    {op = "EQI",      family = "cmp.eq_i",       ops = 1},
    {op = "LTI",      family = "cmp.lt_i",       ops = 1},
    {op = "LEI",      family = "cmp.le_i",       ops = 1},
    {op = "GTI",      family = "cmp.gt_i",       ops = 1},
    {op = "GEI",      family = "cmp.ge_i",       ops = 1},

    -- Test/conditional
    {op = "TEST",     family = "logic.test",     ops = 1},
    {op = "TESTSET",  family = "logic.testset",  ops = 1},

    -- Function call
    {op = "CALL",     family = "call.generic",   ops = 1},
    {op = "TAILCALL", family = "call.tail",      ops = 1},

    -- Return
    {op = "RETURN",   family = "call.return",    ops = 1},
    {op = "RETURN0",  family = "call.return_0",  ops = 1},
    {op = "RETURN1",  family = "call.return_1",  ops = 1},

    -- Numeric for-loop
    {op = "FORLOOP",  family = "loop.forloop",   ops = 1},
    {op = "FORPREP",  family = "loop.forprep",   ops = 1},

    -- Table for-loop
    {op = "TFORPREP", family = "loop.tforprep",  ops = 1},
    {op = "TFORCALL", family = "loop.tforcall",  ops = 1},
    {op = "TFORLOOP", family = "loop.tforloop",  ops = 1},

    -- Closure
    {op = "CLOSURE",  family = "closure.new",    ops = 1},

    -- Varargs
    {op = "VARARG",   family = "vararg.load",    ops = 1},
    {op = "GETVARG",  family = "vararg.get",     ops = 1},
    {op = "ERRNNIL",  family = "vararg.errnnil", ops = 1},
    {op = "VARARGPREP", family = "vararg.prep",  ops = 1},

    -- Extra args
    {op = "EXTRAARG", family = "extra.arg",      ops = 1},
}

-- Build L0 library: one stencil per opcode
function M.build_l0_library()
    local l0 = {
        stencils = {},
        by_opcode = {},
        by_family = {},
    }

    for idx, opcode_def in ipairs(M.opcodes) do
        local stencil = {
            id = idx,
            opcode = opcode_def.op,
            family = opcode_def.family,
            name = opcode_def.family,
            ops = opcode_def.ops,
            arity = 1,
            depth = 0,
            is_l0_primitive = true,
            -- Physical properties (stubbed for now)
            size = 50,  -- typical size
            holes = 2,  -- typical holes
            relocs = 1, -- typical relocs
            benefit = 0, -- base ops have no benefit estimate
        }

        table.insert(l0.stencils, stencil)
        l0.by_opcode[opcode_def.op] = stencil
        if not l0.by_family[opcode_def.family] then
            l0.by_family[opcode_def.family] = {}
        end
        table.insert(l0.by_family[opcode_def.family], stencil)
    end

    return l0
end

-- Report L0 structure
function M.report_l0(l0)
    print("\n=== L0: Lua 5.5 Opcode Stencils ===")
    print(string.format("Total opcodes: %d", #l0.stencils))

    local families = {}
    for family, _ in pairs(l0.by_family) do
        table.insert(families, family)
    end
    table.sort(families)

    print("\nStencil families (by category):")
    local current_category = nil
    for _, family in ipairs(families) do
        local category = family:match("^([^.]+)")
        if category ~= current_category then
            print(string.format("\n  %s:", category))
            current_category = category
        end
        print(string.format("    %s", family))
    end

    local total_size = 0
    for _, st in ipairs(l0.stencils) do
        total_size = total_size + st.size
    end
    print(string.format("\nEstimated L0 code size: %d bytes", total_size))
end

return M
