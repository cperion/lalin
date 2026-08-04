package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema")
require("lalin.impl.tree_region")
local Document = require("lalin.syntax.document")

local P, Tr, Ty, C, B = T.LalinParse, T.LalinTree, T.LalinType, T.LalinCore, T.LalinBind

local i32 = Ty.TScalar(C.ScalarI32)
local function lit(n) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(tostring(n))) end
local function ref(name) return Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefName(name)) end

-- ─────────────────────────────────────────────────────────────
-- 1. ParsedRegionBlock sum replaces the string-kind ParsedEntryBlock
-- ─────────────────────────────────────────────────────────────

assert(P.ParsedEntryBlock == nil, "string-kind ParsedEntryBlock must be removed")
assert(P.ParsedRegionBlock and P.ParsedRegionEntryBlock and P.ParsedRegionBodyBlock,
  "typed ParsedRegionBlock sum leaves must exist")

local doc = Document.parse([[
region Inner(x [i32]; done(v [i32]))
entry start(x [i32]) do
  jump done(x)
end
block tail() do
  jump done(x)
end
end
]], "@region-block-sum.lln")

local parsed = doc.body[1]
assert(asdl.classof(parsed) == P.ParsedRegion)
assert(#parsed.blocks == 2)
assert(asdl.classof(parsed.blocks[1]) == P.ParsedRegionEntryBlock)
assert(asdl.classof(parsed.blocks[2]) == P.ParsedRegionBodyBlock)
assert(parsed.blocks[1].name == "start" and parsed.blocks[1].state[1].name == "x")
assert(parsed.blocks[2].name == "tail" and #parsed.blocks[2].state == 0)
assert(parsed.blocks[1].kind == nil, "block leaves must not carry a string kind")

-- ─────────────────────────────────────────────────────────────
-- 2. Typed continuation projection and lookup
-- ─────────────────────────────────────────────────────────────

local exit = parsed.exits[1]
assert(asdl.classof(exit) == P.ParsedExit and exit.name == "done")
local cont = exit:parsed_region_cont(P.ParsedRegionContInput("Inner", 1))
assert(asdl.classof(cont) == Tr.RegionCont and cont.name == "done")
assert(#cont.params == 1 and cont.params[1].name == "v" and cont.params[1].ty == i32)

local projection = parsed:parsed_cont_projection({ cont })
assert(asdl.classof(projection) == P.ParsedContProjection)
assert(#projection.entries == 1 and projection.entries[1].cont == cont)

local found = projection:parsed_cont_lookup("done")
assert(asdl.classof(found) == P.ParsedContFound)
assert(found.entry.cont == cont, "lookup must return the exact interned continuation")
local missing = projection:parsed_cont_lookup("nope")
assert(asdl.classof(missing) == P.ParsedContMissing and missing.name == "nope")

-- Found/Missing leaves own the retargeting decisions.
local jump = Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel("done"), { Tr.JumpArg("v", ref("x")) })
local retargeted = found:region_retarget_jump(jump)
assert(asdl.classof(retargeted) == Tr.StmtJumpCont)
assert(retargeted.cont == cont and retargeted.args[1].name == "v")
assert(missing:region_retarget_jump(jump) == jump, "missing lookup must pass the jump through")

-- ─────────────────────────────────────────────────────────────
-- 3. Leaf-owned statement retargeting for jump/if/switch and
--    RegionWireBlock (assembly-time)
-- ─────────────────────────────────────────────────────────────

local function cont_projection_for(conts)
  return parsed:parsed_cont_projection(conts)
end
local cp = cont_projection_for({ cont })
local retarget_input = P.ParsedRegionRetargetInput(cp)

assert(asdl.classof(jump:region_retarget_cont(retarget_input)) == Tr.StmtJumpCont)
assert(asdl.classof(Tr.StmtSet(Tr.StmtSurface, Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefName("x")), lit(1)):region_retarget_cont(retarget_input))
  == Tr.StmtSet, "unrelated leaves must pass through unchanged")

-- StmtIf recursion: a jump inside then/else bodies is retargeted.
local if_stmt = Tr.StmtIf(Tr.StmtSurface, ref("x"),
  { jump },
  { Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel("tail"), {}) })
local if_ret = if_stmt:region_retarget_cont(retarget_input)
assert(asdl.classof(if_ret) == Tr.StmtIf)
assert(asdl.classof(if_ret.then_body[1]) == Tr.StmtJumpCont, "if then-body jump must retarget")
assert(asdl.classof(if_ret.else_body[1]) == Tr.StmtJump, "if else-body non-cont jump must pass through")

-- StmtSwitch recursion.
local switch_stmt = Tr.StmtSwitch(Tr.StmtSurface, lit(1),
  { Tr.SwitchStmtArm(Tr.SwitchKeyInt("1"), { jump }) }, {}, {})
local switch_ret = switch_stmt:region_retarget_cont(retarget_input)
assert(asdl.classof(switch_ret) == Tr.StmtSwitch)
assert(asdl.classof(switch_ret.arms[1].body[1]) == Tr.StmtJumpCont, "switch arm body must retarget")

-- StmtVariantSwitchSource recursion.
local variant_source = Tr.StmtVariantSwitchSource(Tr.StmtSurface, ref("x"),
  {},
  { Tr.SwitchVariantSourceStmtArm("Some", { Tr.VariantBindSource("value") }, { jump }) },
  {})
local variant_ret = variant_source:region_retarget_cont(retarget_input)
assert(asdl.classof(variant_ret) == Tr.StmtVariantSwitchSource)
assert(asdl.classof(variant_ret.variant_arms[1].body[1]) == Tr.StmtJumpCont)

-- RegionWireBlock: a wire whose label names a continuation becomes RegionWireCont.
local wire_block = Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("done"), { Tr.JumpArg("v", lit(9)) }))
local wire_ret = wire_block:region_retarget_cont(retarget_input)
assert(asdl.classof(wire_ret) == Tr.RegionContWire)
assert(asdl.classof(wire_ret.target) == Tr.RegionWireCont and wire_ret.target.cont == cont)
local wire_block_other = Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("caller_block"), {}))
local wire_ret_other = wire_block_other:region_retarget_cont(retarget_input)
assert(asdl.classof(wire_ret_other.target) == Tr.RegionWireBlock, "non-cont wire label must pass through")

-- StmtRegionEmit wiring retargeting.
local inner_target = Tr.RegionInvokeTarget(C.Path({ C.Name("Inner") }))
local emit_stmt = Tr.StmtRegionEmit(Tr.StmtSurface, "lln.emit.1", inner_target, { lit(1) },
  { Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("done"), {})) })
local emit_ret = emit_stmt:region_retarget_cont(retarget_input)
assert(asdl.classof(emit_ret) == Tr.StmtRegionEmit)
assert(asdl.classof(emit_ret.wiring[1].target) == Tr.RegionWireCont and emit_ret.wiring[1].target.cont == cont)

-- ─────────────────────────────────────────────────────────────
-- 4. Invoke-time clone: jump/if/switch leaves and RegionWireBlock
-- ─────────────────────────────────────────────────────────────

local wires = { Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("caller_done"), {})) }
local id = "outer"

local jump_clone = Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel("tail"), { Tr.JumpArg("v", ref("x")) })
  :region_clone_for_invoke(id, wires, { cont })
assert(asdl.classof(jump_clone) == Tr.StmtJump and jump_clone.target.name == "outer.tail",
  "invoke clone must prefix jump targets")

local branch = Tr.StmtBranchJump(Tr.StmtSurface, ref("x"),
  Tr.BlockLabel("then_l"), {}, Tr.BlockLabel("else_l"), {})
local branch_clone = branch:region_clone_for_invoke(id, wires, { cont })
assert(asdl.classof(branch_clone) == Tr.StmtBranchJump)
assert(branch_clone.then_target.name == "outer.then_l" and branch_clone.else_target.name == "outer.else_l")

local variant_source_clone = variant_source:region_clone_for_invoke(id, wires, { cont })
assert(asdl.classof(variant_source_clone.variant_arms[1].body[1]) == Tr.StmtJump
  and variant_source_clone.variant_arms[1].body[1].target.name == "outer.done")

local wire_block_clone = Tr.RegionWireBlock(Tr.BlockLabel("caller_block"), { Tr.JumpArg("v", lit(3)) })
  :region_clone_for_invoke(id, wires, { cont })
assert(wire_block_clone.label.name == "outer.caller_block", "wire block labels must be prefixed")

-- RegionWireCont clone retargets through the outer invoke's wiring.
local cont_wire = Tr.RegionContWire("done", Tr.RegionWireCont(cont, { Tr.JumpArg("v", lit(4)) }))
local cont_wire_clone = cont_wire:region_clone_for_invoke(id, wires, { cont })
assert(asdl.classof(cont_wire_clone.target) == Tr.RegionWireBlock
  and cont_wire_clone.target.label.name == "caller_done", "cont wire must retarget to the caller wire target")

-- Nested emit/call compose deterministic invoke ids and clone wiring.
local nested = Tr.StmtRegionEmit(Tr.StmtSurface, "lln.emit.7", inner_target, { lit(2) },
  { Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("after"), {})) })
local nested_clone = nested:region_clone_for_invoke(id, wires, { cont })
assert(asdl.classof(nested_clone) == Tr.StmtRegionEmit)
assert(nested_clone.invoke_id == "outer.lln.emit.7", "nested invoke ids must compose")
assert(nested_clone.wiring[1].target.label.name == "outer.after", "nested wiring labels must be prefixed")

-- StmtIf/StmtSwitch clone still recurse and retarget cont jumps through wiring.
local nested_if = Tr.StmtIf(Tr.StmtSurface, ref("x"),
  { Tr.StmtJumpCont(Tr.StmtSurface, cont, { Tr.JumpArg("v", lit(5)) }) }, {})
local nested_if_clone = nested_if:region_clone_for_invoke(id, wires, { cont })
assert(asdl.classof(nested_if_clone.then_body[1]) == Tr.StmtJump
  and nested_if_clone.then_body[1].target.name == "caller_done",
  "StmtJumpCont inside if must retarget through the wire projection")

-- ─────────────────────────────────────────────────────────────
-- 5. Region assembly and contract lowering (ParsedRegion → Tree.Region)
-- ─────────────────────────────────────────────────────────────

local assembly_doc = Document.parse([[
region R(x [i32]; done(v [i32]))
requires readonly(p)
requires bounds(buf)(n)
entry start(x [i32]) do
  let y [i32] = x
  jump done(y)
end
block tail() do
  jump done(0)
end
end
]], "@region-assembly.lln")

local module = Document.to_module(assembly_doc, "region_assembly")
assert(#module.items == 1)
local item = module.items[1]
assert(asdl.classof(item) == Tr.ItemRegion)
local region = item.region
assert(region.name == "R")
assert(#region.params == 1 and region.params[1].name == "x" and region.params[1].ty == i32)
assert(#region.conts == 1 and region.conts[1].name == "done"
  and region.conts[1].params[1].name == "v")
assert(#region.contracts == 2)
assert(asdl.classof(region.contracts[1]) == Tr.ContractReadonly)
assert(asdl.classof(region.contracts[2]) == Tr.ContractBounds)
assert(region.entry.label.name == "start")
assert(#region.entry.params == 1 and asdl.classof(region.entry.params[1]) == Tr.EntryBlockParam)
assert(region.entry.params[1].init and region.entry.params[1].init.ref.name == "x")
assert(asdl.classof(region.entry.body[1]) == Tr.StmtLet)
assert(asdl.classof(region.entry.body[2]) == Tr.StmtJumpCont
  and region.entry.body[2].cont.name == "done"
  and region.entry.body[2].args[1].value.ref.name == "y",
  "region entry body must lower lets and retarget cont jumps")
assert(#region.blocks == 1 and region.blocks[1].label.name == "tail")
assert(asdl.classof(region.blocks[1].body[1]) == Tr.StmtJumpCont)

-- A region with no declared blocks assembles a default empty entry.
local empty_doc = Document.parse([[
region Empty(; done())
end
]], "@region-empty.lln")
local empty_region = Document.to_module(empty_doc, "region_empty").items[1].region
assert(empty_region.entry.label.name == "entry" and #empty_region.blocks == 0)

-- ─────────────────────────────────────────────────────────────
-- 6. Deterministic source-site invoke IDs
-- ─────────────────────────────────────────────────────────────

local invoke_source = [=[
region K(; done())
entry start() do
  emit K(; done)
  emit K(; done)
  call K(; done)
end
end
]=]
local first = Document.parse(invoke_source, "@invoke-id.lln")
local second = Document.parse(invoke_source, "@invoke-id.lln")
local body = first.body[1].blocks[1].body
assert(#body == 3)
local ids = {}
for i = 1, #body do
  local stmt = body[i].stmt
  assert(stmt.invoke_id and stmt.invoke_id:match("^lln%.[a-z]+%.[0-9]+$"),
    "invoke ids must derive from the source site: " .. tostring(stmt.invoke_id))
  assert(ids[stmt.invoke_id] == nil, "invoke ids must be unique per source site")
  ids[stmt.invoke_id] = true
end
assert(second.body[1].blocks[1].body[1].stmt.invoke_id == body[1].stmt.invoke_id
  and second.body[1].blocks[1].body[2].stmt.invoke_id == body[2].stmt.invoke_id
  and second.body[1].blocks[1].body[3].stmt.invoke_id == body[3].stmt.invoke_id,
  "invoke ids must be deterministic across parses of the same source")

-- ─────────────────────────────────────────────────────────────
-- 7. Typed ParsedRegionBlockAssembly state machine and typed inputs
-- ─────────────────────────────────────────────────────────────

assert(P.ParsedRegionBlockAssembly and P.ParsedRegionBlockAssemblyWaiting
  and P.ParsedRegionBlockAssemblyHasEntry, "typed assembly state leaves must exist")
assert(P.ParsedRegionRetargetInput and P.ParsedRegionBodyInput and P.ParsedRegionAssemblyInput
  and P.ParsedRegionBodyEnv, "typed assembly input products must exist")

local body_env = P.ParsedRegionBodyEnv({})
local ret = P.ParsedRegionRetargetInput(cp)
local body_input = P.ParsedRegionBodyInput("R", ret, body_env)

-- Waiting + body block -> Waiting (body retained); finalize supplies the default entry.
local s1 = P.ParsedRegionBlockAssemblyWaiting({})
local first_block = Tr.ControlBlock(Tr.BlockLabel("first"), {}, { Tr.StmtTrap(Tr.StmtSurface) })
local s2 = P.ParsedRegionBodyBlock("first", {}, {}):parsed_region_accumulate(s1, body_input)
assert(asdl.classof(s2) == P.ParsedRegionBlockAssemblyWaiting)
assert(#s2.blocks == 1 and s2.blocks[1].label.name == "first")
local f1 = s2:parsed_region_block_assembly_finalize(body_input)
assert(asdl.classof(f1) == P.ParsedRegionBlockAssemblyHasEntry)
assert(f1.entry.label.name == "entry" and #f1.blocks == 1, "finalize keeps waiting-state body blocks")

-- Entry block transitions to HasEntry, retaining body blocks seen earlier.
local s3 = P.ParsedRegionEntryBlock("main", {}, {}):parsed_region_accumulate(s2, body_input)
assert(asdl.classof(s3) == P.ParsedRegionBlockAssemblyHasEntry)
assert(s3.entry.label.name == "main" and #s3.blocks == 1 and s3.blocks[1].label.name == "first",
  "entry arrival must retain earlier body blocks")
local s4 = P.ParsedRegionBodyBlock("last", {}, {}):parsed_region_accumulate(s3, body_input)
assert(#s4.blocks == 2 and s4.blocks[2].label.name == "last")

-- A second entry block assembles as a body control block.
local dup_parsed = Document.parse([[
region D(; done())
entry a() do
  jump done()
end
entry b() do
  jump done()
end
end
]], "@dup.lln")
local dup_region = Document.to_module(dup_parsed, "dup").items[1].region
assert(dup_region.entry.label.name == "a" and #dup_region.blocks == 1 and dup_region.blocks[1].label.name == "b")

-- Body-block-first region: entry is found by type, not position.
local ordered_parsed = Document.parse([=[
region O(; done())
block first() do
  jump done()
end
entry main() do
  jump done()
end
block last() do
  jump done()
end
end
]=], "@ordered.lln")
local ordered_region = Document.to_module(ordered_parsed, "ordered").items[1].region
assert(ordered_region.entry.label.name == "main")
assert(#ordered_region.blocks == 2 and ordered_region.blocks[1].label.name == "first"
  and ordered_region.blocks[2].label.name == "last")

-- Leaf-owned ParsedDecl lowering: ParsedRegion assembles through its own leaf.
local leaf_item = parsed:parsed_decl_to_item({}, { 0 })
assert(asdl.classof(leaf_item) == Tr.ItemRegion and leaf_item.region.name == "Inner")

-- ─────────────────────────────────────────────────────────────
-- 8. Typed ParsedContract alternatives replace string dispatch
-- ─────────────────────────────────────────────────────────────

-- The requires parser recognizes surface keywords into typed leaves.
local contract_doc = Document.parse([=[
fn f(p [ptr [i32]], q [ptr [i32]], n [index]) [void] do
  requires readonly(p), noalias(p), bounds(p)(n), disjoint(p)(q), same_len(p)(q)
  return
end
]=], "@typed-contracts.lln")
local func_body = contract_doc.body[1].body
assert(asdl.classof(func_body) == P.ParsedFuncBodyLinear, "typed contracts require a linear function body")
local requires = func_body.body[1]
assert(asdl.classof(requires) == P.StmtRequiresParsed)
assert(requires.exprs == nil, "StmtRequiresParsed must not carry raw Expr alternatives")
assert(#requires.contracts == 5)
assert(asdl.classof(requires.contracts[1]) == P.ParsedContractReadonly)
assert(asdl.classof(requires.contracts[2]) == P.ParsedContractNoAlias)
assert(asdl.classof(requires.contracts[3]) == P.ParsedContractBounds)
assert(asdl.classof(requires.contracts[4]) == P.ParsedContractDisjoint)
assert(asdl.classof(requires.contracts[5]) == P.ParsedContractSameLen)

-- Each leaf owns FuncContract construction; no name strings remain.
assert(asdl.classof(requires.contracts[1]:parsed_contract_value()) == Tr.ContractReadonly)
assert(asdl.classof(requires.contracts[3]:parsed_contract_value()) == Tr.ContractBounds)
assert(asdl.classof(requires.contracts[5]:parsed_contract_value()) == Tr.ContractSameLen)

-- The function path consumes the typed contracts through the same leaves.
local contract_module = Document.to_module(contract_doc, "typed_contracts")
local func_contracts = contract_module.items[1].func.contracts
assert(#func_contracts == 5)
assert(asdl.classof(func_contracts[1]) == Tr.ContractReadonly)
assert(asdl.classof(func_contracts[3]) == Tr.ContractBounds)
assert(asdl.classof(func_contracts[4]) == Tr.ContractDisjoint)

-- Malformed shapes reject at the parse boundary.
local function bad_requires(src)
  return not pcall(Document.parse, src, "@bad-contract.lln")
end
assert(bad_requires([[
fn g() [void] do
  requires readonly(p)(q)
  return
end
]]), "unary contract with two groups must reject")
assert(bad_requires([[
fn g() [void] do
  requires bounds(p)
  return
end
]]), "binary contract with one group must reject")
assert(bad_requires([[
fn g() [void] do
  requires mystery(p)
  return
end
]]), "unknown contract keyword must reject")

-- ─────────────────────────────────────────────────────────────
-- 9. Typed RegionWireArgProjection: named/positional forwarding
-- ─────────────────────────────────────────────────────────────

assert(Tr.RegionWireArgProjection and Tr.RegionWireArgEntry
  and Tr.RegionWireArgFound and Tr.RegionWireArgMissing
  and Tr.RegionWireArgMarkerName and Tr.RegionWireArgMarkerValue,
  "typed wire-argument projection vocabulary must exist")

-- Expression leaves classify forwarding markers; no hidden-field probing.
assert(asdl.classof(ref("left"):region_wire_arg_marker()) == Tr.RegionWireArgMarkerName
  and ref("left"):region_wire_arg_marker().name == "left")
assert(lit(7):region_wire_arg_marker() == Tr.RegionWireArgMarkerValue,
  "non-ref wire arguments must keep their explicit value")

-- Projection lookup over the region exit arguments.
local source_args = {
  Tr.JumpArg("left", ref("x")),
  Tr.JumpArg("right", ref("y")),
}
local entries = {}
for i = 1, #source_args do
  entries[i] = Tr.RegionWireArgEntry(source_args[i].name, source_args[i].value)
end
local wire_projection = Tr.RegionWireArgProjection(entries)
local found_left = wire_projection:region_wire_arg_lookup("left")
assert(asdl.classof(found_left) == Tr.RegionWireArgFound and found_left.entry.value == ref("x"))
assert(asdl.classof(wire_projection:region_wire_arg_lookup("nope")) == Tr.RegionWireArgMissing)

-- Lookup result leaves choose substituted/original jump arguments.
local marker_arg = Tr.JumpArg("left", ref("left"))
local substituted = found_left:region_wire_arg_result(marker_arg)
assert(substituted.name == "left" and substituted.value == ref("x"),
  "found lookup must substitute the region exit value")
local original = wire_projection:region_wire_arg_lookup("nope"):region_wire_arg_result(marker_arg)
assert(original == marker_arg, "missing lookup must keep the explicit argument")

-- End-to-end wire retargeting: named `extra = 7` plus positional markers
-- `left`, `right` forward the region exit values into the caller block.
local wire_block = Tr.RegionWireBlock(Tr.BlockLabel("finished"), {
  Tr.JumpArg("extra", lit(7)),
  Tr.JumpArg("left", ref("left")),
  Tr.JumpArg("right", ref("right")),
})
local jump = wire_block:region_retarget_jump(nil, source_args)
assert(asdl.classof(jump) == Tr.StmtJump and jump.target.name == "finished")
assert(#jump.args == 3)
assert(jump.args[1].name == "extra" and jump.args[1].value == lit(7))
assert(jump.args[2].name == "left" and jump.args[2].value == ref("x"))
assert(jump.args[3].name == "right" and jump.args[3].value == ref("y"))

-- A marker naming no region exit argument keeps its explicit value.
local partial = Tr.RegionWireBlock(Tr.BlockLabel("done"), {
  Tr.JumpArg("extra", ref("extra")),
}):region_retarget_jump(nil, source_args).args
assert(#partial == 1 and partial[1].value == ref("extra"), "unmatched marker must pass through")

-- Empty explicit wire arguments forward the region exit arguments.
local passthrough = Tr.RegionWireBlock(Tr.BlockLabel("done"), {}):region_retarget_jump(nil, source_args).args
assert(#passthrough == 2 and passthrough[1].value == ref("x") and passthrough[2].value == ref("y"))

print("schema ParsedRegion -> Tree.Region tranche ok")
