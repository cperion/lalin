-- impl/lower_emit_c/validate.lua
-- C emission validation methods.
-- Ported from emit_c_validate.lua.

require("lalin.schema_v2")

local C    = require("lalin.schema_v2.c")
local Code = require("lalin.schema_v2.code")

----------------------------------------------------------------------
-- CBackendUnit → validate_c_unit
----------------------------------------------------------------------

function C.CBackendUnit:validate_c_unit()
  local issues = {}

  -- Validate each function in the unit
  for _, func in ipairs(self.funcs or {}) do
    for _, block in ipairs(func.blocks or {}) do
      for _, stmt in ipairs(block.stmts or {}) do
        if stmt:validate_c_stmt(issues) == false then
          -- issue already appended
        end
      end
    end
  end

  return C.CBackendValidationResult(#issues == 0, issues)
end

----------------------------------------------------------------------
-- CBackendStmt → validate_c_stmt
----------------------------------------------------------------------

function C.CBackendStmt:validate_c_stmt(issues)
  return true -- no validation needed by default
end

----------------------------------------------------------------------
-- CBackendType → c_validate_type_eq (visitor pattern for type equality)
----------------------------------------------------------------------

-- Parent defaults — return false for every non-matching pair
function C.CBackendType:c_validate_type_eq(other) return false end
function C.CBackendType:c_validate_eq_void(left) return false end
function C.CBackendType:c_validate_eq_bool8(left) return false end
function C.CBackendType:c_validate_eq_scalar(left) return false end
function C.CBackendType:c_validate_eq_index(left) return false end
function C.CBackendType:c_validate_eq_data_ptr(left) return false end
function C.CBackendType:c_validate_eq_qualified_data_ptr(left) return false end
function C.CBackendType:c_validate_eq_code_ptr(left) return false end
function C.CBackendType:c_validate_eq_imported_code_ptr(left) return false end
function C.CBackendType:c_validate_eq_named(left) return false end
function C.CBackendType:c_validate_eq_array(left) return false end
function C.CBackendType:c_validate_eq_slice_descriptor(left) return false end
function C.CBackendType:c_validate_eq_bytespan_descriptor(left) return false end
function C.CBackendType:c_validate_eq_view_descriptor(left) return false end
function C.CBackendType:c_validate_eq_closure_descriptor(left) return false end
function C.CBackendType:c_validate_eq_hidden_out_ptr(left) return false end
function C.CBackendType:c_validate_eq_vector(left) return false end

-- Void
function C.CBackendVoid:c_validate_type_eq(other) return other:c_validate_eq_void(self) end
function C.CBackendVoid:c_validate_eq_void(left) return true end

-- Bool8
function C.CBackendBool8:c_validate_type_eq(other) return other:c_validate_eq_bool8(self) end
function C.CBackendBool8:c_validate_eq_bool8(left) return true end

-- Index
function C.CBackendIndex:c_validate_type_eq(other) return other:c_validate_eq_index(self) end
function C.CBackendIndex:c_validate_eq_index(left) return true end

-- Scalar
function C.CBackendScalar:c_validate_type_eq(other) return other:c_validate_eq_scalar(self) end
function C.CBackendScalar:c_validate_eq_scalar(left) return self.scalar == left.scalar end

-- DataPtr
function C.CBackendDataPtr:c_validate_type_eq(other) return other:c_validate_eq_data_ptr(self) end
function C.CBackendDataPtr:c_validate_eq_data_ptr(left)
  if self.pointee == nil then return left.pointee == nil end
  if left.pointee == nil then return false end
  return self.pointee:c_validate_type_eq(left.pointee)
end
function C.CBackendDataPtr:c_validate_eq_qualified_data_ptr(left)
  return self:c_validate_eq_data_ptr(left)
end
function C.CBackendDataPtr:c_validate_eq_array(left)
  return self.pointee == nil or self.pointee:c_validate_type_eq(left.elem)
end

-- QualifiedDataPtr
function C.CBackendQualifiedDataPtr:c_validate_type_eq(other)
  return other:c_validate_eq_qualified_data_ptr(self)
end
function C.CBackendQualifiedDataPtr:c_validate_eq_qualified_data_ptr(left)
  if self.pointee == nil then return left.pointee == nil end
  if left.pointee == nil then return false end
  return self.qualifiers == left.qualifiers and self.pointee:c_validate_type_eq(left.pointee)
end

-- CodePtr
function C.CBackendCodePtr:c_validate_type_eq(other) return other:c_validate_eq_code_ptr(self) end
function C.CBackendCodePtr:c_validate_eq_code_ptr(left)
  return self.sig == left.sig
end

-- ImportedCodePtr
function C.CBackendImportedCodePtr:c_validate_type_eq(other)
  return other:c_validate_eq_imported_code_ptr(self)
end
function C.CBackendImportedCodePtr:c_validate_eq_imported_code_ptr(left)
  return self.sig == left.sig
end

-- Named
function C.CBackendNamed:c_validate_type_eq(other) return other:c_validate_eq_named(self) end
function C.CBackendNamed:c_validate_eq_named(left)
  return self.id.module_name == left.id.module_name and self.id.spelling == left.id.spelling
end

-- Array
function C.CBackendArray:c_validate_type_eq(other) return other:c_validate_eq_array(self) end
function C.CBackendArray:c_validate_eq_array(left)
  return self.count == left.count and self.elem:c_validate_type_eq(left.elem)
end

-- SliceDescriptor
function C.CBackendSliceDescriptor:c_validate_type_eq(other)
  return other:c_validate_eq_slice_descriptor(self)
end
function C.CBackendSliceDescriptor:c_validate_eq_slice_descriptor(left)
  if self.elem == nil then return left.elem == nil end
  if left.elem == nil then return false end
  return self.elem:c_validate_type_eq(left.elem)
end

-- ByteSpanDescriptor
function C.CBackendByteSpanDescriptor:c_validate_type_eq(other)
  return other:c_validate_eq_bytespan_descriptor(self)
end
function C.CBackendByteSpanDescriptor:c_validate_eq_bytespan_descriptor(left)
  return true
end

-- ViewDescriptor
function C.CBackendViewDescriptor:c_validate_type_eq(other)
  return other:c_validate_eq_view_descriptor(self)
end
function C.CBackendViewDescriptor:c_validate_eq_view_descriptor(left)
  if self.elem == nil then return left.elem == nil end
  if left.elem == nil then return false end
  return self.elem:c_validate_type_eq(left.elem)
end

-- ClosureDescriptor
function C.CBackendClosureDescriptor:c_validate_type_eq(other)
  return other:c_validate_eq_closure_descriptor(self)
end
function C.CBackendClosureDescriptor:c_validate_eq_closure_descriptor(left)
  return self.sig == left.sig
end

-- HiddenOutPtr
function C.CBackendAbiHiddenOutPtr:c_validate_type_eq(other)
  return other:c_validate_eq_hidden_out_ptr(self)
end
function C.CBackendAbiHiddenOutPtr:c_validate_eq_hidden_out_ptr(left)
  if self.pointee == nil then return left.pointee == nil end
  if left.pointee == nil then return false end
  return self.pointee:c_validate_type_eq(left.pointee)
end

-- Vector
function C.CBackendVector:c_validate_type_eq(other) return other:c_validate_eq_vector(self) end
function C.CBackendVector:c_validate_eq_vector(left)
  return self.lanes == left.lanes and self.elem:c_validate_type_eq(left.elem)
end
