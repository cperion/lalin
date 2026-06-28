-- lalin.syntax.for_to_loop
-- Lowers parsed StmtForRange into LalinTree.ControlStmtRegion (4-block CPS).
-- Follows the same lowering pattern as the DSL's native_loop_stmt_tree.
--
-- Usage: local for_to_loop = require("lalin.syntax.for_to_loop")(T)

local pvm = require("lalin.pvm")

local function bind_context(T)
  if not T.LalinCore then
    require("lalin.schema_projection")(T)
  end
  local C, Ty, B, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree

  local to_tree = require("lalin.syntax.to_tree")(T)
  local M = {}
  local loop_seq = 0

  --- Lower a parsed StmtForRange (1D range) into LalinTree ASDL.
  --   for i in range(lo, hi) do ... end    step defaults to 1
  --   for i in range(lo, hi, step) do ... end
  function M.lower(parsed)
    loop_seq = loop_seq + 1
    local tag = "parsed." .. tostring(loop_seq)
    local index = parsed.index
    local args = parsed.args or {}
    local idx_ty = Ty.TScalar(C.ScalarIndex)

    -- Cast range arguments to index type, matching the DSL lowering pattern.
    local function to_idx(v)
      return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, idx_ty, to_tree.expr(v))
    end
    local zero  = to_idx({ tag = "Literal", kind = "number", value = 0 })
    local one   = to_idx({ tag = "Literal", kind = "number", value = 1 })
    local start_expr = args[1] and to_idx(args[1]) or zero
    local stop_expr  = args[2] and to_idx(args[2]) or one
    local step_expr  = args[3] and to_idx(args[3]) or one

    -- Build loop body: original body statements + tail jump back to loop header
    local body_stmts = to_tree.stmts(parsed.body)
    local index_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(index))
    local next_index = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, index_ref, step_expr)
    local cond = Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, index_ref, stop_expr)

    local entry_label  = Tr.BlockLabel(tag .. ".entry")
    local loop_label   = Tr.BlockLabel(tag .. ".loop")
    local body_label   = Tr.BlockLabel(tag .. ".body")
    local done_label   = Tr.BlockLabel(tag .. ".done")
    local idx_param    = Tr.BlockParam(index, idx_ty)

    body_stmts[#body_stmts + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, {
      Tr.JumpArg(index, next_index),
    })

    return Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(
      tag,
      Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, {
          Tr.JumpArg(index, start_expr),
        }),
      }),
      {
        Tr.ControlBlock(loop_label, { idx_param }, {
          Tr.StmtIf(Tr.StmtSurface, cond, {
            Tr.StmtJump(Tr.StmtSurface, body_label, {
              Tr.JumpArg(index, index_ref),
            }),
          }, {}),
          Tr.StmtJump(Tr.StmtSurface, done_label, {}),
        }),
        Tr.ControlBlock(body_label, { idx_param }, body_stmts),
        Tr.ControlBlock(done_label, {}, {
          Tr.StmtYieldVoid(Tr.StmtSurface),
        }),
      }
    ))
  end

  return M
end

return bind_context
