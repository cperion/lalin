local Compiler = require("lalin.compiler.schema")
local spec = require("support.spec")
local schema_inventory = require("compiler.support.schema_inventory")

local describe, it = spec.describe, spec.it

local function sorted_keys(tbl)
  local out = {}
  for key in pairs(tbl) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function class_at(path)
  local node = Compiler
  for part in path:gmatch("[^.]+") do
    node = assert(node[part], "missing schema path " .. path .. " at " .. part)
  end
  return node
end

local function member_names(path)
  local cls = class_at(path)
  local names = {}
  for member in pairs(cls.members or {}) do
    if member.kind then names[#names + 1] = member.kind end
  end
  table.sort(names)
  return names
end

local function assert_members(path, expected)
  spec.assert_list_equal(member_names(path), expected, path .. " members")
end

describe("frozen compiler schema inventory", function()
  it("has the exact module list", function()
    spec.assert_list_equal(sorted_keys(Compiler.namespaces), {
      "Analysis",
      "C",
      "CMat",
      "Code",
      "Control",
      "Diagnostic",
      "Effect",
      "Host",
      "Kernel",
      "Memory",
      "Ownership",
      "Provenance",
      "Semantic",
      "Source",
      "Target",
      "Types",
    }, "schema modules")
  end)

  it("has the frozen declaration count", function()
    local count = 0
    for _ in pairs(Compiler.definitions) do count = count + 1 end
    spec.assert_equal(count, 1422, "runtime class definition count")
  end)

  it("matches the frozen full field-shape inventory golden", function()
    local path = "next/tests/compiler/golden/schema/inventory.txt"
    local actual = schema_inventory.render(Compiler)
    if os.getenv("LALIN_REGEN_SCHEMA") == "1" then
      schema_inventory.write_file(path, actual)
    end
    local expected = schema_inventory.read_file(path)
    spec.assert_equal(actual, expected, "schema inventory golden")
  end)

  it("has frozen runtime definition counts per module", function()
    local counts = {}
    for name in pairs(Compiler.definitions) do
      local module = assert(name:match("^([^.]+)%..+$"), "definition without module: " .. tostring(name))
      counts[module] = (counts[module] or 0) + 1
    end
    spec.assert_equal(counts.Analysis, 2, "Analysis definition count")
    spec.assert_equal(counts.C, 105, "C definition count")
    spec.assert_equal(counts.CMat, 74, "CMat definition count")
    spec.assert_equal(counts.Code, 113, "Code definition count")
    spec.assert_equal(counts.Control, 95, "Control definition count")
    spec.assert_equal(counts.Diagnostic, 240, "Diagnostic definition count")
    spec.assert_equal(counts.Effect, 23, "Effect definition count")
    spec.assert_equal(counts.Host, 31, "Host definition count")
    spec.assert_equal(counts.Kernel, 31, "Kernel definition count")
    spec.assert_equal(counts.Memory, 100, "Memory definition count")
    spec.assert_equal(counts.Ownership, 7, "Ownership definition count")
    spec.assert_equal(counts.Provenance, 4, "Provenance definition count")
    spec.assert_equal(counts.Semantic, 187, "Semantic definition count")
    spec.assert_equal(counts.Source, 313, "Source definition count")
    spec.assert_equal(counts.Target, 30, "Target definition count")
    spec.assert_equal(counts.Types, 67, "Types definition count")
  end)

  it("has the frozen source declaration count", function()
    local text = assert(io.open("next/lua/lalin/compiler/schema.lua")):read("*a")
    local count = 0
    for _ in text:gmatch("\n  [A-Za-z_][A-Za-z0-9_]*%s*=") do count = count + 1 end
    spec.assert_equal(count, 354, "ASDL declaration count")
  end)

  it("has no duplicate field names inside any class", function()
    local duplicates = {}
    for _, cls in pairs(Compiler.definitions) do
      local seen = {}
      for index, field in ipairs(cls.__fields or {}) do
        if seen[field.name] then
          duplicates[#duplicates + 1] = (cls.name or cls.kind or tostring(cls))
            .. "." .. field.name .. " at fields " .. seen[field.name] .. " and " .. index
        end
        seen[field.name] = index
      end
    end
    spec.assert_equal(table.concat(duplicates, "; "), "", "duplicate schema fields")
  end)

  it("uses no banned field escape-hatch types", function()
    local banned = { any = true, table = true, map = true, func = true,
      ["function"] = true, thread = true, userdata = true, cdata = true }
    local violations = {}
    for _, cls in pairs(Compiler.definitions) do
      for _, field in ipairs(cls.__fields or {}) do
        if banned[field.type] then
          violations[#violations + 1] = (cls.name or cls.kind or tostring(cls))
            .. "." .. field.name .. ":" .. tostring(field.type)
        end
      end
    end
    spec.assert_equal(table.concat(violations, "; "), "", "banned field types")
  end)

  it("has no optional fields in the frozen schema", function()
    local optionals = {}
    for _, cls in pairs(Compiler.definitions) do
      for _, field in ipairs(cls.__fields or {}) do
        if field.optional then
          optionals[#optionals + 1] = (cls.name or cls.kind or tostring(cls))
            .. "." .. field.name
        end
      end
    end
    spec.assert_equal(table.concat(optionals, "; "), "", "optional fields")
  end)

  it("interns every nullary constructor as a singleton ASDL value", function()
    local failures = {}
    local nullary = 0
    for _, cls in pairs(Compiler.definitions) do
      if cls.kind and #(cls.__fields or {}) == 0 then
        nullary = nullary + 1
        if cls() ~= cls() then
          failures[#failures + 1] = cls.name or cls.kind
        end
      end
    end
    table.sort(failures)
    spec.assert_equal(nullary, 205, "nullary constructor count")
    spec.assert_equal(table.concat(failures, ", "), "", "non-singleton nullary constructors")
  end)
end)

describe("source surface schema", function()
  it("pins type-form leaves", function()
    assert_members("Source.TypeForm", {
      "ArrayType", "BoolType", "ClosureType", "FloatType", "FunctionType",
      "ImportedCType", "IndexType", "InvalidateType", "LeaseType", "NamedType",
      "NoaliasType", "NoescapeType", "OwnedType", "PointerType", "PreserveType",
      "RawPointerType", "ReadonlyType", "SignedIntegerType", "SliceType",
      "UnsignedIntegerType", "ViewType", "VoidType", "WriteonlyType",
    })
  end)

  it("pins statement leaves and excludes unreachable yield leaves", function()
    assert_members("Source.Statement", {
      "AssertStatement", "AssignmentStatement", "AtomicFenceStatement",
      "AtomicStoreStatement", "ConditionalJumpStatement", "ContractStatement",
      "ExpressionStatement", "FoldStatement", "IfStatement", "JumpStatement",
      "LetStatement", "LoopStatement", "RegionCallStatement", "RegionEmitStatement",
      "ReturnValueStatement", "ReturnVoidStatement", "ScanStatement",
      "SwitchStatement", "TrapStatement", "VarStatement", "VariantSwitchStatement",
    })
    spec.assert_nil(Compiler.Source.YieldVoidStatement)
    spec.assert_nil(Compiler.Source.YieldValueStatement)
  end)
end)

describe("semantic schema", function()
  it("pins semantic expression leaves", function()
    assert_members("Semantic.Expression", {
      "AddressOfExpression", "AggregateExpression", "AlignOfExpression",
      "ArrayExpression", "AtomicCompareExchangeExpression", "AtomicLoadExpression",
      "AtomicRmwExpression", "BinaryExpression", "BindingExpression", "CallExpression",
      "CastExpression", "ClosureExpression", "CompareExpression", "ConstantExpression",
      "ConstructorExpression", "DereferenceExpression", "FieldExpression",
      "FromReprExpression", "IndexExpression", "IntrinsicExpression", "IsNullExpression",
      "LengthExpression", "LoadExpression", "LogicExpression", "MethodCallExpression",
      "NullExpression", "ReferenceExpression", "ReprExpression", "SelectExpression",
      "SizeOfExpression", "UnaryExpression", "ViewExpression",
    })
    spec.assert_nil(Compiler.Semantic.MachineCastExpression)
    spec.assert_nil(Compiler.Semantic.StringReference)
  end)

  it("pins semantic terminators", function()
    assert_members("Semantic.Terminator", {
      "Branch", "Jump", "RegionCall", "ReturnValue", "ReturnVoid", "Switch",
      "Trap", "Unreachable", "VariantSwitch",
    })
  end)
end)

describe("analysis and optimization schema", function()
  it("pins counted flow and loop flow split", function()
    assert_members("Control.CountedFlow", { "GridFlow", "RangeFlow", "TiledFlow", "WindowFlow" })
    assert_members("Control.LoopFlow", { "CountedLoop", "TraversalLoop", "UncountedLoop" })
    assert_members("Control.Induction", { "AffineInduction", "RecurrenceInduction" })
    assert_members("Control.ReductionAlgebra", { "Reduction", "Scan" })
    spec.assert_nil(Compiler.Control.LoopAlgebra)
  end)

  it("pins memory object relations separately from dependences", function()
    assert_members("Memory.ObjectRelation", {
      "Disjoint", "ExactNoalias", "Incomparable", "MayAlias", "Overlap",
      "ProvenAlias", "SameStore",
    })
    assert_members("Memory.Dependence", {
      "AccessDependence", "LoopDependence", "UnknownDependence",
    })
    spec.assert_nil(Compiler.Memory.Relation)
  end)

  it("pins effect atoms without subjectless analyzed duplicates", function()
    assert_members("Effect.Atom", {
      "AllocateEffect", "FenceEffect", "InvalidateEffect", "KnownCallEffect",
      "NoescapeEffect", "PreserveEffect", "ReadEffect", "RetainEffect",
      "UnknownCallEffect", "WriteEffect",
    })
    spec.assert_nil(Compiler.Effect.VolatileEffect)
    spec.assert_nil(Compiler.Effect.AtomicEffect)
    spec.assert_nil(Compiler.Effect.TrapEffect)
    spec.assert_nil(Compiler.Effect.ExternalEffect)
  end)

  it("pins kernel lanes and result cadence", function()
    assert_members("Kernel.Lane", { "AccumulatorLane", "CounterLane", "InputLane", "OutputLane" })
    assert_members("Kernel.ResultCadence", { "OrdinaryResult", "ReductionResult" })
    spec.assert_nil(Compiler.Kernel.Binding)
    spec.assert_nil(Compiler.Kernel.ScalarResult)
    spec.assert_nil(Compiler.Kernel.ScanResult)
  end)
end)

describe("CMat and C backend schema", function()
  it("pins CMat coordinate leaves and folded basis", function()
    assert_members("CMat.Coordinate", {
      "AbsoluteCoordinate", "DynamicWindowCoordinate", "IterationCoordinate",
      "ScatterCoordinate", "WindowCoordinate",
    })
    spec.assert_nil(Compiler.CMat.Basis)
    spec.assert_nil(Compiler.CMat.Producer)
  end)

  it("pins C operation leaves", function()
    assert_members("C.Operation", {
      "AddressOp", "AggregateOp", "AliasOp", "ArrayOp", "AtomicCompareExchangeOp",
      "AtomicFenceOp", "AtomicLoadOp", "AtomicRmwOp", "AtomicStoreOp", "BinaryOp",
      "CastOp", "ClosureCallOp", "ClosureOp", "CompareOp", "ConstantOp",
      "DirectCallOp", "ExternalCallOp", "HelperCallOp", "IndirectCallOp",
      "IntrinsicOp", "LoadOp", "PointerOffsetOp", "SelectOp", "SliceDataOp",
      "SliceLengthOp", "SliceMakeOp", "StoreOp", "UnaryOp", "VariantConstructOp",
      "VariantPayloadOp", "VariantTagOp", "ViewDataOp", "ViewLengthOp",
      "ViewMakeOp", "ViewStrideOp",
    })
  end)

  it("pins C terminators and host failure leaves", function()
    assert_members("C.Terminator", {
      "Branch", "Jump", "ReturnValue", "ReturnVoid", "Switch", "Trap",
      "Unreachable", "VariantSwitch",
    })
    assert_members("Host.CookFailure", {
      "CompilationFailure", "CompilerUnavailable", "DynamicLoadFailure",
      "FastMathRefused", "FileWriteFailure", "ProcessSpawnFailure",
    })
  end)
end)

describe("diagnostic schema", function()
  it("pins compiler error families", function()
    assert_members("Diagnostic.CompilerError", {
      "AbiRejected", "AnalysisRejected", "BackendRejected", "CEmissionRejected",
      "CheckRejected", "ClosureRejected", "CodeRejected", "ConstantRejected",
      "ContractRejected", "ControlRejected", "LayoutRejected", "MemoryRejected",
      "OptimizationRejected", "OwnershipRejected", "ReducerRejected", "RegionRejected",
      "ResolutionRejected", "SourceRejected", "SynthesisRejected", "TypeRejected",
    })
  end)
end)
