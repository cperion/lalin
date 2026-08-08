package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Physical = require("experiments.retained_compiler.state")

local before_seal = pcall(function() return Physical.Compiler() end)
assert(not before_seal, "the physical compiler must not construct before behavior is sealed")

local Compiler = require("experiments.retained_compiler.machine")
local root = Compiler.Compiler()

local source = [[
let x = 40;
let y = x + 2 * 3;
return y - 1;
 ]]

assert(root:compile(source) == root)
assert(root:succeeded(), root:diagnostic_text())
assert(root.program.binding_count == 2)
assert(root.symbols.entry_count == 2)
assert(root.program.bindings[0].symbol == root.expressions.names[0].symbol)
assert(root.program.bindings[1].symbol == root.expressions.names[1].symbol)
assert(root.resolutions.by_symbol[root.program.bindings[0].symbol].generation == root.generation)
assert(root.expressions.integer_count == 4)
assert(root.expressions.name_count == 2)
assert(root.expressions.binary_count == 3)
assert(root.resolver.resolved_count == 2)
assert(root.typechecker.typed_count == root.expressions.order_count)
assert(root.lowerer.lowered_count == root.expressions.order_count)
assert(root.instructions.count == 8)
assert(root.emitter.emitted_count == root.instructions.count)

local expected = table.concat({
    "r0 = const 40\n",
    "r1 = const 2\n",
    "r2 = const 3\n",
    "r3 = mul r1, r2\n",
    "r4 = add r0, r3\n",
    "r5 = const 1\n",
    "r6 = sub r4, r5\n",
    "return r6\n",
})
assert(root:artifact_text() == expected, root:artifact_text())

for id = 0, root.expressions.order_count - 1 do
    assert(root.types.by_expression[id].generation == root.generation)
    assert(root.types.by_expression[id].type_kind == Compiler.constants.type.i64)
    assert(root.lower.by_expression[id].generation == root.generation)
end

local root_bytes = ffi.sizeof(root)
assert(root_bytes > 1000000 and root_bytes < 2000000)
assert(ffi.offsetof("RetainedCompilerV1_Compiler", "parser")
    > ffi.offsetof("RetainedCompilerV1_Compiler", "expressions"))
assert(ffi.offsetof("RetainedCompilerV1_Compiler", "emitter")
    > ffi.offsetof("RetainedCompilerV1_Compiler", "parser"))

local other = Compiler.Compiler()
assert(other:compile("return 2 + 3 * 4;"):succeeded())
assert(other:artifact_text() == table.concat({
    "r0 = const 2\n",
    "r1 = const 3\n",
    "r2 = const 4\n",
    "r3 = mul r1, r2\n",
    "r4 = add r0, r3\n",
    "return r4\n",
}))
assert(root:artifact_text() == expected, "independent roots must retain independent artifacts")

assert(root:compile("return (2 + 3) * 4;"):succeeded())
assert(root:artifact_text() == table.concat({
    "r0 = const 2\n",
    "r1 = const 3\n",
    "r2 = add r0, r1\n",
    "r3 = const 4\n",
    "r4 = mul r2, r3\n",
    "return r4\n",
}))

assert(not root:compile("return missing;"):succeeded())
assert(root:diagnostic_text() == "unresolved name")

assert(not root:compile("let x = 1; let x = 2; return x;"):succeeded())
assert(root:diagnostic_text() == "duplicate binding")

assert(not root:compile("let x = 1 + ; return x;"):succeeded())
assert(root:diagnostic_text() == "syntax error")

assert(not root:compile("let x = 1;"):succeeded())
assert(root:diagnostic_text() == "missing return")

assert(not root:compile(string.rep(" ", Compiler.capacity.source + 1)):succeeded())
assert(root:diagnostic_text() == "source capacity exhausted")

local late_method = pcall(function() Compiler.Compiler.late = function() end end)
assert(not late_method, "the physical compiler must seal exactly once")

print(("ok retained compiler root=%d expressions=%d instructions=%d"):format(
    root_bytes, other.expressions.order_count, other.instructions.count))
