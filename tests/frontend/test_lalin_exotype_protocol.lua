package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local Exotype = require("lalin.exotype")
local Document = require("lalin.syntax.document")
local asdl = require("lalin.asdl")

local T = require("lalin.schema_v2")
local Tr = T.LalinTree

local getentries_count = 0
local methodmissing_count = 0

local Student = Exotype.new {
  name = "Student",
  metamethods = {
    __getentries = function(self)
      getentries_count = getentries_count + 1
      return {
        { name = "name", ty = "ptr [u8]" },
        { name = "year", ty = "i32" },
      }
    end,
    __methodmissing = function(self, method_name)
      methodmissing_count = methodmissing_count + 1
      local field = method_name:match("^set(.+)$")
      assert(field == "year", "test only expects setyear")
      local doc = Document.parse([=[
fn Student.setyear(self [ptr [Student]], value [i32]) [void]
  return
end
]=], "@student-setyear.lln")
      return doc.body[1]
    end,
  },
}

assert(Exotype.is(Student), "Student should be an exotype")
assert(tostring(Student):match("Student"), "exotype tostring should include typename")
assert(lalin.dsl.make_env({ no_namespaces = true }).exotype == Exotype, "default host env should expose exotype API")
local memo_count = 0
local memo_family = Exotype.memoize(function(Ty)
  memo_count = memo_count + 1
  return Exotype.new { name = "Box" .. Exotype.typename(Ty), entries = { { name = "value", ty = Ty } } }
end)
assert(memo_family(Student) == memo_family(Student) and memo_count == 1, "exotype constructors should memoize by stable type identity")

-- Parsed struct declarations are first-class exotype owners.
local function parsed_student_method_missing(Ty, method_name)
  assert(Exotype.is(Ty), "parsed struct host value should already be an exotype owner")
  local field = method_name:match("^set(.+)$")
  assert(field == "score", "test only expects setscore")
  return Document.parse([=[
fn ParsedStudent.setscore(self [ptr [ParsedStudent]], value [i32]) [void]
  return
end
]=], "@parsed-student-setscore.lln").body[1]
end
local parsed_decls, parsed_doc = assert(lalin.loadstring([=[
struct ParsedStudent
  score [i32]
end

ParsedStudent.metamethods.__methodmissing = parsed_student_method_missing

fn use_parsed_student(s [ptr [ParsedStudent]]) [void]
  s:setscore(99)
  return
end
]=], "@parsed-student-exotype.lln", { env = { parsed_student_method_missing = parsed_student_method_missing } }))
assert(Exotype.is(parsed_doc.env.ParsedStudent), "ordinary parsed struct should bind as exotype owner")
assert(parsed_doc.env.ParsedStudent.methods.setscore ~= nil, "parsed struct owner should receive generated method")
assert(#parsed_decls == 3 and parsed_decls[3].name == "setscore", "parsed method call should synthesize owner method")

-- Top-level exotype HostEval under the decls role synthesizes a concrete struct.
local decls, doc = assert(lalin.loadstring([=[
[Student]

fn accept(s [Student]) [void]
  return
end
]=], "@student-exotype.lln", { env = { Student = Student } }))
assert(#decls == 2, "exotype document should materialize struct + function")
assert(decls[1].tag == "DeclStruct" and decls[1].name == "Student", "exotype layout should become DeclStruct")
assert(#decls[1].fields == 2 and decls[1].fields[2].name == "year", "exotype fields should materialize")
assert(doc.env.Student == Student, "document env keeps exotype owner for later property queries")
assert(getentries_count == 1, "__getentries should be memoized")

local module = lalin.syntax.to_module(decls, "StudentExotype", T)
assert(asdl.classof(module.items[1]) == Tr.ItemType, "exotype struct lowers to ItemType")
assert(asdl.classof(module.items[2]) == Tr.ItemFunc, "function using exotype type lowers to ItemFunc")

local Explicit = Exotype.new {
  name = "Explicit",
  entries = { { name = "x", ty = "i32" } },
  methods = {
    zero = Document.parse([=[
fn Explicit.zero(self [ptr [Explicit]]) [i32]
  return 0
end
]=], "@explicit-zero.lln").body[1],
  },
}
local explicit_decls = assert(lalin.loadstring("[Explicit]", "@explicit-exotype.lln", { env = { Explicit = Explicit } }))
assert(#explicit_decls == 2 and explicit_decls[2].name == "zero", "finite explicit exotype methods should emit with the layout")

-- A method query is staged: the host property creates an ordinary qualified function declaration.
local decls2, doc2 = assert(lalin.loadstring([=[
[Student]
[Student:method("setyear")]
]=], "@student-methodmissing.lln", { env = { Student = Student } }))
assert(#decls2 == 2, "exotype method query should add one function declaration")
assert(decls2[2].tag == "DeclFunc" and decls2[2].name == "setyear", "methodmissing should synthesize DeclFunc")
assert(decls2[2].qualifier[1] == "Student", "synthesized method should be qualified by owner")
assert(doc2.env.Student == Student and doc2.env.Student.setyear == decls2[2], "qualified method binds on exotype owner")
assert(methodmissing_count == 1, "__methodmissing should be memoized")
assert(Student:method("setyear") == decls2[2], "re-querying method should return cached declaration")
assert(methodmissing_count == 1, "cached method query should not re-run property")

local module2 = lalin.syntax.to_module(decls2, "StudentMethodMissing", T)
assert(asdl.classof(module2.items[2]) == Tr.ItemFunc, "synthesized method lowers as ordinary function")
assert(module2.items[2].func.name == "setyear", "synthesized method keeps compiler function name")
assert(#module2.items[2].func.params == 2 and module2.items[2].func.params[1].name == "self", "synthesized method has explicit self")

-- Parsed receiver method calls trigger staged dependency synthesis from the receiver's exotype type.
local decls3 = assert(lalin.loadstring([=[
[Student]

fn use_student(s [Student]) [void]
  s:setyear(2030)
  return
end
]=], "@student-auto-methodmissing.lln", { env = { Student = Student } }))
assert(#decls3 == 3, "method call on exotype-typed receiver should synthesize or reuse missing method declaration")
local has_setyear = false
for _, d in ipairs(decls3) do if d.tag == "DeclFunc" and d.name == "setyear" then has_setyear = true end end
assert(has_setyear, "auto synthesized declaration is setyear")
local module3 = lalin.syntax.to_module(decls3, "StudentAutoMethodMissing", T)
assert(asdl.classof(module3.items[2]) == Tr.ItemFunc and asdl.classof(module3.items[3]) == Tr.ItemFunc, "auto method dependency lowers as ordinary func")

local decls3b = assert(lalin.loadstring([=[
[Student]

fn use_student_ptr(s [ptr [Student]]) [void]
  s:setyear(2030)
  return
end
]=], "@student-auto-methodmissing-ptr.lln", { env = { Student = Student } }))
local has_setyear_ptr = false
for _, d in ipairs(decls3b) do if d.tag == "DeclFunc" and d.name == "setyear" then has_setyear_ptr = true end end
assert(#decls3b == 3 and has_setyear_ptr, "ptr receiver containing exotype owner should synthesize or reuse missing method")

-- Remaining property vocabulary is available through the same staged resolver.
local Hooks = Exotype.new {
  name = "Hooks",
  metamethods = {
    __entrymissing = function(self, name) return "entry:" .. name end,
    __apply = function(self, a, b) return (a or 0) + (b or 0) end,
    __cast = function(self, from_ty, to_ty, expr) return { from_ty, to_ty, expr } end,
    __add = function(self, a, b) return a + b end,
  },
}
assert(Hooks:entry("field") == "entry:field", "__entrymissing hook should resolve")
assert(Hooks:apply(2, 5) == 7, "__apply hook should resolve")
assert(Hooks:operator("add", 10, 32) == 42, "operator hook should resolve")
assert(Hooks:cast("a", "b", "c")[2] == "b", "__cast hook should resolve")

-- Cyclic property queries fail with an exotype diagnostic instead of recursing forever.
local Cyclic = Exotype.new {
  name = "Cyclic",
  metamethods = {
    __getmethod = function(self, name)
      return self:method(name)
    end,
  },
}
local ok, err = pcall(function() return Cyclic:method("loop") end)
assert(not ok and tostring(err):match("E_LALIN_EXOTYPE_PROPERTY"), "cyclic property query should diagnose")

io.write("lalin exotype protocol ok\n")
