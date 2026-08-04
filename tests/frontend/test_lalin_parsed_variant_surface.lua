package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Parsed variant surface through the schema-v2 typed frontend.
--
-- `Union.Case(args)` constructor calls parse as the schema-owned
-- LalinTree.ExprCtor projection and `case variant` arms project to
-- LalinTree.StmtVariantSwitchSource with typed payload binds. The valid
-- surface typechecks and compiles without relying on the retired parser AST.

local lalin = require("lalin")
local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
require("lalin.impl.compiler_api")
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_region")
local Compiler = T.LalinCompiler
local Tr = T.LalinTree
local Document = require("lalin.syntax_v2.document")

local source = [=[
union MaybeI32
  None
  Some(value [i32])
end

fn payload_case() [i32] do
  let value [MaybeI32] = MaybeI32.Some(42)
  switch value do
    case variant Some(payload) then
      return payload
    case variant None then
      return 0
    default then
      return -1
  end
end
]=]

-- The public loader parses the document into typed Parsed ASDL.
local decls = assert(lalin.loadstring(source, "@parsed-variant-surface.lln"))
local module = Document.to_module(decls, "parsed_variant_surface")
assert(asdl.classof(module) == Tr.Module, "parsed variant decls should lower to a typed module")
local func = module.items[2].func

-- `Union.Case(...)` must parse with the precise constructor-call projection leaf.
local ctor = func.body[1].init
assert(asdl.classof(ctor) == Tr.ExprCtor
  and ctor.type_name == "MaybeI32" and ctor.variant_name == "Some",
  "`Union.Case(...)` must parse with the typed constructor projection leaf")
assert(#ctor.args == 1, "constructor arguments must be owned by the typed call projection")

-- `case variant` arms must project to the schema-owned source switch.
local sw = func.body[2]
assert(asdl.classof(sw) == Tr.StmtVariantSwitchSource,
  "parsed variant arms must project to the schema-owned source switch")
assert(sw.variant_arms[1].variant_name == "Some"
  and sw.variant_arms[1].binds[1].name == "payload",
  "payload arm bind must remain explicit")
assert(#sw.variant_arms[2].binds == 0, "nullary arm must carry no bind")

-- The valid surface typechecks with no region-expansion issues.
local function full_typecheck(source_text, name)
  local doc = Document.parse(source_text, name)
  local m = Document.to_module(doc, name)
  local m2 = m:surface_resolve()
  local target = T.LalinHost.HostTargetModel(64, 64, T.LalinHost.HostEndianLittle)
  local m3 = m2:closure_convert(T.LalinSem.ClosureModuleInput(target)).module
  return m3:typecheck_region_expanded()
end
local reg = full_typecheck(source, "parsed_variant_surface")
assert(asdl.classof(reg) == Tr.RegionModuleExpanded,
  "valid nullary/payload constructors and binds must typecheck")
assert(#(reg:region_issues() or {}) == 0, "valid variant surface must carry no issues")

-- The public compile pipeline accepts the valid surface.
local ok_session = Compiler.CompilerSession(source, "parsed_variant_surface")
local ok, ok_result = pcall(function() return ok_session:compile() end)
assert(ok and asdl.classof(ok_result) == Compiler.CompilerArtifactC,
  "valid variant surface must compile to a C artifact")

io.write("lalin parsed variant surface ok\n")
