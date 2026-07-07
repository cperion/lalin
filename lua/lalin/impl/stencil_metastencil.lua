-- impl/stencil_metastencil.lua
-- Leaf methods on LalinStencil types for metastencil fusion.
-- Ported from stencil_metastencil.lua.
--
-- The heavy algorithm logic (legality checking, cover selection, fusion
-- artifact generation) lives as local helpers.  When the stencil_plan
-- infrastructure is fully ported, those will become methods on the
-- appropriate ASDL types.
--
-- Currently installed:
--   Stencil.StencilDescriptor:metastencil_access_named(name)
--   Stencil.StencilReduceScope*:metastencil_dst_name()

local Stencil = require("lalin.schema_v2.stencil")

----------------------------------------------------------------------
-- Stencil.StencilDescriptor:metastencil_access_named
--
-- Finds the access with the given name in this descriptor.
-- Depends on descriptor_accesses, which in the old code is
-- Plan.descriptor_accesses(desc).  In the new impl, this will be
-- a method on StencilDescriptor once stencil_plan.lua is ported.
-- For now we walk the body access list directly.
----------------------------------------------------------------------

function Stencil.StencilDescriptor:metastencil_access_named(name)
  -- Walk the descriptor accesses.  In old code this was Plan.descriptor_accesses(self).
  -- The body may be a StencilBodyPoint with a single access, or more complex.
  local body = self.body
  if body == nil then return nil end

  -- StencilBodyPoint carries the expression; accesses are in the descriptor's
  -- access list (descriptor.accesses) or baked into the body.
  -- Old code gathered accesses via Plan.descriptor_accesses which unified
  -- both the body's expression inputs and any sink-related accesses.
  --
  -- For now, walk what we know: body inputs + sink accesses.
  -- Full unification will come when stencil_plan.lua installs
  -- descriptor_accesses as a method.

  -- body may have an expr with inputs (StencilPointExpr)
  if body.expr ~= nil and body.expr.access ~= nil then
    if body.expr.access.name == name then
      return { name = name, ty = nil, role = nil, layout = nil }
    end
  end

  -- check sink-related accesses if any
  if self.sink ~= nil then
    -- StencilSink subtypes may carry named data references
    if self.sink.dst ~= nil and self.sink.dst.name == name then
      return { name = name, ty = nil, role = self.sink.dst.role, layout = self.sink.dst.layout or nil }
    end
    if self.sink.reduction ~= nil and self.sink.reduction.dst ~= nil and self.sink.reduction.dst.name == name then
      return { name = name, ty = nil, role = "reduce", layout = nil }
    end
  end

  return nil
end

----------------------------------------------------------------------
-- Stencil.StencilReduceScope:metastencil_dst_name
-- Returns the name of the destination access for a reduce scope.
----------------------------------------------------------------------

function Stencil.StencilReduceScope:metastencil_dst_name()
  return nil
end

function Stencil.StencilReduceScopeAxes:metastencil_dst_name()
  if self.dst ~= nil then return self.dst.name end
  return nil
end

function Stencil.StencilReduceScopeWindow:metastencil_dst_name()
  if self.dst ~= nil then return self.dst.name end
  return nil
end
