# Lua 5.5 Opcodes 0–8: Frozen Specialization Matrix

Status: phase 2 semantic freeze. This document defines the first complete residual quotation family.

Scope: `MOVE`, `LOADI`, `LOADF`, `LOADK`, `LOADKX`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`, and `LOADNIL`.

## Principle

These nine opcodes contain only one runtime specialization site: the source value of `MOVE`. Every load opcode is
fully determined by the loaded prototype. The recorder must not rediscover constant tags, immediate values, spans,
or successors.

```text
prototype construction
→ select every load quotation
→ reserve MOVE observation slots

first execution
→ MOVE learner observes source tag and selects one MOVE quotation
→ fixed load learners only execute and confirm path position

matching backedge
→ installer emits the selected quotations and patch payloads
```

## Guest value vocabulary

A complete stack-value vocabulary has these 14 user-visible leaves:

```text
NilValue
FalseValue
TrueValue
IntegerValue
FloatValue
ShortStringValue
LongStringValue
LightUserdataValue
FullUserdataValue
LuaClosureValue
LightCFunctionValue
CClosureValue
TableValue
ThreadValue
```

Internal nil variants, prototypes, upvalue objects, and dead table keys are not legal register values. Encountering
one in a guest register is a corrupt-frame rejection, not another specialization.

The current numeric trace frame implements only `IntegerValue` and `FloatValue`. This matrix freezes the eventual
semantics without pretending that collectable ownership already exists. Reference-valued quotations cannot be
enabled until the guest heap and root contract is explicit.

## Physical value contract

The residual ABI needs an exact tagged slot with:

```text
ValueTag tag
64-bit payload
```

The payload alternatives are integer bits, IEEE-754 double bits, a light pointer, a light C function pointer, or a
stable guest-heap reference. A raw LuaJIT GC pointer is forbidden. A guest-heap reference must remain rooted for the
full native call and must have a generation or identity contract suitable for entry guards.

Stack-to-stack writes do not require a heap write barrier. They do require the destination stack slot to remain part
of the guest root set. Heap writes are addressed later by the table and upvalue opcode families.

## Guard vocabulary

A selected `MOVE` quotation has exactly one of these guard owners:

```text
SourceTagProven
SourceTagGuarded(expected_tag, resume_pc)
```

`SourceTagProven` is legal only when the concrete loop owner proves the source tag from an earlier fixed load or a
closed recurrence invariant. First-iteration observation alone never proves it.

`SourceTagGuarded` checks the source before modifying the destination. Failure leaves the frame coherent and exits at
the `MOVE` instruction's exact PC. Guard code is part of the residual quotation, not recorder profiling.

## Opcode 0: MOVE

Static operands: source register `B`, destination register `A`, and fallthrough successor.
Runtime axis: the source value leaf.

| Selected effect quotation | Source tag | Residual effect | Ownership requirement |
|---|---|---|---|
| `MoveNil` | nil | store known nil tag | None |
| `MoveFalse` | false | store known false tag | None |
| `MoveTrue` | true | store known true tag | None |
| `MoveInteger` | integer | copy integer payload; store integer tag | None |
| `MoveFloat` | float | copy float payload bits; store float tag | None |
| `MoveShortString` | short string | copy stable reference; store short-string tag | Guest root |
| `MoveLongString` | long string | copy stable reference; store long-string tag | Guest root |
| `MoveLightUserdata` | light userdata | copy pointer; store tag | External lifetime |
| `MoveFullUserdata` | full userdata | copy stable reference; store tag | Guest root |
| `MoveLuaClosure` | Lua closure | copy stable reference; store tag | Guest root |
| `MoveLightCFunction` | light C function | copy function pointer; store tag | Stable ABI |
| `MoveCClosure` | C closure | copy stable reference; store tag | Guest root |
| `MoveTable` | table | copy stable reference; store tag | Guest root |
| `MoveThread` | thread | copy stable reference; store tag | Guest root |

`A == B` is legal. A guarded self-move still checks the source tag, then performs no semantic change. The stencil may
omit the physical copy only when the guard remains and the successor contract does not require materialization.

Completeness: 14 effect quotations × 2 guard-owner alternatives. The guard implementation can be shared as a prefix,
but every installed combination has one exact listing and one exact side exit.

## Opcode 1: LOADI

Static operands: destination `A` and signed 17-bit `sBx` in the range `-65535..65536`.

| Quotation | Selection | Patch payload | Residual effect |
|---|---|---|---|
| `LoadImmediateInteger` | Always | destination, exact signed immediate | store integer payload and tag |

No runtime facts and no guards are required.

## Opcode 2: LOADF

Static operands: destination `A` and signed 17-bit `sBx`, converted exactly as Lua 5.5 converts the integer to
`lua_Number`.

| Quotation | Selection | Patch payload | Residual effect |
|---|---|---|---|
| `LoadImmediateFloat` | Always | destination, exact double bits | store float payload and tag |

The installer computes the double bits once. The residual code does not perform an integer-to-double conversion on
every iteration.

## Opcodes 3 and 4: LOADK and LOADKX

Both opcodes select from the same seven constant-value alternatives. They remain distinct opcode owners because
`LOADKX` consumes its following `EXTRAARG`.

| `LOADK` quotation | `LOADKX` quotation | Constant leaf | Patch payload | Ownership |
|---|---|---|---|---|
| `LoadKNil` | `LoadKXNil` | nil | destination | None |
| `LoadKFalse` | `LoadKXFalse` | false | destination | None |
| `LoadKTrue` | `LoadKXTrue` | true | destination | None |
| `LoadKInteger` | `LoadKXInteger` | integer | destination, exact 64-bit value | None |
| `LoadKFloat` | `LoadKXFloat` | float | destination, exact double bits | None |
| `LoadKShortString` | `LoadKXShortString` | short string | destination, stable reference | Prototype root |
| `LoadKLongString` | `LoadKXLongString` | long string | destination, stable reference | Prototype root |

Constant type is a static fact. No learner is permitted to inspect it. The prototype owner selects the quotation at
load time and retains any collectable constant owner for at least as long as the RX artifact.

Malformed `LOADKX` sequences, out-of-range constant indexes, unknown constant tags, or a missing `EXTRAARG` reject the
prototype before recording.

## Opcode 5: LOADFALSE

| Quotation | Patch payload | Residual effect |
|---|---|---|
| `LoadFalse` | destination | store false tag |

No runtime facts or guards are required.

## Opcode 6: LFALSESKIP

| Quotation | Patch payload | Residual effect | Successor |
|---|---|---|---|
| `LoadFalseSkip` | destination | store false tag | static `pc + 2` |

The skipped instruction is not recorded and cannot appear in the installed path. This opcode does not need a branch
guard because its successor is unconditional.

## Opcode 7: LOADTRUE

| Quotation | Patch payload | Residual effect |
|---|---|---|
| `LoadTrue` | destination | store true tag |

No runtime facts or guards are required.

## Opcode 8: LOADNIL

Static operands describe `B + 1` destinations beginning at `A`. The span is in `1..256`. It is a patch-time shape,
not a learned specialization axis.

| Quotation | Patch payload | Residual effect |
|---|---|---|
| `LoadNilSpan` | first destination, static span | store nil into every destination |

The installer emits one known-tag nil store for each destination. This produces straight-line residual code without
creating 256 handwritten stencil variants or a recurring runtime loop. Capacity rejection occurs before publication.


## Frozen quotation count

| Opcode | Fixed effect leaves | Runtime-selected effect leaves |
|---|---:|---:|
| `MOVE` | 0 | 14 |
| `LOADI` | 1 | 0 |
| `LOADF` | 1 | 0 |
| `LOADK` | 7 | 0 |
| `LOADKX` | 7 | 0 |
| `LOADFALSE` | 1 | 0 |
| `LFALSESKIP` | 1 | 0 |
| `LOADTRUE` | 1 | 0 |
| `LOADNIL` | 1 compositional span owner | 0 |
| **Total** | **20** | **14** |

There are 34 effect quotation leaves. `MOVE` additionally composes with either a proven or guarded source-tag owner.
The matrix is closed: unknown tags reject rather than selecting a generic tagged copy.

## Learner slots

Only `MOVE` requires a runtime observation slot:

```text
MoveRecordingSlot
├── selected effect quotation
├── selected guard owner
├── expected source tag
├── source displacement
├── destination displacement
└── guard-failure resume PC
```

Every occurrence consumes one bounded recording slot so path order can be validated. The other eight owners write
their statically preselected quotation identity but no dynamic fact. Only `MOVE` derives its quotation from an
observed runtime tag.

## Differential closure tests

The implementation phase must test:

- every one of the 14 legal `MOVE` tags;
- both proven and guarded `MOVE` installations;
- a changed source tag on a later activation and exact guard-failure resume PC;
- `MOVE` with `A == B`;
- `LOADI` and `LOADF` at `sBx = -65535` and `sBx = 65536`;
- `LOADK` and `LOADKX` for nil, both booleans, integer, float, short string, and long string;
- integer extrema and exact floating bits including signed zero, infinities, and NaN payloads for constants;
- malformed and out-of-range `LOADKX` rejection before recording;
- `LFALSESKIP` path exclusion;
- `LOADNIL` spans 1 and 256;
- capacity rejection before RX publication;
- identical results under LuaJIT JIT-on and `-joff`;
- differential results against stock Lua 5.5.0 for every enabled physical value leaf.

## Implementation status

`opcode_00_08_stencils.c`, `build_opcode_00_08_bank.lua`, and `opcode_00_08.lua` implement the first native learner
and residual bank. The extracted bank contains 17 learner stencils and 21 residual stencils. The physical subset
enables nil, false, true, integer, and float.

The learner executes the first trace-shaped path in immutable RX code and records one selected quotation per
occurrence. The installer creates a separate RW residual, emits the selected quotations, installs exact `MOVE` tag
guards, and publishes it RX. Installed calls allocate no recurring Lua memory after warmup.

Short and long strings are now implemented through the explicit owner in `LUA55_GUEST_HEAP_V1.md`. Other reference
values remain named rejected leaves until their physical lifetime contract exists. This is visible incompleteness of
the physical runtime, not a generic fallback or a missing semantic alternative.

The upvalue specialization and scalar implementation continue in `LUA55_OPCODE_09_10_SPECIALIZATION.md`.
