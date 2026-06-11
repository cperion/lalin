# Moonlift Memory API Guide

**Status:** semantic guide for `moonlift.mem` — hosted memory/resource ceremony  
**Audience:** users designing ownership, lifetimes, cleanup, and realtime-safe memory access

Moonlift has raw pointers and views, but raw pointers are not a memory model.
The memory model lives in the hosted API:

```lua
local mem = require "moonlift.mem"
local M = mem.words()
```

The purpose of `moonlift.mem` is to help you design memory explicitly before
there are bodies. It gives names to ownership, lifetimes, borrow protocols,
resource cleanup, arenas, stores, and scope policy.

The slogan is:

```text
Lua writes the ritual.
Moonlift checks the machine.
```

Lua may provide pleasant syntax. The generated design must remain explicit:
products, protocols, regions, handles, owners, and named outcomes.

---

## 1. The central semantic rule

A memory API call is not just a convenience operation. It answers three design
questions:

```text
Who owns the bytes?
How long are they valid?
What named outcomes can happen when I ask to use them?
```

If you cannot answer those three questions, do not write pointer code yet.
Design the memory topology first.

---

## 2. The one-card API

```text
noun "name" { declaration }
owner:verb { request } { outcomes }
borrowed { dynamic_extent }
```

Examples:

```lua
M.store "voices" { ... }
M.arena "block" { ... }
M.resource_table "files" { ... }

voices:borrow { handle = v } {
    borrowed = function(state) ... end,
    stale = function(e) ... end,
    missing = function(e) ... end,
}

state {
    function(s)
        kernel(s.ptr, s.len)
    end
}
```

Meaning:

| Form | Meaning |
|---|---|
| `noun "name" { declaration }` | declare topology and policy |
| `owner:verb { request } { outcomes }` | request an operation through a protocol |
| `borrowed { function(x) ... end }` | enter a dynamic raw-access extent |

---

## 3. The memory words

### `world`

A world is the top-level memory universe for a subsystem.

```lua
local SynthMemory = M.world "SynthMemory" { ... }
```

Use one world when the declarations share one lifetime story. A synth engine,
scene graph, database cache, compiler session, or audio plugin instance usually
gets one world.

A world is inspectable:

```lua
SynthMemory:summary()
SynthMemory:declarations()
SynthMemory:moonlift_declarations()
```

### `scope`

A scope is a policy boundary.

```lua
M.scope "audio" {
    M.rule "no_general_alloc",
    M.rule "no_resource_close",
}
```

Think of a scope as a lane in the lifetime diagram: `host`, `persistent`,
`program`, `audio`, `ui`, `graph`, `scratch`, etc.

Scope names should answer: **under what constraints does this memory operate?**

### `store`

A store is for stable indexed records addressed by typed handles.

Use a store when:

- there are many records of the same shape
- other structures refer to them by handle
- stale handles are possible
- generation checks matter
- allocation/retirement is an explicit operation

```lua
M.store "voices" {
    base = "VoiceState",
    handle = "VoiceRef",
    owner = "VoicePool",
    record = T.VoiceState,
    capacity = "max_voices",
    generation = true,
}
```

This implies a borrow protocol, not direct indexing:

```lua
voices:borrow { handle = v } {
    borrowed = function(state) ... end,
    stale = function(e) ... end,
    missing = function(e) ... end,
}
```

### `arena`

An arena is for grouped allocation with grouped reset.

Use an arena when:

- objects share a lifetime
- individual free is the wrong abstraction
- reset/rewind is the cleanup operation
- temporary allocations must be cheap and visible

```lua
M.arena "block" {
    size = "8mb",
    reset = "audio_quantum",
    realtime = true,
    allocation = "preallocated_only",
}
```

Arena reset invalidates allocations from the previous generation. If something
must survive reset, it does not belong in that arena.

### `resource_table`

A resource table is for external things with explicit close/cleanup semantics:
files, OS handles, plugin resources, host buffers, GPU objects, mapped memory,
or borrowed host-owned buffers.

```lua
M.resource_table "files" {
    kind = "File",
    close = close_file,
}
```

Resource cleanup is a protocol:

```lua
files:close { handle = file } {
    closed = function() end,
    stale = function(e) ... end,
    missing = function(e) ... end,
    already_closed = function(e) ... end,
}
```

There are no semantic destructors in the design. Cleanup is named.

### `rule`

A rule is a declared policy that tools, reviews, and later compiler passes can
check.

Common rules:

```lua
M.rule "no_general_alloc"
M.rule "no_resource_close"
M.rule "no_handle_discovery"
M.rule "no_program_publish"
M.rule "no_pad_cache_rebuild"
M.rule "only_dynamic_extent_raw_access"
```

A rule should state a real constraint, not a wish.

---

## 4. How to reason from a problem to the API

Do this before choosing words.

### Step 1 — Harvest memory things

List every thing that occupies or points at memory:

```text
patch bytes
prepared program
voice states
effect states
PAD tables
render scratch
host event buffer
host output buffers
file handles
```

Do not classify yet. Just harvest nouns.

### Step 2 — Ask who owns each thing

For each noun, write one owner:

```text
patch bytes          host owns, synth borrows during prepare call
prepared program    synth/program scope owns after validation
voice states         SynthStorage owns for synth lifetime
PAD tables           PadCache owns by program generation
event buffer         host owns, synth borrows during render call
output buffers       host owns, synth borrows writeonly during render call
render scratch       synth owns, reset every audio quantum
```

If two owners appear, you have a design bug. Split the object or introduce an
explicit transfer/publish protocol.

### Step 3 — Draw lifetime lanes

Group objects by lifetime:

```text
host call lifetime       patch bytes, event buffer, output buffers
synth lifetime           VoicePool, ControlBank, EffectRack
program generation       PreparedProgram, PadCache tables
audio block lifetime     RenderScratch temporary views
```

Each lane usually becomes a `scope`.

### Step 4 — Choose the memory word

Use this table:

| Problem shape | Use |
|---|---|
| Stable records + handles + stale refs | `store` |
| Temporary memory reset as a group | `arena` |
| External thing requiring close/release | `resource_table` |
| Host-owned buffer borrowed for a call | `resource_table` or explicit borrow protocol |
| Immutable published data | `store` with `publish = "immutable..."` |
| Hot raw pointer access | `borrowed { function(x) ... end }` |
| Realtime constraints | `scope` + `rule` |

### Step 5 — Turn every failure into a protocol outcome

Never hide memory failure in `nil`, `false`, or status codes internally.

Bad:

```lua
local ptr = voices[v]
if ptr == nil then return false end
```

Good:

```lua
voices:borrow { handle = v } {
    borrowed = function(state) ... end,
    stale = function(e) ... end,
    already_free = function(e) ... end,
}
```

Typical memory outcomes:

```text
borrowed
stale_ref
missing
already_free
already_closed
full
exhausted
bad_buffer
wrong_thread
audio_busy
rebuilding
```

### Step 6 — Put raw pointers only at the leaf

Raw access belongs inside a borrow dynamic extent, usually immediately around a
sealed kernel call:

```lua
buffer {
    function(b)
        render_kernel(b.ptr, b.len)
    end
}
```

A kernel should receive already-borrowed views/pointers. It should not discover
ownership, allocate storage, close resources, or chase handles.

---

## 5. Borrow semantics

Borrowing is a dynamic extent:

```text
request borrow
choose named outcome
enter borrowed callback
raw pointer/view is valid inside callback
callback returns
borrow is invalid
```

This is allowed:

```lua
samples {
    function(s)
        gain_kernel(s.ptr, s.len, gain)
    end
}
```

This is not a valid design:

```lua
local escaped
samples {
    function(s)
        escaped = s.ptr
    end
}
use_later(escaped)
```

Current implementation can enforce dynamic extent for `mem.borrowed` wrapper
objects. More advanced escape analysis is future tooling, but the semantic rule
already applies to authored designs.

---

## 6. Generation semantics

Typed handles usually carry a generation:

```moonlift
struct VoiceRef
    index: u32
    generation: u16
end
```

Generation exists to make stale references a named outcome.

When a record is retired, reused, rebuilt, or replaced, bump the owning
generation. Old handles then produce `stale_ref`, not accidental access.

Use generation handles when:

- records can be reused
- data can be rebuilt in place
- readers may keep handles across phases
- realtime code observes published data while another thread prepares the next generation

Do not use generation as an ad hoc global version counter. It belongs to the
store/resource whose stale references it detects.

---

## 7. Arena semantics

Arena allocation is not ownership of individual objects. The owner is the arena.
Cleanup is reset/rewind.

Good arena uses:

```text
parse scratch
program preparation temporary data
render block temporary buffers
compiler phase workspace
```

Bad arena uses:

```text
objects with unrelated lifetimes
objects closed individually
records referenced by stable handles after reset
resources requiring external cleanup
```

If an object must be individually retired, use a store/resource table. If it
must be reset with a group, use an arena.

---

## 8. Resource cleanup semantics

Resource cleanup is not implicit.

The design must say which operation closes a resource and what can happen:

```lua
resources:close { handle = h } {
    closed = function() end,
    already_closed = function(e) ... end,
    stale = function(e) ... end,
    missing = function(e) ... end,
}
```

In realtime scopes, closing resources is usually forbidden:

```lua
M.scope "audio" {
    M.rule "no_resource_close"
}
```

That means the audio path may release a dynamic borrow at return, but it must
not close OS resources, free heap allocations, rebuild caches, or publish new
program generations.

---

## 9. Realtime memory discipline

A realtime scope should normally declare:

```lua
M.scope "audio" {
    M.arena "block" {
        reset = "audio_quantum",
        realtime = true,
        allocation = "preallocated_only",
    },

    M.rule "no_general_alloc",
    M.rule "no_resource_close",
    M.rule "no_handle_discovery",
    M.rule "only_dynamic_extent_raw_access",
}
```

Reasoning rule:

```text
The audio thread may consume already-published facts.
It may mutate preallocated voice/effect state.
It may use preallocated scratch.
It may not discover, allocate, close, rebuild, or publish.
```

For the Zyn synth header this becomes:

```text
host scope        borrowed patch/event/output buffers
persistent scope  SynthStorage, VoicePool, EffectRack
program scope     PreparedProgram and PadCache generations
audio scope       RenderScratch and dynamic borrows only
```

---

## 10. Common anti-patterns

### Direct handle indexing

```lua
local state = voices[v]
```

Use a borrow protocol so stale/missing/free are named.

### Nullable pointer as outcome

```lua
local p = get_buffer(h)
if p == nil then ... end
```

Use `borrowed | stale | missing | bad_format`.

### Persistent raw pointer cache

```lua
global.ptr = borrowed.ptr
```

Cache a handle or generation-tagged reference, not raw access.

### Cleanup by convention

```lua
-- caller must remember to close this later
```

Declare a resource table and close protocol.

### Audio-thread cache rebuild

```lua
if cache_missing then rebuild_pad_cache() end
```

Make `missing_cache` an outcome. Rebuild off the audio thread and publish the
next generation explicitly.

### One arena for everything

If lifetimes differ, arenas differ. A single global arena means the design has
not been cut at lifetime boundaries.

---

## 11. Review checklist

Before implementing memory bodies, ask:

- [ ] Does every memory object have exactly one owner?
- [ ] Does every pointer/view have a declared lifetime?
- [ ] Are all stable references typed handles, not raw pointers?
- [ ] Can every stale/missing/full/closed case be named in a protocol?
- [ ] Are arena reset points named?
- [ ] Are resource close operations explicit?
- [ ] Are realtime scopes free of allocation, close, discovery, rebuild, and publish?
- [ ] Do kernels receive borrowed facts rather than discovering ownership?
- [ ] Can `world:moonlift_declarations()` be reviewed by a newcomer?

If any answer is no, the problem is not ready for pointer code.

---

## 12. Current implementation boundary

As of this guide, `moonlift.mem` provides:

- hosted declaration DSL
- inspectable topology summaries
- generated Moonlift-shaped declaration text
- protocol-shaped operation staging
- callable `mem.borrowed` dynamic extent wrappers

Planned deeper integration:

- direct ASDL lowering for generated products/protocols
- static checks for scope rules
- stronger borrow escape diagnostics
- connection to substrate runtime APIs such as `moonlift_sar.lua`,
  `host_arena_abi.lua`, and `host_arena_native.lua`

Use the API now as the canonical authored memory design surface. Treat the older
memory APIs as substrate or compatibility layers unless you are working on low-level runtime machinery.
