-- lalin.syntax
-- Terra-like parsed-channel frontend for Lalin, registered as a generic LLBL
-- syntax language.  The parser returns first-class Lalin parsed AST values;
-- repository integration should lower these nodes to LalinTree ASDL or call the
-- existing DSL heads in one place.

local llbl_syntax = require("llbl.syntax")
local Constructor = require("llbl.syntax.constructor")
local Ast = require("lalin.syntax.ast")
local Decl = require("lalin.syntax.decl")
local Expr = require("lalin.syntax.expr")
local Stmt = require("lalin.syntax.stmt")

local LalinSyntax = {}

local function wrap_ast(ast, ctx, opts)
  opts = opts or {}
  local refs = {}
  for _, r in ipairs(ctx.refs or {}) do refs[#refs + 1] = r end
  local outputs = {}
  if ast.name and (ast.tag == "DeclFunc" or ast.tag == "DeclStruct" or ast.tag == "DeclUnion" or ast.tag == "DeclRegion" or ast.tag == "DeclModule") then
    outputs[1] = { name = ast.name }
  end
  return Constructor.new {
    owner = "lalin",
    kind = ast.tag,
    role = opts.role or "decl",
    channel = opts.channel or "parsed:lalin",
    refs = refs,
    outputs = outputs,
    origin = ast.origin,
    ast = ast,
    build = function(env)
      -- Resolve explicit host escapes at construction/evaluation time.  This is
      -- the exact point where Lua lexical values become Lalin constants,
      -- fragments, types, or diagnostics in a full Lalin adapter.
      local copy = ast -- AST is intentionally shared; callsites normally build once.
      Ast.resolve_host_escapes(copy, env)
      return copy
    end,
  }
end

function LalinSyntax.parse_entry(lex, entry, ctx)
  local ast
  if entry == "fn" then
    ast = Decl.parse_fn(lex, ctx, ctx.entry_token)
  elseif entry == "struct" then
    ast = Decl.parse_struct(lex, ctx, ctx.entry_token)
  elseif entry == "union" then
    ast = Decl.parse_union(lex, ctx, ctx.entry_token)
  elseif entry == "region" then
    ast = Decl.parse_region(lex, ctx, ctx.entry_token)
  elseif entry == "module" then
    ast = Decl.parse_module(lex, ctx, ctx.entry_token)
  elseif entry == "expr" then
    ast = Decl.parse_expr_fragment(lex, ctx)
  elseif entry == "stmt" or entry == "quote" then
    ast = Decl.parse_stmt_fragment(lex, ctx)
  elseif entry == "lalin" then
    lex:error_at(ctx.entry_token, "bare `lalin` entrypoint requires a following entry token")
  else
    lex:error_at(ctx.entry_token, "unsupported Lalin syntax entrypoint `" .. tostring(entry) .. "`")
  end
  return wrap_ast(ast, ctx, { role = ast.tag })
end

function LalinSyntax.parse_expression(lex, ctx)
  local ast = Expr.parse(lex, ctx)
  return wrap_ast(ast, ctx, { role = "expr", channel = "parsed:expr" })
end

function LalinSyntax.parse_statement(lex, ctx)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  local ast = Ast.node("StmtFragment", { body = body }, ctx:origin(lex, ctx.entry_token, lex.last, "parsed:stmt"))
  return wrap_ast(ast, ctx, { role = "stmt", channel = "parsed:stmt" })
end

function LalinSyntax.register()
  local spec = {
    name = "lalin",
    owner = "lalin",
    entrypoints = { "fn", "struct", "union", "region", "module", "quote", "expr", "stmt" },
    direct_entrypoints = nil, -- parse-time import activates entrypoints; namespaced form always works.
    keywords = {
      "fn", "region", "struct", "union", "module", "requires", "ensures",
      "do", "end", "if", "then", "elseif", "else", "for", "in", "range",
      "range_nd", "window_nd", "tiled_nd", "return", "jump", "emit", "entry", "block",
      "let", "var",
    },
    parse_entry = LalinSyntax.parse_entry,
    expression = LalinSyntax.parse_expression,
    statement = LalinSyntax.parse_statement,
  }
  LalinSyntax.language_spec = spec
  LalinSyntax.language_name = spec.name
  return llbl_syntax.register(spec)
end

-- ── Convert parsed AST to LalinTree for the compiler pipeline ──────────

function LalinSyntax.to_module(parsed_decls, name, T)
  -- Use caller's pvm context or create a default one.
  local pvm = require("lalin.pvm")
  T = T or pvm.context()
  if not T.LalinTree then
    require("lalin.schema_projection")(T)
  end
  local to_tree = require("lalin.syntax.to_tree")(T)
  local Tr, C, B = T.LalinTree, T.LalinCore, T.LalinBind

  name = name or "parsed"
  local decls = {}

  -- Convert parsed type (e.g. "i32", "ptr[i32]", "array(f64, 4)") to LalinType.Type
  local function parsed_type(ptype)
    if not ptype then return T.LalinType.TScalar(C.ScalarVoid) end
    local Ty = T.LalinType
    local scalars = {
      void = C.ScalarVoid, bool = C.ScalarBool,
      i8 = C.ScalarI8, i16 = C.ScalarI16,
      i32 = C.ScalarI32, i64 = C.ScalarI64,
      u8 = C.ScalarU8, u16 = C.ScalarU16,
      u32 = C.ScalarU32, u64 = C.ScalarU64,
      f32 = C.ScalarF32, f64 = C.ScalarF64,
      index = C.ScalarIndex, rawptr = C.ScalarRawPtr,
    }
    -- Known type constructors with special ASDL representation
    local type_ctors = {
      ptr = function(args)
        return Ty.TPtr(args[1] or Ty.TScalar(C.ScalarVoid))
      end,
      array = function(args)
        return Ty.TArray(Ty.ArrayLenStatic(0), args[1] or Ty.TScalar(C.ScalarVoid))
      end,
    }
    if ptype.tag == "TypeName" then
      if scalars[ptype.name] then
        return Ty.TScalar(scalars[ptype.name])
      end
      return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(ptype.name) })))
    elseif ptype.tag == "TypeApply" then
      local ctor = type_ctors[ptype.name]
      if ctor then
        local args = {}
        for i, a in ipairs(ptype.args or {}) do
          args[i] = parsed_type(a)
        end
        return ctor(args)
      end
      -- Fallback: treat as named application
      return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(ptype.name) })))
    end
    return Ty.TScalar(C.ScalarVoid)
  end

  -- Helper: convert a single parsed decl to a Tr.Item for the module.
  -- The tree ASDL uses Tr.ItemFunc(FuncLocal/FuncExport) for functions,
  -- Tr.ItemType(TypeDeclStruct/TypeDeclTaggedUnionSugar) for structs/unions.
  local function decl_to_item(parsed)
    if not parsed then return nil end
    if parsed.tag == "DeclFunc" then
      local params = {}
      for i, p in ipairs(parsed.params or {}) do
        params[i] = T.LalinType.Param(p.name, parsed_type(p.type))
      end
      local result_ty = parsed_type(parsed.result)
      local body = to_tree.stmts(parsed.body)
      if #body == 0 then
        body = { Tr.StmtReturnVoid(Tr.StmtSurface) }
      end
      local func_spec = Tr.FuncLocal(parsed.name, params, result_ty, body)
      return Tr.ItemFunc(func_spec)
    elseif parsed.tag == "DeclStruct" then
      local fields = {}
      for i, f in ipairs(parsed.fields or {}) do
        fields[i] = T.LalinType.FieldDecl(f.name, parsed_type(f.type))
      end
      return Tr.ItemType(Tr.TypeDeclStruct(parsed.name, fields))
    elseif parsed.tag == "DeclUnion" then
      local variants = {}
      for _, v in ipairs(parsed.variants or {}) do
        local fields = {}
        for i, f in ipairs(v.fields or {}) do
          fields[i] = T.LalinType.FieldDecl(f.name, parsed_type(f.type))
        end
        variants[#variants + 1] = Tr.VariantDecl(v.name, fields)
      end
      return Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(parsed.name, variants))
    end
    error("parsed_to_module: unsupported decl tag " .. tostring(parsed.tag), 2)
  end

  -- Accept single decl or array
  local items = parsed_decls
  if items.tag then items = { items } end
  for _, d in ipairs(items or {}) do
    decls[#decls + 1] = decl_to_item(d)
  end

  return Tr.Module(Tr.ModuleSurface, decls)
end

-- Register on require.
LalinSyntax.register()

return LalinSyntax
