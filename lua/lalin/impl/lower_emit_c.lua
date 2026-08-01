-- Typed Code IR to CBackend lowering composition.
require("lalin.schema_v2")

local Lower = require("lalin.schema_v2.lower")
local Code = require("lalin.schema_v2.code")
local C = require("lalin.schema_v2.c")
local Core = require("lalin.schema_v2.core")

require("lalin.impl.lower_emit_c.code_to_c")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.stencil")
require("lalin.impl.lower_emit_c.fragment")
require("lalin.impl.lower_emit_c.lower_sem")
require("lalin.impl.lower_emit_c.assembly")

function Lower.LowerCSignatureProjection:lower_c_signature_lookup(sig)
  for i = 1, #self.entries do
    if self.entries[i].code_sig == sig then return Lower.LowerCSignatureFound(self.entries[i]) end
  end
  return Lower.LowerCSignatureMissing(sig)
end
function Lower.LowerCSignatureFound:lower_c_sig_id() return self.entry.c_sig_id end
function Lower.LowerCSignatureMissing:lower_c_sig_id() error("C lowering missing validated signature " .. self.sig.text, 2) end
function Lower.LowerFunctionPlanProjection:lower_function_plan_lookup(func)
  for i = 1, #self.entries do
    if self.entries[i].func == func then return Lower.LowerFunctionPlanFound(self.entries[i]) end
  end
  return Lower.LowerFunctionPlanMissing(func)
end
function Lower.LowerFunctionPlanFound:lower_c_function_assembly(input, func, baseline)
  return Lower.LowerCFunctionAssemblyInput(input.spine, func, self.entry.plan, baseline,
    input.materializations, input.plan.addresses):lower_c_function_assembly()
end
function Lower.LowerFunctionPlanMissing:lower_c_function_assembly(_input, func, baseline)
  return Lower.LowerCFunctionAssemblyReady(Lower.LowerCFunctionAssembly(
    func, baseline, {}, baseline:lower_c_body_blocks(), baseline.func.locals, baseline.helpers))
end

function Code.CodeSig:lower_c_signature_entry()
  local params = {}
  for i = 1, #self.params do params[i] = self.params[i]:code_to_c_backend_type() end
  local result = C.CBackendVoid
  if #self.results == 1 then result = self.results[1]:code_to_c_backend_type() end
  local id = C.CBackendFuncSigId(self.id.text)
  return Lower.LowerCSignatureEntry(self.id, self, id, C.CBackendFuncSig(id, params, result))
end
function Code.CodeModule:lower_c_signature_projection()
  local entries = {}
  for i = 1, #self.sigs do entries[i] = self.sigs[i]:lower_c_signature_entry() end
  return Lower.LowerCSignatureProjection(entries)
end

local function append_values(projection, additions)
  local entries = {}
  for i = 1, #projection.entries do entries[#entries + 1] = projection.entries[i] end
  for i = 1, #additions do entries[#entries + 1] = additions[i] end
  return Lower.LowerCValueTypeProjection(entries)
end
local function append_items(target, source) for i = 1, #source do target[#target + 1] = source[i] end end
local function append_helpers(target, source)
  for i = 1, #source do
    local duplicate = false
    for j = 1, #target do if target[j].id == source[i].id then duplicate = true end end
    if not duplicate then target[#target + 1] = source[i] end
  end
end

function Code.CodeParam:lower_c_value_entry()
  return Lower.LowerCValueTypeEntry(self.value, self.ty, self:code_to_c_local())
end

function Code.CodeBlock:lower_c_block(input)
  local values, stmts, helpers, locals, value_sites =
    input.values, {}, {}, {}, {}
  local params = {}
  for i = 1, #self.params do
    local entry = self.params[i]:lower_c_value_entry()
    params[i] = C.CBackendBlockParam(entry.c_local.id, entry.c_local.ty)
  end
  for i = 1, #self.insts do
    local result = self.insts[i]:lower_to_c_backend(Lower.LowerCInstructionInput(input.signatures, values))
    append_items(stmts, result.stmts)
    append_helpers(helpers, result.helpers)
    append_items(locals, result.locals)
    values = append_values(values, result.definitions)
    for j = 1, #result.definitions do
      value_sites[#value_sites + 1] = Lower.LowerCValueSiteEntry(
        result.definitions[j].value,
        Lower.LowerCInstructionSite(self.id, self.insts[i].id))
    end
  end
  if self.term == nil then error("validated C lowering received unterminated block " .. self.id.text, 2) end
  local term = self.term:lower_to_c_backend_term(Lower.LowerCTermInput(values))
  local block = C.CBackendBlock(C.CBackendLabel(self.id.text), params, stmts, term.term)
  return Lower.LowerCBlockEmission(
    block, helpers, locals, values, value_sites)
end

function Code.CodeLinkage:lower_c_visibility() return Core.VisibilityLocal end
function Code.CodeLinkageLocal:lower_c_visibility() return Core.VisibilityLocal end
function Code.CodeLinkageExport:lower_c_visibility() return Core.VisibilityExport end
function Code.CodeLinkageImport:lower_c_visibility() return Core.VisibilityLocal end
function Code.CodeLinkageDeclaration:lower_c_visibility() return Core.VisibilityLocal end

function Code.CodeFunc:lower_c_function(input)
  local value_entries, params, locals, value_sites, block_params =
    {}, {}, {}, {}, {}
  for i = 1, #self.params do
    local entry = self.params[i]:lower_c_value_entry()
    value_entries[#value_entries + 1], params[#params + 1] = entry, entry.c_local
    value_sites[#value_sites + 1] = Lower.LowerCValueSiteEntry(
      entry.value, Lower.LowerCFunctionParamSite)
  end
  for i = 1, #self.locals do
    locals[#locals + 1] = C.CBackendLocal(self.locals[i].id:code_to_c_local_id(), C.CBackendName(self.locals[i].name), self.locals[i].ty:code_to_c_backend_type())
  end
  for i = 1, #self.blocks do
    for j = 1, #self.blocks[i].params do
      local entry = self.blocks[i].params[j]:lower_c_value_entry()
      value_entries[#value_entries + 1] = entry
      value_sites[#value_sites + 1] = Lower.LowerCValueSiteEntry(
        entry.value, Lower.LowerCBlockParamSite(self.blocks[i].id))
      block_params[#block_params + 1] = Lower.LowerCBlockParamEntry(
        self.blocks[i].id, j, entry,
        C.CBackendBlockParam(entry.c_local.id, entry.c_local.ty))
    end
  end
  local values = Lower.LowerCValueTypeProjection(value_entries)
  local blocks, helpers = {}, {}
  for i = 1, #self.blocks do
    local result = self.blocks[i]:lower_c_block(Lower.LowerCBlockInput(input.signatures, values))
    blocks[#blocks + 1] = result.block
    append_helpers(helpers, result.helpers)
    append_items(locals, result.locals)
    values = result.values
    append_items(value_sites, result.value_sites)
  end
  local entry = C.CBackendLabel(self.entry.text)
  local sig_id = input.signatures:lower_c_signature_lookup(self.sig):lower_c_sig_id()
  local func = C.CBackendFunc(C.CBackendName(self.name), self.name, self.linkage:lower_c_visibility(), sig_id, params, locals, C.CBackendBodyBlocks(entry, blocks))
  return Lower.LowerCFunctionEmission(
    func, helpers, values, Lower.LowerCValueSiteProjection(value_sites),
    self, Lower.LowerCBlockParamProjection(block_params))
end

function Code.CodeDataInit:lower_code_data_init_to_c() error("missing lower_code_data_init_to_c leaf method", 2) end
function Code.CodeDataZero:lower_code_data_init_to_c() return C.CBackendDataZero(self.offset, self.size) end
function Code.CodeDataBytes:lower_code_data_init_to_c() return C.CBackendDataBytes(self.offset, self.bytes) end
function Code.CodeDataScalar:lower_code_data_init_to_c() return C.CBackendDataScalar(self.offset, self.ty:code_to_c_backend_type(), self.literal) end
function Code.CodeGlobalRefFunc:lower_c_reloc_target() return C.CBackendRelocFunc(C.CBackendName(self.func.text)) end
function Code.CodeGlobalRefExtern:lower_c_reloc_target() return C.CBackendRelocExtern(C.CBackendName(self.extern.text)) end
function Code.CodeGlobalRefGlobal:lower_c_reloc_target() return C.CBackendRelocGlobal(C.CBackendGlobalId(self.global.text)) end
function Code.CodeGlobalRefData:lower_c_reloc_target() return C.CBackendRelocGlobal(C.CBackendGlobalId(self.data.text)) end
function Code.CodeDataReloc:lower_code_data_init_to_c() return C.CBackendDataReloc(self.reloc.offset, self.reloc.target:lower_c_reloc_target(), self.reloc.addend) end

function Code.CodeType:lower_c_decl_id(fallback_name) return C.CTypeId(fallback_name, fallback_name) end
function Code.CodeTyNamed:lower_c_decl_id(fallback_name) return C.CTypeId(self.module_name, self.type_name) end
function Code.CodeTypeDecl:lower_code_type_decl_to_c() return C.CBackendOpaqueDecl(self.ty:lower_c_decl_id(self.name)) end

local function lower_inits(inits)
  local result = {}
  for i = 1, #inits do result[i] = inits[i]:lower_code_data_init_to_c() end
  return result
end
function Code.CodeGlobal:lower_c_global()
  return C.CBackendGlobal(C.CBackendGlobalId(self.id.text), C.CBackendName(self.name), self.linkage:lower_c_visibility(), self.ty:code_to_c_backend_type(), self.size or 0, self.align or 8, lower_inits(self.inits))
end
function Code.CodeData:lower_c_global()
  return C.CBackendGlobal(C.CBackendGlobalId(self.id.text), C.CBackendName(self.name), self.linkage:lower_c_visibility(), C.CBackendDataPtr(nil), self.size, self.align, lower_inits(self.inits))
end
function Code.CodeExtern:lower_c_extern() return C.CBackendExtern(C.CBackendName(self.name), self.symbol, C.CBackendFuncSigId(self.sig.text), nil) end

function Lower.LowerModule:lower_c_module(input)
  local spine = input.spine
  local code_module = spine.code_module
  local signatures = code_module:lower_c_signature_projection()
  local sigs = {}
  for i = 1, #signatures.entries do sigs[i] = signatures.entries[i].c_sig end
  local functions, cfuncs, helpers, issues = {}, {}, {}, {}
  for i = 1, #code_module.funcs do
    local func = code_module.funcs[i]
    local baseline = func:lower_c_function(Lower.LowerCFunctionInput(signatures))
    local assembly = input.plan.funcs:lower_function_plan_lookup(func.id)
      :lower_c_function_assembly(input, func, baseline)
    for _, emission in ipairs(assembly:lower_c_module_functions()) do
      functions[#functions + 1] = emission
    end
    for _, issue in ipairs(assembly:lower_c_module_issues()) do
      issues[#issues + 1] = issue
    end
  end
  if #issues > 0 then return Lower.LowerCModuleRejected(issues) end
  for i = 1, #functions do cfuncs[#cfuncs + 1] = functions[i].func end
  for i = 1, #functions do append_helpers(helpers, functions[i].helpers) end
  local externs = {}
  for i = 1, #code_module.externs do externs[i] = code_module.externs[i]:lower_c_extern() end
  local globals = {}
  for i = 1, #code_module.globals do globals[#globals + 1] = code_module.globals[i]:lower_c_global() end
  for i = 1, #code_module.data do globals[#globals + 1] = code_module.data[i]:lower_c_global() end
  local types = {}
  for i = 1, #code_module.types do types[i] = code_module.types[i]:lower_code_type_decl_to_c() end
  local unit = C.CBackendUnit(code_module.id.text, spine.target, sigs, types, globals, externs, helpers, cfuncs)
  return Lower.LowerCModuleEmitted(Lower.LowerCModuleEmission(unit, signatures, functions))
end
function Lower.LowerCModuleEmitted:lower_c_unit() return self.emission.unit end
function Lower.LowerCModuleRejected:lower_c_unit()
  error("typed canonical C lowering rejected with " .. #self.issues .. " issue(s)", 2)
end
function Lower.LowerModule:emit_c(input) return self:lower_c_module(input):lower_c_unit() end

return Lower
