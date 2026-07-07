# Plan A — Tree Phase Implementation

**Agent:** A
**Scope:** Frontend tree phases + code_validate + compiler_result + helper deletion
**Lines:** ~11,000

---

## MANDATORY READING — READ THESE FILES COMPLETELY BEFORE WRITING A SINGLE LINE

1. `docs/FILE_ORGANIZATION.md` — the master architectural document. Defines schema_v2/ vs impl/, method shape, forbidden patterns.
2. `docs/ASDL_GUIDE.md` — the ASDL doctrine. Leaf methods ARE dispatch. No classof. No side tables.
3. `TARGET-SCHEMA.md` — the target architecture for schema_v2. You need to know what types exist.
4. `AUDIT-REPORT.md` — known defects and fixes applied to schema_v2.
5. `lua/lalin/schema_v2/` — READ THE ACTUAL FILES. Open schema_v2/tree.lua, schema_v2/code.lua, etc. See what types exist and how they're named.

**Do not skip this.** The previous attempt failed because agents didn't read the docs. Read them ALL.

---

## WHAT YOU ARE BUILDING

This is a **REWRITE, not a port.** You are NOT copy-pasting old files into impl/. You are writing NEW code that installs methods on schema_v2 ASDL types.

**The architecture:**
- `lua/lalin/schema_v2/tree.lua` defines `LalinTree` schema: types like `Tree.ExprCall`, `Tree.StmtLet`, `Tree.Module`, etc. These are Lua tables with metatables.
- `lua/lalin/impl/tree_code.lua` requires schema_v2 types and installs methods: `function Tree.ExprCall:lower_expr_to_code(lctx) ... end`
- When code calls `some_expr:lower_expr_to_code(lctx)`, Lua's metatable dispatches to the correct leaf method.

**The method shape:**
```lua
-- impl/tree_code.lua
local Tree = require("lalin.schema_v2.tree")
local Code = require("lalin.schema_v2.code")
local TreeCode = require("lalin.schema_v2.tree_code")

function Tree.ExprLit:lower_expr_to_code(lctx)
  -- Produce a CodeConst for this literal
  return lctx.builder:const(self.value)
end

function Tree.ExprCall:lower_expr_to_code(lctx)
  -- Lower callee and args, emit call instruction
  local callee = self.callee:lower_expr_to_code(lctx)
  local args = {} -- lower each arg
  return lctx.builder:call(callee, args)
end
```

**The old code provides LOGIC, not STRUCTURE.** Read `lua/lalin/tree_lower.lua` to understand what logic each lowering function performs, then write that logic as a leaf method on the concrete ASDL type. Do NOT require the old file. Do NOT wrap it. Do NOT (T)-call it.

---

## FORBIDDEN — IF YOU DO ANY OF THESE, YOU FAIL

```lua
-- FAIL: requiring old implementation files
local old = require("lalin.tree_lower")(T)  -- NO. NEVER.

-- FAIL: classof dispatch
if asdl.classof(expr) == Tree.ExprCall then  -- NO. Write Tree.ExprCall:method() instead.

-- FAIL: handler maps
local handlers = { ExprCall = f1, ExprLit = f2 }  -- NO. Leaf methods.

-- FAIL: side tables / caches keyed by nodes
local cache = {}  -- NO. Use ASDL interned products or method parameters.

-- FAIL: trying to make the file 'runnable'
-- Do NOT add test code. Do NOT add wrappers. Do NOT try to require() and run it.
-- The file installs methods. That's it. pipeline.lua calls them later.

-- FAIL: compatibility shims or links to old code
-- Do NOT add wrappers that delegate to the old implementation.
-- This is a REWRITE. New code only.

-- FAIL: kind-string dispatch
if expr.kind == "ExprCall" then  -- NO. Leaf method on Tree.ExprCall.
```

**The only verification:** `luajit -e "require('lalin.impl.tree_code')"` must not error. That's it. Not 'works'. Not 'runs'. Just loads.

---

## HOW TO APPROACH EACH FILE

1. Read the old source file(s) listed for the impl file you're writing. Understand the LOGIC.
2. Read the schema_v2 file(s) for the types you're installing methods on. Know the TYPE NAMES.
3. Write `lua/lalin/impl/xxx.lua`. Start with `require("lalin.schema_v2.xxx")` statements.
4. For each function in the old file: identify the receiver type, write `function ReceiverType:method_name(params) ... end`
5. If the old code uses `classof` to branch on type X vs Y: write a separate method on each concrete leaf.
6. After writing the file: `luajit -e "require('lalin.impl.xxx')"`. If it errors, fix it. If it loads, commit.

---

## FILE INVENTORY

---

## FILE INVENTORY

### Files to CREATE

| # | Impl file | Lines (est.) | Old source files |
|---|-----------|-------------|------------------|
| 1 | `impl/tree_surface.lua` | ~150 | `surface_resolve.lua` |
| 2 | `impl/tree_closure.lua` | ~850 | `closure_convert.lua` |
| 3 | `impl/tree_check/init.lua` | ~30 | `tree_typecheck.lua` (composition part) |
| 4 | `impl/tree_check/type.lua` | ~600 | `tree_typecheck_type.lua` |
| 5 | `impl/tree_check/expr.lua` | ~700 | `tree_typecheck_expr.lua` |
| 6 | `impl/tree_check/stmt.lua` | ~900 | `tree_typecheck_stmt.lua` |
| 7 | `impl/tree_check/scope.lua` | ~750 | `tree_typecheck_fact.lua` |
| 8 | `impl/tree_check/layout.lua` | ~50 | `tree_typecheck_layout.lua` |
| 9 | `impl/tree_check/control.lua` | ~500 | `tree_control_facts.lua` |
| 10 | `impl/tree_check/contract.lua` | ~200 | `tree_contract_facts.lua` |
| 11 | `impl/tree_check/const.lua` | ~650 | `const_eval.lua` |
| 12 | `impl/tree_check/module.lua` | ~400 | `tree_module_type.lua` |
| 13 | `impl/tree_code.lua` | ~3800 | `tree_lower.lua` + `layout_resolve.lua` |
| 14 | `impl/code_validate.lua` | ~900 | `code_validate.lua` |
| 15 | `impl/compiler_result.lua` | ~100 | `compiler_abi.lua` |

### Files to DELETE (after methods moved to leaf methods)

| # | Old file | Destination |
|---|----------|-------------|
| 1 | `core_scalar.lua` | Leaf methods on `Core.Scalar` union (installed in `impl/tree_check/type.lua`) |
| 2 | `core_operator.lua` | Leaf methods on `Core.BinaryOp`, `Core.UnaryOp` unions (installed in `impl/tree_check/expr.lua`) |
| 3 | `type_classify.lua` | Leaf methods on `Ty.Type` union (installed in `impl/tree_check/type.lua`) |
| 4 | `type_abi_classify.lua` | Leaf methods on `Ty.Type` union (installed in `impl/tree_check/type.lua`) |

---

## 1. `impl/tree_surface.lua` — :surface_resolve() on LalinTree types

**Old file:** `surface_resolve.lua` (137 lines)
**Pattern:** ⚠️ `asdl.classof` dispatch via recursive walk. Needs leaf methods.
**Source reference:** Read `lua/lalin/surface_resolve.lua` fully before starting.

### What it does
Resolves identifiers in the parse tree to their symbol bindings. Walks expressions, statements, items, and types to replace parse-time identifiers with resolved symbol references.

### Method signatures to install

```lua
-- On LalinTree.Module (entry point):
function Tree.Module:surface_resolve() → Tree.Module

-- On LalinTree.Expr leaves (ExprIdent, ExprCall, ExprField, ExprIndex, etc.):
function Tree.ExprIdent:surface_resolve(scope) → Tree.Expr
function Tree.ExprCall:surface_resolve(scope) → Tree.Expr
function Tree.ExprField:surface_resolve(scope) → Tree.Expr
-- ... every Expr leaf

-- On LalinTree.Stmt leaves:
function Tree.StmtLet:surface_resolve(scope) → Tree.Stmt
-- ... every Stmt leaf

-- On LalinTree.Item leaves:
function Tree.ItemFunc:surface_resolve(scope) → Tree.Item
-- ... every Item leaf

-- On LalinTree.Func leaves:
function Tree.FuncLocal:surface_resolve(scope) → Tree.Func
-- ... every Func leaf

-- On LalinType.Type (for type references in annotations):
function Type.TypeRefPath:surface_resolve(scope) → Type.Type
-- ... every Type leaf that can contain identifiers
```

### Refactoring the classof dispatch
The old code uses `asdl.classof` to dispatch on expression/statement kind. Replace with leaf methods:
- Every `if classof(expr) == Tr.ExprIdent then ...` becomes a `Tree.ExprIdent:surface_resolve(scope)` method.
- The recursive walker becomes `expr:surface_resolve(scope)` calls on children.
- Module-level scope building (tracking which names are in scope) remains in the `Module:surface_resolve()` orchestrator.

### Output
Return the resolved `Tree.Module` with all identifier references replaced by resolved symbol facts. The module is structurally identical but identifier nodes now carry resolution data.

---

## 2. `impl/tree_closure.lua` — :closure_convert() on LalinTree types

**Old file:** `closure_convert.lua` (819 lines)
**Pattern:** ✅ Mostly clean leaf methods + helper functions.
**Source reference:** Read `lua/lalin/closure_convert.lua` fully before starting.

### What it does
Converts closures (lambdas that capture outer variables) into explicit environment records. For each closure, creates a record type containing captured variables, replaces the closure's free variable references with environment field accesses, and transforms the closure into a function that takes an explicit environment parameter.

### Method signatures to install

```lua
-- On LalinTree.Module (entry point):
function Tree.Module:closure_convert() → Tree.Module

-- On LalinTree.Expr leaves that can be closures:
function Tree.ExprLambda:closure_convert(env) → Tree.Expr
  -- Captures free variables, creates closure record, rewrites body

-- On LalinTree.Func leaves:
function Tree.FuncLocal:closure_convert() → Tree.Func
  -- If the function contains nested closures, convert them

-- On LalinTree.Item leaves:
function Tree.ItemFunc:closure_convert() → Tree.Item
  -- Entry point for converting closures in a function item

-- On LalinType.Type (for computing closure record layouts):
function Type.TStruct:closure_size_align() → { size, align }
  -- Already exists in old code as leaf method, port directly

-- On LalinBind.ValueRef (for rewriting captured variable references):
function Bind.ValueRefCapture:closure_rewrite(env_record, field_map) → Bind.ValueRef
  -- Rewrite a captured variable reference to an environment field access
```

### Port notes
The old code is already method-oriented. The main work is:
1. Update all `require` paths from `lalin.schema.*` to `lalin.schema_v2.*`
2. Verify that all ASDL type names match the v2 schema (some types may have been renamed)
3. Ensure the `ClosureHelperVariant` → `ClosureEnvShape` rename is consistent
4. The mutable global that was eliminated during methodification must NOT reappear — thread the rewrite input through method parameters

---

## 3. `impl/tree_check/` — :typecheck() on LalinTree types

**Old files:** 9 files, ~5,300 lines total
**Pattern:** Mixed — some clean leaf methods, some classof dispatch
**Organization:** Sub-folder with one file per type category + init.lua

### 3.1 `impl/tree_check/init.lua` (~30 lines)

```lua
-- Requires all sub-files so that importing tree_check installs all methods
require("lalin.impl.tree_check.type")
require("lalin.impl.tree_check.expr")
require("lalin.impl.tree_check.stmt")
require("lalin.impl.tree_check.scope")
require("lalin.impl.tree_check.layout")
require("lalin.impl.tree_check.control")
require("lalin.impl.tree_check.contract")
require("lalin.impl.tree_check.const")
require("lalin.impl.tree_check.module")
```

### 3.2 `impl/tree_check/type.lua` (~600 lines)

**Old files:** `tree_typecheck_type.lua` (565 lines), `type_classify.lua`, `type_abi_classify.lua`, `core_scalar.lua`
**Pattern:** ✅ Clean leaf methods on `Core.Scalar` and `Ty.Type`.
**Source reference:** Read all four old files fully before starting.

#### Methods to install on `LalinCore.Scalar`

Port every function from `core_scalar.lua` as leaf methods on the `Scalar` union:

```lua
-- Classification (each leaf answers)
function Core.ScalarVoid:is_integer() → bool
function Core.ScalarBool:is_integer() → bool
function Core.ScalarI8:is_integer() → bool
function Core.ScalarI16:is_integer() → bool
function Core.ScalarI32:is_integer() → bool
function Core.ScalarI64:is_integer() → bool
function Core.ScalarU8:is_integer() → bool
function Core.ScalarU16:is_integer() → bool
function Core.ScalarU32:is_integer() → bool
function Core.ScalarU64:is_integer() → bool
function Core.ScalarF32:is_integer() → bool   -- returns false
function Core.ScalarF64:is_integer() → bool   -- returns false
function Core.ScalarRawPtr:is_integer() → bool
function Core.ScalarIndex:is_integer() → bool

function Core.ScalarI8:is_float() → bool       -- returns false for int scalars
function Core.ScalarF32:is_float() → bool      -- returns true
function Core.ScalarF64:is_float() → bool      -- returns true

function Core.ScalarI8:is_signed() → bool
function Core.ScalarU8:is_signed() → bool       -- returns false

function Core.ScalarI8:scalar_size() → number   -- returns byte size (1, 2, 4, 8)

function Core.ScalarI8:scalar_name() → str      -- returns "i8", "f32", etc.

function Core.ScalarI8:to_unsigned() → Core.Scalar  -- i8→u8, i16→u16, etc.

function Core.ScalarI8:promote_float() → Core.Scalar  -- i32→f32, i64→f64, etc.

function Core.ScalarI8:is_compatible_with(other) → bool
```

After installing all methods, verify that NO function from `core_scalar.lua` remains unported. Delete `core_scalar.lua` only after verifying.

#### Methods to install on `LalinType.Type`

Port every function from `tree_typecheck_type.lua`, `type_classify.lua`, and `type_abi_classify.lua`:

```lua
-- Type canonicalization (from tree_typecheck_type.lua):
function Type.TScalar:canonicalize() → Type.Type
function Type.TPtr:canonicalize() → Type.Type
function Type.TArray:canonicalize() → Type.Type
function Type.TStruct:canonicalize() → Type.Type
function Type.TUnion:canonicalize() → Type.Type
function Type.TFunc:canonicalize() → Type.Type
function Type.TView:canonicalize() → Type.Type
function Type.TSlice:canonicalize() → Type.Type
function Type.THandle:canonicalize() → Type.Type
function Type.TByteSpan:canonicalize() → Type.Type
function Type.TypeRefPath:canonicalize() → Type.Type
function Type.TypeRefGlobal:canonicalize() → Type.Type
function Type.TypeRefLocal:canonicalize() → Type.Type

-- Type predicates (from type_classify.lua):
function Type.TScalar:is_scalar() → bool
function Type.TPtr:is_scalar() → bool          -- returns false
function Type.TStruct:is_aggregate() → bool
function Type.TUnion:is_aggregate() → bool
function Type.TView:is_view_type() → bool
function Type.TSlice:is_view_type() → bool
function Type.THandle:is_opaque() → bool
function Type.TByteSpan:is_byte_span() → bool
function Type.TFunc:is_function_type() → bool
-- ... every predicate in type_classify.lua as a leaf method

-- ABI classification (from type_abi_classify.lua):
function Type.TScalar:abi_classify(target) → Type.AbiClass
  -- returns AbiDirect { ... }
function Type.TPtr:abi_classify(target) → Type.AbiClass
  -- returns AbiDirect { ... }
function Type.TStruct:abi_classify(target) → Type.AbiClass
  -- may return AbiIndirect or AbiDescriptor depending on size
function Type.TUnion:abi_classify(target) → Type.AbiClass
function Type.TArray:abi_classify(target) → Type.AbiClass
function Type.TView:abi_classify(target) → Type.AbiClass
function Type.TSlice:abi_classify(target) → Type.AbiClass
function Type.THandle:abi_classify(target) → Type.AbiClass
function Type.TByteSpan:abi_classify(target) → Type.AbiClass
function Type.TFunc:abi_classify(target) → Type.AbiClass
function Type.TypeRefPath:abi_classify(target) → Type.AbiClass
  -- resolve the ref, then classify the resolved type
function Type.TypeRefGlobal:abi_classify(target) → Type.AbiClass
function Type.TypeRefLocal:abi_classify(target) → Type.AbiClass
```

#### Helper methods on `LalinType.Type` (from tree_typecheck_type.lua):

```lua
function Type.TScalar:typecheck_is_identical_to(other) → bool
function Type.TPtr:typecheck_is_identical_to(other) → bool
function Type.TArray:typecheck_is_identical_to(other) → bool
-- ... every type leaf

function Type.TScalar:typecheck_subtype_of(super) → bool
function Type.TPtr:typecheck_subtype_of(super) → bool
-- ... every type leaf

function Type.TScalar:typecheck_display_name() → str
-- ... every type leaf
```

### 3.3 `impl/tree_check/expr.lua` (~700 lines)

**Old file:** `tree_typecheck_expr.lua` (628 lines)
**Pattern:** ⚠️ Closure-based `type_expr` dispatch — needs leaf methods.
**Source reference:** Read `lua/lalin/tree_typecheck_expr.lua` fully before starting.

#### Refactoring the dispatch
The old code uses a closure-based dispatch pattern. Replace with leaf methods:

```lua
-- Entry point (method on Expr union, dispatches via metatable to concrete leaf):
function Tree.Expr:typecheck(input)  -- default error
  error("abstract: Expr leaf must implement :typecheck")
end

-- Concrete Expr leaves:
function Tree.ExprLit:typecheck(input) → Check.TypeExprResult
  -- input: Check.TypeExprInput { scope [Check.TypeValueScope] }
  -- Infers type from literal: LitInt→ScalarI32, LitFloat→ScalarF64, LitString→TScalar(ScalarIndex)+TPtr, etc.
  -- Returns TypeExprResult(expr=self, ty=inferred_ty, issues={})

function Tree.ExprIdent:typecheck(input) → Check.TypeExprResult
  -- Looks up the identifier in scope, returns its type
  -- If not found, adds TypeIssueUnknownIdent

function Tree.ExprUnary:typecheck(input) → Check.TypeExprResult
  -- typechecks operand, validates unary op applicability
  -- OpNeg: operand must be numeric (int or float)
  -- OpNot: operand must be bool
  -- OpBitNot: operand must be integer
  -- OpDeref: operand must be pointer → returns pointed-to type
  -- OpRef: operand must be a place → returns pointer to place type

function Tree.ExprBinary:typecheck(input) → Check.TypeExprResult
  -- typechecks lhs and rhs, applies binary op type rules
  -- Arithmetic (Add, Sub, Mul, Div, Mod): both operands must be same numeric type
  -- Comparison (Eq, Ne, Lt, Le, Gt, Ge): both operands must be comparable → returns bool
  -- Logical (And, Or): both operands must be bool → returns bool
  -- Bitwise (BitAnd, BitOr, BitXor, Shl, Shr): both must be same integer type

function Tree.ExprCall:typecheck(input) → Check.TypeExprResult
  -- typechecks callee (must be function type), typechecks args against param types
  -- Returns the function's return type

function Tree.ExprField:typecheck(input) → Check.TypeExprResult
  -- typechecks base expression, checks it's a struct/union, looks up field
  -- Returns the field's type

function Tree.ExprIndex:typecheck(input) → Check.TypeExprResult
  -- typechecks base (must be array or view), typechecks index (must be integer)
  -- Returns element type

function Tree.ExprCast:typecheck(input) → Check.TypeExprResult
  -- typechecks source expression, checks cast validity
  -- Numeric casts (widening/narrowing): valid
  -- Pointer casts: valid but may warn
  -- Invalid casts: add TypeIssueInvalidCast

function Tree.ExprSizeOf:typecheck(input) → Check.TypeExprResult
  -- Resolves the target type, returns its size as ScalarIndex

function Tree.ExprView:typecheck(input) → Check.TypeExprResult
  -- View expression: typechecks the view target, validates view operations

function Tree.ExprRegion:typecheck(input) → Check.TypeExprResult
  -- Region expression: delegates to region typechecking

-- ... every Expr leaf from the old code
```

Also port `core_operator.lua` methods onto the operator unions:

```lua
-- On LalinCore.BinaryOp:
function Core.BinaryOpAdd:operator_precedence() → number
function Core.BinaryOpSub:operator_precedence() → number
-- ... every binary op leaf

function Core.BinaryOpAdd:is_comparison() → bool    -- false
function Core.BinaryOpEq:is_comparison() → bool     -- true

function Core.BinaryOpAdd:is_boolean_result() → bool -- false
function Core.BinaryOpEq:is_boolean_result() → bool  -- true

function Core.BinaryOpAdd:result_type(lhs_ty, rhs_ty) → Type.Type
  -- given operand types, what type does this op produce?

-- On LalinCore.UnaryOp:
function Core.UnaryOpNeg:operator_precedence() → number
function Core.UnaryOpNot:result_type(operand_ty) → Type.Type
-- ... every unary op leaf

-- On LalinCore.CmpOp:
function Core.CmpOpEq:negate() → Core.CmpOp  -- Eq→Ne, Lt→Ge, etc.
function Core.CmpOpLt:is_strict() → bool
-- ... every comparison op leaf
```

### 3.4 `impl/tree_check/stmt.lua` (~900 lines)

**Old file:** `tree_typecheck_stmt.lua` (852 lines)
**Pattern:** ⚠️ Some `asdl.classof` dispatch.
**Source reference:** Read `lua/lalin/tree_typecheck_stmt.lua` fully before starting.

#### Methods to install

```lua
-- Entry point for statement typechecking:
function Tree.Stmt:typecheck(input) → Check.TypeStmtResult
  -- default error for abstract

-- Concrete Stmt leaves:
function Tree.StmtLet:typecheck(input) → Check.TypeStmtResult
  -- input: Check.TypeStmtInput { scope [Check.TypeValueScope] }
  -- Typechecks the initializer expression, infers or validates the declared type
  -- Adds the binding to scope
  -- Returns updated scope as part of TypeStmtResult

function Tree.StmtAssign:typecheck(input) → Check.TypeStmtResult
  -- Typechecks lhs (must be a mutable place), typechecks rhs
  -- Validates assignment compatibility

function Tree.StmtIf:typecheck(input) → Check.TypeStmtResult
  -- Typechecks condition (must be bool)
  -- Typechecks then-branch and else-branch (if present)
  -- Ensures both branches produce compatible results (if they are expression branches)

function Tree.StmtSwitch:typecheck(input) → Check.TypeStmtResult
  -- Typechecks the switch value, typechecks each arm
  -- Validates that arms are exhaustive (default arm present)
  -- Uses SwitchKeyClass from the new schema (no SwitchKeyDecision)

function Tree.StmtBlock:typecheck(input) → Check.TypeStmtResult
  -- Opens a new scope, typechecks all statements, returns final scope

function Tree.StmtReturn:typecheck(input) → Check.TypeStmtResult
  -- Typechecks the return value against the enclosing function's declared return type
  -- If in a void function, validates no value is returned

function Tree.StmtExpr:typecheck(input) → Check.TypeStmtResult
  -- Typechecks the expression, discards its value
  -- (expression statement — allowed only for effectful expressions)

-- Region invoke statements:
function Tree.StmtRegionInvoke:typecheck(input) → Check.TypeStmtResult
  -- Resolves the region target, validates against the region protocol
  -- Uses typed RegionInvokeReject (from new schema) instead of string rejection

-- Control flow labels:
function Tree.BlockLabel:typecheck_block_label(input) → Check.TypeBlockLabelResult
  -- Validates that break/continue target valid blocks
  -- In the new schema, BlockLabel is a proper ASDL type
```

### 3.5 `impl/tree_check/scope.lua` (~750 lines)

**Old file:** `tree_typecheck_fact.lua` (708 lines)
**Pattern:** ✅ Clean methods on `TypeValueScope` product.
**Source reference:** Read `lua/lalin/tree_typecheck_fact.lua` fully before starting.

#### Methods to install on `LalinCheck.TypeValueScope`

```lua
-- The scope is a product with method interface:
function Check.TypeValueScope:typecheck_tree_add_value(name, ty, binding_role, residence) → Check.TypeValueScope
  -- Adds a new value binding to scope, returns NEW scope (immutable)
  -- Validates no duplicate names

function Check.TypeValueScope:typecheck_tree_lookup_value(name) → Check.TypeValueLookupResult
  -- Looks up a name in scope, returns the binding info
  -- TypeValueLookupResult is an ASDL sum: Found { binding }, NotFound, Ambiguous { candidates }

function Check.TypeValueScope:typecheck_tree_add_type(name, ty) → Check.TypeValueScope
  -- Adds a type alias to scope

function Check.TypeValueScope:typecheck_tree_lookup_type(name) → Check.TypeValueLookupResult
  -- Looks up a type name in scope

function Check.TypeValueScope:typecheck_tree_open_child() → Check.TypeValueScope
  -- Opens a nested scope (for blocks, if branches, etc.)
  -- Returns a child scope that chains to this one

function Check.TypeValueScope:typecheck_tree_close_child(child_scope) → Check.TypeValueScope
  -- Closes a child scope, returning to parent

function Check.TypeValueScope:typecheck_tree_all_bindings() → [many Bind.Binding]
  -- Returns all bindings visible in this scope (including parent scopes)
```

### 3.6 `impl/tree_check/layout.lua` (~50 lines)

**Old file:** `tree_typecheck_layout.lua` (43 lines)
**Pattern:** ✅ Inline — clean.
**Source reference:** Read `lua/lalin/tree_typecheck_layout.lua` fully before starting.

#### Methods to install

```lua
function Type.TScalar:type_layout() → Sem.MemLayout
  -- Returns the memory layout (size, alignment) for this scalar type
  -- Uses type_size_align.lua logic (which is a utility, kept as-is)

function Type.TPtr:type_layout() → Sem.MemLayout
function Type.TArray:type_layout() → Sem.MemLayout
  -- array layout = elem_count * element_size, with element alignment
function Type.TStruct:type_layout() → Sem.MemLayout
  -- walks fields, computes offsets with alignment padding
function Type.TUnion:type_layout() → Sem.MemLayout
  -- size is max field size, alignment is max field alignment
function Type.THandle:type_layout() → Sem.MemLayout
  -- handles have pointer layout
function Type.TByteSpan:type_layout() → Sem.MemLayout
  -- (pointer, length) pair layout

function Tree.FieldRef:field_offset_in_layout(parent_layout) → number
  -- Given a struct layout and a field reference, return the byte offset
```

### 3.7 `impl/tree_check/control.lua` (~500 lines)

**Old file:** `tree_control_facts.lua` (473 lines)
**Pattern:** ❌ **HEAVY `schema.classof` dispatch.** MUST be refactored to leaf methods.
**Source reference:** Read `lua/lalin/tree_control_facts.lua` fully before starting.

#### Refactoring strategy
The old code computes control flow facts (which blocks can break/continue/return, which paths are reachable) by switching on statement kind via `schema.classof`. Replace EVERY classof branch with a leaf method.

```lua
-- On LalinTree.Stmt leaves:
function Tree.StmtLet:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Local binding does not affect control flow
  -- Returns ctx unchanged

function Tree.StmtIf:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Condition is evaluated
  -- Then-branch and else-branch both analyzed
  -- Merges control flow from both branches
  -- If both branches terminate, the merge point is unreachable

function Tree.StmtBlock:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Analyzes each statement in sequence
  -- If any statement terminates (return, break, continue), subsequent statements unreachable

function Tree.StmtReturn:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Marks current path as terminated
  -- Validates return is inside a function

function Tree.StmtBreak:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Marks current path as terminated
  -- Validates break targets a loop

function Tree.StmtContinue:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Marks current path as terminated
  -- Validates continue targets a loop

function Tree.StmtSwitch:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Analyzes condition, then each arm
  -- Ensures default arm exists (exhaustiveness)
  -- Merges control flow from all arms
  -- No fallthrough — each arm is independent

function Tree.StmtExpr:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Expression statement, does not affect control flow

function Tree.StmtRegionInvoke:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Region invoke may involve control flow through the region protocol

-- On LalinTree.Region:
function Tree.RegionFor:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Analyzes the loop body
  -- After the loop body, control flow continues (unless body always returns)

function Tree.RegionWhile:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Similar to RegionFor

function Tree.RegionRange:control_flow_facts(ctx) → Check.ControlFlowResult
  -- Range iteration control flow

-- On LalinTree.Block:
function Tree.Block:control_flow_facts(label, ctx) → Check.ControlFlowResult
  -- A labeled block — break can target it, continue cannot
```

The `ControlFlowResult` must be an ASDL type (add to Check schema if not present) carrying:
- `terminated` — whether this path always terminates
- `reachable_after` — whether execution can continue after this statement
- Any diagnostics about unreachable code

### 3.8 `impl/tree_check/contract.lua` (~200 lines)

**Old file:** `tree_contract_facts.lua` (169 lines)
**Pattern:** ❌ **`schema.classof` dispatch.** MUST be refactored to leaf methods.
**Source reference:** Read `lua/lalin/tree_contract_facts.lua` fully before starting.

#### Methods to install

```lua
-- On LalinTree.FuncContract leaves (each contract clause type):
function Tree.FuncContractPure:extract_contract_facts() → [many Sem.FuncContractFact]
  -- A pure contract: no side effects, no aliasing

function Tree.FuncContractNoAlias:extract_contract_facts() → [many Sem.FuncContractFact]
  -- A no-alias contract: certain pointer parameters don't alias

function Tree.FuncContractNoEscape:extract_contract_facts() → [many Sem.FuncContractFact]
  -- A no-escape contract: certain references don't escape

function Tree.FuncContractTerminates:extract_contract_facts() → [many Sem.FuncContractFact]
  -- A terminates contract: function always returns

function Tree.FuncContractCaptures:extract_contract_facts() → [many Sem.FuncContractFact]
  -- A captures contract: explicitly lists captured variables

-- ... every contract clause type in the schema

-- On LalinTree.Expr leaves (for contracts expressed as expressions):
function Tree.ExprCall:extract_contract_from_expr() → Sem.FuncContractFact | nil
  -- If this call is a contract annotation, extract the contract fact
```

### 3.9 `impl/tree_check/const.lua` (~650 lines)

**Old file:** `const_eval.lua` (608 lines)
**Pattern:** ✅ Clean leaf methods on `Sem.ConstExprResult`, `Sem.ConstValue`, `Sem.ConstStmtFlow`.
**Source reference:** Read `lua/lalin/const_eval.lua` fully before starting.

This file is already clean. Port by updating require paths and verifying type names match v2.

```lua
-- On LalinSem.ConstValue leaves:
function Sem.ConstValueInt:const_add(other) → Sem.ConstValue
function Sem.ConstValueInt:const_sub(other) → Sem.ConstValue
function Sem.ConstValueInt:const_mul(other) → Sem.ConstValue
function Sem.ConstValueInt:const_div(other) → Sem.ConstExprResult  -- may fail (division by zero)
function Sem.ConstValueInt:const_neg() → Sem.ConstValue
function Sem.ConstValueInt:const_cmp(op, other) → Sem.ConstValue  -- returns ConstValueBool
-- Similarly for ConstValueFloat, ConstValueBool, ConstValuePtr, ConstValueEnum, etc.
-- Every const value leaf must implement all supported operations

-- On LalinTree.Expr leaves (for constant folding):
function Tree.ExprLit:const_eval() → Check.ConstExprResult  -- always ConstKnown
function Tree.ExprUnary:const_eval() → Check.ConstExprResult
  -- If operand is constant, fold; otherwise ConstNotFoldable with typed reject
function Tree.ExprBinary:const_eval() → Check.ConstExprResult
function Tree.ExprCast:const_eval() → Check.ConstExprResult
function Tree.ExprSizeOf:const_eval() → Check.ConstExprResult  -- always ConstKnown
-- ... every expression that can be constant-folded

-- On LalinTree.Stmt leaves (for const statement flow):
function Tree.StmtLet:const_stmt_flow() → Sem.ConstStmtFlow
function Tree.StmtIf:const_stmt_flow() → Sem.ConstStmtFlow
  -- If condition is constant true, only then-branch executes
  -- If condition is constant false, only else-branch executes
-- ... every statement that affects const evaluation flow
```

### 3.10 `impl/tree_check/module.lua` (~400 lines)

**Old file:** `tree_module_type.lua` (365 lines)
**Pattern:** ✅ Clean leaf method dispatch.
**Source reference:** Read `lua/lalin/tree_module_type.lua` fully before starting.

#### Methods to install

```lua
-- Module-level typechecking:
function Tree.Module:typecheck(input) → Check.TypeModuleResult
  -- input: Check.TypeModuleInput { source [Source.DocumentUri] }
  -- Creates initial scope with built-in types (ScalarVoid, ScalarBool, ScalarI8, ..., ScalarF64, etc.)
  -- Typechecks each top-level item in order
  -- Threads scope through declarations
  -- Returns TypeModuleResult with all typechecked items and accumulated diagnostics

-- On LalinTree.Item leaves:
function Tree.ItemFunc:typecheck(input) → Check.TypeItemResult
  -- input: Check.TypeItemInput { scope [Check.TypeValueScope] }
  -- Typechecks function signature (params, return type)
  -- Creates function-level scope with parameters
  -- Typechecks function body
  -- Returns TypeItemResult with typechecked function and diagnostics

function Tree.ItemExtern:typecheck(input) → Check.TypeItemResult
  -- Typechecks extern function declaration
  -- Validates extern ABI compatibility

function Tree.ItemStruct:typecheck(input) → Check.TypeItemResult
  -- Typechecks struct declaration
  -- Adds struct type to scope

function Tree.ItemStatic:typecheck(input) → Check.TypeItemResult
  -- Typechecks static variable declaration
  -- Validates initializer (must be const-evaluable)

-- On LalinTree.Func leaves:
function Tree.FuncLocal:typecheck_signature(input) → Check.TypeFuncResult
  -- Typechecks only the function signature (params + return type), not the body
  -- Used when a function is referenced before its body is typechecked

function Tree.FuncExport:typecheck_signature(input) → Check.TypeFuncResult
  -- Same, for exported functions

-- On LalinTree.ModuleHeader leaves:
function Tree.ModuleHeader:typecheck_module_scope() → Check.TypeValueScope
  -- Creates the initial scope for a module

-- On LalinTree.Func (parent union, shared default):
function Tree.Func:typecheck_return_type_check(return_expr_ty, declared_return_ty) → [many Check.TypeIssue]
  -- Validates that a return expression matches the declared return type
```

---

## 4. `impl/tree_code.lua` — :lower_to_code() on LalinTree types

**Old files:** `tree_lower.lua` (3067 lines), `layout_resolve.lua` (678 lines)
**Pattern:** ✅ Clean leaf methods (tree_lower), ⚠️ some classof dispatch (layout_resolve)
**Source reference:** Read both old files fully before starting.

### What tree_lower.lua does
Lowers typechecked LalinTree to LalinCode IR. Each tree node becomes code instructions. This is the largest single file in the compiler.

### Method signatures (tree_lower.lua)

```lua
-- Entry point:
function Tree.Module:lower_to_code(input) → TreeCode.TreeCodeModuleResult
  -- input: TreeCode.TreeCodeInput { scope, facts [Check.TypeModuleFacts], opts }
  -- Lowers every function in the module to Code IR
  -- Returns TreeCodeModuleResult with CodeModule and lowering facts

-- On LalinTree.Expr leaves:
function Tree.ExprLit:lower_expr_to_code(lctx) → Code.CodeValueId
  -- lctx: TreeCode.TreeCodeLowerContext
  -- Produces a CodeConst for the literal value
  -- Returns the CodeValueId of the produced constant

function Tree.ExprIdent:lower_expr_to_code(lctx) → Code.CodeValueId
  -- Looks up the binding, produces a CodePlace read

function Tree.ExprUnary:lower_expr_to_code(lctx) → Code.CodeValueId
  -- Lowers operand, emits unary instruction

function Tree.ExprBinary:lower_expr_to_code(lctx) → Code.CodeValueId
  -- Lowers lhs and rhs, emits binary instruction

function Tree.ExprCall:lower_expr_to_code(lctx) → Code.CodeValueId
  -- Lowers callee and args, emits call instruction

function Tree.ExprField:lower_expr_to_code(lctx) → Code.CodeValueId
  -- Lowers base, emits field access instruction (extractvalue or GEP equivalent)

function Tree.ExprIndex:lower_expr_to_code(lctx) → Code.CodeValueId
  -- Lowers base and index, emits element access instruction

-- ... every Expr leaf (~30 leaves)

-- On LalinTree.Stmt leaves:
function Tree.StmtLet:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult
function Tree.StmtAssign:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult
  -- Lowers rhs to code, emits store instruction to lhs place
function Tree.StmtIf:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult
  -- Lowers condition, creates conditional branch in CFG
function Tree.StmtSwitch:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult
  -- Lowers switch value, creates switch terminator
function Tree.StmtBlock:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult
  -- Lowers all statements in sequence
function Tree.StmtReturn:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult
  -- Lowers return value, emits return terminator
function Tree.StmtExpr:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult
  -- Lowers expression, discards result

-- ... every Stmt leaf

-- On LalinTree.Func leaves:
function Tree.FuncLocal:lower_func_to_code(lctx) → Code.CodeFunc
  -- Creates CodeFunc, lowers parameters to code places
  -- Walks body, emits instructions
  -- Returns complete CodeFunc ready for graph construction

function Tree.FuncExport:lower_func_to_code(lctx) → Code.CodeFunc

-- On LalinTree.Item leaves:
function Tree.ItemFunc:lower_item_to_code(lctx) → Code.CodeFunc
function Tree.ItemExtern:lower_item_to_code(lctx) → Code.CodeFunc  -- extern decl, no body

-- On LalinTree.Place leaves:
function Tree.PlaceVar:lower_place_to_code(lctx) → Code.CodePlace
function Tree.PlaceDeref:lower_place_to_code(lctx) → Code.CodePlace
function Tree.PlaceField:lower_place_to_code(lctx) → Code.CodePlace
function Tree.PlaceIndex:lower_place_to_code(lctx) → Code.CodePlace
-- ... every Place leaf

-- CodeType methods installed during lowering:
function Code.CodeType:tree_code_is_float_type() → bool
function Code.CodeType:tree_code_is_aggregate_type() → bool
function Code.CodeType:tree_code_is_view_type() → bool
function Code.CodeType:tree_code_index_cast_op() → Core.BinaryOp

-- On LalinCore.Scalar leaves (lowering helpers):
function Core.ScalarI8:tree_code_scalar_to_code_type() → Code.CodeType
function Core.ScalarF32:tree_code_scalar_to_code_type() → Code.CodeType
-- ... every scalar leaf
```

### Method signatures (layout_resolve.lua)

```lua
-- These are installed on tree types and called during lowering
-- Refactor classof dispatch to leaf methods:

function Tree.Expr:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
  -- default: error (abstract)

function Tree.ExprIdent:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
  -- Resolves the layout of an identifier's value

function Tree.ExprField:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
  -- Resolves field access layout (byte offset, field size)

function Tree.ExprIndex:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
  -- Resolves array element layout (element stride, element size)

function Tree.ExprUnary:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
  -- Resolves dereference/reference layout

-- On LalinTree.Stmt leaves:
function Tree.StmtLet:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
  -- Resolves layout for the binding's storage

-- On LalinTree.Place leaves:
function Tree.PlaceVar:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
function Tree.PlaceField:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
function Tree.PlaceDeref:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
function Tree.PlaceIndex:sem_layout_resolve(lctx) → Sem.LayoutResolveResult
-- ... every Place leaf

-- On LalinSem.LayoutResolveResult — this is the ASDL result type:
-- Each leaf method returns a LayoutResolveResult union value:
--   LayoutResolved { offset, size, alignment }
--   LayoutUnresolved { reason [LayoutResolveFailure] }
```

---

## 5. `impl/code_validate.lua` — :validate() on CodeModule types

**Old file:** `code_validate.lua` (840 lines)
**Pattern:** ⚠️ Mutable Machine wrapper. Should model validation state as ASDL.
**Source reference:** Read `lua/lalin/code_validate.lua` fully before starting.

### What it does
Validates the generated Code IR: type consistency, SSA invariants, block terminators, use-def chains, relocation completeness.

### Refactoring the Machine wrapper
The old code wraps validation state in a mutable Machine object. In the new schema, `LalinCodeValidation.CodeValidationMachine` is an ASDL product. Methods consume it and produce updated machines:

```lua
-- Entry point:
function Code.CodeModule:validate() → CodeValidation.CodeValidateResult
  -- Creates initial CodeValidationMachine
  -- Runs all validation passes
  -- Returns result with diagnostics

-- On CodeValidation.CodeValidationMachine:
function CodeValidation.CodeValidationMachine:validate_types() → CodeValidation.CodeValidateResult
  -- Validates type consistency of all instructions

function CodeValidation.CodeValidationMachine:validate_ssa() → CodeValidation.CodeValidateResult
  -- Validates SSA dominance: every use has a single definition
  -- Every value is defined before use

function CodeValidation.CodeValidationMachine:validate_blocks() → CodeValidation.CodeValidateResult
  -- Every block has exactly one terminator
  -- Every terminator targets valid blocks
  -- No unreachable blocks (or flag them)

function CodeValidation.CodeValidationMachine:validate_relocs() → CodeValidation.CodeValidateResult
  -- All relocations are complete (no dangling references)
  -- All relocated values exist

function CodeValidation.CodeValidationMachine:validate_calls() → CodeValidation.CodeValidateResult
  -- Call targets are valid function references
  -- Argument counts match parameter counts
  -- Argument types match parameter types

-- On Code.CodeInst leaves (for instruction-specific validation):
function Code.CodeInstCall:validate_inst(vm) → CodeValidation.CodeValidateResult
function Code.CodeInstBranch:validate_inst(vm) → CodeValidation.CodeValidateResult
function Code.CodeInstReturn:validate_inst(vm) → CodeValidation.CodeValidateResult
-- ... every CodeInst leaf
```

---

## 6. `impl/compiler_result.lua` — report methods

**Old file:** `compiler_abi.lua` (96 lines)
**Pattern:** ✅ Clean.
**Source reference:** Read `lua/lalin/compiler_abi.lua` fully before starting.

```lua
-- On LalinCompiler.CodeResult leaves:
function Compiler.CodeResultOk:report() → Compiler.CompileReport
  -- Produces a success report with module info

function Compiler.CodeResultError:report() → Compiler.CompileReport
  -- Produces an error report with diagnostics

-- On LalinCompiler.CodeResult (parent union, for result checking):
function Compiler.CodeResult:is_ok() → bool
function Compiler.CodeResult:diagnostics() → [many Source.Diagnostic]
```

---

## 7. HELPER DELETION

After all methods above are installed and verified, delete these four files:

```lua
-- Delete lua/lalin/core_scalar.lua
--   All functions now live as leaf methods on Core.Scalar union
-- Delete lua/lalin/core_operator.lua
--   All functions now live as leaf methods on Core.BinaryOp, Core.UnaryOp, Core.CmpOp
-- Delete lua/lalin/type_classify.lua
--   All predicates now live as leaf methods on Ty.Type union
-- Delete lua/lalin/type_abi_classify.lua
--   All ABI classification now lives as leaf methods on Ty.Type union
```

Before deleting each file, verify:
1. `grep` the codebase for any `require` of these files
2. Remove those requires (they should no longer exist since all callers use leaf methods)
3. `rg` for any function name from the file to ensure it's installed as a method somewhere
4. Delete the file
5. Commit: `delete: core_scalar.lua — methods moved to Core.Scalar leaf methods`

---

## 8. COMMIT ORDER

1. `impl/tree_code.lua` — tree_code_is_* methods on CodeType (needed by later files)
2. `impl/tree_check/type.lua` — scalar + type methods (foundation for all checking)
3. `impl/tree_check/scope.lua` — scope management (needed by expr/stmt)
4. `impl/tree_check/layout.lua` — layout methods
5. `impl/tree_check/const.lua` — const eval (needed by module typecheck)
6. `impl/tree_check/control.lua` — refactored from classof
7. `impl/tree_check/contract.lua` — refactored from classof
8. `impl/tree_check/expr.lua` — expression typechecking + operator methods
9. `impl/tree_check/stmt.lua` — statement typechecking
10. `impl/tree_check/module.lua` — module-level composition
11. `impl/tree_check/init.lua` — sub-folder loader
12. `impl/tree_surface.lua` — surface resolution
13. `impl/tree_closure.lua` — closure conversion
14. `impl/code_validate.lua` — code validation
15. `impl/compiler_result.lua` — result reporting
16. Delete `core_scalar.lua`
17. Delete `core_operator.lua`
18. Delete `type_classify.lua`
19. Delete `type_abi_classify.lua`
