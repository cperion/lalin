# LUA55 Opcodes 49–52 Specialization: UNM, BNOT, NOT, LEN

Frozen matrix for the unary family. Exact stock semantics from
`lvm.c` (Lua 5.5.0). These opcodes are **standalone**: unlike the
arithmetic family, the Lua 5.5 compiler (`lcode.c:codeunexpval`) emits
**no `MMBIN` companion** for unary operations — `luaT_trybinTM` /
`luaV_objlen` are called inline from the vmcase on the non-primitive
path. The native occurrence therefore falls through at `pc + 1` and
rejects the non-primitive shapes to the host.

## Formats

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 49 | `UNM` | A B | `R[A] := -R[B]` |
| 50 | `BNOT` | A B | `R[A] := ~R[B]` |
| 51 | `NOT` | A B | `R[A] := not R[B]` |
| 52 | `LEN` | A B | `R[A] := #R[B]` |

## Exact semantics (stock `lvm.c`)

### UNM (49)
```c
if (ttisinteger(rb)) { lua_Integer ib = ivalue(rb);
                       setivalue(s2v(ra), intop(-, 0, ib)); }          /* wrap */
else if (tonumberns(rb, nb)) setfltvalue(s2v(ra), luai_numunm(L, nb)); /* -nb */
else Protect(luaT_trybinTM(L, rb, rb, ra, TM_UNM));                    /* __unm */
```
- `intop(-, 0, ib)` is unsigned wrap: `(int64_t)((uint64_t)0 - (uint64_t)ib)`.
  `-MININT` wraps to `MININT` (defined behavior).
- Float: exact negation.
- Non-numeric (string/nil/boolean/table): `__unm` metamethod → **REJECT**.

### BNOT (50)
```c
if (tointegerns(rb, &ib)) setivalue(s2v(ra), intop(^, ~l_castS2U(0), ib)); /* ~ib */
else Protect(luaT_trybinTM(L, rb, rb, ra, TM_BNOT));                       /* __bnot */
```
- `tointegerns` = integer or integral float in int64 range (`F2Ieq`), with
  the 2^63 magnitude fast path.
- `~ib` bitwise complement.
- Else `__bnot` metamethod → **REJECT**.

### NOT (51)
```c
if (l_isfalse(rb)) setbtvalue(s2v(ra));  /* nil or false -> true */
else setbfvalue(s2v(ra));                /* everything else -> false */
```
- Never errors, never invokes a metamethod. Total function over all tags.

### LEN (52)
```c
void luaV_objlen (lua_State *L, StkId ra, const TValue *rb) {
  switch (ttypetag(rb)) {
    case LUA_VTABLE: {
      Table *h = hvalue(rb);
      tm = fasttm(L, h->metatable, TM_LEN);
      if (tm) break;                               /* __len metamethod */
      setivalue(s2v(ra), l_castU2S(luaH_getn(L, h)));  /* primitive len */
      return;
    }
    case LUA_VSHRSTR: case LUA_VLNGSTR:
      setivalue(s2v(ra), cast(lua_Integer, tsvalue(rb)->len)); return;
    default: luaG_runerror(L, "attempt to get length of a %s value", ...);
  }
  luaT_callTM(L, tm, rb, rb, ra, ...);             /* __len metamethod */
}
```
- Short/long string: the interned string's `length` as an integer.
- Table: `luaH_getn` — the length of the leading run of non-nil array
  entries (first boundary). `luaH_getn`'s `alimit` invariant resolves to:
  `LEN = largest i such that array[0..i-1] are all non-nil`. With an
  `__len` metamethod → metamethod path → **REJECT**.
- Any other tag: runtime error → **REJECT** (host raises).

## Guest heap contract for LEN

- Table values must pass identity: `kind == LUA55_OBJECT_TABLE`,
  `heap == frame->heap`, `metatable_reference == 0` (metamethod absence).
  Otherwise **REJECT**.
- The closed subset never places integer keys in the field part (all
  integer-keyed writes are array-part-bounded and out-of-range writes are
  rejected at learn time), so `luaH_getn`'s hash-part extension never
  applies; string-keyed fields do not affect the length.
- String values are immutable interned objects; length is stable.

## Variants (quote = `opcode << 16 | variant`)

| opcode | variant | leaf | result |
|--------|---------|------|--------|
| 49 UNM | 1 | source integer | wrap negate |
| 49 UNM | 2 | source float | `-x` |
| 50 BNOT | 1 | source integer | `~x` |
| 50 BNOT | 2 | source float, `F2Ieq` | `~x` (coerced) |
| 51 NOT | 1 | source nil/false | `true` |
| 51 NOT | 2 | source truthy | `false` |
| 52 LEN | 1 | short string | `length` |
| 52 LEN | 2 | long string | `length` |
| 52 LEN | 3 | table (no metatable) | leading-run length |

Non-listed shapes (e.g. `UNM` on a string, `LEN` on an integer) are
named rejection leaves: the learner records `LUA55_QUOTE_REJECTED` and
the host re-executes the primitive, which runs the metamethod or raises
exactly as stock.

## Guard policy (residuals)

- Tag guards on the source register; a changed tag is a guard exit to the
  primitive PC (`frame->resume_pc = pc`, `LUA55_GUARD_FAILED`).
- `BNOT` float leaf re-coerces with `F2Ieq` at each run (guard-fails if the
  float became non-integral).
- `LEN` table leaf guards table identity (reference, heap, kind,
  metatable absence, collection epoch) and recomputes the leading-run
  length from the **current** array contents each run (shape decision at
  learn time; value recompute at run time — never a recorded length).

## Learner/residual summary

- 4 learners (`lua55_learn_unm/bnot/not/len`)
- 9 residuals:
  - `lua55_residual_unm_int`, `lua55_residual_unm_flt`
  - `lua55_residual_bnot_int`, `lua55_residual_bnot_flt`
  - `lua55_residual_not_falsy`, `lua55_residual_not_truthy`
  - `lua55_residual_len_shrt`, `lua55_residual_len_lng`,
    `lua55_residual_len_table`
- All math inline; no libc calls. The only memory reads are the source
  register and (for `LEN` table) the guest table's array values.
