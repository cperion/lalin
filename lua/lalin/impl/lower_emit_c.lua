-- impl/lower_emit_c.lua
-- Entry point: LowerModule:emit_c(code_module) → CBackendUnit
-- Ported from lower_to_c.lua lower module emission logic.

require("lalin.schema_v2")
local Lower  = require("lalin.schema_v2.lower")
local Code   = require("lalin.schema_v2.code")
local C      = require("lalin.schema_v2.c")
local Core   = require("lalin.schema_v2.core")

-- Load sub-modules for schedule forms and code-to-c conversion
require("lalin.impl.lower_emit_c.schedule_form")
require("lalin.impl.lower_emit_c.code_to_c")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.validate")

-----------------------------------------------------------------------
-- Forward declarations (prevent capture of global LLBL symbols)
-----------------------------------------------------------------------
local lower_code_func
local lower_code_block

-----------------------------------------------------------------------
-- lower_code_block: CodeBlock → CBackendBlock
-----------------------------------------------------------------------
local function lower_code_block(block, helpers)
  local stmts = {}
  local lowered = { stmts = stmts, helpers = helpers }

  -- Lower instructions
  for _, inst in ipairs(block.insts or {}) do
    inst:lower_to_c_backend(lowered)
  end

  -- Lower terminator
  local term
  if block.term then
    term = block.term:lower_to_c_backend_term(lowered)
  else
    term = C.CBackendTrap
  end

  local label = C.CBackendLabel(block.id.text)
  return C.CBackendBlock(label, {}, stmts, term)
end

-----------------------------------------------------------------------
-- lower_code_func: CodeFunc → { cfunc = CBackendFunc, helpers = [] }
-----------------------------------------------------------------------
local function lower_code_func(cfunc, csig_by_id)
  local locals = {}
  local blocks = {}
  local helpers = {}

  -- Map params to CBackendLocal
  for _, param in ipairs(cfunc.params or {}) do
    locals[#locals + 1] = param:code_to_c_local()
  end

  -- Collect all CodeValueIds used in insts and block params for local registration
  local value_local = {}
  for _, param in ipairs(cfunc.params or {}) do
    value_local[param.value.text] = true
  end

  local function scan_value_id(vid)
    if vid and vid.text and not value_local[vid.text] then
      value_local[vid.text] = true
    end
  end

  for _, block in ipairs(cfunc.blocks or {}) do
    for _, bparam in ipairs(block.params or {}) do
      scan_value_id(bparam.value)
    end
    for _, inst in ipairs(block.insts or {}) do
      if inst.op then
        local dst = inst.op.dst
        if dst then scan_value_id(dst) end
      end
    end
  end

  -- Register discovered non-param values as locals
  for vtext, _ in pairs(value_local) do
    local already_param = false
    for _, param in ipairs(cfunc.params or {}) do
      if param.value.text == vtext then already_param = true; break end
    end
    if not already_param then
      locals[#locals + 1] = C.CBackendLocal(
        C.CBackendLocalId(vtext),
        C.CBackendName(vtext),
        C.CBackendScalar(Core.ScalarI32)
      )
    end
  end

  -- Lower each block
  local entry_label = nil
  for _, block in ipairs(cfunc.blocks or {}) do
    if entry_label == nil then
      entry_label = C.CBackendLabel(block.id.text)
    end
    local lowered_block = lower_code_block(block, helpers)
    blocks[#blocks + 1] = lowered_block
  end

  if entry_label == nil then
    entry_label = C.CBackendLabel("entry")
  end

  local sig_id = cfunc.sig and csig_by_id[cfunc.sig.text]
    or C.CBackendFuncSigId(cfunc.id.text .. "_sig")

  local param_count = #(cfunc.params or {})
  local param_locals = {}
  for i = 1, param_count do
    param_locals[i] = locals[i]
  end
  -- Remove params from locals to avoid double-declaration
  for i = param_count, 1, -1 do table.remove(locals, i) end

  local visibility = Core.VisibilityExport
  if cfunc.linkage and cfunc.linkage == Code.CodeLinkageLocal then
    visibility = Core.VisibilityLocal
  end

  local cfunc_result = C.CBackendFunc(
    C.CBackendName(cfunc.name),
    cfunc.name,
    visibility,
    sig_id,
    param_locals,
    locals,
    C.CBackendBodyBlocks(entry_label, blocks)
  )

  return { cfunc = cfunc_result, helpers = helpers }
end

-----------------------------------------------------------------------
-- LowerModule:emit_c(code_module) → CBackendUnit
-----------------------------------------------------------------------

function Lower.LowerModule:emit_c(code_module)
  local sigs = {}
  local helpers = {}
  local cfuncs = {}

  -- Build a temporary CodeSig→CBackendFuncSig index
  local csig_by_id = {}
  for _, sig in ipairs(code_module.sigs or {}) do
    local params = {}
    for _, ct in ipairs(sig.params or {}) do
      params[#params + 1] = ct:code_to_c_backend_type()
    end
    local results = {}
    for _, rt in ipairs(sig.results or {}) do
      results[#results + 1] = rt:code_to_c_backend_type()
    end
    local result_ty
    if #results == 0 then
      result_ty = C.CBackendVoid
    elseif #results == 1 then
      result_ty = results[1]
    else
      result_ty = C.CBackendVoid
    end
    local c_sig_id = C.CBackendFuncSigId(sig.id.text)
    local c_sig = C.CBackendFuncSig(c_sig_id, params, result_ty)
    csig_by_id[sig.id.text] = c_sig_id
    sigs[#sigs + 1] = c_sig
  end

  -- Lower each CodeFunc
  for _, cfunc in ipairs(code_module.funcs or {}) do
    local lowered = lower_code_func(cfunc, csig_by_id)
    for _, h in ipairs(lowered.helpers or {}) do
      helpers[#helpers + 1] = h
    end
    cfuncs[#cfuncs + 1] = lowered.cfunc
  end

  return C.CBackendUnit(
    code_module.id.text,
    C.CBackendTarget(
      C.CBackendC99,
      C.CBackendHostedNative,
      64,
      64,
      C.CBackendLittleEndian,
      true
    ),
    sigs,
    {},
    {},
    {},
    helpers,
    cfuncs
  )
end
