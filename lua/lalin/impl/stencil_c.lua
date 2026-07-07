-- impl/stencil_c.lua
-- C-specific stencil codegen methods on LalinStencil types.
-- Ported from stencil_c.lua.

local Stencil = require("lalin.schema_v2.stencil")

----------------------------------------------------------------------
-- StencilProducerShape → stencil_c_param_structs
----------------------------------------------------------------------

function Stencil.StencilProducerShape:stencil_c_param_structs()
  return {}
end

function Stencil.StencilProduceRange1D:stencil_c_param_structs()
  return {}
end

function Stencil.StencilProduceRangeND:stencil_c_param_structs()
  local structs = {}
  for _, axis in ipairs(self.axes or {}) do
    structs[#structs + 1] = { axis = axis, kind = "range_nd" }
  end
  return structs
end

function Stencil.StencilProduceWindowND:stencil_c_param_structs()
  local structs = {}
  for _, axis in ipairs(self.axes or {}) do
    structs[#structs + 1] = { axis = axis, kind = "window_nd" }
  end
  return structs
end

function Stencil.StencilProduceTiledND:stencil_c_param_structs()
  local structs = {}
  for _, axis in ipairs(self.axes or {}) do
    structs[#structs + 1] = { axis = axis, kind = "tiled_nd" }
  end
  return structs
end

----------------------------------------------------------------------
-- StencilProducerShape → stencil_c_loop
----------------------------------------------------------------------

function Stencil.StencilProducerShape:stencil_c_loop(body_for_index)
  error("stencil_c: unsupported producer shape for C loop emission", 2)
end

function Stencil.StencilProduceRange1D:stencil_c_loop(body_for_index)
  return "for (size_t i = 0; i < n; ++i) { " .. body_for_index("i") .. " }"
end

function Stencil.StencilProduceRangeND:stencil_c_loop(body_for_index)
  local inner = body_for_index("i0")
  for i = #self.axes, 2, -1 do
    local idx = "i" .. tostring(i - 1)
    inner = "for (size_t " .. idx .. " = 0; " .. idx .. " < n" .. tostring(i) .. "; ++" .. idx .. ") { " .. inner .. " }"
  end
  return inner
end

function Stencil.StencilProduceWindowND:stencil_c_loop(body_for_index)
  return Stencil.StencilProduceRangeND:stencil_c_loop(body_for_index)
end

function Stencil.StencilProduceTiledND:stencil_c_loop(body_for_index)
  return Stencil.StencilProduceRangeND:stencil_c_loop(body_for_index)
end

----------------------------------------------------------------------
-- StencilProducerShape → stencil_c_is_window_nd / is_range1d
----------------------------------------------------------------------

function Stencil.StencilProducerShape:stencil_c_is_window_nd() return false end
function Stencil.StencilProduceWindowND:stencil_c_is_window_nd() return true end

function Stencil.StencilProducerShape:stencil_c_is_range1d() return false end
function Stencil.StencilProduceRange1D:stencil_c_is_range1d() return true end

----------------------------------------------------------------------
-- StencilDescriptor → stencil_c_access_named
----------------------------------------------------------------------

function Stencil.StencilDescriptor:stencil_c_access_named(name)
  for _, access in ipairs(self.accesses or {}) do
    if access.name == name then return access end
  end
  return nil
end

----------------------------------------------------------------------
-- StencilAccessLayout → is_scalar_layout / offset / access_expr
----------------------------------------------------------------------

function Stencil.StencilAccessLayout:stencil_c_is_scalar_layout() return false end
function Stencil.StencilLayoutScalar:stencil_c_is_scalar_layout() return true end

function Stencil.StencilAccessLayout:stencil_c_offset(access, index, access_scope, loop_scope)
  return "0"
end

function Stencil.StencilLayoutFieldProjection:stencil_c_offset(access, index, access_scope, loop_scope)
  return "offsetof(/* struct */, " .. self.field_name .. ")"
end

function Stencil.StencilLayoutSoAComponent:stencil_c_offset(access, index, access_scope, loop_scope)
  return "offsetof(/* struct */, " .. self.field_name .. ") + comp * sizeof(elem)"
end

function Stencil.StencilLayoutIndexed:stencil_c_offset(access, index, access_scope, loop_scope)
  local stride = self.stride or 1
  return "(" .. index .. ") * " .. tostring(stride) .. " * sizeof(elem)"
end

function Stencil.StencilLayoutAffine1D:stencil_c_offset(access, index, access_scope, loop_scope)
  local scale = self.scale or 1
  local base = self.offset or "0"
  return "(" .. base .. " + (" .. index .. ") * " .. tostring(scale) .. ") * sizeof(elem)"
end

function Stencil.StencilLayoutAffineND:stencil_c_offset(access, index, access_scope, loop_scope)
  local terms = {}
  for _, term in ipairs(self.terms or {}) do
    local coeff = term.coeff or 1
    local idx = term.axis_index or "0"
    terms[#terms + 1] = tostring(coeff) .. " * " .. idx
  end
  local base = self.offset or "0"
  return "(" .. base .. " + " .. table.concat(terms, " + ") .. ") * sizeof(elem)"
end

function Stencil.StencilLayoutViewDescriptor:stencil_c_offset(access, index, access_scope, loop_scope)
  return "(" .. index .. ") * view_stride * sizeof(elem)"
end

function Stencil.StencilAccessLayout:stencil_c_access_expr(access, base, index, access_scope, loop_scope)
  local offset = self:stencil_c_offset(access, index, access_scope, loop_scope)
  return "*((" .. (access.ty and "elem_t*" or "char*") .. ")((char*)" .. base .. " + " .. offset .. "))"
end

function Stencil.StencilLayoutFieldProjection:stencil_c_access_expr(access, base, index, access_scope, loop_scope)
  return base .. "->" .. self.field_name
end

----------------------------------------------------------------------
-- StencilAccessLayout → stencil_c_field_layout_for_param
----------------------------------------------------------------------

function Stencil.StencilAccessLayout:stencil_c_field_layout_for_param()
  return "void*"
end

function Stencil.StencilLayoutFieldProjection:stencil_c_field_layout_for_param()
  return self.record_ty and self.record_ty:code_to_c_type_name() or "void*"
end

function Stencil.StencilLayoutIndexed:stencil_c_field_layout_for_param()
  return "void*"
end

function Stencil.StencilLayoutAffine1D:stencil_c_field_layout_for_param()
  return "void*"
end

function Stencil.StencilLayoutAffineND:stencil_c_field_layout_for_param()
  return "void*"
end

----------------------------------------------------------------------
-- StencilSelected → stencil_c_emit (stub)
----------------------------------------------------------------------

function Stencil.StencilSelected:stencil_c_emit(ctx)
  -- C emission entry point for a selected stencil.
  -- Full emission requires schedule, producer, and access context.
  local descriptor = self.descriptor
  if descriptor == nil then return "/* no descriptor */" end
  local producer = descriptor.producer
  if producer == nil then return "/* no producer */" end
  local shape = producer.shape
  local body = "/* stencil body */"
  return shape:stencil_c_loop(function(idx) return body end)
end
