package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ll = require("llpvm")
assert(ll.T and ll.B, "llpvm exposes ASDL context and FastBuilders")

local vm = ll.vm { cache_bytes = 64 * 1024 }

local Expr = vm.abi "Expr" {
    Int = { value = ll.i64 },
    Add = { left = ll.node, right = ll.node },
}

local Back = vm.abi "Back" {
    ConstI64 = { value = ll.i64 },
    AddI64 = {},
}

local ExprWorld = Expr:world()
local BackWorld = Back:world()

local input = vm.seq(ExprWorld) {
    Expr.Int { value = 1 },
    Expr.Int { value = 2 },
    Expr.Add {},
}

local ops = input:drain()
assert(#ops == 3, "seq drains to three authored ops")
assert(ops[1].kind == "Int", "first op kind preserved")
assert(ops[1].payload[1] == 1, "named payload lowers to schema order")

local machine = vm.machine "lower_expr" {
    from = ExprWorld,
    to = BackWorld,
    entry = "ll_lower_expr",
}

local lower = vm.phase "lower_expr" {
    from = ExprWorld,
    to = BackWorld,
    machine = machine,
    cache = "full",
}

local mapped = lower {
    target = "wasm32",
    opt = 3,
} (input)

local mapped_node = mapped:one()
assert(mapped_node.kind == "phase_map", "phase call returns a phase-map stream")

local retained_input = vm.retain(input)
local rebuilt = vm.rebuild(function(next_vm)
    return next_vm.seq(ExprWorld) {
        retained_input:get():drain()[1],
        Expr.Int { value = 4 },
    }
end)
assert(#rebuilt:drain() == 2, "retained nodes can seed an incremental rebuild")

local program = vm.program { input, mapped }
assert(#vm.abis == 2, "program captures ABIs")
assert(#vm.worlds == 2, "program captures implicit worlds")
assert(#vm.machines == 1, "program captures machines")
assert(#vm.phases == 1, "program captures phases")
assert(#program.root_ids == 2, "program captures roots")
assert(program:bytecode():sub(1, 4) == "LLPV", "program proxy encodes to LLPVM bytecode")

local direct = ll.B.LlPvm.Symbol { value = "direct-literal" }
assert(ll.symbol(direct) ~= nil, "standard ASDL layer remains available")

print("llpvm lua api ok")
