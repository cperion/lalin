# Lua 5.5 Real-Program Runner (`run55`)

`run55.lua` runs a **real Lua 5.5 program** (source or compiled chunk)
through the native trace subset: stock `luac` bytecode -> `undump55` ->
per-proto block-graph call plans -> native block execution with
host-mediated boundaries. It is the first end-to-end "program runner" on
top of the opcode banks, and it is deliberately minimal: every library
function crosses the FFI boundary into LuaJIT, while the user's own code
runs natively.

## Pipeline

```
source (.lua)
  -> stock Lua 5.5.0 luac            (subprocess; run55.compile)
  -> undump55                        (bytecode decode)
  -> build_plans                     (DFS global proto indices; per-proto
                                      project_call_plan; CLOSURE occurrences'
                                      relative proto indices patched to the
                                      global indices)
  -> env                             (guest _ENV table: builtin markers for
                                      pairs/ipairs/next/select/rawget/rawset,
                                      host callbacks for print/tostring/math.*,
                                      guest tables for the math namespace)
  -> invoke(main_plan)               (native blocks + host boundaries)
  -> results                         (main's returns converted to host values)
```

## Driver semantics

- **Native blocks**: straight-line runs of the opcode occurrences, cached
  per (plan, block) so loop bodies re-run the installed residual (the
  learner runs once, not per iteration).
- **CALL / TAILCALL**: host dispatch. A guest closure resolves its plan via
  `Lua55GuestClosureV1.proto_index` (patched global index); upvalue cells
  are copied into the callee frame; vararg callees get `vararg_count` +
  registers arranged by the host. A builtin marker dispatches to a native
  leaf (next / rawget / rawset) or a LuaJIT host callback with guest<->host
  value conversion.
- **TFORCALL**: native `next` / `ipairs-iter` iterators or a native closure
  iterator invoked with `(state, control)`.
- **Numeric for**: `FORPREP` is a host boundary running the exact stock
  `forprep` (integer count-down or float limit/step/control; skip
  decision); `FORLOOP` is a **native terminal** that updates the control
  variable, tests the continuation, and reports the back-edge or
  fallthrough pc.
- **Stack top**: a per-frame `top` tracks the last call's result extent so
  `CALL B=0` ("all args") reads the previous call's results correctly
  (e.g. `math.floor(math.sqrt(x))`, `print(a, f())`).

## New native surface added for the runner

- **FORLOOP (73) terminal** — `opcode_for_stencils.c` /
  `opcode_for.lua` / `build_opcode_for_bank.lua`. Integer path: count-down
  (`count - 1`, `idx += step` with intop wrap); float path: `idx += step`,
  `idx <= limit` per step sign. A single residual branches internally on
  the step cell's tag (FORPREP fixes the loop's shape).
- **GETUPVAL closure variants** (9, 11/12): the recursive
  `local function fact` self-capture needs GETUPVAL of a closure.
- **GETI/GETFIELD/SETI/SETFIELD closure variants** (13,9 / 14,10 / 17,9 /
  18,9): `math.floor` etc. are closure-tagged builtins read from the guest
  `math` table.
- **GETTABUP string-key table variant** (15,18): `_ENV.math` is a guest
  table.
- **Block-graph fix**: a compare (with its owned JMP) now starts its own
  block, so a loop back-edge that targets the loop-head compare resolves
  (previously a latent "branch target is not a block start" for
  `while ... do ... end` bodies).

## Value conversions

`guest_to_host` (nil/false/true/int/float/string -> Lua; tables/closures
render as `table: 0x..` / `function: 0x..`). `host_to_guest` writes
nil/false/true; integral doubles in int64 range become guest integers,
non-integral doubles guest floats; strings intern through the guest heap.

## Run

```sh
luajit experiments/copy_patch_cps/lua55_trace/run55_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/run55_test.lua
```

## Speed vs stock

Measured against PUC Lua 5.5.0: **numeric-for and while loops now run
1.7-2.7x faster than stock** (native loop back-edges: each loop SCC is one
RX arena with patched `jmp` links, so an iteration never crosses into the
Lua host). Recursion and generic-for remain host-mediated (a CALL / TFORCALL
boundary per call) and are ~180-190x slower than stock there. The Lua
driver is proper CPS (`InvokeMachine`: named methods, strict tail calls as
the edges, no mutable pc loop). See `RUNNER_VS_PUC.md` for the full table,
the design corrections, and the remaining host-mediated boundaries.

The demo (`run55_demo.lua`) exercises: recursive `fact`, a numeric-for
loop, a while loop, an ipairs generic-for, a pairs generic-for, a table
literal, `math.floor(math.sqrt(...))` with a `B=0` arg chain, string
concat with exact `%.14g`, `rawget`/`rawset`, and `select` with
multi-return — all matching stock stdout byte-for-byte.
