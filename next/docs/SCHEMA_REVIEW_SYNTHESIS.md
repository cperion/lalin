# Schema Review Synthesis

DeepSeek reviewed the first `next` compiler ASDL schema in five parallel passes: front-end, code/control/memory, backend, ASDL doctrine, and whole-schema closure.

The review result was not that the schema was too large. The result was that it was misallocated: several durable language facts were missing, some physical facts lived too early, CMat summarized value flow instead of owning it, and a few bag unions would force `.kind` filtering during implementation.

Applied rebalancing in the schema:

- source surface now includes integer division, window boundary policy, scan mode, call-site requires, contract statements, repr/from_repr, qualified declaration headers, and unique identity authority;
- projections now carry explicit generation tokens and coherence diagnostics for generation/target mismatch;
- semantic bindings are canonical, variants no longer own physical discriminants, ownership transfer is explicit on returns/jumps/routes, and erasure is a durable semantic projection;
- layouts are target/policy pinned and variant discriminants moved to layout;
- code load/store/atomic instructions carry volatility;
- control trip counts distinguish zero/affine/ceil-div trips;
- memory has indirect roots, multi-index access, bounds-derived trap evidence, contract realizations, and generated model identity;
- kernel evidence bags were replaced with typed fact fields;
- CMat streams now carry explicit input edges, sinks carry explicit input streams, window coordinates carry boundary policy, and fragments own source-value bindings;
- C functions are assembled from parts instead of a single baseline-or-fragment source, function/extern linkage is explicit, and C parameters can carry restrict evidence;
- host symbol resolution no longer duplicates request/capability records;
- diagnostic coverage now includes checking, layout, ABI, coherence, and several missing region/ownership/materialization/backend leaves;
- Lua-keyword `function` fields were renamed to method-friendly `fn`;
- lower layers now use `Code.Ordinal` instead of `Source.Ordinal` for positional handles;
- the unreferenced `Source.ScalarContract` wrapper was deleted;
- O18 effects and O33 ownership were split out of `Memory` into `Effect` and `Ownership` namespaces;
- cursor realization is now an explicit CMat value (`Cursor`, `CursorStep`, `CursorRealization`) consumed by fused fragments;
- round-2 cleanup deleted dead closure/region-seal/session/source-expression scaffolding, removed `Kernel.Form`, removed duplicated `Kernel.ResultProtocol`/`CMat.Result.protocol`/`CMat.SinkOperation`, unified CMat address/coordinate basis, and added a source-to-semantic reducer bridge for SOAC fold/scan;
- C and fragment lowering now keep block parameters, fragment entries, scalar meaning, memory-use links for loads/stores, cursor local identity, and terminator effects;
- role enums that only repeated their owner were folded into ASDL leaves (`Kernel.Lane`, `Control.Edge`, `Control.Induction`, `Memory.Access`, `CMat.Access`, and `Semantic.Capture`);
- pure wrappers were folded where they carried no durable meaning (`Source.ProgramSource`, `CMat.AddressEnvironment`, and `CMat.CoveredBlock`);
- the schema now validates at 354 declarations;
- review-3 cleanup removed seq-cst-only `Source.AtomicOrdering`, orphaned `Source.MachineCast`, single-leaf `Semantic.ErasureKind`, pure `Control.Trip`, duplicate `C.CPointerAccess`, duplicate `Memory.StorageKind`, and pure `CMat.Result`;
- semantic bindings now carry mutability, code parameters/locals carry their owning function, and control uses carry an operand slot;
- `Kernel.Kernel` now references the control/memory/effect/ownership facets instead of re-owning their fact lists;
- fragment CFG is explicit: fragments contain blocks, operations carry ordinal/origin, labels have parameters, and branches/jumps carry arguments;
- memory accesses carry volatility and diagnostics now include volatile fusion rejection, RMW materialization rejection, unsupported fragment carries, reducer validation failures, unsatisfied call-site requires, and loop-domain/body validation failures;
- semantic reference targets and relocatable static initializers now give downstream relocation/global-reference vocabulary real producers;
- public/backend/host symbol names now use one `Source.Symbol` authority carrying linkage instead of parallel symbol/linkage strings;
- vector and masked-tail schedule vocabulary was removed until vector C/CMat operations exist, leaving an honest scalar fused contract;
- CMat memory uses now have one coordinate plus address bindings, with no duplicate `UseIndex`, `Address`, or `CursorKind`;
- helper symbols, backend symbols, ABI signature collisions, and host symbol requests all use the same typed symbol value;
- cook policy carries `Host.FloatCompilerMode` so fast-math/reassociation choices are represented at the GCC boundary;
- restrict qualification now directly references proven `Memory.Relation` values instead of `CMat.RestrictGroup`/`QualificationPair` wrappers;
- C function definitions now carry explicit ABI parameter/result-slot zippers and fragment-entry parameter zippers, with diagnostics for invalid ABI parameters, inconsistent restrict qualification, and overlapping C function parts;
- review-4 cleanup typed `CMat.FragmentValue`, removed hidden-result double modeling, deleted dead `Semantic.OwnershipEvidence`, folded scalar-only schedule fields, removed unreachable find/all/any/allcompare result leaves, and folded `CMat.Producer`;
- code instructions and terminators now carry their owning block and ordinal, multi-axis loop flows carry per-axis trips, and Memory no longer depends on Ownership states;
- call-site requires survive into `Code.CallInstruction`, code block parameters can be generated, semantic lease origins and unique identity authorities are resolved values, and semantic method calls retain receiver/method shape;
- analyzed effect atoms no longer carry subjectless trap/volatile/atomic/external/unknown-access duplicates; fences have a distinct effect;
- C artifacts derive exported symbols from unit entities rather than carrying a separate artifact-symbol authority;
- final scaled-review repair removed the non-finite `Effect.Atom -> CallableEffect -> Atom` embedding cycle by making call atoms reference `Code.Callee` and storing callable effects in keyed entries;
- `Source.DeclaredEffect` was folded into direct declared-effect atom lists while preserving the authored `Source.DeclaredEffectAtom` vocabulary;
- semantic call-site `requires` is call-only again (`Semantic.CallArgument`), with `Code.CallInstruction` and `Memory.CallRequireRealization` as the downstream carriers;
- target tail permission and kernel tail decision are separate named facts, not one duplicated authority;
- multi-axis loop trips are carried by axis/trip entry products instead of parallel arrays;
- custom reducer scaffolding was trimmed: only built-in reducers remain until an authored reducer-law declaration exists;
- reduction algebra and loop arithmetic are split, scan mode lives at the control algebra owner;
- CMat edges now flow through consumer inputs and `StreamSource` values, CMat basis is object-only, sinks name their producer, and scatter coordinates are explicit;
- C ABI result slots name hidden sret parameters, intrinsic operations use `CallResult`, C terminators carry origin, and host cook failures include `FastMathRefused`;
- memory/effect/ownership facets are aligned per function graph, noescape/contract realization has real consumers, and CMat memory uses carry live ownership states;
- schema churn is frozen unless a true P0 schema correctness issue appears.

Still open for the next pass:

- finish diagnostic family granularity without reintroducing process scaffolding;
- ByteSpan is deliberately not restored as a separate semantic/code type for now: byte spans lower through `view`/`slice`, `ByteRangePlace`, and width/alignment facts. Restore a minimal ByteSpan only if implementation proves this loses a durable decision.

