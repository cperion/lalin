# MOM Agent Rules

This is the only MOM-specific agent contract. Keep it short and executable.

## Source of truth

1. Hosted compiler behavior is the semantic oracle. Read the relevant file under `lua/moonlift/` before changing MOM behavior.
   - backend lowering: `lua/moonlift/tree_to_back.lua`
   - typechecking: `lua/moonlift/tree_typecheck.lua`
   - control lowering: `lua/moonlift/tree_control_to_back.lua`
   - validation/facts: matching hosted phase file
2. Wire/layout facts come from `BACK_WIRE_FORMAT.md` and `lua/moonlift/mom/schema/*.mlua`.
3. `lua/moonlift/mom/tags/mom_tags.lua` is generated constants only. Do not infer design from numeric tag values.

## Hard bans

- Do not invent semantics.
- Do not add TODO/FIXME/placeholder/simplified/not-yet/for-now comments.
- Do not emit `CmdTrap` as a fallback unless the hosted compiler has equivalent unsupported behavior.
- Do not write raw command slots in lowerers.
- Do not use `@malloc` or hidden allocation in compiler phases.
- Do not use fake continuation arguments like `?`.
- Do not use `emit foo(...)()`.

## Command emission

`lua/moonlift/mom/back/cmd.mlua` owns command slot layout.

Lowerers should call named command helpers. They must not hand-pack command slots such as:

```moonlift
mb_push_cmd(@{T.CmdSelect}, ...)
mb_stmt_push_cmd(@{T.CmdCompare}, ...)
```

Driver bootstrap code may use compact raw emission only at the product ABI boundary, and only with layout checked against `BACK_WIRE_FORMAT.md`.

## Work protocol

For any implementation change:

1. Read the hosted source of truth.
2. State the exact input/output contract in the commit/response, not in a new doc.
3. Use or add named helpers before changing lowerers.
4. Add or run a focused test.
5. Report exact commands run.

If unsure, stop. Do not guess.
