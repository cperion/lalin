# CBlock ASDL Specification

**Status:** normative design specification. This document is the authority for
the ASDL migration of CBlock. Where it conflicts with the current
`cblock.lua`, this document wins and the implementation must follow.

**Canonical ASDL runtime:** `next/lua/asdl.lua` (the Terra-pattern runtime:
`NewContext`, `Define`, `Extern`, product/sum/`unique`, method installation on
ASDL classes, sum membership, `isclassof`).

**Doctrine authorities:** `docs/ASDL_GUIDE.md`, `docs/DESIGN_BIBLE.md`,
`docs/LUA_OBJECT_REGIONS.md`, `docs/OBJECT_REGION_PROJECTION_PATTERN.md`.

---

## 1. Core model

### 1.1 One object universe

There is exactly one semantic object universe. Everything that carries
semantic meaning is an ASDL value:

```text
authored facts        -> ASDL
validated facts       -> ASDL
active computations   -> ASDL
foreign ownership     -> ASDL
published projections -> ASDL
diagnostics           -> ASDL
builders              -> ASDL
```

There are **not** two universes:

```text
ASDL objects    (durable)
Lua machines    (untyped)
```

The correct statement is:

```text
machine ⊂ ASDL semantic objects
```

A *machine* is an ASDL object whose meaning is: "this exact computation is
currently in progress, with this input, ownership, cursor, builders, and
continuation graph."

Lua does not introduce a second model. Lua provides:

- methods (installed on ASDL classes);
- labels (method names);
- CPS edges (strict tail calls through stable unbound methods).

### 1.2 Three object roles

An ASDL object plays one of three roles. The role is decided by lifetime and
authority, not by a class hierarchy.

| Role | Meaning | Example |
|------|---------|---------|
| authoritative subject | durable, reusable, non-running semantic fact | `Code.Module`, `Tree.ExprCall`, `Checked.Function` |
| active computation | one invocation in progress, owns evolving state | `Machine.GccJitCook`, `Machine.ModuleCheck` |
| published projection | durable artifact/fact derived from an operation | `GccJit.Artifact`, `Host.ModuleProjection`, `Diagnostic` |

### 1.3 The separation decision test

For every proposed pair of objects, ask:

> Can these two things have different lifetimes, or coexist independently?

- `Code.Module` vs `Machine.GccJitCook` → **yes** → separate objects
  (a module is reusable across cooks, configurations, and backends).
- `GccJitCookRequest` vs `GccJitCookFrame` vs `GccJitCookMachine` →
  **no** → collapse into one `Machine.GccJitCook` object.
- an instruction vs a "projection operation" with no surviving state →
  **no** → a method on the instruction leaf, not a child machine.

Consequences:

- A durable subject SHALL NOT contain one invocation's mutable state.
- A machine exists only when state survives a CPS edge (cursor, builder,
  ownership, pending work, variable destination, independent rejection).
- Otherwise the operation is an ordinary leaf method.

### 1.4 "Inside the object" means owned operation

"Machines are inside the ASDL objects" means **semantic ownership**, not
physical mutable containment:

```lua
function T.Tree.Module:check(request, parent, on_checked, on_rejected)
    local cc = T.Machine.ModuleCheck(self, request, ...)
    return cc:run(parent, on_checked, on_rejected)
end
```

The module owns the operation vocabulary and constructs the exact computation
object. It does not store the running computation as a mutable field.

---

## 2. ASDL runtime contract

### 2.1 Runtime vocabulary

The following `next/lua/asdl.lua` vocabulary is normative:

```text
NewContext()            -> a fresh ASDL context
Context:Define(text)     -> declare products/sums from the DSL
Context:Extern(name,pred) -> register an exact foreign-type predicate
ClassName:method(...)    -> install a Lua method on an ASDL class
ClassName(...)           -> construct an ASDL value
parent:isclassof(v)      -> sum-membership test
unique                   -> interning (hash-consing) of products/constructors
```

`ClassName` is the **namespace-flat registered name**: sum constructors are
registered at namespace level (for example `CBlock.Tree.DirectValue`,
`CBlock.Tree.StmtIf`), not under their parent sum. The parent
(`CBlock.Tree.CallResult`) groups them through membership
(`parent:isclassof(v)`). Constructors of different sums in one namespace must
have unique basenames; the schema above satisfies this.

Prohibited for semantic values:

```text
asdl.classof / .kind / .tag dispatch
handler maps / visitor tables / rule tables
side tables keyed by nodes, symbols, names, or handles
ad hoc { kind = ... } / { ok = ... } records
loose context bags
nil as a semantic convention
```

### 2.2 DSL surface

The grammar used in every schema block of this document:

```text
module Name { Definition* }          namespace
Name = (Type field, Type2? opt, T3* list)     product
Name = Ctor | Other(Type x) | Nullary         sum
unique                                  interning attribute
Type name                                field (type first, then name)
Type? name                               optional field
Type* name                               list field
attributes (common fields)               shared fields on all sum constructors
```

All names are declared before any is defined, so mutually recursive type
references are legal. Cross-module references use full dotted names.

**Executable form.** Schema blocks write dotted module headers
(`module CBlock.X { ... }`) as notation. The executable form nests them and
issues one `Define` call per module block, in this dependency order:

```text
1. CBlock.Foreign pointer types   Context:Extern, before any Define
2. CBlock.Export, CBlock.Tree
3. CBlock.Checked, CBlock.Host, CBlock.Diagnostic
4. CBlock.Code
5. CBlock.Foreign products
6. CBlock.Machine
```

### 2.3 Immutability split

- **Durable semantic values** (Tree, Checked, Code nodes, diagnostics,
  projections) SHALL be treated as immutable after construction. Derive a
  projection; never mutate a phase value to attach later facts.
- **Machine objects and builders** are mutable by design. Their mutation is
  confined to named methods (`advance`, `append`, `freeze`,
  `transition_ownership`), never raw field writes outside those methods.
- **Ownership alternatives** are ASDL values stored in a machine frame and
  replaced only by a named transition method.

### 2.4 Methods

Two kinds, both installed on ASDL classes:

**Leaf methods** own one semantic case:

```lua
function T.Tree.ExprCall:check(input, cc, on_checked, on_rejected)
    return self.callee:check_call(
        T.Checked.CallInput(self.arguments, input.expected),
        cc, on_checked, on_rejected)
end
```

**Machine label methods** are static control nodes:

```lua
function T.Machine.ModuleCheck:expression_checked(checked)
    self.checked_builder:append(checked)
    self.cursor = self.cursor + 1
    return self:check_next()
end
```

Calling the concrete leaf method is the only variant dispatch.

### 2.5 CPS signature

The canonical operation shape:

```lua
return object:operation(
    typed_input,
    asdl_machine,            -- cc: the exact running machine, forwarded unchanged
    Machine.operation_ready, -- stable unbound method
    Machine.operation_rejected)
```

Rules:

- `cc` is an ASDL value of an exact machine class.
- Exits are stable unbound methods on that machine's class.
- Exit functions receive the machine first, then typed payloads.
- Machine label methods do **not** receive another continuation parameter;
  they name their successor directly.
- A stored named method is used only for a genuinely variable join or
  suspension.
- Immediate alternatives use peer exits; a durable result union is used only
  when the outcome is stored, queued, or crosses a sealed host boundary.

---

## 3. Schema universes

Four object universes, each with exact ASDL definitions.

```text
Tree       authored declarations and forms
Checked    validated, resolved, typed forms
Code       the single backend contract (C emission and libgccjit)
Host/Foreign/Diagnostic/Machine  supporting universes
```

### 3.1 `CBlock.Tree`

Authored language facts. Nothing here contains later-phase facts.

```lua
module CBlock.Tree {

  TypeShape =
      TypeVoid
    | TypeBool
    | TypeI8  | TypeI16 | TypeI32 | TypeI64
    | TypeU8  | TypeU16 | TypeU32 | TypeU64
    | TypeF32 | TypeF64
    | TypeUSize | TypeISize
    | TypePointer(TypeShape pointee) unique
    | TypeArray(TypeShape element, number count) unique
    | TypeStruct(string name) unique
    | TypeUnion(string name) unique
    | TypeOpaqueStruct(string tag) unique
    | TypeFunctionPointer(CBlock.Tree.FunctionABI abi) unique

  StructLayout = (TypeStruct struct, CBlock.Tree.Field* fields)
  UnionLayout  = (TypeUnion  union,  CBlock.Tree.Field* fields)
  Field        = (string name, TypeShape type)

  FunctionABI  = (TypeShape* parameters, CBlock.Tree.CallResult result)
  CallResult =
      DirectVoid
    | DirectValue(TypeShape type)
    | NamedExits(CBlock.Tree.Exit* exits)
  Exit        = (string name, CBlock.Tree.ExitPayload payload)
  ExitPayload = ExitWithoutValue | ExitWithValue(TypeShape type)

  Global = (string name, TypeShape type, CBlock.Tree.GlobalInitializer initializer)
  GlobalInitializer =
      GlobalInteger(number value)
    | GlobalFloat(number value)
    | GlobalBool(boolean value)
    | GlobalZero
    | GlobalArray(CBlock.Tree.Constant* elements)
    | GlobalCString(string text)
  Constant = ConstantInteger(number value)
           | ConstantFloat(number value)
           | ConstantBool(boolean value)

  Module      = (CBlock.Tree.Declaration* declarations, CBlock.Export.Binding* exports)
  Declaration =
      DeclFunction(Function callable)
    | DeclExtern(Extern extern)
    | DeclStruct(CBlock.Tree.StructLayout layout)
    | DeclUnion(CBlock.Tree.UnionLayout layout)
    | DeclGlobal(Global global)

  Function = (string name, FunctionABI abi, CBlock.Tree.Block* blocks, CBlock.Tree.Stmt* body)
  Extern   = (string name, FunctionABI abi)

  Block = (string name, TypeShape* parameter_types, CBlock.Tree.Stmt* body)

  Callee = CalleeFunction(Function callable) | CalleeExtern(Extern extern)

  Stmt =
      StmtIf(Expr condition, CBlock.Tree.Stmt on_true, CBlock.Tree.Stmt on_false)
    | StmtJump(Block target, Expr* arguments)
    | StmtExit(Exit exit, Expr? value)
    | StmtTailCall(Callee callee, Expr* arguments)
    | StmtTailPointerCall(Expr pointer, Expr* arguments)
    | StmtNamedExitCall(Callee callee, Expr* arguments, CBlock.Tree.ExitHandler* handlers)
    | StmtReturn(Expr? value)
    | StmtStore(Place place, Expr value)
    | StmtVoidCall(Callee callee, Expr* arguments)
    | StmtVoidPointerCall(Expr pointer, Expr* arguments)
    | StmtTerminateVoidCall(Callee callee, Expr* arguments)
    | StmtTerminateVoidPointerCall(Expr pointer, Expr* arguments)
    | StmtSequence(Stmt* statements)
    | StmtSwitch(Expr value, CBlock.Tree.SwitchCase* cases, Block default)
    | StmtPipelineStore(CBlock.Tree.Producer producer, Expr destination, Expr value)

  SwitchCase = (number value, Block target)
  ExitHandler = (Exit exit, Expr? result, CBlock.Tree.Stmt body)

  Expr =
      ExprConstant(CBlock.Tree.Constant value)
    | ExprParameter(number index)
    | ExprBlockParameter(Block block, number index)
    | ExprExitResult(number id)
    | ExprCall(Callee callee, Expr* arguments)
    | ExprPointerCall(Expr pointer, Expr* arguments)
    | ExprField(Expr object, Field field)
    | ExprStructConstructor(TypeStruct struct, CBlock.Tree.FieldInit* fields)
    | ExprUnionConstructor(TypeUnion union, Field field, Expr value)
    | ExprLoad(Place place)
    | ExprAddress(Place place)
    | ExprCast(Expr value, TypeShape type)
    | ExprSizeOf(TypeShape type)
    | ExprFunctionAddress(Callee callee)
    | ExprBinary(CBlock.Tree.BinaryOperation operation, Expr left, Expr right)
    | ExprSelect(Expr condition, Expr on_true, Expr on_false)
    | ExprLet(Expr value)
    | ExprPipelineLoad(Producer producer, Expr pointer)
    | ExprPipelineReduce(Producer producer, Expr value, Expr initial, CBlock.Tree.Reducer reducer)

  FieldInit = (Field field, Expr value)

  Place =
      PlaceVariable(number id, TypeShape type, Expr initial)
    | PlaceGlobal(Global global)
    | PlaceIndex(CBlock.Tree.IndexBase base, Expr index)
    | PlaceMember(Place object, Field field)
    | PlaceDereference(Expr pointer)

  IndexBase = IndexBasePlace(Place place) | IndexBasePointer(Expr pointer)

  Producer = ProducerRange(Expr first, Expr last)

  BinaryOperation =
      Add | Subtract | Multiply | Divide | Modulo
    | BitAnd | BitOr | BitXor | ShiftLeft | ShiftRight
    | LogicalAnd | LogicalOr

  Reducer = ReducerAdd | ReducerMultiply

  Conversion =
      NumericIntegerToInteger
    | NumericIntegerToFloat
    | NumericFloatToInteger
    | NumericFloatToFloat
    | NumericBoolToNumeric
    | NumericNumericToBool
    | PointerPointerToPointer
    | PointerPointerToInteger
    | PointerIntegerToPointer
}
```

Notes that are normative:

- `TypePointer`, `TypeArray`, `TypeFunctionPointer` are `unique`: identical
  shapes intern to one value.
- `TypeStruct`/`TypeUnion` are `unique` on **name**, not on fields. Each
  declaration allocates a distinct name at declaration time (not at a later
  collection phase). Two distinct structs never merge.
- Recursive aggregates are modeled as *opaque-first*: the `TypeStruct(name)`
  identity exists before its `StructLayout`, so a field may hold
  `TypePointer(TypeStruct(name))` and resolve to the same interned identity.
  This mirrors C forward declarations and libgccjit's
  `new_opaque_struct` + `set_fields`.
- A `Region` does not appear in Tree. Inlining and sealing are **staging**
  decisions: an inlined region splices statements; `call(region)` yields an
  internal `Function`. The Tree only sees functions and externs.
- `view(T)` is an ordinary `StructLayout` with ordered `ptr` and `length`
  fields; it is not a distinct type form.
- Enums remain staging constants; they create no backend type.
- Field, parameter, exit, and case order is authoritative physical order.

### 3.2 `CBlock.Checked`

A projection of Tree. Never reached by mutating Tree nodes.

```lua
module CBlock.Checked {

  Module = (CBlock.Tree.Module source, CBlock.Checked.Declaration* declarations)

  Declaration =
      CheckedFunction(Function callable)
    | CheckedExtern(Extern extern)
    | CheckedStruct(CBlock.Tree.StructLayout layout)
    | CheckedUnion(CBlock.Tree.UnionLayout layout)
    | CheckedGlobal(CBlock.Tree.Global global)

  Function = (CBlock.Tree.Function source, CBlock.Checked.Block* blocks,
              CBlock.Checked.Stmt* body, CBlock.Tree.FunctionABI abi)
  Extern   = (CBlock.Tree.Extern source, CBlock.Tree.FunctionABI abi)
  Block    = (CBlock.Tree.Block source, CBlock.Checked.Stmt* body)

  Stmt =
      CheckedIf(CBlock.Checked.Expr condition, CBlock.Checked.Stmt on_true, CBlock.Checked.Stmt on_false)
    | CheckedJump(Block target, CBlock.Checked.Expr* arguments)
    | CheckedExit(CBlock.Tree.Exit exit, CBlock.Checked.Expr? value)
    | CheckedTailCall(CBlock.Tree.Callee callee, CBlock.Checked.Expr* arguments)
    | CheckedNamedExitCall(CBlock.Tree.Callee callee, CBlock.Checked.Expr* arguments,
                           CBlock.Checked.ExitHandler* handlers)
    | CheckedReturn(CBlock.Checked.Expr? value)
    | CheckedStore(CBlock.Checked.Place place, CBlock.Checked.Expr value)
    | CheckedVoidCall(CBlock.Tree.Callee callee, CBlock.Checked.Expr* arguments)
    | CheckedTailPointerCall(CBlock.Checked.Expr pointer, CBlock.Checked.Expr* arguments)
    | CheckedVoidPointerCall(CBlock.Checked.Expr pointer, CBlock.Checked.Expr* arguments)
    | CheckedTerminateVoidCall(CBlock.Tree.Callee callee, CBlock.Checked.Expr* arguments)
    | CheckedTerminateVoidPointerCall(CBlock.Checked.Expr pointer, CBlock.Checked.Expr* arguments)
    | CheckedSequence(Stmt* statements)
    | CheckedSwitch(CBlock.Checked.Expr value, CBlock.Checked.SwitchCase* cases, Block default)
    | CheckedPipelineStore(CBlock.Tree.Producer producer, CBlock.Checked.Expr destination,
                           CBlock.Checked.Expr value)

  ExitHandler = (CBlock.Tree.Exit exit, CBlock.Checked.Expr? result, CBlock.Checked.Stmt body)
  SwitchCase  = (number value, Block target)

  Expr =
      CheckedConstant(CBlock.Tree.Constant value, CBlock.Tree.TypeShape type)
    | CheckedParameter(number index, CBlock.Tree.TypeShape type)
    | CheckedBlockParameter(Block block, number index, CBlock.Tree.TypeShape type)
    | CheckedExitResult(number id, CBlock.Tree.TypeShape type)
    | CheckedCall(CBlock.Tree.Callee callee, CBlock.Checked.Expr* arguments,
                  CBlock.Tree.TypeShape result_type)
    | CheckedPointerCall(CBlock.Checked.Expr pointer, CBlock.Checked.Expr* arguments,
                         CBlock.Tree.TypeShape result_type)
    | CheckedField(CBlock.Checked.Expr object, CBlock.Tree.Field field,
                   CBlock.Tree.TypeShape result_type)
    | CheckedStructConstructor(CBlock.Tree.TypeStruct struct, CBlock.Checked.FieldInit* fields,
                               CBlock.Tree.TypeShape result_type)
    | CheckedUnionConstructor(CBlock.Tree.TypeUnion union, CBlock.Tree.Field field,
                              CBlock.Checked.Expr value, CBlock.Tree.TypeShape result_type)
    | CheckedLoad(CBlock.Checked.Place place, CBlock.Tree.TypeShape type)
    | CheckedAddress(CBlock.Checked.Place place, CBlock.Tree.TypeShape type)
    | CheckedCast(CBlock.Checked.Expr value, CBlock.Tree.Conversion conversion,
                  CBlock.Tree.TypeShape type)
    | CheckedSizeOf(CBlock.Tree.TypeShape measured, CBlock.Tree.TypeShape type)
    | CheckedFunctionAddress(CBlock.Tree.Callee callee, CBlock.Tree.TypeShape type)
    | CheckedBinary(CBlock.Tree.BinaryOperation operation, CBlock.Checked.Expr left,
                    CBlock.Checked.Expr right, CBlock.Tree.TypeShape left_compute_type,
                    CBlock.Tree.TypeShape right_compute_type, CBlock.Tree.TypeShape result_type)
    | CheckedCompare(CBlock.Tree.BinaryOperation comparison, CBlock.Checked.Expr left,
                     CBlock.Checked.Expr right, CBlock.Tree.TypeShape compute_type)
    | CheckedSelect(CBlock.Checked.Expr condition, CBlock.Checked.Expr on_true,
                    CBlock.Checked.Expr on_false, CBlock.Tree.TypeShape type)
    | CheckedLet(CBlock.Checked.Expr value, CBlock.Tree.TypeShape type)
    | CheckedPipelineLoad(CBlock.Tree.Producer producer, CBlock.Checked.Expr pointer,
                          CBlock.Tree.TypeShape type)
    | CheckedPipelineReduce(CBlock.Tree.Producer producer, CBlock.Checked.Expr value,
                            CBlock.Checked.Expr initial, CBlock.Tree.Reducer reducer,
                            CBlock.Tree.TypeShape type)

  FieldInit = (CBlock.Tree.Field field, CBlock.Checked.Expr value)

  Place =
      CheckedVariablePlace(number id, CBlock.Tree.TypeShape type)
    | CheckedGlobalPlace(CBlock.Tree.Global global, CBlock.Tree.TypeShape type)
    | CheckedIndexPlace(CBlock.Checked.IndexBase base, CBlock.Checked.Expr index,
                        CBlock.Tree.TypeShape element)
    | CheckedFieldPlace(CBlock.Checked.Place object, CBlock.Tree.Field field,
                        CBlock.Tree.TypeShape type)
    | CheckedDereferencePlace(CBlock.Checked.Expr pointer, CBlock.Tree.TypeShape type)

  IndexBase = CheckedIndexBasePlace(CBlock.Checked.Place place)
            | CheckedIndexBasePointer(CBlock.Checked.Expr pointer)
}
```

Normative rules:

- Every `CheckedExpr` and `CheckedPlace` carries its exact resolved type.
- `CheckedBinary` carries `left_compute_type` and `right_compute_type` (the C
  integer promotions) and `result_type` (the storage type). No backend may
  infer these.
- `CheckedCall` references a `Function` object, not a C name.
- `CheckedField` references a `Field` object, not a string.
- `CheckedCast` records an explicit `Conversion` alternative (see §7.2).
- Checking failures are CPS exits; they never produce a `{ok=false}` record.

### 3.3 `CBlock.Code`

The single backend contract. Both `emit_c` and `cook_gccjit` consume this
universe. Pipelines and `let`/`select`/`if_` have fully desugared here; only
the closed primitive set remains.

```lua
module CBlock.Code {

  Module = (
    CBlock.Code.TypeEntry* types,
    CBlock.Code.Global* globals,
    CBlock.Code.Callable* callables,
    CBlock.Code.Function* functions,
    CBlock.Tree.StructLayout* struct_layouts,
    CBlock.Tree.UnionLayout* union_layouts
  )

  TypeEntry = (number id, CBlock.Tree.TypeShape shape)
  Global    = (number id, string name, CBlock.Tree.TypeShape type,
               CBlock.Tree.GlobalInitializer initializer)
  Callable  = (number id, string c_name, CBlock.Tree.FunctionABI abi, CBlock.Code.CallableKind kind)
  CallableKind =
      CallableExported
    | CallableInternal
    | CallableImported
    | CallableBoundHost(CBlock.Host.HostSymbolBinding binding)

  Function = (number callable, CBlock.Code.Register* registers,
              CBlock.Code.Block* blocks, number entry_block_id)
  Register = (number id, CBlock.Tree.TypeShape type)
  Block    = (number id, CBlock.Code.Instruction* instructions, CBlock.Code.Terminator terminator)
}
```

`id` fields are the canonical spine references (dense, 1-based, function-local
for registers and blocks, module-local for types/globals/callables). The
`many` lists are dense arrays aligned to those ids.

`TypeEntry` enumerates every distinct type shape used anywhere in the module
(primitives, pointers, arrays, structs, unions, fnptrs) in deterministic
first-use order; backends project densely over this list.

### 3.4 Supporting universes

```lua
module CBlock.Host {
  HostSymbolBinding = (string symbol_name, CBlock.Foreign.VoidPtr address,
                       CBlock.Tree.TypeShape fnptr_type)

  ModuleProjection = (
    CBlock.Host.AggregateEntry* aggregates,
    CBlock.Host.CallableEntry* callables
  )
  AggregateEntry = (CBlock.Tree.TypeStruct struct, string ffi_typedef, string ffi_name)
  CallableEntry  = (CBlock.Code.Callable callable, string ffi_function_type, string symbol_name)
}

module CBlock.Diagnostic {
  Diagnostic =
      UnknownField(CBlock.Tree.TypeStruct struct, string name)
    | DuplicateField(CBlock.Tree.TypeStruct struct, string name)
    | UnknownExit(CBlock.Tree.FunctionABI abi, string name)
    | DuplicateExit(CBlock.Tree.FunctionABI abi, string name)
    | MissingArgument(CBlock.Tree.FunctionABI abi, string name)
    | ExtraArgument(CBlock.Tree.FunctionABI abi, string name)
    | ArgumentTypeMismatch(CBlock.Tree.FunctionABI abi, number ordinal,
                           CBlock.Tree.TypeShape expected, CBlock.Tree.TypeShape actual)
    | InvalidCast(CBlock.Tree.TypeShape source, CBlock.Tree.TypeShape target)
    | InvalidReturn(CBlock.Tree.FunctionABI abi, CBlock.Tree.TypeShape expected,
                    CBlock.Tree.TypeShape actual)
    | UnterminatedBlock(CBlock.Tree.Block block)
    | DuplicateSwitchCase(number value)
    | InvalidSwitchCondition(CBlock.Tree.TypeShape actual)
    | RecursiveValueLayout(CBlock.Tree.TypeStruct struct)
    | ArrayByValueRejected(CBlock.Tree.TypeShape type)
    | OpaqueByValueRejected(CBlock.Tree.TypeShape type)
    | FunctionPointerReturnRejected(CBlock.Tree.FunctionABI abi)
    | UnsupportedCallPosition(CBlock.Tree.FunctionABI abi)
    | UnsupportedGlobalInitializer(CBlock.Tree.Global global)
    | GccJitRejected(string reason, string first_error)
}
```

```lua
module CBlock.Export {
  Path = (string* segments)
  Binding = (CBlock.Export.Path path, CBlock.Tree.Declaration declaration)
}
```


The following foreign handle types are registered with `Context:Extern`
(exact predicates in §11.1), **not** with `Define`:

- `CBlock.Foreign.GccJitContextPtr`
- `CBlock.Foreign.GccJitResultPtr`
- `CBlock.Foreign.GccJitTypePtr`
- `CBlock.Foreign.GccJitFieldPtr`
- `CBlock.Foreign.GccJitStructPtr`
- `CBlock.Foreign.GccJitFunctionPtr`
- `CBlock.Foreign.GccJitBlockPtr`
- `CBlock.Foreign.GccJitRValuePtr`
- `CBlock.Foreign.GccJitLValuePtr`
- `CBlock.Foreign.GccJitParamPtr`
- `CBlock.Foreign.GccJitCasePtr`
- `CBlock.Foreign.VoidPtr`

`CBlock.Foreign` types are registered with `Context:Extern` using exact
predicates (§11.1). No `any`, `table`, `userdata`, or `cdata` built-in is used.

---

## 4. Active machines

Machines are ASDL products in `CBlock.Machine`. They are created by their
owning semantic subject and exist for one exact operation.

### 4.1 Machine products

```lua
module CBlock.Machine {

  ModuleCheck = (
    CBlock.Tree.Module source,
    CBlock.Checked.DeclarationBuilder declarations,
    CBlock.Diagnostic.DiagnosticBuilder diagnostics,
    number cursor
  )

  FunctionCheck = (
    CBlock.Machine.ModuleCheck parent,
    CBlock.Tree.Function callable,
    CBlock.Checked.BlockBuilder blocks,
    CBlock.Checked.ExprBuilder locals,
    number cursor
  )

  ModuleLower = (
    CBlock.Checked.Module source,
    CBlock.Code.ModuleBuilder code,
    number cursor
  )

  FunctionLower = (
    CBlock.Machine.ModuleLower parent,
    CBlock.Checked.Function callable,
    CBlock.Code.FunctionBuilder builder
  )

  CEmission = (
    CBlock.Code.Module code,
    CBlock.Code.CNameFacet names,
    CBlock.Code.DocumentBuilder document,
    number cursor
  )

  GccJitCook = (
    CBlock.Code.Module code,
    CBlock.Code.GccJitConfiguration configuration,
    CBlock.Host.HostSymbolBinding* bindings,
    CBlock.Foreign.GccContextOwnership context,
    CBlock.Foreign.GccResultOwnership result,
    CBlock.Foreign.GccTypeProjection* types,
    CBlock.Foreign.GccFieldProjection* fields,
    CBlock.Foreign.GccGlobalProjection* globals,
    CBlock.Foreign.GccCallableProjection* callables,
    CBlock.Foreign.GccRegisterProjection* registers,
    CBlock.Foreign.GccBlockProjection* blocks,
    CBlock.Foreign.GccPublishedSymbolBuilder symbols,
    CBlock.Diagnostic.DiagnosticBuilder diagnostics,
    number cursor
  )
}
```

Where referenced builder/ownership/facet types are:

```lua
module CBlock.Checked {
  DeclarationBuilder = (CBlock.Checked.Declaration* items)
  BlockBuilder       = (CBlock.Checked.Block* items)
  ExprBuilder        = (CBlock.Checked.Expr* items)
}

module CBlock.Diagnostic {
  DiagnosticBuilder = (CBlock.Diagnostic.Diagnostic* items)
}

module CBlock.Code {
  ModuleBuilder   = (CBlock.Code.TypeEntry* types, CBlock.Code.Global* globals,
                     CBlock.Code.Callable* callables, CBlock.Code.Function* functions)
  FunctionBuilder = (CBlock.Code.Register* registers, CBlock.Code.Block* blocks)
  DocumentBuilder = (string* lines)
  CNameFacet = (CBlock.Code.TypeNameEntry* types, CBlock.Code.CallableNameEntry* callables,
                CBlock.Code.GlobalNameEntry* globals)
  TypeNameEntry     = (CBlock.Tree.TypeShape type, string c_name)
  CallableNameEntry = (CBlock.Code.Callable callable, string c_name)
  GlobalNameEntry   = (CBlock.Code.Global global, string c_name)

  GccJitConfiguration = (
    CBlock.Code.GccOptimization optimization,
    string* command_line_options,
    CBlock.Code.GccInspection inspection
  )
  GccOptimization = Optimize0 | Optimize1 | Optimize2 | Optimize3
  GccInspection   = NoInspection | WriteInspectionArtifacts(string directory)
}

module CBlock.Foreign {
  GccContextOwnership =
      GccContextUnacquired
    | GccContextOwned(CBlock.Foreign.GccJitContextPtr context)
    | GccContextReleased

  GccResultOwnership =
      GccResultUnavailable
    | GccResultOwned(CBlock.Foreign.GccJitResultPtr result)
    | GccResultReleased

  GccTypeProjection     = (CBlock.Code.TypeEntry source, CBlock.Foreign.GccJitTypePtr handle)
  GccFieldProjection    = (CBlock.Tree.Field source, CBlock.Foreign.GccJitFieldPtr handle)
  GccGlobalProjection   = (CBlock.Code.Global source, CBlock.Foreign.GccJitLValuePtr handle)
  GccCallableProjection = (CBlock.Code.Callable source, CBlock.Foreign.GccJitFunctionPtr handle)
  GccRegisterProjection = (CBlock.Code.Register source, CBlock.Foreign.GccJitLValuePtr handle)
  GccBlockProjection    = (CBlock.Code.Block source, CBlock.Foreign.GccJitBlockPtr handle)
  GccPublishedSymbolBuilder = (CBlock.Foreign.PublishedSymbol* items)
  PublishedSymbol = (CBlock.Code.Callable callable, CBlock.Foreign.VoidPtr address)
}
```

### 4.2 Machine laws

1. A machine owns one coherent computation and no unrelated fact bag.
2. A machine's named methods are its static control graph; strict tail calls
   are the edges.
3. A machine SHALL NOT be a universal phase object, scheduler, or
   control-state family.
4. A machine stores a named method only for a genuinely variable join or
   suspension.
5. Reentrancy is a second machine instance, never one machine with a global
   mode.
6. A machine SHALL NOT cache foreign handles keyed by semantic nodes outside
   the projection entry products declared above.
7. A machine owns diagnostics for decisions it makes; a later machine wraps
   them with an explicit diagnostic, never by mutating a shared blob.

### 4.3 Builders

- A builder preserves one ordered family.
- `builder:append(value)` adds exactly one member.
- `builder:freeze()` returns a durable `many` product and forbids further
  append. After freeze the machine transitions to a method that no longer
  references the builder.
- A builder is not a generic accumulator. It is used only when nested machines
  must append into one shared sink (e.g. diagnostics); otherwise the machine
  owns the accumulating list directly.

---

## 5. The complete code vocabulary

### 5.1 Instructions

```lua
module CBlock.Code {

  Instruction =
      CodeConstant(number destination, CBlock.Tree.Constant value)
    | CodeMove(number destination, number source)
    | CodeBinary(number destination, CBlock.Tree.BinaryOperation operation,
                 number left, number right, CBlock.Tree.TypeShape left_compute_type,
                 CBlock.Tree.TypeShape right_compute_type, CBlock.Tree.TypeShape result_type)
    | CodeCompare(number destination, CBlock.Tree.BinaryOperation comparison,
                  number left, number right, CBlock.Tree.TypeShape compute_type)
    | CodeCast(number destination, number source, CBlock.Tree.Conversion conversion)
    | CodeSizeOf(number destination, CBlock.Tree.TypeShape measured_type)
    | CodeLoad(number destination, CBlock.Code.Place source_place)
    | CodeStore(CBlock.Code.Place destination_place, number value)
    | CodeAddress(number destination, CBlock.Code.Place source_place)
    | CodeArrayDecay(number destination, CBlock.Code.Place source_place)
    | CodePointerLoad(number destination, number pointer, number index)
    | CodePointerStore(number pointer, number index, number value)
    | CodeFieldValue(number destination, number object, CBlock.Tree.Field field)
    | CodeStructConstructor(number destination, CBlock.Tree.TypeStruct type,
                            CBlock.Code.FieldValue* fields)
    | CodeUnionConstructor(number destination, CBlock.Tree.TypeUnion type,
                           CBlock.Tree.Field field, number value)
    | CodeDirectCall(number? destination, number callable, number* arguments)
    | CodePointerCall(number? destination, number pointer, number* arguments)
    | CodeEvaluateCall(number callable, number* arguments)
    | CodeEvaluatePointerCall(number pointer, number* arguments)
    | CodeFunctionAddress(number destination, number callable)

  FieldValue = (CBlock.Tree.Field field, number value)

  Place =
      PlaceRegister(number register)
    | PlaceGlobal(number global)
    | PlaceIndex(CBlock.Code.PlaceOrPointer base, number index)
    | PlaceField(CBlock.Code.Place base, CBlock.Tree.Field field)
    | PlaceDeref(number pointer)

  PlaceOrPointer = PlaceOrPointerPlace(CBlock.Code.Place place)
                 | PlaceOrPointerRegister(number pointer)
}
```

All id fields are `number` spine references (register, global, and callable
ids are dense ordinals, function-local for registers and blocks, module-local
for types/globals/callables). `number?` is absent exactly for a void call.

### 5.2 Terminators

```lua
module CBlock.Code {

  Terminator =
      TerminatorJump(number target)
    | TerminatorConditional(number condition, number on_true, number on_false)
    | TerminatorSwitch(number value, CBlock.Code.SwitchCase* cases, number default)
    | TerminatorReturnVoid
    | TerminatorReturnValue(number value)
    | TerminatorReturnExit(number ordinal, number? value)
    | TerminatorTailCall(number callable, number* arguments)
    | TerminatorTailPointerCall(number pointer, number* arguments)
    | TerminatorCallThenJump(number? destination, number callable, number* arguments,
                             number successor)
    | TerminatorNamedExitCall(number tag_destination, number callable, number* arguments,
                              CBlock.Code.NamedExitSuccessor* exits)

  SwitchCase = (number value, number target)
  NamedExitSuccessor = (number ordinal, number? carried_destination, number target)
}
```

### 5.3 Termination and trap rules

- Every `Code.Block` has exactly one terminator.
- A block SHALL NOT be emitted or projected as falling off its end.
- A terminating void call (`StmtTerminateVoidCall`,
  `StmtTerminateVoidPointerCall`) lowers to `CodeEvaluateCall` /
  `CodeEvaluatePointerCall` followed by `TerminatorReturnVoid`. A
  non-terminating `StmtVoidCall` / `StmtVoidPointerCall` lowers to the
  evaluate instruction only.
- `TerminatorSwitch` default and `TerminatorNamedExitCall` invalid-ordinal
  successor are represented by a synthesized trap block:

  ```text
  __builtin_trap();
  goto self;
  ```

  The self-edge satisfies libgccjit's terminated-block requirement; GCC
  recognizes `__builtin_trap` as non-returning. An invalid exit ordinal
  therefore fails visibly rather than falling through or silently mapping to
  an exit.

### 5.4 Parallel jump semantics

`StmtJump`/`TerminatorJump` with multiple block arguments is lowered as:

1. compute every source register;
2. assign every destination register;
3. jump.

This preserves `loop(i - 1, acc + i)`. The C emitter and the libgccjit
projector both implement this order; no backend may reorder argument
evaluation.

---

## 6. Type, place, and arithmetic semantics

### 6.1 Type projection

| CBlock type | C emission | libgccjit |
|---|---|---|
| `void` | `void` | `GCC_JIT_TYPE_VOID` |
| `bool` | `bool` | `GCC_JIT_TYPE_BOOL` |
| `i8…i64` | exact `int*_t` | exact signed sized type |
| `u8…u64` | exact `uint*_t` | exact unsigned sized type |
| `f32` | `float` | `GCC_JIT_TYPE_FLOAT` |
| `f64` | `double` | `GCC_JIT_TYPE_DOUBLE` |
| `usize` | `size_t` | `GCC_JIT_TYPE_SIZE_T` |
| `isize` | `ptrdiff_t` | signed `get_int_type` of `ptrdiff_t` width (8 on LP64) |
| `ptr(T)` | `T *` | `gcc_jit_type_get_pointer(T)` |
| `array(T,N)` | `T[N]` | `new_array_type` |
| struct | `struct name {…}` | opaque struct + `set_fields` |
| union | `union name {…}` | `new_union_type` |
| opaque | `struct Tag;` | `new_opaque_struct` |
| fnptr | `R (*)(…)` | `new_function_ptr_type` |
| `view(T)` | its struct | its struct |

### 6.2 Integer promotions

The checker records C promotions explicitly. Both backends consume
`left_compute_type`/`right_compute_type`/`result_type`; neither infers them
from storage width.

```text
i8 + i8   compute i32, then convert to i8 destination
u8 + u8   compute i32, then convert to u8 destination
i16 < i16 compare promoted i32 operands
u32 + u32 compute u32
i64 / i64 compute i64
f32 * f32 compute f32
f64 * f64 compute f64
```

Shifts record the promoted left type (`left_compute_type`), the promoted
right operand type (`right_compute_type`), and the final storage conversion
(`result_type`). For non-shift binary operations the two compute types are
equal. Signed overflow keeps GCC/C semantics. CBlock does not silently
introduce wrapping semantics.

### 6.3 Cast semantics

Conversions are decided during checking and recorded exactly:

```text
NumericConversion
  IntegerToInteger | IntegerToFloat | FloatToInteger
  FloatToFloat     | BoolToNumeric  | NumericToBool
PointerConversion
  PointerToPointer | PointerToInteger | IntegerToPointer
```

Projection:

- numeric conversions → `gcc_jit_context_new_cast`;
- same-size pointer reinterpretation → `new_bitcast`;
- pointer→smaller-integer → pointer → `usize` bitcast → numeric cast;
- smaller-integer→pointer → numeric cast → `usize` → pointer bitcast.

Aggregate/numeric, float/pointer, and incompatible function-pointer
conversions are rejected by the checker and never reach a backend.

### 6.4 Aggregate construction

- Struct: `gcc_jit_context_new_struct_constructor`; field handles derived from
  `FieldId`, never field names. CBlock requires all struct fields exactly
  once; no zero-fill-by-omission.
- Union: `gcc_jit_context_new_union_constructor`; exactly one active field.
- Array: `gcc_jit_context_new_array_constructor`; arrays are never callable
  values — they appear in fields, globals, indexing, and decay.
- C string global: one `u8` rvalue per byte plus the final NUL (a string
  literal rvalue cannot initialize a `char[]` in libgccjit).

### 6.5 Recursion

- Recursive value layout is rejected (`RecursiveValueLayout`).
- Recursion through pointers is legal and uses the opaque-first struct model.

---

## 7. Backend A — C emission

### 7.1 Request and result

```lua
function T.Code.Module:emit_c(request, cc, on_emitted, on_rejected)
```

`request` carries the `CNameFacet` and target facts. `cc` is a
`Machine.CEmission`. `on_emitted` publishes a `C.Artifact`:

```lua
C.Artifact = (string* lines)
```

### 7.2 Emission order

Deterministic, independent of Lua iteration order:

1. includes (`<stdint.h>`, `<stdbool.h>`, `<stddef.h>`);
2. aggregate typedefs (`typedef struct T T;`), then forward opaque tags;
3. aggregate definitions in dependency order (reject recursive value layout);
4. internal globals with constant initializers;
5. extern prototypes;
6. function prototypes;
7. function bodies.

### 7.3 Names

Names come from `CNameFacet` (§9). Emission NEVER synthesizes names by
string-munging a semantic object on the fly.

---

## 8. Backend B — libgccjit

### 8.1 Public boundary

```lua
local module, runtime = C.gccjit(build, request)
```

Semantics are identical to other CBlock cooking:

- whole module cooks lazily on first exported call;
- subsequent calls reuse the published result;
- exported structs use existing LuaJIT FFI definitions;
- direct functions return direct values;
- named-exit functions return `exit_name, optional_value`;
- `module:free()` releases the result;
- `module.source` remains the emitted-C representation of the same
  `Code.Module` for inspection and AOT.

There is no automatic TCC fallback. A libgccjit rejection remains visible.

### 8.2 Control graph

`Machine.GccJitCook` methods form the graph:

```text
run
  -> acquire
  -> project_declared_types
  -> project_fields
  -> project_globals
  -> project_callables
  -> project_function_bodies
  -> validate_context
  -> compile_context
  -> publish_symbols
  -> release_context
  -> published
  |  -> rejected   (from any node)
```

Each node is a named method. Peers are `published` and `rejected`.

### 8.3 Ownership lifecycle

- Construction objects (types, fields, globals, params, functions, blocks,
  lvalues, rvalues, cases) are context-owned and never individually released.
- Successful cook: compile → retain result → publish symbols → release
  context → retain result + host callbacks until module release.
- Rejection: copy `get_first_error` → record rejection → release context →
  release result if any → clear borrowed pointers → enter rejected.
- Module release: invalidate wrappers → clear pointers → release result →
  release retained host callback cdata → released. Release is idempotent;
  invocation after release is an explicit lifecycle error.
- The first libgccjit error is authoritative. `get_last_error` is transient
  and is never persisted.

### 8.4 Instruction mapping

| Instruction | libgccjit call |
|---|---|
| constant (int) | `new_rvalue_from_long` / `new_rvalue_from_int` |
| constant (float) | `new_rvalue_from_double` |
| constant zero/one | `gcc_jit_context_zero` / `one` |
| move | `gcc_jit_block_add_assignment` |
| binary | `new_binary_op` (op per `BinaryOperation`, result type = `left_compute_type`) |
| compare | `new_comparison` |
| cast | `new_cast` / `new_bitcast` (§6.3) |
| sizeof | `new_sizeof` |
| load place | `gcc_jit_lvalue_as_rvalue` |
| store place | `add_assignment(place_lvalue, value)` |
| address | `gcc_jit_lvalue_get_address` |
| array decay | address of element zero → `T *` |
| pointer load | `new_array_access` → `lvalue_as_rvalue` |
| pointer store | `add_assignment(array_access_lvalue, value)` |
| field value | `gcc_jit_rvalue_access_field` |
| struct constructor | `new_struct_constructor` |
| union constructor | `new_union_constructor` |
| direct call (value) | `new_call` |
| pointer call (value) | `new_call_through_ptr` |
| evaluate call | `add_eval` |
| function address | `gcc_jit_function_get_address` (generated/imported) or bound-host ptr rvalue |

### 8.5 Terminator mapping

| Terminator | libgccjit call |
|---|---|
| jump | `end_with_jump` |
| conditional | `end_with_conditional` |
| switch | `end_with_switch` (default = trap block) |
| return void | `end_with_void_return` |
| return value | `end_with_return` |
| return exit | deref out-param assignment + `end_with_return(ordinal)` |
| tail call | `new_call` + `set_bool_require_tail_call(1)` + `end_with_return` |
| tail pointer call | `new_call_through_ptr` + require tail + `end_with_return` |
| call then jump | `add_assignment`/`add_eval` + `end_with_jump` |
| named exit call | `new_call` + assign tag + conditional chain on ordinals |

### 8.6 Function and extern projection

- All aggregate types, globals, and callable signatures are declared before
  function bodies (recursion and mutual calls).
- `CallableExported` → `GCC_JIT_FUNCTION_EXPORTED`.
- `CallableInternal` → `GCC_JIT_FUNCTION_INTERNAL`.
- `CallableImported` → `GCC_JIT_FUNCTION_IMPORTED` (resolved by the process
  dynamic linker by C name).
- `CallableBoundHost` → exact `new_function_ptr_type` +
  `new_rvalue_from_ptr` + `new_call_through_ptr`, so LuaJIT FFI callbacks work
  without process-symbol-table visibility.
- The result/session owner retains every host callback cdata until the result
  is released.
- Missing/extra bindings are rejected before compilation.

### 8.7 Register and block projection

- Every register becomes one libgccjit local lvalue (`function_new_local` or
  `function_new_temp`).
- Parameters remain libgccjit parameters; a prologue assigns them to their
  register locals and jumps to the CBlock entry block.
- Register reads always use `lvalue_as_rvalue`.
- Every CBlock block becomes one `gcc_jit_block` (plus synthesized trap
  blocks).
- Projection arrays align to `Code` spine ids; there are no side tables.

### 8.8 Configuration

```text
optimization            Optimize0..Optimize3 (default Optimize3)
command_line_options    e.g. "-march=native" (opt-in only)
inspection              NoInspection | WriteInspectionArtifacts(directory)
```

Inspection writes: context dump, one CFG/DOT per function, assembler output,
and a manifest (library version, target, optimization, exported symbols).

### 8.9 Published artifact

```lua
GccJit.Artifact = (
  CBlock.Foreign.GccResultOwnership result,
  CBlock.Foreign.PublishedSymbol* symbols,
  CBlock.Host.ModuleProjection host_module
)
```

---

## 9. Naming determinism (`CNameFacet`)

Names are a derived facet, never written back onto source values.

- Exported declarations: namespace path joined by `_` (e.g. `math.add` →
  `math_add`).
- Generated private names use fixed serials allocated at declaration time:
  `cblock_func_<n>`, `cblock_view_<n>`, `cblock_s<n>` (struct tag),
  `cblock_global_<n>`, `cblock_str_<n>`.
- Serial allocation order equals declaration order; the facet is reproducible
  from the module spine alone.
- Only exported callables and exported aggregates receive public names;
  everything else is internal/static.
- Externs MUST be exported: their namespace path is the linker symbol.
- No backend resolves a function or field by string. Strings are emitted
  metadata only.
- Export status is an authored `CBlock.Export.Binding` on `Tree.Module`: a
  bound declaration is exported (public C name); everything else is
  internal/static.

---

## 10. Host ABI projection

The physical ABI is the single contract shared by all backends:

```c
DirectVoid:  void f(P...);
DirectValue: T f(P...);
NamedExits:  int32_t f(P..., T1 *k1_out, ..., Tn *kn_out);
```

- Only value-carrying exits add out-parameters.
- Out-parameters appear in exit declaration order.
- Exit ordinals are declaration order, 1-based.
- `Runtime:invoke` returns `exit_name, optional_value` via `f.conts[ordinal]`.

`Host.ModuleProjection` owns the LuaJIT FFI spellings and exported ABI shape.
Cooking produces it; it is never attached as `host_runtime` on source
declarations.

---

## 11. Foreign handle types

### 11.1 Exact predicates

Every `CBlock.Foreign` type is registered with `Context:Extern` and an exact
predicate:

```lua
local function gcc_ptr(ctype)
    local t = ffi.typeof(ctype)
    return function(v) return ffi.istype(t, v) end
end

T:Extern("CBlock.Foreign.GccJitContextPtr", gcc_ptr("gcc_jit_context *"))
T:Extern("CBlock.Foreign.GccJitResultPtr",  gcc_ptr("gcc_jit_result *"))
T:Extern("CBlock.Foreign.GccJitTypePtr",     gcc_ptr("gcc_jit_type *"))
T:Extern("CBlock.Foreign.GccJitFieldPtr",    gcc_ptr("gcc_jit_field *"))
T:Extern("CBlock.Foreign.GccJitStructPtr",   gcc_ptr("gcc_jit_struct *"))
T:Extern("CBlock.Foreign.GccJitFunctionPtr", gcc_ptr("gcc_jit_function *"))
T:Extern("CBlock.Foreign.GccJitBlockPtr",    gcc_ptr("gcc_jit_block *"))
T:Extern("CBlock.Foreign.GccJitRValuePtr",   gcc_ptr("gcc_jit_rvalue *"))
T:Extern("CBlock.Foreign.GccJitLValuePtr",   gcc_ptr("gcc_jit_lvalue *"))
T:Extern("CBlock.Foreign.GccJitParamPtr",    gcc_ptr("gcc_jit_param *"))
T:Extern("CBlock.Foreign.GccJitCasePtr",     gcc_ptr("gcc_jit_case *"))
T:Extern("CBlock.Foreign.VoidPtr",           gcc_ptr("void *"))
```

### 11.2 Enum tables (authoritative; verify against installed header)

```text
GCC_JIT_TYPE_*:
  VOID=0 VOID_PTR=1 BOOL=2 CHAR=3 SIGNED_CHAR=4 UNSIGNED_CHAR=5
  SHORT=6 UNSIGNED_SHORT=7 INT=8 UNSIGNED_INT=9 LONG=10 UNSIGNED_LONG=11
  LONG_LONG=12 UNSIGNED_LONG_LONG=13 FLOAT=14 DOUBLE=15 LONG_DOUBLE=16
  CONST_CHAR_PTR=17 SIZE_T=18 FILE_PTR=19 COMPLEX_FLOAT=20 COMPLEX_DOUBLE=21
  COMPLEX_LONG_DOUBLE=22 UINT8_T=23 UINT16_T=24 UINT32_T=25 UINT64_T=26
  UINT128_T=27 INT8_T=28 INT16_T=29 INT32_T=30 INT64_T=31 INT128_T=32
  BFLOAT16=33 FLOAT16=34 FLOAT32=35 FLOAT64=36 FLOAT128=37

GCC_JIT_BINARY_OP_*:
  PLUS=0 MINUS=1 MULT=2 DIVIDE=3 MODULO=4 BITWISE_AND=5 BITWISE_XOR=6
  BITWISE_OR=7 LOGICAL_AND=8 LOGICAL_OR=9 LSHIFT=10 RSHIFT=11

GCC_JIT_COMPARISON_*:
  EQ=0 NE=1 LT=2 LE=3 GT=4 GE=5

GCC_JIT_FUNCTION_*:
  EXPORTED=0 INTERNAL=1 IMPORTED=2 ALWAYS_INLINE=3

GCC_JIT_INT_OPTION_OPTIMIZATION_LEVEL = 0
GCC_JIT_OUTPUT_KIND_ASSEMBLER = 0
```

A startup self-test SHALL assert these against the loaded library before any
cook proceeds.

---

## 12. Ownership and lifetime rules

1. Context-owned handles never escape context lifetime.
2. Code pointers never outlive their result.
3. Host callback cdata outlives generated code.
4. Rejection copies the first error and retires the context (a context with an
   error is poisoned).
5. Release order: wrappers → borrowed pointers → result → host callbacks →
   context (context already released on success).
6. `Code.Module` never holds a context, result, cursor, or rejection.

---

## 13. Diagnostics

- Diagnostics are ASDL leaves carrying entities, expected/actual types, and
  origins — never a bare formatted string.
- Formatting is a method on the diagnostic leaf.
- Diagnostics accumulate in a `DiagnosticBuilder` (one shared sink threaded
  through nested machines).
- A backend wraps a foreign failure in a precise diagnostic leaf (e.g.
  `GccJitCompileRejected { reason, first_error }`), never in a stringly result.

---

## 14. Migration procedure

### 14.1 Phase line

```text
Lua staging
  -> CBlock.Tree
  -> (check) CBlock.Checked
  -> (lower) CBlock.Code
  -> (emit_c | cook_gccjit) artifacts
```

No phase may bypass or duplicate another. The old tagged pipeline is removed,
not wrapped.

### 14.2 Deletion list

The migration is incomplete while any of these remain as semantic mechanisms:

```text
.kind / .stmt / .op dispatch
def_check / def_lower handler tables
is_terminator string classification
BINOP string maps
lowered tuple instructions ("calln", "struct_init", ...)
function lookup by C-name string
field lookup by field-name string
T.checked mutation
T.c / T.name mutation
Struct.by_name semantic maps
host_runtime attached to declarations
compatibility conversion from ASDL to old tagged tables
weak Lua interning caches for pointer/array/fnptr identity
```

### 14.3 No shims

There is no dual semantic pipeline and no conversion shim between ASDL and the
old tagged records. Tests fail loudly until call sites use exact ASDL values.

---

## 15. Validation gates

1. **Leaf coverage** — every concrete Tree/Checked/Code leaf owns each
   declared method (check, lower, emit_c, project_gccjit) or legally inherits
   a shared default. Missing behavior is a missing leaf method.
2. **CPS conformance** — every multi-exit operation names its complete peer
   exit set; every exit is a stable unbound method; every selection is a
   strict tail call.
3. **Differential semantics** — every CBlock test module runs through emitted
   C/GCC and libgccjit; outputs and named exits agree.
4. **ABI parity** — structs by value, pointer args, void functions, named
   multi-exit functions, out-parameters, and host callbacks match across
   backends.
5. **Arithmetic parity** — promotion-sensitive cases (`u8+u8`, `i16<i16`,
   shifts) produce identical values in both backends.
6. **Performance** — warmed LuaJIT vs CBlock/TCC vs CBlock/libgccjit vs
   emitted C/GCC on hailstone and SAXPY.
7. **Inspection** — vectorization, tail-call shape, and absence of accidental
   dispatch are confirmed in emitted assembly.
8. **Lifetime** — context release, result release, module reuse, rejection
   cleanup, and post-`free()` invocation errors are all tested.
9. **Long-process cost** — compile latency and RSS measured over 1/10/100/500
   modules; documented as a constraint.
10. **Determinism** — same module spine yields byte-identical C text and
    identical exported symbol sets.

---

## 16. Numbered invariants

1. `emit_c` and `cook_gccjit` consume the same `CBlock.Code` value.
2. Every reference uses stable entity identity (object identity or spine id),
   not strings.
3. Every block terminates; invalid ordinals trap.
4. Integer promotions are explicit in `CheckedBinary`.
5. Parallel jump assignment preserves source values.
6. Named-exit ABI is identical across C and libgccjit.
7. Tail edges are marked as required tail calls.
8. Host callback cdata outlives generated code.
9. Context objects never escape context lifetime.
10. Code pointers never outlive their result.
11. Diagnostics preserve the first libgccjit error.
12. No missing operation silently falls back to emitted C or TCC.
13. Exported aggregate FFI layout and libgccjit target layout are
    ABI-identical.
14. Machines, builders, ownership, projections, diagnostics, and
    foreign-handle relations are all ASDL values.
15. Lua contributes only methods, labels, and CPS edges between ASDL objects.
