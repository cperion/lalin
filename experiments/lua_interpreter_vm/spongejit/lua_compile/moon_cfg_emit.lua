-- moon_cfg_emit.lua -- mechanical MoonCFG -> Moonlift source renderer.
--
-- This renderer prints MoonCFG only.  It must not inspect LuaSrc/LuaNF to
-- choose semantics and must not synthesize out_tag/protocol continuations.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local CFG = T.MoonCFG
local Validate = require("lua_compile.moon_cfg_validate")

local M = {}

local function class(v) return pvm.classof(v) end
local function n(v) return tonumber(v) or 0 end
local function int_lit(v) return tostring(math.floor(n(v))) end
local function i64_lit(v) return "as(i64, " .. int_lit(v) .. ")" end
local function f64_lit(v)
  local s = tostring(tonumber(v) or 0)
  if not s:find("[%.eE]") then s = s .. ".0" end
  return s
end
local function par(s) return "(" .. s .. ")" end

local function render_name(name)
  local s = tostring(name and name.text or name or "")
  s = s:gsub("[^%w_]", "_")
  if s == "" then s = "_" end
  if s:match("^%d") then s = "_" .. s end
  return s
end

local function render_type(ty)
  return tostring(ty and ty.moon_type or ty or "void")
end

local function render_param(p)
  return render_name(p.name) .. ": " .. render_type(p.type)
end

local function render_const(c)
  local cls = class(c)
  if cls == CFG.I64Const then return i64_lit(c.value)
  elseif cls == CFG.F64Const then return f64_lit(c.value)
  elseif cls == CFG.BoolConst then return c.value == true and "true" or "false"
  elseif cls == CFG.StringConst then return string.format("%q", c.value or "") end
  error("unsupported MoonCFG.Const reached emission: " .. tostring(c and c.kind))
end

local function render_place(place)
  local cls = class(place)
  if cls == CFG.Temp then return render_name(place.name)
  elseif cls == CFG.StackSlot then return "stack_" .. int_lit(place.index)
  elseif cls == CFG.ConstSlot then return "const_" .. int_lit(place.index)
  elseif cls == CFG.UpvalueSlot then return "upvalue_" .. int_lit(place.index)
  elseif cls == CFG.VarargSlot then return "vararg_" .. int_lit(place.index)
  elseif cls == CFG.FrameTop then return "frame_top"
  elseif cls == CFG.ExecCtx then return "exec_ctx" end
  error("unsupported MoonCFG.Place reached emission: " .. tostring(place and place.kind))
end

local render_value
local function render_args(args)
  local out = {}
  for _, a in ipairs(args or {}) do out[#out + 1] = render_value(a) end
  return out
end

function render_value(v)
  local cls = class(v)
  if cls == CFG.PlaceValue then return render_place(v.place)
  elseif cls == CFG.ConstValue then return render_const(v.const)
  elseif cls == CFG.ParamValue then return render_name(v.name)
  elseif cls == CFG.UnitValue then return "nil" end
  error("unsupported MoonCFG.Value reached emission: " .. tostring(v and v.kind))
end

local function join_binary(xs, op, empty)
  if #xs == 0 then return empty end
  local s = xs[1]
  for i = 2, #xs do s = par(s .. " " .. op .. " " .. xs[i]) end
  return s
end

local function render_primitive(op, args)
  local k = op and op.kind
  local xs = render_args(args)
  if k == "AddI64" then return join_binary(xs, "+", i64_lit(0))
  elseif k == "SubI64" then return #xs == 1 and par(i64_lit(0) .. " - " .. xs[1]) or join_binary(xs, "-", i64_lit(0))
  elseif k == "MulI64" then return join_binary(xs, "*", i64_lit(1))
  elseif k == "IDivI64" then return join_binary(xs, "/", i64_lit(0))
  elseif k == "ModI64" then return join_binary(xs, "%", i64_lit(0))
  elseif k == "DivF64" then return join_binary(xs, "/", f64_lit(0))
  elseif k == "Eq" then return par((xs[1] or "false") .. " == " .. (xs[2] or "false"))
  elseif k == "Lt" then return par((xs[1] or "false") .. " < " .. (xs[2] or "false"))
  elseif k == "Le" then return par((xs[1] or "false") .. " <= " .. (xs[2] or "false"))
  elseif k == "Not" then return par("not " .. (xs[1] or "false"))
  elseif k == "Truthy" then return xs[1] or "false" end
  error("unsupported MoonCFG.PrimOp reached emission: " .. tostring(k))
end

local function render_expr(e)
  local cls = class(e)
  if cls == CFG.ValueExpr then return render_value(e.value)
  elseif cls == CFG.Primitive then return render_primitive(e.op, e.args or {})
  elseif cls == CFG.Load then return render_place(e.place)
  elseif cls == CFG.AddressOf then return "&" .. render_place(e.place)
  elseif cls == CFG.Convert then return "as(" .. render_type(e.type) .. ", " .. render_value(e.value) .. ")" end
  error("unsupported MoonCFG.Expr reached emission: " .. tostring(e and e.kind))
end

local function infer_expr_type(e)
  local cls = class(e)
  if cls == CFG.Primitive then
    local k = e.op and e.op.kind
    if k == "DivF64" then return "f64" end
    if k == "Eq" or k == "Lt" or k == "Le" or k == "Not" or k == "Truthy" then return "bool" end
    return "i64"
  elseif cls == CFG.ValueExpr then
    local v = e.value
    if class(v) == CFG.ConstValue then
      local ck = class(v.const)
      if ck == CFG.F64Const then return "f64" elseif ck == CFG.BoolConst then return "bool" else return "i64" end
    end
  elseif cls == CFG.Convert then return render_type(e.type) end
  return "i64"
end

local function render_op(op)
  local cls = class(op)
  if cls == CFG.Let then
    return "    let " .. render_place(op.dst) .. ": " .. infer_expr_type(op.expr) .. " = " .. render_expr(op.expr)
  elseif cls == CFG.Assign then
    return "    " .. render_place(op.dst) .. " = " .. render_value(op.src)
  elseif cls == CFG.Store then
    return "    " .. render_place(op.dst) .. " = " .. render_value(op.src)
  elseif cls == CFG.Assert then
    return "    if not " .. render_expr(op.condition) .. " then return as(i64, 0) end"
  end
  error("unsupported MoonCFG.Op reached emission: " .. tostring(op and op.kind))
end

local function render_terminator(term)
  local cls = class(term)
  if cls == CFG.Return then
    local xs = {}
    for _, v in ipairs(term.values or {}) do xs[#xs + 1] = render_value(v) end
    if #xs == 0 then return "    return" end
    return "    return " .. table.concat(xs, ", ")
  elseif cls == CFG.Unreachable then
    return "    return as(i64, 0)"
  end
  error("unsupported MoonCFG.Terminator reached emission in first slice: " .. tostring(term and term.kind))
end

local function render_returns(returns)
  local rs = returns or {}
  if #rs == 0 then return "void" end
  if #rs == 1 then return render_type(rs[1]) end
  local out = {}
  for _, r in ipairs(rs) do out[#out + 1] = render_type(r) end
  return table.concat(out, ", ")
end

local function render_kernel(kernel, opts)
  local params = {}
  for _, p in ipairs(kernel.params or {}) do params[#params + 1] = render_param(p) end
  local name = opts.name or render_name(kernel.id and kernel.id.name) or "lua_compile_kernel"
  local lines = {}
  lines[#lines + 1] = "local " .. name .. " = func(" .. table.concat(params, ", ") .. ") -> " .. render_returns(kernel.returns)
  local blocks = kernel.body and kernel.body.blocks or {}
  assert(#blocks == 1, "MoonCFG emitter first slice expects one block after validation")
  local block = blocks[1]
  for _, op in ipairs(block.ops or {}) do lines[#lines + 1] = render_op(op) end
  lines[#lines + 1] = render_terminator(block.terminator)
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "return " .. name
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function M.emit(kernel, opts)
  opts = opts or {}
  local ok, errors = Validate.validate(kernel)
  if not ok then error("MoonCFG validation failed before emission: " .. table.concat(errors, "; "), 2) end
  return render_kernel(kernel, opts)
end

return M
