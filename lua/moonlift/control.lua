---moon.control: user-defined control structures as moon.chain.
---
---Every control structure emits flat ASDL — blocks, jumps, yields, switches.
---The compiler never learns about `loop` or `foreach`; it only sees the
---primitives. This file defines:
---
---  control.loop      – counted loop:  for i = from, to-1 { body }
---  control.foreach   – view iterate:  for x in view { body }
---  control.while_true – while loop:    while cond { body }
---  control.if_else   – conditional:   if cond { then } else { else }
---  control.switch_on – value switch:  switch val { arm -> body; ... }
---  control.with      – acquire/release:  let res = acquire; body; release(res)
---
---Each is a moon.chain instance:  control.XXX{ bindings }[[ body ]].
---
---@module moonlift.control

local M = {}

---Build the control structure suite bound to a session.
---@param session table  Host session with `.T` ASDL context.
---@param chain_factory table Chain factory from `chain.bind(session, ...)`.
---                Must have `make(config)` and `make_quote(parse,wrap,expand,table_fn)`.
---@return table  { loop, foreach, while_true, if_else, switch_on, with }
function M.build(session, chain_factory)
  local Tr   = session.T.MoonTree
  local C    = session.T.MoonCore
  local Ty   = session.T.MoonType
  local O    = session.T.MoonOpen
  local Bind = session.T.MoonBind
  local Sem  = session.T.MoonSem

  local ast_parse = require("moonlift.parse")

  -- ASDL builders — acquire a context in case the chain body needs parsing
  local function new_parser()
    return ast_parse.Define(session.T)
  end

  -- ── Helpers ──────────────────────────────────────────────────────────

  -- Turn a Lua number into an i32 literal expression.
  local function i32_lit(n)
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(n)))
  end

  -- Turn a Lua number into an index literal.
  local function idx_lit(n)
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(n)))
  end

  -- Extract raw ASDL type from a binding value.
  local function as_ty(v, default)
    if v == nil then return default end
    if type(v) == "table" then
      if v.ty then return v.ty end               -- host TypeValue
      if type(v.as_type_value) == "function" then
        local tv = v:as_type_value()
        return tv and tv.ty or default
      end
      return v                                    -- raw ASDL
    end
    return default
  end

  -- Extract raw ASDL expression from a binding value.
  local function as_expr(v)
    if v == nil then return nil end
    if type(v) == "number" then
      return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(v)))
    end
    if type(v) ~= "table" then return v end
    -- host ExprValue / RefValue etc.
    if type(v.as_expr_value) == "function" then
      local ev = v:as_expr_value()
      return ev and ev.expr or v
    end
    -- host int/float literal values
    if type(v.as_moonlift_expr) == "function" then
      return v:as_moonlift_expr("binding")
    end
    return v  -- raw ASDL or other
  end

  -- Wrap a local name as a value reference expression.
  local function var_ref(name)
    return Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName(name))
  end

  -- Binary expression: a OP b
  local function bin(op_class, a, b)
    return Tr.ExprBinary(Tr.ExprSurface, op_class, a, b)
  end

  -- Compare expression: a OP b
  local function cmp(op_class, a, b)
    return Tr.ExprCompare(Tr.ExprSurface, op_class, a, b)
  end

  -- Jump argument: name = expr
  local function jump_arg(name, value)
    return Tr.JumpArg(name, value)
  end

  -- ── control.loop: counted loop ──────────────────────────────────────
  --   control.loop{ from = Expr, to = Expr, idx_name = "i", idx_ty = Ty }[[ body_stmts ]]
  --
  -- Expands to:
  --   block start(i: idx_ty = from)
  --     if i >= to then yield end
  --     body_stmts
  --     jump start(i = i + 1)
  --   end
  local function ctl_loop_make_chain()
    return chain_factory.make {
      name = "control.loop",

      parse = function(T, src)
        return new_parser().parse_stmts(src)
      end,

      wrap = function(parsed_body, parsed, T, src, bindings)
        local name     = bindings.name or "loop_body"
        local idx_name = bindings.idx_name or "i"
        local idx_ty   = as_ty(bindings.idx_ty, Ty.TScalar(C.ScalarI32))
        local from     = as_expr(bindings.from) or i32_lit(0)
        local to       = as_expr(bindings.to)
        if not to then error("control.loop: `to` binding required", 3) end

        local iv     = var_ref(idx_name)                           -- i
        local one    = i32_lit(1)                                   -- 1
        local next_i = bin(C.BinAdd, iv, one)                       -- i + 1
        local cond   = cmp(C.CmpGe, iv, to)                         -- i >= to

        local exit_body = { Tr.StmtYieldVoid(Tr.StmtSurface) }
        local exit_if   = Tr.StmtIf(Tr.StmtSurface, cond, exit_body, {})

        local full_body = { exit_if }
        for _, s in ipairs(parsed_body) do full_body[#full_body + 1] = s end
        full_body[#full_body + 1] = Tr.StmtJump(Tr.StmtSurface,
          Tr.BlockLabel(name),
          { jump_arg(idx_name, next_i) })

        local entry = Tr.EntryControlBlock(
          Tr.BlockLabel("start"),
          { Tr.EntryBlockParam(idx_name, idx_ty, from) },
          full_body)

        local region = Tr.ControlStmtRegion(session:symbol_key("ctl", name), entry, {})
        return Tr.StmtControl(Tr.StmtSurface, region)
      end,

      expand = function(e, value, env)
        return e.stmts(value, env)
      end,
    }
  end

  -- ── control.foreach: view iteration ─────────────────────────────────
  --   control.foreach{ view = Expr, elt_name = "x", elt_ty = Ty }[[ body_stmts ]]
  --
  -- Expands to:
  --   block loop(i: index = 0)
  --     if i >= view.len then yield end
  --     let x = view[i]    -- via PlaceIndex then Load
  --     body_stmts
  --     jump loop(i = i + 1)
  --   end
  local function ctl_foreach_make_chain()
    return chain_factory.make {
      name = "control.foreach",

      parse = function(T, src)
        return new_parser().parse_stmts(src)
      end,

      wrap = function(parsed_body, parsed, T, src, bindings)
        local name     = bindings.name or "foreach_loop"
        local elt_name = bindings.elt_name or "x"
        local elt_ty   = as_ty(bindings.elt_ty, Ty.TScalar(C.ScalarI32))
        local view_val = as_expr(bindings.view)
        if not view_val then error("control.foreach: `view` binding required", 3) end

        local index_ty = Ty.TScalar(C.ScalarIndex)
        local iv       = var_ref("i")
        local zero     = idx_lit(0)
        local one      = idx_lit(1)
        local next_i   = bin(C.BinAdd, iv, one)                     -- i + 1

        -- view.len
        local view_len = Tr.ExprLen(Tr.ExprSurface, view_val)
        local cond     = cmp(C.CmpGe, iv, view_len)                  -- i >= len

        -- view[i] — use ExprIndex with IndexBaseExpr (works for views, ptrs, arrays)
        local elem_load = Tr.ExprIndex(Tr.ExprSurface,
          Tr.IndexBaseExpr(view_val),
          iv)

        -- let x = view[i]
        local let_stmt = Tr.StmtLet(Tr.StmtSurface,
          Bind.Binding(C.Id("local:" .. elt_name), elt_name, elt_ty, Bind.BindingClassLocalValue),
          elem_load)

        -- Build body
        local exit_if = Tr.StmtIf(Tr.StmtSurface, cond,
          { Tr.StmtYieldVoid(Tr.StmtSurface) }, {})

        local full_body = { exit_if, let_stmt }
        for _, s in ipairs(parsed_body) do full_body[#full_body + 1] = s end
        full_body[#full_body + 1] = Tr.StmtJump(Tr.StmtSurface,
          Tr.BlockLabel(name),
          { jump_arg("i", next_i) })

        local entry = Tr.EntryControlBlock(
          Tr.BlockLabel(name),
          { Tr.EntryBlockParam("i", index_ty, zero) },
          full_body)

        local region = Tr.ControlStmtRegion(session:symbol_key("ctl", name), entry, {})
        return Tr.StmtControl(Tr.StmtSurface, region)
      end,

      expand = function(e, value, env)
        return e.stmts(value, env)
      end,
    }
  end

  -- ── control.while_true: simple while loop ───────────────────────────
  --   control.while_true{ cond = Expr, name = "while_loop" }[[ body_stmts ]]
  --
  -- Expands to:
  --   block while_loop()
  --     if not cond then yield end
  --     body_stmts
  --     jump while_loop()
  --   end
  local function ctl_while_true_make_chain()
    return chain_factory.make {
      name = "control.while_true",

      parse = function(T, src)
        return new_parser().parse_stmts(src)
      end,

      wrap = function(parsed_body, parsed, T, src, bindings)
        local name  = bindings.name or "while_loop"
        local cond  = as_expr(bindings.cond)
        if not cond then error("control.while_true: `cond` binding required", 3) end

        -- if not cond then yield end → if cond {} else yield
        local exit_if = Tr.StmtIf(Tr.StmtSurface, cond,
          {},                                                -- then: empty (continue)
          { Tr.StmtYieldVoid(Tr.StmtSurface) })              -- else: yield (exit)

        local full_body = { exit_if }
        for _, s in ipairs(parsed_body) do full_body[#full_body + 1] = s end
        full_body[#full_body + 1] = Tr.StmtJump(Tr.StmtSurface,
          Tr.BlockLabel(name), {})

        local entry = Tr.EntryControlBlock(
          Tr.BlockLabel(name), {}, full_body)

        local region = Tr.ControlStmtRegion(session:symbol_key("ctl", name), entry, {})
        return Tr.StmtControl(Tr.StmtSurface, region)
      end,

      expand = function(e, value, env)
        return e.stmts(value, env)
      end,
    }
  end

  -- ── control.if_else: conditional statement ──────────────────────────
  --   control.if_else{ cond = Expr }                            -- returns header
  --   control.if_else{ cond = Expr, then_body = Stmt[], else_body = Stmt[] }
  --
  -- Form A (binder):  control.if_else{ then_body = ..., else_body = ... }[[ cond ]]
  --   Parses [[ cond ]] as condition expression, wraps with then/else bodies.
  -- Form B (builder): control.if_else{ cond, then_body, else_body }
  --   All ASDL, calls table_fn.
  local function ctl_if_else_make_chain()
    return chain_factory.make {
      name = "control.if_else",

      parse = function(T, src)
        return new_parser().parse_expr(src)
      end,

      wrap = function(cond_expr, parsed, T, src, bindings)
        return Tr.StmtIf(Tr.StmtSurface, cond_expr,
          bindings.then_body or bindings.then_ or {},
          bindings.else_body or bindings.else_ or {})
      end,

      expand = function(e, value, env)
        return e.expr(value, env)
      end,

      -- Array form: { cond_expr, then_stmts, else_stmts }
      table_fn = function(arg)
        return Tr.StmtIf(Tr.StmtSurface,
          arg[1] or i32_lit(0),
          arg[2] or {},
          arg[3] or {})
      end,
    }
  end

  -- ── control.switch_on: value switch ─────────────────────────────────
  --   control.switch_on{ value = Expr, arms = SwitchArm[], default = Stmt[] }
  --
  -- Arms format (from moon.switch_arms):
  --   { { raw_key = "42", body = { ... } }, ... }
  -- Or compact:
  --   control.switch_on{ value = expr }[[ 42 -> { ... }; 10 -> { ... }; default -> { ... } ]]
  local function ctl_switch_on_make_chain()
    return chain_factory.make {
      name = "control.switch_on",

      parse = function(T, src)
        return new_parser().parse_stmts(src)
      end,

      wrap = function(parsed_body, parsed, T, src, bindings)
        local val_expr = as_expr(bindings.value)
        local arms     = bindings.arms or {}
        local default_body = bindings.default_body or bindings.default_ or {}
        if not val_expr then error("control.switch_on: `value` binding required", 3) end

        -- Convert compact arms [{key, body}, ...] to SwitchStmtArm[]
        local switch_arms = {}
        for _, a in ipairs(arms) do
          if a.raw_key then
            switch_arms[#switch_arms + 1] = a
          elseif type(a) == "table" and #a >= 2 then
            switch_arms[#switch_arms + 1] = Tr.SwitchStmtArm(tostring(a[1]), a[2])
          end
        end

        return Tr.StmtSwitch(Tr.StmtSurface, val_expr, switch_arms, {}, default_body)
      end,

      expand = function(e, value, env)
        return e.stmts(value, env)
      end,

      -- Array form: { val_expr, arms_array, default_body }
      table_fn = function(arg)
        local v     = arg[1]
        local arms  = arg[2] or {}
        local deflt = arg[3] or {}
        local s_arms = {}
        for _, a in ipairs(arms) do
          s_arms[#s_arms + 1] = Tr.SwitchStmtArm(tostring(a[1] or a.raw_key), a[2] or a.body)
        end
        return Tr.StmtSwitch(Tr.StmtSurface, v, s_arms, {}, deflt)
      end,
    }
  end

  -- ── control.with: acquire / body / release ──────────────────────────
  --   control.with{ acquire = Expr, release = Expr, name = "res" }[[ body_stmts ]]
  --
  -- Expands to:
  --   let res: ptr(T) = acquire()
  --   body_stmts
  --   release(res)
  local function ctl_with_make_chain()
    return chain_factory.make {
      name = "control.with",

      parse = function(T, src)
        return new_parser().parse_stmts(src)
      end,

      wrap = function(parsed_body, parsed, T, src, bindings)
        local res_name = bindings.name or "res"
        local acquire  = as_expr(bindings.acquire)
        local release  = as_expr(bindings.release)
        if not acquire then error("control.with: `acquire` binding required", 3) end
        if not release then error("control.with: `release` binding required", 3) end

        local ptr_ty    = Ty.TPtr(Ty.TScalar(C.ScalarVoid))
        local res_bind  = Bind.Binding(C.Id("local:" .. res_name), res_name, ptr_ty, Bind.BindingClassLocalValue)
        local let_stmt  = Tr.StmtLet(Tr.StmtSurface, res_bind, acquire)
        local release_stmt = Tr.StmtExpr(Tr.StmtSurface, release) -- evaluate for effect

        local stmts = { let_stmt }
        for _, s in ipairs(parsed_body) do stmts[#stmts + 1] = s end
        stmts[#stmts + 1] = release_stmt
        return stmts
      end,

      expand = function(e, value, env)
        return e.stmts(value, env)
      end,
    }
  end

  -- ── Assemble ────────────────────────────────────────────────────────

  return setmetatable({
    loop       = ctl_loop_make_chain(),
    foreach    = ctl_foreach_make_chain(),
    while_true = ctl_while_true_make_chain(),
    if_else    = ctl_if_else_make_chain(),
    switch_on  = ctl_switch_on_make_chain(),
    with       = ctl_with_make_chain(),
  }, {
    __call = function(self, key)
      error("moon.control." .. tostring(key) .. " is not a valid control structure. "
        .. "Available: " .. table.concat({"loop","foreach","while_true","if_else","switch_on","with"}, ", "), 2)
    end,
  })
end

return M
