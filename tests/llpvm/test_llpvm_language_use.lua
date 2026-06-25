package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local LLPVM = require("llpvm")

local env = {}
local session = lalin.language.use { scope = "env", target = env, global = false }
local desc = session:describe()
assert(desc.dialect == "lalin", "language session is named")
assert(env.lln and env.lalin and env.llpvm and env.schema, "language installs member namespaces")
assert(env.lln == env.lalin, "lln should be the short alias for the Lalin namespace")
assert(env.region == require("llbl").region, "language installs generic LLBL region as the bare region head")
assert(rawget(env, "fn") == nil and rawget(env, "pvm") == nil and rawget(env, "i32") == nil and rawget(env, "task") == nil, "language does not leak member heads as bare globals")
assert(env.schema.product and env.schema.module and env.schema.LanguageProbe, "language installs LalinSchema through the schema namespace")
assert(require("llbl").describe(env.lalin).tag == "Namespace", "Lalin language export should be an LLBL namespace")
assert(require("llbl").describe(env.llpvm).tag == "Namespace", "LLPVM language export should be an LLBL namespace")
assert(require("llbl").describe(env.schema).tag == "Namespace", "LalinSchema language export should be an LLBL namespace")
assert(require("llbl").describe(env.schema).default_head, "LalinSchema namespace should expose a default module head")

local audit = lalin.language.audit()
assert(audit.tag == "LanguageAudit", "language audit is inspectable")
assert(#audit.smells == 0, audit.smells[1] and audit.smells[1].message or "language should have no semantic ownership smells")
assert(audit.owner["type-language"] == "lalinschema.dsl", "LalinSchema owns product/sum/type-language semantics")
assert(audit.owner["native-type-values"] == "lalin.dsl", "Lalin owns native type values")
assert(audit.owner["bytecode-program"] == "llpvm.dsl", "LLPVM owns bytecode programs")
local llpvm_reuses_type_language = false
for _, member in ipairs(audit.members or {}) do
  if member.name == "llpvm.dsl" then
    for _, semantic in ipairs(member.uses or {}) do
      llpvm_reuses_type_language = llpvm_reuses_type_language or semantic == "type-language"
    end
  end
end
assert(llpvm_reuses_type_language, "LLPVM should reuse schema type-language semantics")

local chunk = assert(loadstring([[
return {
  fields = lln.product { a [lln.i32], b [lln.i64] },

  lalin = lln {
    lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
      lln.ret (a + b),
    },
  },

  proc = llpvm.task. compile {
    llpvm.input [lln.i32],
    llpvm.output [lln.i64],
    llpvm.event. progress [lln.i32],
  },

  low = llpvm {
    llpvm.pvm. Demo {
      llpvm.lang. Demo {
        llpvm.type. Node {
          llpvm.op. Int { value [lln.i64] },
        },
      },

      llpvm.world. raw [Demo],

      llpvm.tape. raw_items [raw] {
        llpvm.record. one (Node.Int { value = 1 }),
      },

      llpvm.root { raw_items, one },
    },
  },
}
]], "llpvm_language_use.lua"))
setfenv(chunk, env)

local out = chunk()
assert(#out.fields.items == 2, "Lalin fragment uses language auto names")
assert(out.lalin.name == "lalin" and #out.lalin.items == 1, "lalin zone is installed")
assert(out.lalin.items[1].name == "add" and out.lalin.items[1]:syntax_item(), "Lalin function consumes generic LLBL symbols")
assert(getmetatable(out.proc) == LLPVM.TaskSpec, "LLPVM task head is installed")
assert(out.low.name == "llpvm" and #out.low.items == 1, "llpvm zone is installed")
assert(getmetatable(out.low.items[1]) == LLPVM.ProgramSpec, "LLPVM pvm head is installed")
assert(LLPVM.bytecode(out):sub(1, 4) == "LLPV", "language-authored LLPVM zone projects to bytecode")
local schema_zone = lalin.language.load([[
return schema {
  schema. LanguageSchemaSmoke {
    schema.product. Pair { schema.interned, left [LalinType.Type], right [LalinType.Type] },
  },
}
]], "language_schema.lua")
assert(schema_zone.name == "schema" and schema_zone.items[1].name == "LanguageSchemaSmoke", "LalinSchema language namespace projects to schema zone")
local native = lalin.compile("LanguageZoneSmoke", out)
assert(native.add(3, 4) == 7, "language-authored Lalin zone projects to LuaJIT bytecode")

local formatted = lalin.language.format(out, { width = 100 })
assert(formatted:match("lalin%s*{"), "language formatter preserves lalin zone")
assert(formatted:match("llpvm%s*{"), "language formatter preserves llpvm zone")
assert(lalin.language.format(schema_zone):match("schema%. LanguageSchemaSmoke"), "language formatter delegates LalinSchema zones")
assert(formatted:match("fn%. add"), "language formatter delegates Lalin declarations")
assert(formatted:match("pvm%. Demo"), "language formatter delegates LLPVM programs")
assert(formatted:match("task%. compile"), "language formatter delegates direct LLPVM task values")
assert(LLPVM.format(out.proc):match("input %[i32%]"), "LLPVM formatter should render scalar input as source type")
assert(LLPVM.format(out.proc):match("\n  output %[i64%],"), "LLPVM formatter should use multiline task bodies")

local diagnostics = lalin.language.diagnostics(out)
assert(not diagnostics:has_errors(), "language diagnostics should accept coherent mixed language value")

local bad = lalin.language.load([[
return lalin {
  lln.fn. bad {} [lln.i32] {
    lln.ret "not an integer",
  },
}
]], "language_bad.lua")
local bad_diagnostics = lalin.language.diagnostics(bad)
assert(bad_diagnostics:has_errors(), "language diagnostics should report Lalin semantic errors")
assert(bad_diagnostics.items[1].primary ~= nil or bad_diagnostics.items[1].message ~= nil, "language diagnostic should carry blame information")

local index = lalin.language.index(out)
local saw_add, saw_demo, saw_task = false, false, false
for _, sym in ipairs(index.symbols or {}) do
  saw_add = saw_add or sym.name == "add"
  saw_demo = saw_demo or sym.name == "Demo"
  saw_task = saw_task or sym.name == "compile"
end
assert(saw_add and saw_demo and saw_task, "language index should include Lalin and LLPVM symbols")

local markdown = lalin.markdown { title = "Lalin Language Reference" }
assert(markdown:match("# Lalin Language Reference"), "lalin markdown should include title")
assert(markdown:match("## LLBL Syntax Model"), "lalin markdown should include shared syntax primer")
assert(markdown:match("## Language Extension Audit"), "lalin markdown should include language audit")
assert(markdown:match("type%-language"), "lalin markdown should document semantic owners")
assert(markdown:match("no semantic ownership overlaps"), "lalin markdown should report clean language audit")
assert(markdown:match("fn%. add"), "lalin markdown should explain canonical dot-head style")
assert(markdown:match("Shared Lua Language Builder substrate"), "lalin markdown should include llbl singleton docs")
assert(markdown:match("## lalin%.dsl"), "lalin markdown should delegate Lalin member docs")
assert(markdown:match("## llpvm%.dsl"), "lalin markdown should delegate LLPVM member docs")
assert(markdown:match("## lalinschema%.dsl"), "lalin markdown should delegate LalinSchema member docs")
assert(markdown:match("schema%. product") or markdown:match("schema%.product"), "lalin markdown should document the LalinSchema namespace")
assert(markdown:match("Lalin LLBL Surface"), "lalin markdown should include Lalin fallback introspection")
assert(markdown:match("LLPVM LLBL Surface"), "lalin markdown should include LLPVM fallback introspection")

local loaded = lalin.language.load([[
return llpvm.task. quick {
  llpvm.input [lln.i32],
  llpvm.output [lln.i32],
}
]], "language_load.lua")
assert(getmetatable(loaded) == LLPVM.TaskSpec, "language load uses composed environment")

io.write("llpvm language_use ok\n")
