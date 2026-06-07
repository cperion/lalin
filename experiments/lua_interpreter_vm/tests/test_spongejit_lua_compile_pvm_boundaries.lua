#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local C = require("lua_compile")
local T = C.schema.get()
local Src, RT, Exec, S = T.LuaSrc, T.LuaRT, T.LuaExec, T.Stencil

local Decode = C.lua_src_from_puc_decode
local Collect = C.lua_src_window_collect
local EvidenceImport = C.lua_fact_from_runtime_observe
local Unit = C.lua_compile_unit
local ExecLower = C.lua_src_to_lua_exec_lower
local ExecToMoon = C.lua_exec_to_moon_cfg_lower
local StaticInline = C.lua_exec_static_region_inline
local Emit = C.moon_cfg_emit
local CFGKey = C.moon_cfg_key
local ContractKey = C.compile_contract_key
local StencilKey = C.stencil_key
local Plan = C.stencil_materialization_plan
local Materialize = C.stencil_materialize
local Bundle = C.stencil_bundle

local function assert_cached(label, phase, thunk)
  assert(phase and phase.reset and phase.stats, label .. " is not a pvm.phase")
  phase:reset()
  thunk()
  local h1 = phase:stats().hits
  thunk()
  local h2 = phase:stats().hits
  assert(h2 > h1, label .. " did not report a cache hit")
end

local event = Decode.canonical_event({ op = "RETURN0", pc = 1 })
assert_cached("decode", Decode.phase, function()
  local op = Decode.decode_event(event)
  assert(op.kind == "RETURN0")
end)

local batch = Collect.event_batch({ event })
assert_cached("window collect", Collect.phase, function()
  local window = Collect.collect(batch)
  assert(#window.ops == 1 and window.ops[1].kind == "RETURN0")
end)

local evidence_input = EvidenceImport.evidence_input({}, T.LuaRegion.RegionSet({}))
assert_cached("evidence import", EvidenceImport.phase, function()
  local evidence = EvidenceImport.import(evidence_input)
  assert(pvm.classof(evidence) == T.LuaFact.Evidence)
end)

assert_cached("unit construction", Unit.phase, function()
  local unit = Unit.from_inputs(batch, evidence_input)
  assert(pvm.classof(unit) == T.LuaCompile.Unit)
end)

local window = Collect.collect(batch)
local evidence = EvidenceImport.import(evidence_input)
assert_cached("LuaSrc to LuaExec success", ExecLower.phase, function()
  local result = ExecLower.lower_result(window, evidence)
  assert(result.kind == "ExecLowerOk")
end)

local bad_window = Collect.collect({ { op = "CALL", pc = 1, a = 0, b = 2, c = 2 }, { op = "RETURN0", pc = 2 } })
assert_cached("LuaSrc to LuaExec reject", ExecLower.phase, function()
  local result = ExecLower.lower_result(bad_window, evidence)
  assert(result.kind == "ExecLowerReject")
end)

local call_op = Src.CALL(Src.Pc(1), Src.Slot(0), Src.Count(2), Src.Count(2))
local call_ret_ref = Exec.BlockRef(Exec.BlockId(Exec.Name("ret")))
local no_args = {}
assert_cached("source CALL products reject", C.lua_src_call_static_model.phase, function()
  local r = pvm.one(C.lua_src_call_static_model.phase(call_op, evidence, call_ret_ref, no_args))
  assert(r.kind == "StaticCallProductsReject")
end)

local closure_op = Src.CLOSURE(Src.Pc(1), Src.Slot(0), Src.KRef(9))
assert_cached("source CLOSURE products reject", C.lua_src_closure_static_model.phase, function()
  local r = pvm.one(C.lua_src_closure_static_model.phase(closure_op, evidence))
  assert(r.kind == "StaticClosureProductsReject")
end)

local exec_product = assert(ExecLower.lower(window, evidence))
assert(pvm.classof(exec_product) == Exec.Kernel)
assert_cached("LuaExec to MoonCFG kernel", ExecToMoon.phase, function()
  local result = ExecToMoon.lower_result(exec_product)
  assert(result.kind == "MoonLowerOk")
end)
local cfg = assert(ExecToMoon.lower(exec_product))

local empty_module = Exec.Module({}, {})
assert_cached("static inline reject", StaticInline.phase, function()
  local r = StaticInline.inline_result(empty_module, "")
  assert(r.kind == "StaticInlineReject")
end)
assert_cached("LuaExec module to MoonCFG reject", ExecToMoon.module_phase, function()
  local r = ExecToMoon.lower_module_result(empty_module, nil)
  assert(r.kind == "MoonLowerReject")
end)

assert_cached("MoonCFG emit", Emit.phase, function()
  local src = Emit.emit(cfg, { name = "pvm_boundary_kernel" })
  assert(src:match("pvm_boundary_kernel"))
end)
assert_cached("MoonCFG key", CFGKey.phase, function()
  assert(CFGKey.key(cfg):match("MoonCFG"))
end)
assert_cached("CompileContract key", ContractKey.phase, function()
  assert(ContractKey.key(cfg.contract):match("CompileContract"))
end)

local variant_opts = {}
local variant = Plan.variant_for_kernel(cfg, cfg.contract, variant_opts)
assert_cached("Stencil variant for kernel", Plan.variant_phase, function()
  local v = Plan.variant_for_kernel(cfg, cfg.contract, variant_opts)
  assert(pvm.classof(v) == S.VariantKey)
end)
assert_cached("Stencil semantic key", StencilKey.semantic_phase, function()
  assert(#StencilKey.semantic_key(cfg) > 0)
end)
assert_cached("Stencil variant key", StencilKey.variant_phase, function()
  assert(StencilKey.variant_key(variant):match("Stencil.VariantKey"))
end)

local bytes = string.char(1, 2, 3, 4)
local entry = S.Symbol(S.Name("entry"), S.EntrySymbol, S.Local, 0)
local code = S.CodeBlobRef(S.Name("blob"), #bytes, "sha256:" .. Materialize.sha256_hex(bytes))
local template = S.StencilTemplate(
  S.Name("boundary_template"),
  S.KernelStencil,
  variant,
  code,
  {},
  {},
  { entry },
  S.MaterializationPlan({}, {}, S.EntryPoint(entry, variant.target_abi))
)
assert_cached("Stencil template key", StencilKey.template_phase, function()
  assert(StencilKey.template_key(template):match("Stencil.Template"))
end)
local blob_map = { blob = bytes }
local mat_opts = {}
assert_cached("Stencil materialize", Materialize.phase, function()
  local image = assert(Materialize.materialize(template, blob_map, mat_opts))
  assert(image.bytes == bytes)
end)

local bank = S.BankIndex({ variant }, { S.TemplateIndexEntry(variant, template.name) })
local module = S.StencilModule(bank, { template }, { entry }, S.Linkage({}, {}, {}))
local bundle_opts = {}
assert_cached("Stencil bundle materialize all", Bundle.materialize_all_phase, function()
  local bundle = assert(Bundle.materialize_all(module, blob_map, bundle_opts))
  assert(#bundle.images == 1)
end)

-- Direct guardrails remain rejected through existing public APIs.
local direct_emit_region = Exec.Region(Exec.Name("r"), Exec.ReturnRegion, {}, {}, Exec.BlockId(Exec.Name("entry")), {
  Exec.Block(Exec.BlockId(Exec.Name("entry")), {}, { Exec.EmitRegion(Exec.Name("callee"), {}, {}) }, Exec.Unreachable)
})
local frame_ref = RT.FrameRef(RT.Name("frame0"))
local direct_kernel = Exec.Kernel(Exec.Name("k"), RT.Frame(frame_ref, RT.StackRef(frame_ref), RT.TopRef(frame_ref), RT.NoVarargs, RT.CloseChain(frame_ref, {}), RT.Pc(1)), direct_emit_region, Exec.Contract({}, {}))
local bad_cfg, bad_errors = ExecToMoon.lower(direct_kernel)
assert(not bad_cfg and table.concat(bad_errors or {}, ";"):match("EmitRegion"), "direct kernel EmitRegion must still reject")

print("ok - SpongeJIT LuaCompile PVM boundaries")
