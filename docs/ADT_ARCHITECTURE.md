# `adt` Architecture

**Status:** pre-implementation architecture, informed by the M1 runtime experiment.

**Target:** LuaJIT 2.1, with GC64 recommended.

**Build-time dependency:** LLBL and Lalin's ASDL runtime.

**Generated-runtime dependency:** LuaJIT built-ins only (`ffi`, `bit`, and optionally
`string.buffer`). Generated artifacts do not require LLBL, Lalin, or an `adt` package.

The measurements behind the representation choices live in
[`experiments/adt/RESULTS.md`](../experiments/adt/RESULTS.md).

---

## 1. Decision

`adt` is a build-time compiler for **typed segmented stores and monomorphic
consumers**. It is not an object system with a more compact node representation.

The central model is:

```text
semantic sum          closed family of constructor products
constructor product   dense segment of homogeneous rows
sum value             typed coordinate (constructor tag, row index)
phase annotation      named facet aligned with constructor rows
pass                   compiled consumer over one or more segments
```

The packed handle is an encoding of a typed coordinate. The tag is not where
semantic dispatch lives. Semantic behavior belongs to ASDL leaves; generated tags
exist only at the physical boundary.

The design can be summarized as:

> Turn variants into populations, references into coordinates, annotations into
> facets, and visitors into schedules of monomorphic kernels.

---

## 2. Why this shape

The M1 experiment established four useful facts on the test machine:

1. Chunked constructor pools reduced one million nodes from roughly 149 MiB of RSS
   growth to roughly 10 MiB.
2. Full Lua GC over those nodes fell from roughly 60 ms to approximately 0.1 ms.
3. Constructors and constructor-local sweeps traced as one loop with no aborts and
   were about an order of magnitude faster than table equivalents.
4. Generated access shape mattered more than the handle arithmetic. Keeping an FFI
   interior pointer live across recursion caused cdata allocation and GC; loading
   child handles into scalar locals first removed that GC and made the recursive
   arena evaluator much faster.

The same experiment rejected dense recursive vtables as the primary execution
model. `V[tag](index)` was slower than the table equivalent even after it compiled.
Methods remain useful as a cold convenience API, but optimized consumers must have
an explicit execution shape.

---

## 3. Goals

1. Zero persistent Lua GC objects per declared node.
2. Stable, nominal handles instead of persistent interior pointers.
3. Fixed-arity constructors that lower to counter arithmetic, page selection, and
   scalar stores.
4. Monomorphic constructor sweeps with no tag test in the inner loop.
5. Scalarized recursive consumers that hold no cdata pointer across a call.
6. Generation-time exhaustiveness for closed consumers.
7. Named, typed phase facets rather than node-keyed side tables.
8. A checked table artifact with the same semantic API as the arena artifact.
9. Readable generated source and deterministic golden files.
10. Serialization without graph traversal or pointer fixup.
11. No LLBL, Lalin, or generator dependency in a generated runtime artifact.

---

## 4. Non-goals

The first implementation does not provide:

- per-node deletion, reuse, compaction, or moving GC;
- runtime schema extension;
- a general graph query engine;
- automatic incremental recomputation;
- arbitrary Lua callbacks in optimized loops;
- a universal fast visitor or method-vtable mechanism;
- portable cross-endian or cross-ABI cache files;
- memory-mapped zero-copy loading;
- 64-bit handles;
- SoA layout selection;
- bucketed worklists or parallel execution;
- nested sequence storage;
- arbitrary Lua values embedded in nodes;
- concurrent mutation or thread-safe access to one world.

These are not hidden extension promises. Each requires a demonstrated workload and
a new typed design decision before entering the architecture.

---

## 5. Three separate descriptions

The system keeps three algebras separate.

### 5.1 Semantic schema

The semantic schema names authored sums, constructors, fields, enums, facets, and
closed consumer cases. It answers what values and facts mean.

### 5.2 Store layout

The store layout is a projection from the checked semantic schema. It chooses tags,
handle encoding, field representation, C layout, pages, facet storage, and serialized
sections. It answers where facts live.

### 5.3 Consumer plan

A consumer plan selects an execution shape and carries one typed kernel per
constructor case. It answers in what order facts are consumed.

No layer rediscovers the preceding layer through `.kind`, strings, loose tables, or
handler maps. Each transition consumes and returns named ASDL products or unions.

---

## 6. Build-time phase architecture

```text
.lua schema authored through the Adt LLBL dialect
        │
        ▼
AdtSource ASDL
  declaration entities, unresolved references, origins
        │ :check()
        ▼
AdtChecked ASDL
  resolved sums/enums, exact field alternatives, closed consumer cases
        │ :plan_store()
        ├─────────────────────────────┐
        ▼                             ▼
AdtStorePlan ASDL               AdtConsumerPlan ASDL
  handles, segments, pages,      sweep/recursive plans,
  facets, C fields, sections     typed leaf kernels
        │                             │
        └──────────────┬──────────────┘
                       ▼
                AdtArtifactPlan ASDL
                       │ :emit()
              ┌────────┴────────┐
              ▼                 ▼
      checked table source   arena LuaJIT source
              │                 │
              └────────┬────────┘
                       ▼
              optional metadata sidecar
```

`AdtSource`, `AdtChecked`, `AdtStorePlan`, `AdtConsumerPlan`, and
`AdtArtifactPlan` are ASDL values. There is no plain-table Schema IR seam inside the
generator.

Generated Lua source and literal test fixtures are ordinary text boundaries. Runtime
table nodes are permitted in the checked reference artifact because tables are the
representation being implemented there, not compiler semantic state.

---

## 7. Semantic ASDL vocabulary

The exact spelling belongs in the schema module, but the vocabulary must include the
following precise concepts.

### 7.1 Declaration entities

- `AdtModuleEntity`
- `AdtSumEntity`
- `AdtConstructorEntity`
- `AdtEnumEntity`
- `AdtFacetEntity`
- `AdtConsumerEntity`

Entities that require stable identity are unique ASDL products. Ordered declaration
fields use `many` over named products; keyed relations are represented as named entry
products, never maps.

### 7.2 Field alternatives

`AdtFieldType` is an ASDL union with leaves equivalent to:

- `AdtRefField` — required reference to one declared sum;
- `AdtOptionalRefField` — reference to one declared sum, with handle zero absent;
- `AdtSequenceField` — sequence of references to one declared sum;
- `AdtEnumField` — value of one declared enum;
- `AdtScalarField` — one scalar from the supported C scalar set;
- `AdtSymbolField` — identifier in the injected symbol capability.

Nested sequences are rejected. There is no opaque, any, table, userdata, raw bytes,
or host-value field leaf.

Each field leaf owns its store-planning method. For example, reference leaves produce
handle storage, enum leaves select an unsigned width, and scalar leaves produce their
declared C type. Parent field methods do not inspect leaf classes or tag strings.

### 7.3 Facets

A facet is a named semantic plane aligned to a sum's segmented spine. Examples are:

- source origin;
- resolved symbol;
- inferred type;
- constant value;
- lowering decision.

A facet declaration names its domain sum and has precise typed fields. A source facet
may be populated by constructors. A derived facet is created and filled by a later
consumer. Facets are not generic attribute maps and do not attach hidden fields to
source nodes.

### 7.4 Consumer alternatives

`AdtConsumerPlan` initially has two real leaves:

- `AdtVariantSweepPlan`;
- `AdtScalarRecursivePlan`.

The leaves own validation and emission. A mode string such as `"sweep"` is not part
of semantic compiler state.

---

## 8. LLBL authoring boundary

`adt.dsl` defines the authoring dialect. LLBL owns heads, roles, fragments, origins,
ordered assembly, and diagnostics. Dialect heads remain thin and construct source
ASDL values.

The intended data surface remains close to:

```lua
local adt = require("adt.dsl")

return adt.module. Lang {
  adt.enum. op { Add, Sub, Mul, Div },

  adt.sum. expr {
    adt.ctor. Num   { value [f64] },
    adt.ctor. Var   { name [symbol] },
    adt.ctor. Binop { left [expr], op [op], right [expr] },
    adt.ctor. Call  { fn [expr], args [list [expr]] },
    adt.facet. origin { value [u32] },
  },
}
```

Exact surface syntax is subordinate to correct role behavior. In particular:

- constructor and field order are structural;
- field names are unique within a constructor;
- constructor names are unique within a sum;
- fragments produce role-tagged values;
- references resolve to declared ASDL entities during checking;
- every declaration carries its LLBL origin.

Only `adt.dsl` and build-time schema modules require LLBL.

---

## 9. Checking and diagnostics

Checking is a projection from source ASDL to checked ASDL, not mutation of source
nodes. It resolves declaration references and assigns stable checked identities.

The checker rejects:

- duplicate modules, sums, enums, constructors, fields, facets, or consumer cases;
- references to missing or wrong-category declarations;
- nested sequences;
- unsupported scalar C types;
- more than 255 constructors or more than 255 sequence domains in one generated
  module;
- empty enums or enum widths unsupported by v1;
- facet fields that cannot be represented;
- missing consumer cases without an explicit typed default;
- cases for constructors outside the consumer's domain sum;
- writes to structural fields after construction;
- same-constructor allocation inside a sweep over that constructor;
- recursive kernel shapes that would require a row pointer to cross a call;
- source names whose sanitized generated Lua or C identifiers collide.

Diagnostics include the active head, slot, role, declaration origin, and the related
origin when two declarations conflict. Exhaustiveness diagnostics point to both the
consumer declaration and the missing constructor declaration.

---

## 10. Store and spine model

A generated module exports a world factory:

```lua
local Lang = require("gen.lang")
local world = Lang.new(host_symbols)
```

The world is the runtime owner. It owns pool bytes, handle validity, sequence arenas,
source facets, reset, release, and serialization. Multiple worlds from the same
generated schema are independent.

Each sum has a segmented spine: one constructor segment per leaf, ordered by assigned
tag. A handle identifies a position on that spine. No separate global node array is
allocated unless a later consumer explicitly derives an order projection.

```text
Expr spine
  tag 1: Num rows    [0 .. Num.count)
  tag 2: Var rows    [0 .. Var.count)
  tag 3: Binop rows  [0 .. Binop.count)
  tag 4: Call rows   [0 .. Call.count)
```

Facets repeat the same segmentation and row coordinates. `Binop` row 42 in an
`ExprTypeFacet` corresponds exactly to `Binop` row 42 in the structural store.

---

## 11. Handle encoding

Version 1 uses one physical encoding:

```text
31        24 23                              0
┌──────────┬──────────────────────────────────┐
│ module-  │ constructor-local row index      │
│ wide tag │                                  │
└──────────┴──────────────────────────────────┘
   8 bits                 24 bits
```

Rules:

- tag zero is reserved; handle zero is invalid and represents absent optional refs;
- tags are assigned deterministically in checked module declaration order;
- tags are unique across the generated module;
- row indices are local to one constructor segment;
- a handle is meaningful only with its owning generated world;
- reset invalidates all handles issued by that world;
- there is no per-node generation counter in the arena encoding;
- the checked table artifact detects stale and cross-world handles.

Public APIs expose nominal sum-specific handle concepts even though LuaJIT stores
them as exact Lua numbers and FFI fields store `uint32_t`. Generated validation knows
the tag set belonging to every sum.

The 8/24 split is frozen for serialization format version 1. A real schema exceeding
its limits causes a design review and a new format, not a runtime option.

---

## 12. Constructor segments and paging

One pool exists per constructor. The default physical row layout is AoS.

The 65,536-row first allocation used by M1 wastes too much memory for rare
constructors. Version 1 therefore uses a simple two-tier page plan:

```text
first page       256 rows, allocated on the first constructor call
regular page     4096 rows
regular directory allocated only when row 256 is crossed
```

For row `i`:

```text
i < 256      -> first_page[i]
otherwise    -> j = i - 256
                page = j >> 12
                slot = j & 0x0fff
```

The regular directory has 4096 entries, preserving the 24-bit row space. It and all
row pages are allocated with `malloc` and released explicitly or by `ffi.gc`
finalizers. Existing pages never move.

Generated sweeps use two loops—one for the small first page and one over regular
pages—rather than testing the tier on every row.

This page policy is intentionally fixed, not configurable at runtime. Before format
v1 is frozen, M2 must repeat construction, sweep, GC, and realistic many-rare-variant
benchmarks against the M1 65,536-row policy. If the tiered plan loses the clean trace
shape materially, the evidence decides the final constants.

Each constructor owns specialized allocation code. No generic pool descriptor or
element-type switch appears in a constructor hot path.

---

## 13. Physical row layout

For each constructor the layout planner:

1. projects semantic fields to physical storage leaves;
2. orders physical fields by descending alignment, preserving declaration order
   among equal alignments;
3. emits a named C struct prefixed by a sanitized module name and schema-hash
   fragment so independent generated modules cannot collide in LuaJIT's global
   `ffi.cdef` namespace;
4. records declaration-to-physical field projections in typed layout products;
5. includes size, alignment, and field order in the schema/layout fingerprint.

Constructor arguments remain in semantic declaration order. Physical reordering is
not observable.

Version 1 supports AoS only. SoA requires a measured consumer and a new layout-plan
leaf; it is not a constructor flag in v1.

Structural rows are immutable after construction. Transformations create new nodes
or write named derived facets. This keeps source truth stable and prevents mutation
protocols from leaking into every consumer.

---

## 14. Facet storage

Each generated facet type has a runtime factory owned by the world:

```lua
local inferred = world.facets.ExprType.new()
world.kernels.infer_types(inferred)
```

A facet instance contains constructor-segmented pages aligned to its domain spine.
Pages are allocated before a writing kernel enters the corresponding constructor
range. The inner loop therefore performs no allocation or optional-page check.

Source facets, such as origin, may be populated directly by constructors. Their
arguments are uniform across all constructors in the sum and appear first in fixed
constructor argument order.

Derived facets are explicit consumer inputs or results. A kernel never writes a
node-keyed Lua side table or hidden field.

---

## 15. Typed sequence stores

Every sequence field has a logical element domain. Generated APIs distinguish
`ExprSeqRef`, `TypeSeqRef`, and other sequence-reference domains even if their
physical elements are all `uint32_t` handles.

A constructor stores one `uint32_t` sequence reference, not an ad hoc Lua pair. Each
element domain owns two append-only stores:

```text
descriptor rows   { offset: uint32_t, count: uint32_t }
word arena        consecutive uint32_t element handles
```

A sequence reference uses a domain-local 8/24 encoding: domain tag plus descriptor
index. Sequence-reference tags live in a separate physical namespace from node tags
because field storage already determines which handle category is being interpreted.
Reference zero is the canonical empty sequence. Non-empty descriptors point into the
word arena.

Version 1 provides:

```lua
local mark = world.expr_seq:open()
world.expr_seq:push(mark, child)
local seq = world.expr_seq:close(mark)
local call = world.expr.Call(origin, fn, seq)
```

The mark is a scalar nesting token, not a temporary Lua table. One persistent builder
stack per sequence store remembers open offsets. Open builders obey LIFO nesting, and
a nested builder's words are deliberately part of its parent's range; nesting always
means splice. A caller needing an unrelated sequence closes the parent first. The
table artifact validates mark ownership, nesting, element handle domain,
and use after reset.

Closing a non-empty builder appends one descriptor and returns its packed numeric
sequence reference. Constructors validate the expected sequence-domain tag and
descriptor bound. Generated kernels resolve the descriptor into scalar `offset` and
`count` locals before any call, following the same no-pointer-across-calls rule as
node rows.

Closed fixed-arity helpers may be generated for small sequences. Nested sequence
*types* remain rejected; callers introduce an intermediate constructor when needed.

There is no untyped module-global `extra` arena in the semantic model. An emitter may
share a lower physical word allocator only if generated typed APIs preserve domains
and the layout projection records that sharing explicitly.

---

## 16. Symbols and enums

A `symbol` field stores a `uint32_t` supplied by a symbol capability injected into
the world. The generated module does not duplicate an existing host interner.

The required runtime capability is narrow: intern/resolve for construction and
debugging, plus an identity fingerprint when serialized stores contain symbol IDs.
If the host capability cannot provide stable serialized identity, saving a store with
symbols is rejected. A default standalone symbol implementation is a separate
optional generated companion, not a hidden dependency.

Enums are assigned values in declaration order. Storage uses the smallest supported
unsigned integer covering every case. Enum names and values are emitted as constants
and included in reflection metadata.

---

## 17. Generated runtime API

A generated arena module returns schema constants and `new`:

```lua
local Lang = require("gen.lang")
local world = Lang.new(symbols)

local Expr = world.expr
local Num = Expr.Num
local Binop = Expr.Binop

local one = Num(origin, 1.0)
local root = Binop(origin, one, Lang.op.Add, one)
```

The exact generated API contains:

- fixed-arity constructors;
- nominal tag predicates and constants;
- scalar field getters for cold/ad-hoc code;
- facet constructors and scalar facet accessors;
- typed sequence builders and readers;
- generated optimized consumers;
- reset, release, save, and load;
- cold formatting and validation entry points.

### 17.1 Runtime trust boundary

Arena constructors validate the tag domain of required and optional references before
storing them. Optional zero is accepted; required zero is rejected. Typed sequence
builders validate every element reference before append, and constructors accept only
their generated sequence-reference values. These checks are predictable integer
branches to cold error functions and must be included in constructor benchmarks.

Scalar getters validate their expected constructor tag and row bound because they are
cold public boundaries. Generated kernels enter a known constructor segment and use
trusted row indices, so they do not repeat those checks in inner loops.

A raw 32-bit handle cannot prove world ownership or detect a stale generation. The
arena contract requires callers to use handles with their originating live world.
The table artifact checks the stronger contract. Cross-world or stale handles that
happen to have valid tag/index bits remain unsafe misuse in the arena artifact.

There is no general public `get(handle)` returning an interior row pointer. An
explicitly unsafe constructor-specific borrow operation may be emitted behind a debug
or expert option, but optimized generated code never depends on it.

Hot callers may localize generated functions. World ownership remains explicit even
though the functions close over direct directory and counter upvalues.

---

## 18. Kernel authoring

Optimized kernel bodies cannot be opaque Lua functions. A string emitter cannot
inline a closure's source, and bytecode inspection is not a semantic interface.

Kernel bodies are therefore typed `AdtKernel` ASDL constructed through LLBL kernel
heads or through a build-time Lua builder that immediately returns `AdtKernel` ASDL.
A builder callback is metaprogramming syntax only: it is executed during assembly and
is never stored in schema or consumer state.

The initial kernel vocabulary is deliberately small:

- scalar and enum constants;
- constructor field and facet loads;
- typed sequence length and element loads;
- tag predicates for a declared sum;
- arithmetic, comparison, and boolean expressions;
- typed local bindings;
- conditional statements;
- facet stores;
- construction of other constructors;
- recursive call on a handle for scalar-recursive consumers;
- scalar result.

Kernel ASDL has no row-pointer, arbitrary cdata, or borrow value. A kernel can name
a constructor row only through its typed current-row capability, from which it may
load declared scalar fields. The capability cannot be stored, returned, or passed to
a recursive operation. Pointer lifetime safety is therefore structural, not linted.

Kernel inputs and results are named ASDL products. There is no generic `ctx`, `env`,
options table, raw callback, or arbitrary host value. Fixed external scalar
operations require explicit typed declarations and fixed generated bindings.

The vocabulary grows only when a real kernel cannot be expressed. It is not intended
to become a second general-purpose language.

---

## 19. Variant sweeps

A sweep names one or more constructor leaves and supplies one kernel per selected
leaf. The generated function enters each constructor segment directly:

```lua
function kernels.fold_binop(input, output)
  -- first-page loop
  for i = 0, first_n - 1 do
    -- generated Binop body
  end

  -- regular-page loop
  for j = 0, regular_n - 1 do
    -- generated Binop body
  end
end
```

Inner loops contain no tag test, function callback, pool descriptor lookup, varargs,
or allocation.

Sweep validation computes explicit effects from Kernel ASDL. A sweep may:

- read structural fields;
- read or write declared facets;
- construct nodes of other constructors;
- read typed sequences.

It may not:

- mutate structural fields;
- allocate the constructor currently being swept;
- change the swept facet's population;
- call opaque Lua;
- retain a row pointer.

A cold `each_Binop(callback)` convenience may be generated, but it is documented as
non-optimized and is absent from performance claims.

---

## 20. Scalarized recursive consumers

A scalar-recursive consumer is used when dependency or tree order is intrinsic. It
has one exhaustive leaf kernel per constructor in its domain sum.

The emitter generates direct tag dispatch, not a dense function vtable. Before any
recursive call, the active leaf loads every field needed after that call into scalar
locals:

```lua
local function eval(handle, input)
  local tag = tag_of(handle)
  local row = index_of(handle)

  if tag == TAG_Num then
    return load_Num_value(row)
  elseif tag == TAG_Binop then
    local left = load_Binop_left(row)
    local right = load_Binop_right(row)
    local op = load_Binop_op(row)
    return combine(op, eval(left, input), eval(right, input))
  end

  return invalid_expr_tag(handle)
end
```

The source semantic behavior still belongs to constructor leaves. The emitted branch
is the physical closed-union encoding produced from those leaf methods.

Recursive dispatch may form side traces. The architecture promises correct
scalarization and no pointer-induced GC, not a single monomorphic trace for mixed
trees.

Dense runtime vtables are not emitted for optimized recursive consumers. If a cold
dynamic method table is requested for ergonomics, it is separate and carries no
performance guarantee.

---

## 21. Future execution projections

Bucketed frontiers and explicit ordered schedules fit the architecture as additional
`AdtConsumerPlan` leaves, but are not part of v1. They will be introduced only after
a benchmark demonstrates a workload where scalar recursion and variant sweeps are
both inadequate.

This keeps storage independent from control without prematurely building a query or
worklist framework.

---

## 22. Checked table artifact

Every checked schema can emit a plain-table artifact with the same semantic API:

- constructors return nominal table handles owned by one world;
- structural fields become immutable after construction;
- facets are named aligned products, not arbitrary node properties;
- sequence builders enforce typed domains and LIFO marks;
- consumer kernels execute the same Kernel ASDL semantics;
- reset invalidates all old handles.

The table artifact additionally validates:

- world ownership;
- stale generation;
- bounds;
- expected sum for every reference store and load;
- constructor arity and scalar range;
- facet alignment;
- sequence mark nesting;
- sweep population invariants.

It also provides structural `tostring` and rich errors through reflection metadata.
It is the reference semantics for differential testing and portability, not a
compatibility representation hidden inside the arena module.

---

## 23. Reflection and diagnostics

Generation emits a cold metadata sidecar:

```lua
return {
  schema_hash = "...",
  constructors = {
    [3] = {
      name = "Binop",
      sum = "expr",
      origin = "lang_schema.lua:14",
      fields = { "left", "op", "right" },
    },
  },
}
```

The hot module does not load it. Failure and debugging functions load it lazily to
format constructor, field, sum, and declaration-origin context.

Generated fast paths branch to separate non-inlined error functions. They do not
format strings, use `pcall`, or load metadata on success.

---

## 24. Lifecycle

`world:reset()` does the following:

1. increments the world generation used by the checked table artifact;
2. zeroes constructor counts;
3. resets sequence arenas;
4. resets or invalidates source facet counts;
5. invalidates every structural handle, sequence reference, sequence mark, and facet
   instance tied to the previous population;
6. retains allocated pages for reuse.

`world:release()` detaches finalizers, frees every allocated page and directory, and
makes further operations fail. Release is idempotent on the cold path.

The arena artifact cannot encode stale generation in a 32-bit handle. Stale-handle
use after reset is an unsafe contract violation there and a checked error in the
table artifact.

---

## 25. Serialization

Serialization is a same-schema, same-generator, same-ABI cache format. It is not a
portable interchange format.

The header records:

- magic and format version;
- normalized semantic schema hash;
- generator version;
- layout-plan hash;
- ABI fingerprint including endianness, pointer width, scalar sizes, struct sizes,
  alignments, and page policy;
- section count and flags.

Base snapshot sections represent structural constructor rows, world-owned source
facet rows, typed sequence descriptors and words, and optional default-symbol data.
Derived facet
instances are not included in a v1 base snapshot; callers recompute them after load.
A future cached projection must be a separately declared named snapshot product, not
a runtime list of optional facets.

Rows are written in logical row order. Saving performs one copy per used page into
the output buffer; loading allocates pages and copies them back. Chunking therefore
does not appear in the logical section order.

No node traversal and no pointer fixup occur because all durable references remain
node handles, sequence references, and internal word offsets.

Load rejects every hash, version, ABI, section-size, count, tag, or symbol-capability
mismatch. There is no warning mode. Memory mapping and zero-copy views are deferred.

---

## 26. Exhaustiveness and defaults

A closed recursive consumer must cover every constructor in its sum. A sweep covers
the constructors it explicitly declares because a sweep is a query over selected
populations, not a sum eliminator.

A recursive consumer may declare one typed default kernel. The default is represented
by an ASDL leaf and is expanded against missing constructors during checking. It is
not stored as `_` in a runtime handler table.

Adding a constructor invalidates the schema hash and causes every non-exhaustive
consumer to fail generation with both origins reported.

---

## 27. Generated-source requirements

Generated source is an artifact, not an opaque cache. It must be:

- deterministic;
- formatted consistently;
- readable without the generator;
- annotated with schema hash, layout hash, generator version, source path, and ABI;
- free of runtime LLBL/Lalin imports;
- checked into `gen/` where the owning project chooses checked-in generation;
- verified in CI by regeneration with no diff.

Specialized constructor and kernel code may be repetitive. Repetition is intentional
when it removes generic descriptors or runtime dispatch from a hot path.

---

## 28. Repository organization

The implementation should remain flat by semantic ownership:

```text
lua/adt/dsl.lua              LLBL authoring dialect
lua/adt/schema.lua           source and checked ASDL vocabulary
lua/adt/kernel.lua           Kernel ASDL vocabulary and leaf behavior
lua/adt/layout.lua           store/layout ASDL vocabulary and planning methods
lua/adt/check.lua            root checked-schema wiring and diagnostics
lua/adt/emit_arena.lua       self-contained LuaJIT arena artifact emitter
lua/adt/emit_table.lua       checked reference artifact emitter
lua/adt/emit_meta.lua        cold reflection sidecar emitter
lua/adt/serialize.lua        build-time serialization-section planning
tests/adt/                   focused semantic and generated-artifact tests
benchmarks/bench_adt_store.lua
gen/                         project-owned generated artifacts
```

There is no `lua/adt/runtime/` dependency in the generated program. Small pool and
serialization routines are specialized and emitted into the artifact.

---

## 29. Testing

### 29.1 Semantic boundaries

- source ASDL construction and LLBL origins;
- field leaf `:check()` and `:plan_storage()` methods;
- checked schema resolution;
- layout projection and deterministic tags;
- consumer exhaustiveness and Kernel ASDL validation;
- artifact-plan construction.

### 29.2 Differential behavior

Every runtime behavior test runs both table and arena artifacts and compares:

- constructed values through scalar getters;
- tags and sum predicates;
- sequences;
- source and derived facets;
- sweep results;
- recursive results;
- reset behavior where both artifacts can observe it;
- save/load round trips.

### 29.3 Diagnostics

Negative tests assert both message meaning and origins for duplicates, unresolved
references, wrong-sum handles, stale handles, invalid sequence nesting, missing cases,
forbidden sweep effects, and serialization mismatches.

### 29.4 Generated artifacts

- literal checked schemas test layout without LLBL;
- LLBL dialect tests stop at checked ASDL;
- generated source has golden files;
- generated source loads in a clean LuaJIT process without repository packages;
- checked table artifacts run on supported non-FFI Lua for tooling.

### 29.5 Performance gates

The minimum benchmark set is:

- one million node construction;
- full GC after construction;
- constructor-local read and mutation sweeps;
- scalarized mixed recursive evaluation;
- many rare constructors to expose first-page waste;
- reset and rebuild;
- save and load.

`-jv` logs are CI artifacts. Constructors and sweeps must have no hot-loop aborts.
In-process `jit.p` sampling begins after setup and warmup. Recursive consumers must
show no pointer-induced GC samples; they are not required to form one trace.

---

## 30. Milestones

### M0 — Runtime evidence (complete)

The hardcoded arena/table experiment establishes the representation and emitter rules.

### M1 — Typed schema and checking

Define source and checked ASDL, field leaves, entities, origins, resolution, and
negative tests. Drive it with literal ASDL values; do not build the dialect yet.

### M2 — Store plan and generated vertical slice

Generate `Num`, `Var`, and `Binop` stores, handles, constructors, scalar getters,
reset, and release. Implement the tiered page policy and repeat M1 measurements before
freezing constants.

### M3 — Checked table parity

Generate the reference artifact and differential tests. Add reflection metadata and
golden generated source.

### M4 — LLBL dialect

Add heads, roles, fragments, and origin-rich diagnostics. The authoring example in
this document must produce the already-tested checked ASDL.

### M5 — Facets, typed sequences, enums, and symbols

Add one feature at a time with table/arena differential tests. Do not introduce a
generic extra arena or attribute map.

### M6 — Typed consumers

Define the minimal Kernel ASDL, then implement variant sweeps and scalarized recursive
consumers. Exhaustiveness, effect validation, trace gates, and profiler gates are part
of completion.

### M7 — Serialization

Add fingerprints, logical sections, same-ABI save/load, hard mismatch rejection, and
round-trip property tests.

Bucketed worklists, SoA, 64-bit handles, mmap, deletion, and runtime extension require
separate evidence and architecture updates after M7.

---

## 31. Rejected designs

### Node objects with compact payloads

Still one GC-visible object per node and still pointer-chasing.

### Dense recursive vtables

Measured slower than table dispatch for the arena case. They remain optional cold
ergonomics, not optimized execution.

### Public interior-pointer access

Encourages pointers to cross calls and caused measurable cdata GC. Public APIs use
handles and scalar access; generated kernels keep row pointers private and local.

### Opaque Lua sweep callbacks

Cannot be inlined by a source emitter without unsound source or bytecode inspection.
Optimized bodies are typed Kernel ASDL.

### Plain-table Schema IR

Would duplicate the semantic model outside ASDL and force string/kind dispatch.
Compiler phase values are typed ASDL projections.

### One generic extra arena

Erases sequence element domains and encourages unrelated overflow payloads to share
an untyped protocol. Sequence stores remain logically typed.

### Mutable structural nodes

Makes every consumer reason about invalidation and silently mixes authored structure
with later facts. Structural rows are immutable; later facts are facets or new stores.

### Per-node freeing and compaction

Require free lists, generations, remapping, and reference repair. Whole-world reset is
the intended lifecycle.

### Runtime layout options

Put configuration branches and compatibility burden into the hot artifact. Layout is
chosen at generation time and fingerprinted.

---

## 32. Binding invariants

1. Semantic alternatives are ASDL unions; physical tags are only encodings.
2. Concrete ASDL leaves own checking, storage planning, and kernel behavior.
3. Compiler phases exchange named ASDL inputs and results, never loose tables.
4. The world owns all bytes and invalidation; handles name rows within that world.
5. Structural rows are immutable after construction.
6. Facets are named phase products aligned to a segmented spine.
7. Handles may cross calls; interior pointers may not.
8. Recursive emitters scalarize all required fields before any call.
9. Optimized loops contain no opaque callbacks or runtime layout dispatch.
10. Sweeps dispatch once per constructor population, never once per node.
11. Generated runtime artifacts are self-contained and deterministic.
12. The checked table artifact is the reference semantics.
13. Cache mismatches are hard errors.
14. Unmeasured features remain out of v1.

---

## 33. Final architecture

`adt` has one deep abstraction: a generated world that stores closed semantic
populations and compiles their consumers.

```text
closed ASDL schema
    -> segmented structural store
    -> typed handles and sequence coordinates
    -> aligned semantic facets
    -> leaf-owned kernels
    -> sweep or scalar-recursive consumer plans
    -> self-contained table and arena artifacts
```

The elegance comes from moving distinctions to the correct layer. Sums express
meaning. Layout projections express bytes. Consumer projections express order. The
build step composes them, and the runtime pays only for the one concrete machine that
was selected.
