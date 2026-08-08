# V2 Residual Specialization Inventory

This inventory audits the complete Lua 5.5 V2 opcode vocabulary against one
publication rule:

> A published residual may guard its selected semantic shape and execute it.
  It must not classify runtime values to choose a different implementation.

Program-data decisions remain valid: comparison outcomes, loop termination,
bounds failures, overflow publication, nil termination, and genuinely variable
CPS joins are not implementation dispatch.

## Status summary

The 85 Lua 5.5 opcodes currently divide as follows:

- **Red — 49:** published records still select among semantic implementations.
- **Amber — 15:** one broad shape, but a static choice or fast/slow protocol is
  still bundled, or a modeled mutable protocol state remains in the record.
- **Green — 16:** one semantic shape plus guards and program-data control.
- **Structural — 5:** MMBIN/MMBINI/MMBINK, VARARGPREP, and EXTRAARG are not
  emitted as executable residual occurrences.

The bank contains 74 ordinary records and eight CPS records. CALL, TAILCALL,
RETURN, RETURN0, RETURN1, and CLOSURE account for opcode behavior in the CPS
bank; host_exit and host_tail_return are boundary records.

## Red: semantic dispatch remains in RX

### Constants

- `LOADK`, `LOADKX`: branch on the statically known constant tag.
- Arithmetic/comparison `K` records reconstruct generic constant cells and
  branch on their statically known tag.
- Constant table writes load tag, integer, float, and reference holes and
  select a payload on every execution.

Required leaves are tag-specific: Nil, False, True, Integer, Float, String,
and other exact supported references. Unused holes must not exist in a leaf.

### Arithmetic — opcodes 21-45

All arithmetic, division/modulo, bitwise, shift, and POW records classify
integer/float operand combinations at runtime. Bitwise and shift records also
choose integer versus exactly-integral-float conversion in the residual.

Required leaves include exact operand products such as `IntegerIntegerAdd`,
`IntegerFloatAdd`, `FloatIntegerAdd`, and `FloatFloatAdd`. Conversion, zero
division, and metamethod rejection are guards/exits of the selected leaf, not
routes to sibling implementations.

### Unary — opcodes 49, 50, 52

- `UNM`: integer versus float.
- `BNOT`: integer versus exactly-integral float.
- `LEN`: string versus table.

`NOT` is green: truthiness is the operation's program-data result, not an
implementation selection.

### Comparisons — opcodes 57-65

EQ, LT, LE, EQK, EQI, LTI, LEI, GTI, and GEI classify integer/float/string/
identity alternatives after publication. Each exact operand pair needs its own
leaf. The comparison result and the bytecode `k` edge remain program-data
control.

### Dynamic tables — opcodes 12 and 16

- `GETTABLE`: chooses integer-array versus string-field lookup by key tag.
- `SETTABLE`: chooses integer-array versus string-field write, and bundles
  in-bounds write, growth, field creation, and rejection.

The current constant SETTABLE record is 1,334 bytes and contains the complete
array growth and field growth machinery. It also reconstructs all constant
payload alternatives. This is the measured sieve bottleneck.

Required leaves separate key domain, value shape, table shape, and storage
state. Examples:

- `GetArrayIntegerKeyPresent` / `GetArrayIntegerKeyMissing`
- `SetArrayIntegerKeyBooleanTrueInBounds`
- `SetArrayIntegerKeyBooleanTrueGrow`
- `SetArrayIntegerKeyRegisterValueInBounds`
- `GetFieldExactStringPresent` / `GetFieldExactStringMissing`
- `SetFieldExactStringExisting` / `SetFieldExactStringCreate`

Growth is a cold tail-transfer leaf with an exact continuation, not code inside
the hot write leaf.

### CONCAT — opcode 53

The record scans every operand twice and selects String/Integer/Float formatting
inside both loops. The selected concat shape must carry the exact operand-shape
vector. Its residual directly measures and writes each known operand shape.
Result length and short/long output remain program data.

### Calls — opcodes 68, 69, and 76

CALL, TAILCALL, and TFORCALL classify native closure, builtin closure, invalid
callee, prototype descriptor, fixed/open arguments, and vararg behavior in one
record. Required call-site leaves separate native fixed, native vararg, host
builtin, and rejection shapes. Dynamic callees require an exact guard and a
coherent relearn/reject exit.

### Numeric for — opcodes 73-74

FORPREP and FORLOOP choose integer versus float protocols at runtime. FORPREP
also converts mixed integer/float triples and chooses step sign. The numeric-for
projection must produce exact integer/float and positive/negative-step leaves.
Loop continuation remains program-data control.

### CLOSURE — opcode 79

The record receives a static capture count and four static instack/index pairs,
then branches on those facts at runtime. Capture vectors must select exact
unrolled closure leaves. Open-cell search is mutable identity protocol, not
capture-kind dispatch.

### GETVARG — opcode 81

The record chooses integer-index, string `"n"`, and other-key behavior by tag.
These require separate exact key-shape leaves.

## Amber: narrow but not fully residualized

- `LOADNIL`: patched span is static but executed as a generic count loop.
- `GETUPVAL`, `SETUPVAL`: branch on the genuinely mutable open/closed cell state.
- `GETTABUP`, `SETTABUP`: exact string key, but upvalue state and field
  presence/create protocol remain bundled.
- `GETI`, `GETFIELD`, `SELF`: key domain is exact; present/missing lookup remains
  in one record.
- `SETI`, `SETFIELD`: key domain is exact; in-bounds/existing and grow/create
  paths remain bundled.
- `TBC`: nil/false supported guard remains combined.
- `RETURN`: patched B still chooses fixed versus open-result behavior at runtime.
- `TFORPREP`: supported nil closing shape and rejection are combined.
- `SETLIST`: in-bounds/growth and per-value barrier alternatives are bundled.
- `VARARG`: statically known fixed/all request still branches on `wanted == -1`.

These are second-wave splits. Mutable upvalue state and result-sink joins may
remain explicit protocol branches if the state genuinely changes during one
published image; static alternatives may not.

## Green: exact leaves or legitimate program-data control

- `MOVE`, `LOADI`, `LOADF`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`
- `NEWTABLE`
- `NOT`
- `CLOSE`
- `JMP`
- `TEST`, `TESTSET`
- `RETURN0`, `RETURN1`
- `TFORLOOP`
- `ERRNNIL`

Overflow checks, table/object guards, comparison outcomes, loop termination,
TFOR nil termination, and ERRNNIL's language error condition are valid control.
A guard validates the selected shape; it does not select a sibling behavior.

## Staging ownership violations

The Lua staging layer also retains manual dispatch that must move to concrete
occurrence leaves:

- `ArithOccurrence:append_v2` derives an opcode from `quote_base`.
- `CompareOccurrence:append_v2` derives an opcode from `quote_base`.
- `UnaryOccurrence:append_v2` derives an opcode from `quote_base`.
- `PowOccurrence:append_v2` derives an opcode from `quote_base`.
- `GenericTableOccurrence:append_v2` uses learner-name/opcode `if/elseif`.
- `ReturnOccurrence:append_v2` uses learner-name string selection.
- call-plan return discovery inspects `occ.learner_name`.

Each concrete occurrence leaf must own selection of its exact semantic-shape
product and exact bank record. No quote-name, class-name, or opcode switch may
stand in for leaf dispatch.

## Missing stage product

Current V2 publication happens before runtime operand values exist. The builder
therefore knows bytecode facts and constants but not all dynamic operand shapes.
The current implementation compensated by publishing generic tag-dispatching
records.

Complete specialization needs two sources of facts:

1. **Projection-proven facts:** constants, immediate kinds, numeric-for induction
   types, exact table keys, capture vectors, fixed/open counts, and declared
   builtin identities are resolved before execution.
2. **Learned guarded facts:** genuinely runtime operand tags, table storage
   shapes, dynamic callees, and concat operand vectors are observed in a
   separate learning image. They produce a named per-occurrence shape product
   before the immutable residual image is linked and published.

An observation is never an unguarded proof. The installed leaf validates its
exact shape and uses a named rejection/relearn exit on mismatch. Executing RX
memory is never rewritten.

## Migration order

1. Static constant leaves everywhere; remove generic constant-cell builders.
2. Exact table key/value/storage leaves; isolate growth into cold tail leaves.
3. Integer/float arithmetic, unary, and comparison leaves.
4. Integer/float/sign numeric-for leaves.
5. Exact native/host call-site and TFORCALL leaves.
6. Exact CONCAT operand-vector leaves.
7. Exact closure capture-vector leaves.
8. Split remaining amber static alternatives and remove staging string/opcode
   dispatch.

After each batch, disassembly must prove that a hot leaf contains only its
selected implementation, guards, named exits, and direct successor transfer.

## Concrete correction procedure

Section 21.6 of `NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md` is the binding
implementation blueprint. In summary:

1. Define named family-specific selection products; never a universal shape
   record or tag map.
2. Resolve constants, immediates, induction facts, exact keys, capture vectors,
   counts, and declared builtins during projection.
3. Run unknown occurrences through a separate family-specific learning image
   backed by invocation-owned mmap learning products.
4. Reject conflicting/unseen required observations; never publish a generic
   fallback.
5. Link a different immutable residual image containing one exact C leaf per
   selected product.
6. On guard mismatch, publish typed `SpecializationMismatchV2`; do not execute a
   sibling implementation, rewrite RX, replay effects, or deoptimize.
7. Split the existing bank into closed learning and exact-residual vocabularies.
8. Modify existing V2 stencil files in place; do not create a V3 or parallel
   generic backend.

The first code batch is constants plus tables. Table learning records allocation
site, key domain, value shape, metatable absence, and observed array/field
capacity. Residual NEWTABLE preallocates the guarded observed capacity floor;
hot table leaves contain only exact in-bounds operations; cold tail leaves own
growth and field creation.

Every migrated family adds manifest, deliberate mismatch, disassembly, JIT,
`-joff`, differential, ownership, W^X, and retained-performance gates before
its inventory entries become green.
