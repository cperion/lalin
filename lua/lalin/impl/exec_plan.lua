-- impl/exec_plan.lua
-- Leaf methods on Kernel.*, Exec.*, and Stencil.* types for execution planning.
-- Ported from exec_plan.lua.
--
-- The full plan() orchestrator (which chains graph/flow/value/mem/effect
-- analysis) will be wired in pipeline.lua once all impl files exist.

local Exec    = require("lalin.schema_v2.exec")
local Kernel  = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local Flow    = require("lalin.schema_v2.flow")

----------------------------------------------------------------------
-- Kernel plan id helpers
----------------------------------------------------------------------

function Kernel.KernelPlan:exec_kernel_plan_id()
  return nil
end

function Kernel.KernelPlanned:exec_kernel_plan_id()
  return self.id
end

----------------------------------------------------------------------
-- Stencil selection → exec stencil decision
----------------------------------------------------------------------

function Stencil.StencilSelection:select_exec_stencil(input)
  return Exec.ExecSelectSkip(input.unselected_reason)
end

function Stencil.StencilSelected:select_exec_stencil(input)
  if input.artifact == nil then return Exec.ExecSelectSkip(input.missing_artifact_reason) end
  if input.func == nil then return Exec.ExecSelectSkip(input.missing_func_reason) end
  return Exec.ExecSelectStencil(input.selected_reason)
end

----------------------------------------------------------------------
-- ExecStencilSelection → add_exec_stencil
-- These methods produce ExecPlanEntry fragments from stencil selection
-- decisions.  The parent union defaults to an error; concrete leaves
-- implement the actual logic.
----------------------------------------------------------------------

function Exec.ExecStencilSelection:add_exec_stencil(entries, by_func, entry, index, kernel_plan, loop_by_id, artifact, func_id)
  error("exec_plan: unsupported exec stencil selection", 2)
end

function Exec.ExecSelectStencil:add_exec_stencil(entries, by_func, entry, index, kernel_plan, loop_by_id, artifact, func_id)
  -- kernel_blocks is a helper that resolves loop/domain subjects to
  -- their containing CodeBlockIds.  This is a local helper ported from
  -- the old code; in the new architecture the subject resolution
  -- should become a method on KernelSubject leaves.
  local function kernel_blocks(kplan, loop_by_id)
    local subject = kplan and kplan.subject or nil
    -- use class-based dispatch via the union type hierarchy
    if Kernel.KernelSubjectFragment and subject == Kernel.KernelSubjectFragment then
      -- HACK: direct field access until proper leaf methods exist
      local fragments = rawget(subject, "fragments") or {}
      local blocks = {}
      for _, f in ipairs(fragments) do
        local entry = rawget(f, "entry")
        local exit_ = rawget(f, "exit")
        if entry then blocks[#blocks + 1] = entry end
        if exit_ then blocks[#blocks + 1] = exit_ end
      end
      return blocks
    end
    if Kernel.KernelSubjectLoop and subject == Kernel.KernelSubjectLoop then
      local loop_ref = rawget(subject, "loop")
      local loop = loop_by_id[loop_ref and loop_ref.text]
      if loop then
        local blocks = {}
        if loop.header then blocks[#blocks + 1] = loop.header.block end
        for _, b in ipairs(loop.body or {}) do blocks[#blocks + 1] = b.block end
        return blocks
      end
    end
    if Kernel.KernelSubjectDomain and subject == Kernel.KernelSubjectDomain then
      local domain = rawget(subject, "domain")
      -- domain may be FlowDomainBlockRange or FlowDomainLoop
      local blk_range = Flow.FlowDomainBlockRange and domain
      if blk_range then
        return { rawget(blk_range, "entry"), rawget(blk_range, "exit") }
      end
      if Flow.FlowDomainLoop then
        local loop = loop_by_id[rawget(domain, "loop") and rawget(domain, "loop").text]
        if loop then
          local blocks = {}
          if loop.header then blocks[#blocks + 1] = loop.header.block end
          for _, b in ipairs(loop.body or {}) do blocks[#blocks + 1] = b.block end
          return blocks
        end
      end
    end
    return {}
  end

  local blocks = kernel_blocks(kernel_plan, loop_by_id)

  local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
  end

  local fragment = Exec.ExecFragment(
    Exec.ExecFragmentId("exec:" .. sanitize(func_id.text) .. ":stencil:" .. tostring(index)),
    func_id,
    blocks,
    Exec.ExecFragmentStencil(artifact, {}, Exec.ExecResultVoid)
  )
  entries[#entries + 1] = Exec.ExecPlanEntry(entry.kernel, Exec.ExecMaterializeStencil(fragment, self.reason))
  local list = by_func[func_id.text]
  if list == nil then list = {}; by_func[func_id.text] = list end
  list[#list + 1] = fragment
end

function Exec.ExecSelectSkip:add_exec_stencil(entries, by_func, entry, index, kernel_plan, loop_by_id, artifact, func_id)
  entries[#entries + 1] = Exec.ExecPlanEntry(entry.kernel, Exec.ExecSkipStencil(self.reason))
end

----------------------------------------------------------------------
-- Stencil selection → exec_plan_artifact / exec_plan_missing_artifact_reason
----------------------------------------------------------------------

function Stencil.StencilSelection:exec_plan_artifact(by_instance)
  return nil
end

function Stencil.StencilSelected:exec_plan_artifact(by_instance)
  return by_instance[self.instance.id.text]
end

function Stencil.StencilSelection:exec_plan_missing_artifact_reason()
  return "selected stencil instance has no artifact"
end

function Stencil.StencilSelected:exec_plan_missing_artifact_reason()
  return "selected stencil instance has no artifact " .. self.instance.id.text
end
