package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- schema-v2 parity for the /tmp/probe2.lua `ownership` and `domain_contract`
-- bracket surfaces. A qualified `handle Store.Ref [u32]` referenced in type
-- position `[Store.Ref]` must adapt through the canonical HostTypeSymbol/type
-- role boundary into a qualified TNamed(TypeRefPath), and must never collapse
-- back to its own HostEval when the bracket does not resolve.
--
-- Covers:
--   * parse-time qualified handle binding: `handle Store.Ref` installs the
--     HostTypeSymbol at both the plain name and the qualified path
--   * `[Store.Ref]` in region parameters and continuation fields adapting to
--     TNamed(TypeRefPath(Store, Ref))
--   * llbl.host_eval.evaluate preserving a nil evaluation result instead of
--     returning the HostEval itself ("HostEval yields another HostEval")
--   * end-to-end compile_v2 (CompilerSession:compile) for both probe sources
-- Everything is driven through the public pipeline and typed schema leaves.

local asdl = require("lalin.asdl")
local llbl = require("llbl")

local T = require("lalin.schema_v2")
require("lalin.impl.compiler_api")
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_region")
require("lalin.impl.tree_code")

local Compiler = T.LalinCompiler
local C, P, Tr, Ty = T.LalinCore, T.LalinParse, T.LalinTree, T.LalinType
local Document = require("lalin.syntax_v2.document")

local passed = 0

local function ok(name, cond)
  assert(cond, name .. ": assertion failed")
  passed = passed + 1
end

-- ============================================================
-- Qualified handle bracket adaptation at parse time
-- ============================================================
print("=== Qualified handle type bracket adaptation ===")

local doc_source = [=[
struct Record
  value [i32]
end
struct Store
  records [ptr [Record]]
end
handle Store.Ref [u32]
  invalid = 0
  domain [Store]
  target [Record]
end
region Store.borrow(self [readonly [ptr [Store]]], ref [Store.Ref];
  borrowed(record [lease("self", ptr [Record])]),
  stale(ref [Store.Ref]),
  missing(ref [Store.Ref])
)
  entry start()
    jump missing(ref)
  end
end
]=]

local doc = Document.parse(doc_source, "@qualified-handle-bracket.lln")
ok("qualified handle document has 4 root declarations", #doc.body == 4)
ok("handle parsed with qualified name", asdl.classof(doc.body[3]) == P.ParsedHandle)

local region = doc.body[4]
ok("region parsed", asdl.classof(region) == P.ParsedRegion)
ok("region inputs include self and ref", #region.inputs == 2)

-- `ref [Store.Ref]` adapts to a qualified named type, not the HostEval.
local ref_ty = region.inputs[2].ty
ok("ref param type is TNamed", asdl.classof(ref_ty) == Ty.TNamed)
ok("ref param type ref is TypeRefPath", asdl.classof(ref_ty.ref) == Ty.TypeRefPath)
ok("ref param path is Store.Ref",
  #ref_ty.ref.path.parts == 2
  and ref_ty.ref.path.parts[1].text == "Store"
  and ref_ty.ref.path.parts[2].text == "Ref")

-- The continuation fields reference the same qualified handle type.
local missing = region.exits[3]
ok("missing continuation parsed", missing.name == "missing")
local missing_ty = missing.fields[1].ty
ok("missing ref field is TNamed", asdl.classof(missing_ty) == Ty.TNamed)
ok("missing ref path is Store.Ref",
  asdl.classof(missing_ty.ref) == Ty.TypeRefPath
  and #missing_ty.ref.path.parts == 2
  and missing_ty.ref.path.parts[2].text == "Ref")

-- to_module emits the handle decl under its qualified compiler name.
local module = Document.to_module(doc, "qualified_handle_bracket")
local handle_decl = module.items[3]
ok("handle lowered to TypeDeclHandle",
  asdl.classof(handle_decl) == Tr.ItemType
  and asdl.classof(handle_decl.t) == Tr.TypeDeclHandle)
ok("handle compiler name is Store.Ref", handle_decl.t.name == "Store.Ref")

-- ============================================================
-- llbl.host_eval.evaluate must not collapse a nil result to itself
-- ============================================================
print("=== HostEval nil evaluation preservation ===")

local unresolved = llbl.host_eval.parsed("Store.Ref", { "Store", "Ref" }, nil,
  { source = "@unresolved.lln" }, { role = "type" })
-- `Store` resolves (so no _G fallback), but the symbol has no `Ref`
-- member; the bracket HostEval therefore yields nil and must return
-- nil instead of collapsing back to its own HostEval.
local unresolved_env = {
  Store = setmetatable({}, { __index = {} }),
}
local eval_result = llbl.host_eval.evaluate(unresolved, unresolved_env)
ok("unresolved HostEval evaluates to nil, not to itself",
  eval_result == nil)
ok("unresolved HostEval is not returned as another HostEval",
  not llbl.is(eval_result, "HostEval"))

-- A resolved bracket still adapts through the canonical symbol boundary.
local TypeSyntax = require("lalin.syntax_v2.type")
local env = {}
TypeSyntax.extend_host_env(env)
local store_sym = TypeSyntax.named_symbol("Store")
env.Store = store_sym
env.Store.Ref = TypeSyntax.named_symbol_path({ "Store", "Ref" })
local resolved = llbl.host_eval.parsed("Store.Ref", { "Store", "Ref" }, nil,
  { source = "@resolved.lln" }, { role = "type" })
local resolved_value = llbl.host_eval.evaluate(resolved, env)
ok("resolved HostEval adapts to a HostTypeSymbol",
  type(resolved_value) == "table"
  and type(resolved_value.parsed_host_type) == "function")
ok("resolved HostTypeSymbol path is Store.Ref",
  resolved_value.ty.ref.path.parts[1].text == "Store"
  and resolved_value.ty.ref.path.parts[2].text == "Ref")

-- ============================================================
-- End-to-end compile_v2 for the probe ownership/domain_contract sources
-- ============================================================
print("=== compile_v2 ownership and domain_contract ===")

local function compile_artifact(source, name)
  local session = Compiler.CompilerSession(source, name)
  local okc, result = pcall(function() return session:compile() end)
  ok(name .. ": compile_v2 pipeline did not crash", okc)
  ok(name .. ": expected CompilerArtifactC, got "
    .. tostring(asdl.classof(result)) .. " (" .. tostring(result.message or "") .. ")",
    asdl.classof(result) == Compiler.CompilerArtifactC)
  return result
end

compile_artifact([=[
struct Record
  value [i32]
end
struct Store
  record [Record]
end
handle Store.Ref [u32]
  invalid = 0
  domain [Store]
  target [Record]
end
region Store.resolve(self [readonly [ptr [Store]]], ref [Store.Ref];
  granted(record [lease("self", ptr [Record])]),
  missing(ref [Store.Ref])
)
  entry start()
    jump missing(ref)
  end
end
fn f_read(p [readonly [ptr [i32]]]) [i32] do
  return p[0]
end
fn f_write(p [writeonly [ptr [i32]]], value [i32]) [i32] do
  p[0] = value
  return p[0]
end
fn ownership_matrix(p [ptr [i32]]) [i32] do
  let a [i32] = f_read(p)
  let b [i32] = f_write(p, a + 1)
  return a + b
end
]=], "probe_ownership")

compile_artifact([=[
struct Record
  value [i32]
end
struct Store
  records [ptr [Record]]
end
handle Store.Ref [u32]
  invalid = 0
  domain [Store]
  target [Record]
end
region Store.borrow(self [readonly [ptr [Store]]], ref [Store.Ref];
  borrowed(record [lease("self", ptr [Record])]),
  stale(ref [Store.Ref]),
  missing(ref [Store.Ref])
)
  entry start()
    jump missing(ref)
  end
end
fn Store.count(self [ptr [Store]]) [index]
  requires preserve(self)
  return 0
end
]=], "probe_domain_contract")

print("schema-v2 qualified handle type bracket ok (" .. passed .. " assertions)")
