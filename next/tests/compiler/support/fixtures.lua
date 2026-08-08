local List = require("terralist")
local Compiler = require("lalin.compiler.schema")

local Fixtures = {}

function Fixtures.list(values)
  local out = List()
  for _, value in ipairs(values or {}) do out:insert(value) end
  return out
end

function Fixtures.name(text)
  return Compiler.Source.Name(text)
end

function Fixtures.qualified_name(text)
  return Compiler.Source.QualifiedName(Fixtures.list({ Fixtures.name(text) }))
end

function Fixtures.path(text)
  return Compiler.Source.Path(text)
end

function Fixtures.file(path, bytes)
  return Compiler.Source.File(Fixtures.path(path or "@fixture.lln"), bytes or "")
end

function Fixtures.range(start, length)
  return Compiler.Source.Range(
    Compiler.Source.ByteOffset(start or 0),
    Compiler.Source.ByteLength(length or 0))
end

function Fixtures.origin(path, bytes, start, length)
  return Compiler.Source.Written(
    Fixtures.file(path or "@fixture.lln", bytes or ""),
    Fixtures.range(start or 0, length or 0))
end

function Fixtures.built_origin(source, ordinal)
  return Compiler.Source.Built(source or "fixture", Compiler.Source.Ordinal(ordinal or 0))
end

function Fixtures.symbol(name, linkage)
  return Compiler.Source.Symbol(name, linkage or Compiler.Source.InternalLinkage())
end

function Fixtures.generation(key)
  return Compiler.Provenance.Generation(key or "fixture-generation")
end

function Fixtures.code_ordinal(value)
  return Compiler.Code.Ordinal(value or 0)
end

function Fixtures.i32()
  return Compiler.Types.SignedInteger(32)
end

function Fixtures.u32()
  return Compiler.Types.UnsignedInteger(32)
end

function Fixtures.bool()
  return Compiler.Types.Bool()
end

function Fixtures.index()
  return Compiler.Types.Index()
end

function Fixtures.float(bits)
  return Compiler.Types.Float(bits or 64)
end

function Fixtures.raw_pointer()
  return Compiler.Types.RawPointer()
end

function Fixtures.pointer(element)
  return Compiler.Types.Pointer(element or Fixtures.i32())
end

function Fixtures.imported_c(spelling)
  return Compiler.Types.ImportedC(spelling or "intptr_t")
end

function Fixtures.void()
  return Compiler.Types.Void()
end

function Fixtures.default_target()
  return Compiler.Target.Spec(
    "x86_64-unknown-linux-gnu",
    Compiler.Target.Pointer64(),
    Compiler.Target.Index64(),
    Compiler.Target.LittleEndian(),
    Compiler.Target.Lp64())
end

function Fixtures.source_void_type(origin)
  return Compiler.Source.VoidType(origin or Fixtures.built_origin("void", 0))
end

function Fixtures.source_header(name, origin)
  return Compiler.Source.DeclarationHeader(
    Fixtures.qualified_name(name or "fixture_fn"),
    Compiler.Source.LocalVisibility(),
    origin or Fixtures.built_origin("header", 0))
end

function Fixtures.source_function_declaration(name)
  local origin = Fixtures.built_origin(name or "source-fn", 0)
  return Compiler.Source.FunctionDeclaration(
    Fixtures.source_header(name or "fixture_fn", origin),
    Fixtures.list(),
    Fixtures.source_void_type(origin),
    Fixtures.list(),
    Compiler.Source.StatementBody(Fixtures.list({ Compiler.Source.ReturnVoidStatement(origin) })))
end

function Fixtures.semantic_block_label(name, ordinal)
  return Compiler.Semantic.BlockLabel(
    Fixtures.name(name or "entry"),
    Fixtures.built_origin(name or "block", ordinal or 0))
end

function Fixtures.semantic_function(name, result)
  local label = Fixtures.semantic_block_label("entry", 0)
  local origin = Fixtures.built_origin(name or "semantic-fn", 0)
  local terminator = Compiler.Semantic.ReturnVoid(Compiler.Semantic.GeneratedTerminator(origin), origin)
  local block = Compiler.Semantic.Block(label, Fixtures.list(), Fixtures.list(), terminator)
  local body = Compiler.Semantic.Body(label, Fixtures.list({ block }))
  return Compiler.Semantic.Function(
    Fixtures.source_function_declaration(name or "fixture_fn"),
    Fixtures.list(),
    result or Fixtures.void(),
    Fixtures.list(),
    body)
end

function Fixtures.semantic_callable(fn)
  return Compiler.Semantic.FunctionCallable(fn)
end

function Fixtures.semantic_erasure(callable)
  return Compiler.Semantic.Erasure(callable, Fixtures.list())
end

function Fixtures.empty_source_program(key)
  local generation = Fixtures.generation(key or "empty-source")
  return Compiler.Source.DocumentProgram(
    Fixtures.file("@empty.lln", ""),
    Fixtures.list(),
    generation)
end

function Fixtures.empty_semantic_program(key)
  local generation = Fixtures.generation(key or "empty-semantic")
  return Compiler.Semantic.Program(
    Fixtures.empty_source_program(key or "empty-source"),
    Fixtures.list(),
    generation)
end

function Fixtures.empty_code_module(key)
  local generation = Fixtures.generation(key or "empty-code")
  return Compiler.Code.Module(
    Fixtures.empty_semantic_program(key or "empty-semantic"),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    generation)
end

function Fixtures.c_type(type_value, size, alignment)
  local layout = Compiler.Types.ScalarLayout(
    type_value,
    Fixtures.default_target(),
    Compiler.Target.NaturalLayout(),
    size or 4,
    alignment or size or 4)
  return Compiler.C.Type(type_value, layout)
end

function Fixtures.c_i32_type()
  return Fixtures.c_type(Fixtures.i32(), 4, 4)
end

function Fixtures.c_u32_type()
  return Fixtures.c_type(Fixtures.u32(), 4, 4)
end

function Fixtures.c_void_type()
  return Fixtures.c_type(Fixtures.void(), 0, 1)
end

function Fixtures.code_signature(parameter_types, result_type)
  return Compiler.Code.Signature(Fixtures.list(parameter_types or {}), result_type or Fixtures.void())
end

function Fixtures.code_function(name, signature)
  return Compiler.Code.Function(Fixtures.semantic_function(name or "fn", signature.result), signature)
end

function Fixtures.callable_abi(callable, parameters, result)
  return Compiler.Types.CallableABI(
    callable,
    Fixtures.default_target(),
    Compiler.Types.Cdecl(),
    Fixtures.list(parameters or {}),
    result or Compiler.Types.VoidResult(),
    Fixtures.semantic_erasure(callable))
end

function Fixtures.c_signature_for_function(fn, parameter_passings, result_abi)
  return Compiler.C.Signature(
    fn.signature,
    Fixtures.callable_abi(Fixtures.semantic_callable(fn.source), parameter_passings, result_abi))
end

function Fixtures.c_generated_local(name, type_value, ordinal)
  return Compiler.C.Local(
    Compiler.C.GeneratedLocal(Fixtures.built_origin(name or "local", ordinal or 0)),
    type_value or Fixtures.c_i32_type(),
    Fixtures.code_ordinal(ordinal or 0))
end

function Fixtures.c_generated_parameter(name, type_value, ordinal)
  return Compiler.C.Parameter(
    Compiler.C.GeneratedParameter(Fixtures.built_origin(name or "param", ordinal or 0)),
    type_value or Fixtures.c_i32_type(),
    Compiler.CMat.OrdinaryPointer(),
    Fixtures.code_ordinal(ordinal or 0))
end

function Fixtures.c_label(fn, name, ordinal)
  local block = Compiler.Code.Block(fn, Fixtures.semantic_block_label(name or "entry", ordinal or 0), Fixtures.code_ordinal(ordinal or 0))
  return Compiler.C.Label(Compiler.C.CodeLabel(block), Fixtures.code_ordinal(ordinal or 0))
end

function Fixtures.c_local_value(local_value)
  return Compiler.C.LocalValue(local_value)
end

function Fixtures.c_constant_i32(raw)
  return Compiler.Code.SemanticConstant(
    Compiler.Types.IntegerConstant(raw or "0", raw or "0", Fixtures.i32()))
end

function Fixtures.c_constant_value(raw)
  return Compiler.C.ConstantValue(Fixtures.c_constant_i32(raw or "0"))
end

function Fixtures.scalar_meaning()
  return Compiler.Semantic.ScalarMeaning(
    Compiler.Source.WrappingOverflow(),
    Compiler.Source.IeeeFloat(),
    Compiler.Source.Nontrapping())
end

function Fixtures.c_i32_add_function_definition()
  local i32 = Fixtures.i32()
  local c_i32 = Fixtures.c_i32_type()
  local code_sig = Fixtures.code_signature({ i32, i32 }, i32)
  local code_fn = Fixtures.code_function("add", code_sig)
  local c_sig = Fixtures.c_signature_for_function(
    code_fn,
    { Compiler.Types.Direct(i32), Compiler.Types.Direct(i32) },
    Compiler.Types.DirectResult(i32))
  local c_fn = Compiler.C.Function(code_fn, c_sig, Fixtures.symbol("add", Compiler.Source.ExportLinkage()))
  local param_a = Fixtures.c_generated_parameter("a", c_i32, 0)
  local param_b = Fixtures.c_generated_parameter("b", c_i32, 1)
  local result = Fixtures.c_generated_local("result", c_i32, 0)
  local label = Fixtures.c_label(code_fn, "entry", 0)
  local origin = Fixtures.built_origin("i32_add", 0)
  local op = Compiler.C.BinaryOp(
    result,
    Compiler.Source.Add(),
    Compiler.C.ParameterValue(param_a),
    Compiler.C.ParameterValue(param_b),
    Fixtures.scalar_meaning())
  local statement = Compiler.C.Statement(op, Fixtures.code_ordinal(0), origin)
  local terminator = Compiler.C.ReturnValue(Compiler.C.LocalValue(result), origin)
  local block = Compiler.C.Block(label, Fixtures.list(), Fixtures.list({ statement }), terminator)
  return Compiler.C.FunctionDefinition(
    c_fn,
    Fixtures.list({ Compiler.C.FunctionParameter(param_a, Compiler.Types.Direct(i32)), Compiler.C.FunctionParameter(param_b, Compiler.Types.Direct(i32)) }),
    Compiler.C.DirectSlot(result),
    Fixtures.list({ result }),
    label,
    Fixtures.list({ block }),
    Fixtures.list())
end

function Fixtures.empty_c_unit(key)
  local generation = Fixtures.generation(key or "empty-c-unit")
  return Compiler.C.Unit(
    Fixtures.empty_code_module(key or "empty-code"),
    Fixtures.default_target(),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    Fixtures.list(),
    generation)
end

return Fixtures
