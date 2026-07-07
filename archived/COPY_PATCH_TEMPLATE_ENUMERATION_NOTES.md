# Copy-Patch Template Enumeration Notes

> **ARCHIVED — Historical Research.** This document has been moved from `docs/` to
> `archived/` as of 2026-07-07. It records the historical research pass for
> redesigning the experimental Lalin native bank from first principles. It is not
> the main implementation contract.
>
> For the current experimental native copy-patch architecture, see
> `docs/RESIDUAL_NATIVE_ARCHITECTURE.md`. For the main JIT/AOT path, see the
> `emit_c` pipeline documented in `docs/ARCHITECTURE.md`.

This note records the historical research pass for redesigning the experimental
Lalin native bank from first principles. It is not the main implementation
contract. The main JIT/AOT path is `emit_c`: GCC cooks emitted C into a shared
object for JIT-like execution, and the same C output is the AOT artifact. The
copy-patch architecture is documented in `docs/RESIDUAL_NATIVE_ARCHITECTURE.md`
as an experimental backend track. A complete experimental language bank is
produced from the closed micro-op capability vocabulary defined there; subset
support domains are only tests or target subsets. The offline generator builds
verified native template banks, and runtime compilation only copies, patches,
and installs bank entries when that experimental path is explicitly selected.

## Sources Read

- Copy-and-Patch Compilation, Haoran Xu and Fredrik Kjolstad:
  <https://fredrikbk.com/publications/copy-and-patch.pdf>
- Copy-and-Patch arXiv record:
  <https://arxiv.org/abs/2011.13127>
- PyPy/RPython JIT docs:
  <https://rpython.readthedocs.io/en/latest/jit/pyjitpl5.html>
- Applying a Tracing JIT to an Interpreter, PyPy:
  <https://pypy.org/posts/2009/03/applying-tracing-jit-to-interpreter-3287844903778799266.html>
- RPython JIT hint source notes:
  <https://github.com/reingart/pypy/blob/master/rpython/rlib/jit.py>
- The Impact of Meta-Tracing on VM Design and Implementation:
  <https://tratt.net/laurie/research/pubs/html/bolz_tratt__the_impact_of_metatracing_on_vm_design_and_implementation/>
- Futhark performance guide:
  <https://futhark.readthedocs.io/en/stable/performance.html>
- Design and GPGPU Performance of Futhark's Redomap Construct:
  <https://www.futhark-lang.org/publications/array16.pdf>
- Futhark PLDI paper:
  <https://elsman.com/pdf/pldi17.pdf>

## Copy-Patch Lessons

Copy-patch is a baseline compiler architecture, not a compression format for
already fully generated exact functions. The bank contains binary stencils:
precompiled code fragments with known holes. Runtime compilation selects
stencils, copies their code bytes into executable memory, and patches holes such
as literals, stack offsets, branch targets, and call targets.

The paper's stencil library is organized around semantic program fragments:
bytecode opcodes, AST nodes, and deliberately selected supernodes. Supernodes
represent common subtrees or bytecode sequences where combining nodes improves
machine code. This is not the same as enumerating every product of producer,
layout, scalar type, point expression, sink, and schedule. The library can still
be large, but its units are semantic implementation fragments.

Important numbers from the paper:

- WebAssembly implementation: 1666 stencils, 35 kB.
- High-level language implementation: 98,831 stencils, 17.5 MB.

Those numbers matter because they show that a large stencil library is normal,
but also that it is structured. It is not a blind all-axis expansion. The paper
explicitly calls out Cartesian growth as a problem.

The most important anti-explosion trick is local relevance. A stencil only cares
about its own true inputs. Values that must pass through but are not inspected by
the stencil are represented with a longest/pass-through type, preventing
exponential growth in all possible live-register type combinations. In Lalin
terms, a template should not specialize on every fact carried through a loop
unless that fact changes generated instructions for that template.

The copy-patch runtime builds a CPS call graph. It plans register/value flow,
selects stencil configurations, copies stencils in depth-first order, and elides
fallthrough jumps when adjacent copied fragments make the jump unnecessary.
Remaining jumps correspond to real control flow: branches, loops, and calls.

Implication for Lalin: the bank should not contain one monolithic stencil for
every fused whole loop. It should contain composable binary templates for loop
semantic fragments plus selected supertemplates for hot/common fused shapes.

## PyPy Lessons

PyPy's tracing JIT does not enumerate all possible program loops. It observes
hot loops and specializes around a loop identity. In RPython terms, green
variables identify the loop/program position; red variables are runtime state.
The JIT traces the actual loop path, produces guards for assumptions, and falls
back or builds bridges when guards fail.

For interpreter JITs, the crucial trick is to make the loop identity correspond
to the interpreted program's loop, not the interpreter dispatch loop. PyPy does
this by adding program-counter-like values to the position key. Then tracing
unrolls the bytecode dispatch until an application-level backward jump closes a
loop.

Promotion is powerful but dangerous. Promoting a runtime value to a constant
adds guards and enables constant folding, but over-promotion creates code
explosion. The same warning applies directly to patch-template coordinates:
only values that materially change instruction selection should become family
axes; values merely inserted into existing instruction operands should be holes.

Implication for Lalin: distinguish classes explicitly:

- Complete-bank axes: closed machine/control micro-op families only.
- Graph repetition: repeated terms, lanes, effects, producer axes, parameters,
  results, and body members.
- Patch coordinates: values inserted into holes of an already selected template.
- Runtime/frame parameters: ordinary ABI values and frame slots passed to copied
  code.
- Lowering facets: program-specific type/layout/proof facts used while binding
  graph nodes.

Do not promote patch coordinates, counts, names, signatures, sizes, ranks,
strides, scales, offsets, or compiler flag strings into family axes.

## Futhark Lessons

Futhark treats SOACs as semantic algebra, not storage categories. `map`,
`reduce`, `scan`, and related constructs compose through fusion rules. Map can
generally be a producer; reduce/scan-like SOACs are consumers. Fusion is based
on a dependency graph, not source adjacency. Horizontal fusion combines
independent consumers of the same input into one traversal.

Futhark's redomap is not a user-facing bank family. It is a compiler-synthesized
operator that results from map-reduce fusion. The compiler fuses compositions
aggressively, including producer-consumer and horizontal fusion, and then lowers
the fused semantic operator to efficient code. This is the correct analogue for
Lalin: SOAC composition should remain semantic; the bank stores implementation
templates for the resulting normalized semantic forms.

Futhark also treats many layout operations as "free" views until use forces
materialization. Arrays of tuples use structure-of-arrays representation, making
zip/unzip cheap in many cases. The broader lesson is that layout transforms are
semantic access projections. They should influence template selection only when
they change address-generation code.

Implication for Lalin: template enumeration should be driven by normalized
loop/SOAC forms after fusion and view/layout normalization, not by raw source
surface combinations.

## Correct Lalin Bank Model

The bank is a fast copy-patch compiler for Lalin loop semantics.

The semantic flow is:

```text
Lalin loop/source semantics
  -> Code/Kernel/Stencil ASDL facts
  -> complete-bank closed micro-op families and NativeTemplateSourceManifest
  -> verified NativeTemplateBank entries built offline
  -> NativeTemplateGraph selection at runtime
  -> copy code and constant-pool bytes
  -> patch node-scoped typed holes, continuations, constants, and runtime symbols
  -> installed native executable entry
```

The bank is not:

- an exact artifact archive,
- a table of all Cartesian combinations,
- a set of "SOAC family names",
- a dedupe pass over generated cells,
- an alternate artifact path for missing template-bank entries.

The bank is:

- a typed implementation vocabulary for loop semantic fragments,
- a set of patchable binary templates,
- a small set of selected supertemplates for important fused shapes,
- a selector that maps normalized ASDL semantics to templates and holes.

## Enumeration Doctrine

Template enumeration must start from the language loop grammar, not from the
machine-bank axes.

Correct root domains:

- producer/control skeletons: range, ND range, tiled range, window, pull/stream
  protocol shapes;
- body expression fragments: input, const, unary, binary, compare, select, cast,
  predicate, window input;
- sink consumers: store, reduce, scan, scatter, scatter-reduce, partition/find
  only when those are real normalized sinks;
- access projections: contiguous, affine, view/slice/bytespan descriptors,
  field projection, SoA component, indexed access;
- schedule fragments: scalar, vector, unroll/tail/reduction strategy only when
  they change binary code shape.

Bad root domains:

- arbitrary `producer x layout x scalar x input_count x point x sink x schedule`
  products;
- exact "cell" records;
- budget-limited enumeration as architecture;
- synthetic stage names that do not correspond to ASDL semantics.

## Native Kernel and Stencil Complete-Bank Contract

Kernel and Stencil lowering use two ASDL layers that must not be collapsed.

**Semantic/native projections** are program-specific. They carry concrete
semantic values, frame roles, storage layouts, runtime value ids, descriptors,
proofs, and patch bindings. These facts are for lowering and binding only.

**Complete-bank micro-op shapes** are bank-specific and finite. They describe one
primitive instruction/control/address/ABI family at a time. They do not summarize
whole bodies, whole expressions, ranks, term counts, field names, or schedules.

The required flow is:

```text
semantic leaf
  -> Native*Projection / Native*LoweringInput    -- program-specific facts
  -> primitive NativeTemplateGraph nodes         -- graph repetition for counts
  -> closed micro-op source family axes          -- complete-bank selection
  -> holes/frame/runtime/constant-pool bindings  -- program-specific payloads
```

It is invalid for a `NativeChunkKernelOp` or `NativeChunkStencilOp` family axis
to carry a concrete semantic node, program identity, full type, full signature,
field name, raw byte size/alignment, rank, count, stride, scale, step, or
compiler flag string. Those facts are represented as graph repetition, holes,
frame/runtime values, constant-pool entries, or named lowering facets.

## Axis Classification

Family axes are fixed only when they are closed machine/control classes that
alter instruction shape, object shape, control shape, or ABI micro-op shape:

- target architecture/ABI/endianness/pointer-width class;
- machine scalar/value class;
- concrete closed operation leaf such as arithmetic, cast, compare, reduction,
  store, scan, scatter, call, branch, return;
- closed logical location class;
- closed successor/extraction class;
- closed vector/unroll/schedule capability leaf.

Patch coordinates are holes or patch formulas:

- scalar constants;
- byte sizes and alignments;
- field and component offsets;
- affine offsets, coefficients, terms, strides, scales, and steps;
- window offsets;
- branch/call/continuation targets;
- stack/frame offsets and frame size.

Runtime/frame parameters remain values:

- base pointers;
- dynamic lengths;
- dynamic starts/stops;
- dynamic descriptor fields and view strides;
- external init values;
- user scalar values consumed by the loop or call.

Counts are graph repetition:

- producer axes;
- window offsets;
- affine/logical terms;
- lanes/effects/bindings/body members;
- ABI parameters/results;
- expression tree depth.

## Supertemplate Policy

Supertemplates should be selected by semantic frequency and instruction benefit,
not generated by full expansion.

Good supertemplate candidates:

- map-to-store chains;
- map-to-reduce/redomap;
- map-to-scan;
- horizontal map/reduce consumers over the same producer;
- window-neighborhood map/store and window reduction;
- field/SoA projection plus simple arithmetic;
- common predicate/select store and reduce forms.

Bad supertemplate candidates:

- every possible depth of expression tree;
- every possible arity stack;
- all combinations of layout and sink when the layout is just a pass-through
  address projection;
- variants that differ only by values that can be holes.

## ASDL Consequences

The native schema models template compilation and runtime copy-patch facts
directly:

- a complete-bank capability product enumerates closed target/scalar/control/
  location classes;
- `NativeTemplateSourceManifest` closes bank cardinality before sources are
  emitted;
- stencil generators, configurations, signatures, hole ordinals, continuation
  ordinals, and relocation declarations describe reusable template identity;
- `NativeTemplateGraph`, node/instance identities, frame/value/control plans,
  edge-copy plans, and node-scoped patch bindings describe program-specific
  runtime copying;
- `NativeStorageLayout`, `NativeValueRepresentation`, `NativeCodeTypeLayoutPlan`,
  `NativeModuleAddressPlan`, `NativeKernelLoweringInput`, and
  `NativeStencilLoweringInput` carry semantic lowering facts without side tables.

Methods live on concrete ASDL leaves. Stencil and Kernel lowering derive
program-specific projections, then emit primitive graph nodes whose families are
closed micro-op axes. Generated bank families do not key on concrete program
bodies. No selector tables, kind strings, cell records, side maps, subset
support lists, or placeholder support values are part of the complete-bank
architecture.

## Superseded Enumeration Warning

Older experiments measured large template streams from broad cross-products.
Those measurements remain useful only as warnings. The current direction is
manifest-first complete capability enumeration plus graph composition, closed
micro-op source families, and supertemplates only when a semantic owner provides
a precise ASDL projection.

