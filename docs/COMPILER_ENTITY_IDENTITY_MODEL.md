# Compiler Entity and Identity Model

Status: Step 2 of the ground-up Lua-ASDL compiler model.
Prerequisite: `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`.

This document determines what is an entity, what is only a value or coordinate, where
identity is created, which boundaries preserve it, and where a genuinely new physical entity
appears. It does not define replacement ASDL products, machines, spines, facets, or passes.

---

## 1. Identity is not interning

The active ASDL runtime aliases `interned` to structural `unique` construction. Values are
canonicalized through a trie keyed by their fields. Consequently:

```text
CodeValueId("v_f_1") == CodeValueId("v_f_1")
```

means that two equal text values were interned to one Lua object. It does not prove that the
compiler has modeled a durable entity.

Current compiler identity is overwhelmingly:

```text
typed wrapper around composed text
  + process-global structural interning
  + equality by interned value/text
```

This is canonical value equality, not entity identity.

The new model must keep these concepts separate:

- semantic entity identity;
- structural occurrence coordinate;
- namespace/name key;
- immutable structural value;
- derived projection reference;
- physical artifact identity;
- host resource identity.

## 1.1 Entity test

A thing is an entity only when at least one observer must distinguish it from another thing
with equal fields or equal spelling.

Questions:

1. Can two equal-looking instances coexist?
2. Can the thing be renamed while remaining the same thing?
3. Can references survive movement, reprojection, or time?
4. Does it have an independent lifetime or invalidation boundary?
5. Can two projections refer to the same thing?
6. Must a diagnostic identify this occurrence rather than merely describe its value?

If every consumer can use structural equality, the thing is a value, not an entity.

## 1.2 Coordinate test

A coordinate identifies a position inside one immutable generation: declaration slot, block
slot, instruction slot, memory-use slot, field offset, or source span.

Coordinates are useful and typed, but they do not claim identity across generations. A change
that rebuilds the containing structure may assign new coordinates.

## 1.3 Name-key test

A qualified name is a lookup key in a namespace. It is not the identity of the declaration
that currently occupies that key.

This distinction is required to diagnose duplicates: two declarations can have the same key
while remaining two different authored occurrences.

## 1.4 Physical-identity test

A physical entity is created when materialization establishes an independently referenceable
runtime or artifact object: exported symbol, backend function, static object, helper definition,
shared object, or live loaded session.

Physical identity must retain typed provenance to semantic identity. It must not replace it.

---

## 2. Identity classes

The compiler needs five identity classes.

### 2.1 Authored semantic entities

User- or generator-authored things whose occurrence must remain distinguishable during
resolution, checking, diagnostics, and semantic projection.

Examples: declaration occurrence, binding declaration, nominal type declaration, region
declaration, block declaration, continuation declaration.

Lifetime: one authored-program generation.

### 2.2 Generated semantic entities

Entities created by a semantic operation rather than directly authored, but still meaningful
before physical backend construction.

Examples: expanded region block/value occurrence, closure environment field, code function,
code block/instruction/value occurrence, memory object, memory access occurrence, recognized
kernel candidate.

Lifetime: the generation of the producing semantic world.

### 2.3 Structural coordinates

Positions inside an immutable spine or product. They are valid only with the identity of the
containing generation.

Examples: authored declaration slot, block order, instruction ordinal, continuation ordinal,
memory-use slot, axis ordinal, field offset.

### 2.4 Physical entities

Materialized C/runtime objects and addressable artifact structures.

Examples: backend function, exported symbol, backend global/data object, helper definition,
C local/label, emitted translation unit.

Lifetime: one backend/artifact generation.

### 2.5 Host resource entities

Resources whose liveness is managed outside ordinary compiler semantics.

Examples: loaded shared-object session and resolved dynamic symbol capability.

Lifetime: explicit load/free boundary.

---

## 3. Universal identity laws

1. **Creation authority:** one concern creates each entity identity.
2. **Generation scope:** every identity is valid in one explicit generation or durable domain.
3. **Names are keys:** spelling and qualification never substitute for occurrence identity.
4. **No encoded identity:** semantic relationships do not require parsing or recomposing names.
5. **Typed provenance:** a new derived/physical entity references the source entity or subject
   that caused it.
6. **Projection preservation:** a one-to-one semantic projection preserves source identity
   unless it establishes an independent lifetime.
7. **One-to-many creation:** when one source produces several derived entities, the producing
   concern owns explicit occurrence identity or slots.
8. **Coordinates travel with their container:** a slot/ordinal is meaningless without its
   spine/world generation.
9. **Interning is an optimization:** structural canonicalization cannot define entity lifetime.
10. **Symbols are physical projections:** public C spelling does not become semantic function
    identity.
11. **Origins are provenance, not identity:** equal source spans may produce distinct generated
    entities; one entity may carry several causal origins.
12. **No session leakage:** process-global canonical values may be reused internally, but no
    compilation result may depend on prior-session allocation order or mutable counters.

---

## 4. Authored program identity

### 4.1 Compilation unit

A compilation request establishes one authored-program generation. The current implementation
hardcodes module name `module` and later `module_module`; source name is threaded separately.
That is not a reliable semantic identity.

Required meaning:

- one program generation contains one ordered declaration population;
- source name/chunk name is provenance and diagnostic context;
- a program/module identity is established by the compilation request, not inferred from a
  hardcoded string or emitted symbol prefix;
- independently compiled equal programs need semantic equivalence, not shared entity identity.

### 4.2 Declaration occurrence

Every authored or generated declaration is an occurrence entity before name resolution.
It must be possible to represent:

```text
two function declarations with the same qualified key
two type declarations with the same qualified key
two generated declarations with equal spelling but different origins
```

Resolution then decides whether a namespace key maps to one declaration, is missing, or is
duplicated. Current duplicate detection often happens only after code IDs such as `fn_f` are
created; duplicate structs/fields may pass silently. That is too late and too string-dependent.

### 4.3 Namespace key

A namespace key is a value composed from semantic namespace and qualified authored name.
It supports lookup and diagnostics. It does not identify the declaration occurrence.

Distinct namespaces may admit the same spelling. Namespace membership must be explicit, not
encoded in prefixes such as `fn_`, `extern_`, or `global_`.

### 4.4 Nominal declarations

Nominal type, handle, region, function, extern, constant, and static identity derives from
the resolved declaration occurrence—not solely from its name.

Renaming changes the namespace key and public spelling but need not destroy every semantic
reference inside the same rewritten program generation.

### 4.5 Field and variant identity

Fields and variants are authored child entities of one nominal declaration. Their semantic
identity is the parent declaration plus child occurrence, not target offset or discriminant.

Physical field offset and variant tag are O37 layout facts. Reordering may change physical
representation while preserving the distinction between semantic identity and layout.

### 4.6 Binding identity

Every binding declaration creates exactly one binding entity: function parameter, block
parameter, local `let`, mutable binding, pattern payload, capture, or generated parameter.

All checking, expansion, closure, and code construction references must carry that same typed
binding reference. They must not independently mint formats such as:

```text
parsed:<line>:<col>:<name>
dsl:<name>:<counter>
arg_<function>_<name>
region:param:<...>
control:param:<...>
emit:local:<...>
```

Current phases manually coordinate these strings. The new identity model forbids that.

### 4.7 Region identity

A region declaration is an authored declaration entity. Its blocks and continuations are
child occurrence entities scoped to that region.

A continuation name is a namespace key within the protocol. Its ordinal is an ordering fact,
not a second identity. Current `RegionCont` combines region/name/index while wiring uses names;
the target model must select one declaration identity and preserve it.

### 4.8 Invocation and generated expansion identity

A region invocation is a source/control occurrence. Open expansion creates new generated
block, binding, and value occurrences with typed provenance:

```text
generated occurrence
  caused by invocation occurrence
  cloned from definition occurrence
```

Source byte offset may be part of origin, but it is not sufficient entity identity and cannot
be concatenated into hierarchical names to establish semantic uniqueness.

### 4.9 Closure capture identity

A capture references the original binding entity. Environment construction creates a new
physical/representation field with provenance to that binding. Capture analysis must not
rename the captured entity into a new semantic binding by convention.

---

## 5. Types and signatures

### 5.1 Structural types are values

Pointers, arrays, views, slices, scalar types, function shapes, and composed structural types
are immutable values. Structural interning is appropriate. They are not entities.

### 5.2 Nominal types are entities

A nominal type reference targets the resolved nominal declaration entity. Its qualified name
is a lookup/display key.

### 5.3 Layout is a projection

Size, alignment, field offset, variant tag, aggregate class, and physical handle representation
are O37 projections aligned to nominal/structural type meaning and target generation.
They do not create new semantic type identity.

### 5.4 Function signature is a structural value

A signature shape is structurally internable. It need not receive a fresh semantic ID merely
because several functions use it.

A backend may create a physical signature entry for serialization or C declaration reuse;
that entry retains provenance to the structural signature value and target.

---

## 6. Code-generation identity

Code construction creates one immutable code generation from one accepted checked generation.

### 6.1 Code function

A code function is a semantic projection of one function/region materialization subject.
It carries typed provenance to that source entity. Internal code identity and public symbol
spelling are separate.

A generated sealed-region function also carries the seal/materialization subject that caused
it.

### 6.2 Code structural occurrence family

The following are generation-scoped structural occurrences:

- block;
- instruction;
- terminator;
- value definition;
- local storage slot;
- parameter occurrence.

They need typed references because control, def-use, diagnostics, memory facts, and lowering
cross-reference them. They do not require globally meaningful text IDs.

One code-structure authority creates their occurrences and order. Their identity may be a typed
reference/slot within the code generation, provided it is never used without that generation.

### 6.3 Value identity

A code value identifies one SSA-like definition or parameter occurrence. It is not the string
name emitted in C. A value may carry provenance to an authored binding, instruction result,
constant, or generated control parameter.

### 6.4 Code type/data/global/extern references

Nominal code types preserve their source nominal declaration identity. Data/global/extern
objects are code-generation entities with provenance to authored constant/static/extern
declarations or generated literals.

String literal data is a generated data entity caused by a literal occurrence. Its trailing
backend NUL is not semantic identity.

### 6.5 Relocation

A relocation is a physical/reference relation inside a data initializer, not a free-standing
semantic entity unless another fact must refer to that exact relocation occurrence. Its
target is a typed function/global/data entity reference, never encoded target text.

---

## 7. Control topology identity

### 7.1 Graph nodes preserve code occurrences

A graph block is a projection of a code block. It does not need a second block identity class.
Edges, definitions, and uses are typed relations among existing code occurrences.

### 7.2 Edge is a relation value

An edge is structurally described by source block, target block, and edge occurrence/arm where
multiple edges may share endpoints. It needs an occurrence slot only when two same-endpoint
edges must remain distinguishable.

### 7.3 Loop is a topology-derived region

Loop identity is created by the control-topology projection, not flow interpretation. It is
generation-scoped and invalidated by topology changes such as block splitting.

A loop is a derived structural entity only because several later concerns refer to the same
recognized cycle. Its identity is not the string serialization of function/header/latch.

Flow owns interpretations of that loop—domain, induction, trips—not another loop identity.

### 7.4 Definitions and uses

Definition and use occurrences are relations anchored to code values/instructions/blocks.
If later concerns refer to a particular use occurrence, the topology concern supplies a typed
occurrence slot. Rebuilding text-keyed def/use maps cannot become semantic authority.

---

## 8. Flow, algebra, and proofs

Flow domains, induction facts, ranges, trip evidence, reductions, closed forms, and proofs are
immutable derived values aligned to code values and topology loops.

They are not durable entities merely because the current schema wraps them in `interned`
products or unused `*Id` classes.

Rules:

- flow interpretation references the topology loop entity;
- value-copy canonicalization references code values;
- reduction/closed-form facts reference loop and value occurrences;
- proofs are evidence values whose provenance is their premises;
- proof identity is structural unless independently referenced as an occurrence.

`FlowDomainId`, `EffectId`, `MemProofId`, and similar producer-less IDs are not admitted into
the new model without an actual identity observation.

---

## 9. Memory identity

### 9.1 Memory object

A memory object is a semantic storage entity within one memory-analysis generation. Its
identity must be independent of the particular access path that first revealed it.

Storage roots include parameters, locals, globals, data, views/slices, or declared stores.
Subobjects are projections from a root object plus a typed field/index/slice provenance path.

The current implementation lazily creates object IDs from revealing value text (`view:<dst>`,
`ptr-offset:<dst>`, and similar) and reconciles same-store relations afterward. That behavior
is evidence of required provenance, not the target identity model.

### 9.2 Memory-object provenance

Every object records how it relates to storage: root, field, slice, view, byte span, pointer
offset, external object, or unresolved provenance. Two paths may resolve to one object or to
related subobjects without requiring string comparison.

### 9.3 Memory access occurrence

A memory access is both:

- a structural occurrence in code;
- the subject of semantic access facts.

One code instruction may conceptually contain more than one access, so access identity is the
code operation plus an access occurrence slot—not necessarily one ID per instruction.

Bounds, alignment, trap, effect, alias, dependence, and backend-readiness facts reference that
access occurrence.

### 9.4 Memory relations and proofs

Alias, same-store, disjointness, slice-of, dependence, and noalias are relation/proof values.
They are not objects with arbitrary IDs. Pairwise facts reference exact object/access entities.

### 9.5 Contracts

A checked contract references checked binding/place subjects. Memory analysis projects those
subjects to memory object/access entities and owns that relation. It does not reparse names.

---

## 10. Effect identity

An effect occurrence is anchored to the operation that causes it: instruction, terminator,
call site, contract boundary, or external function.

Effect summaries are projections over functions and memory objects/accesses. They are values,
not independent entities. An `EffectId` is unjustified unless another operation must refer to
two equal-looking effect occurrences independently.

---

## 11. Kernel and schedule identity

### 11.1 Kernel

Kernel recognition creates a derived computation object from one topology/semantic subject.
The kernel is semantically distinguishable from the source loop because it owns recognized
lanes, bindings, result shape, and rejection/admission history, and future models may admit
more than one candidate per subject.

However, a separate textual `KernelId` is not automatically required. Within Lua ASDL, later
facts can reference the kernel value/entity directly. If keyed relations require a reference,
the kernel-recognition concern creates it with typed provenance to the subject.

Current `kernel:<loop-text>` is a one-to-one string echo and proves no durable identity.

### 11.2 Kernel lanes and bindings

Lanes and kernel values are derived child occurrences of one kernel. They reference source
memory accesses and code values directly. Their identity is kernel-local occurrence identity,
not a new global string namespace.

### 11.3 Schedule

A schedule is a decision facet of one kernel, not an independent durable entity. Its form,
tail strategy, capability evidence, and rejected alternatives are values aligned to the kernel.

Current `schedule:<kernel>:<emitter>` text is a display/serialization key, not semantic identity.

---

## 12. Fused computation and CMat identity

### 12.1 Fused computation

A fused computation is a derived semantic/materialization projection of kernel plus schedule.
It preserves kernel provenance and introduces child stream, access, producer, sink, and result
occurrences only where the fused shape requires distinct cross-references.

### 12.2 Streams, accesses, producers, and sinks

These are occurrences within one fused-computation structure. Their stable coordinate is in
that structure. Text such as `kernel-stream:*` or `kernel-sink:*` is unnecessary for semantic
identity.

A fused access retains typed provenance to the kernel lane and memory access it realizes.

### 12.3 Memory-use spine

A materialized memory-use occurrence is genuinely new physical-shape identity. Several uses
may arise from one stream/access, especially window occurrences. Its identity is a slot in one
memory-use spine plus typed provenance to the semantic access/stream/sink.

This is the strongest correct identity pattern in the current compiler: new physical-use
occurrence plus explicit provenance.

### 12.4 Coordinates and cursors

A coordinate is a facet value aligned to a memory-use occurrence. It is not an entity.

A cursor is a physical plan occurrence when several uses share one address basis. It is local
to one address-plan generation. Cursor reuse is an explicit relation, not name equality.

---

## 13. Lowering and backend identity

### 13.1 Lowering strategy and fragment

A selected strategy is a decision value aligned to its candidate subject.

A planned fragment is a derived assembly occurrence when coverage, replacement, diagnostics,
or materialization refers to it independently. Its identity is local to one function-lowering
generation and carries typed provenance to covered loop/block/kernel subjects.

### 13.2 Backend function

Backend construction creates a physical function entity from a code function plus selected
materializations. It preserves typed provenance to the semantic function.

Its internal identity is not its C spelling.

### 13.3 Symbols

A public or local C symbol is a physical namespace key projected from backend entity and
linkage policy. Symbol spelling is externally observable. It is not semantic function identity.

Function-address relocations target the backend function entity and serialize its projected
symbol. The current path that sometimes uses `fn_<name>` and sometimes public `<name>` is an
identity defect and requires a focused regression before cutover.

### 13.4 Backend structural occurrences

Backend blocks, labels, locals, helpers, signatures, data, globals, externs, and relocation
occurrences are physical generation-scoped entities or coordinates as follows:

- function/global/data/extern/helper definitions: physical entities;
- block/label/local: structural coordinates inside one backend function;
- signature shape/type: structural values, with physical declaration entries only if shared;
- relocation: typed relation occurrence;
- helper name: physical symbol projection.

### 13.5 Emitted text

Emitted source/header are artifact values. Their deterministic content matters; they are not
entity identity.

---

## 14. Artifact and session identity

### 14.1 Artifact

A compiled artifact is a physical value containing emitted source/header, backend provenance,
and optional filesystem outputs. Randomized paths used for loader isolation are not semantic
identity.

### 14.2 Loaded session

A loaded shared-object session is a host resource entity with explicit liveness. Its identity
ends at `free`; release is idempotent; symbol access after release fails.

### 14.3 Resolved symbol capability

A resolved symbol is a host capability tied to live session, symbol key, and requested FFI
type. It cannot outlive the session. The FFI type is boundary evidence, not semantic function
identity.

---

## 15. Origin and provenance

Origin answers “why/where was this produced?” Identity answers “which entity is this?” They
must remain separate.

Required provenance relations include:

- declaration occurrence → source/generated origin;
- generated declaration → generator/splice cause;
- checked entity → authored entity;
- expanded entity → invocation occurrence + cloned definition entity;
- closure field → captured binding;
- code function/value/block → checked semantic cause;
- topology loop → code blocks/edges;
- memory object/access → code/storage provenance;
- kernel → topology/semantic subject;
- fused occurrence → kernel lane/access/value;
- memory use → fused access/stream/sink;
- fragment → covered subject and strategy;
- backend entity → code/materialization entity;
- public symbol → backend entity and linkage.

Current `CodeOriginSource` is rarely constructed; authored origin is often reduced to generated
strings. O01/O27 require this provenance to survive the full semantic chain.

---

## 16. Generation and invalidation

Identity validity is explicit by generation:

```text
authored generation
  → checked generation
  → expanded checked generation
  → code generation
  → topology/analysis generation
  → plan/materialization generation
  → backend generation
  → artifact/session lifetime
```

This does not require a generic global phase framework. Each published identity-bearing world
or spine names its source generation and own generation where stale mixing is possible.

Rules:

- a reference from one generation cannot enter an unrelated generation by structural equality;
- rebuilding a projection either preserves typed source identity or creates a new typed entity
  with provenance;
- process-global ASDL interning cannot grant cross-generation validity;
- deterministic recompilation may produce equivalent output without preserving entity identity;
- builder-global counters cannot affect semantic identity or emitted output.

---

## 17. Current identity disposition

### Preserve as semantic requirements, but not current text encoding

- program/declaration occurrence;
- nominal declaration, field, variant, handle, region;
- binding and capture subject;
- region block/continuation/invocation occurrence;
- code function/block/instruction/terminator/value/local occurrence;
- topology loop;
- memory object and access occurrence;
- kernel and kernel-local lane/binding occurrence;
- fused-computation child occurrences where cross-referenced;
- CMat memory-use occurrence;
- planned fragment;
- backend function/global/data/extern/helper;
- loaded session.

### Treat as structural values or relations, not entities

- structural type;
- function signature shape;
- layout facts;
- graph edge/def/use unless a duplicate occurrence needs a slot;
- flow domain/induction/trip/range;
- value expression/reduction/closed-form/proof;
- alias/dependence/effect facts;
- schedule decision;
- coordinate;
- strategy decision;
- emitted text.

### Treat as physical namespace keys or coordinates

- public C symbol;
- local C name/label;
- declaration/block/instruction/use/memory-use slots;
- field offset and variant tag;
- source span;
- randomized artifact path.

### Remove or require new evidence before admitting

- producer-less Core `ModuleId`/`ItemId`/`FieldId`/symbol families;
- unused `FlowDomainId`, `EffectId`, `MemBaseId`, `MemProofId`, `MemLeaseId`, `MemScopeId`;
- unused backend-command/CodeBack/Host/Phase/Exec/Project identity families;
- metastencil/artifact/provider/realized-schedule identities with no active producer;
- RegionBundle identity while the projection remains empty;
- separate CMat kernel ID that only copies kernel text;
- schedule ID used only as a formatted echo.

---

## 18. Answers to the Step-1 identity questions

1. **Authored identities surviving checking:** declaration and binding references, nominal
   child occurrences, region blocks/continuations, and origins must survive. Current code
   preserves mostly names and selected binding objects; that is insufficient.
2. **Function boundary:** code construction creates a code-function projection/entity with
   typed provenance to authored function. It does not replace semantic function identity;
   backend construction later creates the physical function.
3. **Code structural family:** blocks, instructions, terminators, values, locals, and parameters
   are one code-generation occurrence family with distinct typed roles.
4. **Loop:** topology creates generation-scoped loop identity; flow only interprets it.
5. **Memory object:** yes, storage-object identity must be independent of whichever place/access
   revealed it; subobjects carry typed provenance paths.
6. **Memory access:** one access occurrence is anchored to code occurrence plus access ordinal
   and carries semantic facts. It is both structural occurrence and semantic subject.
7. **Kernel:** kernel recognition creates a derived computation entity/projection with subject
   provenance; no global text ID is required merely because current code emits one kernel per
   loop.
8. **Schedule:** schedule is a decision facet of kernel, not an independent durable entity.
9. **Fused/materialized identity:** semantic kernel/access provenance is preserved; CMat creates
   new memory-use and physical-plan occurrences aligned through typed provenance.
10. **Backend:** externally required identity is symbol/linkage and live session capability;
    internal code/backend IDs are generation-local structure or serialization coordinates.

---

## 19. Required regressions before identity cutover

The new model must add focused tests for currently unproven identity behavior:

1. duplicate function/type/field/extern/region declarations rejected at authored resolution;
2. same-spelled declarations remain distinct occurrences for diagnostics;
3. nested scopes with same local names preserve distinct bindings through code and GCC;
4. parsed and builder inputs produce equivalent semantics without relying on equal internal IDs;
5. two builder compilations in one process produce deterministic emitted C despite global counters;
6. open-region cloned identities remain unique for repeated and nested invocations at equal
   source offsets across documents;
7. authored loop derives one topology loop and aligned flow facts without hand-built fixtures;
8. multiple memory accesses in one code operation remain distinguishable if supported;
9. two provenance paths to the same storage establish correct same-object/subobject relation;
10. function-address data relocation uses the projected public/local backend symbol consistently;
11. authored/generated origins survive checking, expansion, code, and public diagnostics;
12. stale identities from one generation are rejected by another generation's projections.

---

## 20. Step 2 exit verdict

The entity/identity model is closed enough to begin concern decomposition because:

- entity, value, coordinate, key, physical entity, and host resource are distinguished;
- every required entity class has a creation boundary and lifetime;
- every phase boundary states preserve-versus-create behavior;
- current interned text IDs are classified as evidence rather than copied;
- the ten Step-1 identity questions have evidence-based answers;
- dead and speculative identity families are excluded;
- unresolved current defects are captured as required regressions;
- no replacement ASDL product, machine, spine, or facet has yet been declared.

## Next step — Concern and authority decomposition

Step 3 assigns every obligation and identity creation decision to one distinguished Lua-ASDL
semantic receiver. Only after that authority graph is closed will we define spines and facets.
