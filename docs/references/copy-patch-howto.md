# The stencil vocabulary problem

### How producer / body / sink + apply / reduce / scan solves copy-patch

*A guide for compiler developers who want to build their own copy-patch JIT.*

---

## The thing nobody tells you about copy-patch

Copy-patch is the compilation technique where you pre-compile a library of code
*templates with holes* ahead of time with a real optimizing compiler, and at
runtime you copy a template's machine code, patch the holes (relocations), and
jump into it. No compiler runs at materialization time, so you get near-zero
codegen latency with full `-O3` quality inside each template. CPython's 3.13 JIT
uses it; the original Xu & Kjolstad paper is the reference.

Here is the part the papers undersell: **the mechanical half of copy-patch is
trivial, and the vocabulary half is the entire problem.**

The mechanical half — extract a template's bytes and relocations from an object
file, `mmap` it, patch the holes, `mprotect` it executable, cast to a function
pointer — is a few hundred lines, it is the same for everyone, and it is fully
solved. You will write it in an afternoon.

The vocabulary half is the question: **what *is* a stencil?** What is the unit
you pre-compile? Get this wrong and the technique collapses:

- **Too fine** (one stencil per IR op, the naive approach): the optimizer runs
  *inside* each stencil but never *across* the seams between them. At runtime
  you concatenate stencils and get no cross-stencil register allocation, no
  global scheduling, no vectorization. Every value round-trips through memory at
  the seam. You are memory-bound and you lose to a normal AOT compiler.
- **Too coarse** (one stencil per whole function): you cannot pre-bake it,
  because every function is different. You are back to invoking a compiler per
  program — which is exactly the thing copy-patch exists to avoid.
- **Ad hoc** (a pile of hand-picked kernels): the library explodes
  combinatorially, you cannot reason about coverage, and you spend your life
  adding special cases.

So the real question of building a copy-patch compiler is: **what is the closed,
finite, composable set of templates that is coarse enough for `-O3` to optimize
the whole hot body, finite enough to pre-bake, and complete enough to cover real
workloads?**

Those three requirements pull against each other. The claim of this document is
that **producer / body / sink, with the sink drawn from {apply, reduce, scan},
is the factoring that resolves all three at once** — and that once you have it,
copy-patch is just the easy mechanical part again.

---

## The one observation everything rests on

**A stencil is a loop. Every loop has exactly three parts.**

```c
ACC acc = init;                 // (3) SINK: how results are consumed
for (idx i = start; i < stop; i += step) {   // (1) PRODUCER: where/what order
    elem v = load(i);           // (1) PRODUCER: address generation + load
    elem r = f(v);              // (2) BODY: the per-element computation
    acc = combine(acc, r);      // (3) SINK: store / fold / prefix-fold
}
```

That is it. That is the whole insight. The three regions of a loop are three
*orthogonal axes*, and a stencil vocabulary is their product:

| Axis | What it owns | Maps to | Varies |
|---|---|---|---|
| **Producer** | iteration domain + address generation | loop header + load | freely (1D, ND, strided, gather, window, tiled) |
| **Body** | per-element computation, a pure fused expression | loop interior (straight-line) | freely (any depth of fused scalar ops) |
| **Sink** | how each result is consumed | store / accumulator / carried prefix | **closed: exactly three** |

The reason this is *the* factoring and not just *a* factoring is the asymmetry
in that last column. The producer and the body vary without bound. The **sink
does not** — and that closed axis is precisely what makes the bank pre-bakeable.

---

## Why the sink is closed at three

There are exactly three things a single pass over a sequence can do with the
stream of values the body produces:

1. **Keep them positionally** → `out[i] = body(in[i])`. This is **apply** (a.k.a.
   map). Embarrassingly parallel; the store is independent per lane.
2. **Collapse them to a point** → `acc = acc ⊕ body(in[i])`. This is **reduce**.
   Parallel under associativity; vectorizes as a tree / horizontal reduction.
3. **Collapse them while emitting the running result** → `out[i] = out[i-1] ⊕
   body(in[i])`. This is **scan** (prefix). Loop-carried; needs a real parallel
   scan algorithm or it stays scalar.

These are the three catamorphism shapes over a sequence: identity, terminal, and
the one that retains intermediate state. **There is no fourth.** Anything you
might reach for — filter, partition, find, count, histogram — is a *composition*
of these three, not a new sink. (Filter = apply a predicate, scan the flags to
positions, scatter. Count = reduce a predicate. Find = reduce with a min-index
combiner.)

That completeness-and-closure is the load-bearing fact. You bake **three sink
templates, forever.** You are not discovering new sinks as workloads arrive; the
sink axis is finished.

---

## Why this makes `-O3` work *for* you instead of *against* you

Because a stencil is `producer + body + sink` = a **complete loop**, not a
fragment, when you hand it to gcc/clang the optimizer sees the entire hot body
as one function. It does cross-op register allocation, instruction scheduling,
and — the prize — **vectorization of the fused body**, all *inside one stencil*.
There are no seams left for it to fail to optimize across, because you fused them
away before emission.

This is the difference between "hope the inliner flattens my call chain" and
"there is nothing to flatten." Contrast the two failure modes:

```c
/* WRONG — per-op stencils, seam survives to runtime */
tmp[i] = square(x[i]);   /* stencil A writes an array */
acc    = reduce(tmp, n); /* stencil B reads it back   */
/* two memory passes; gcc optimized each loop but never the pair */

/* RIGHT — producer+body+sink fused into ONE loop */
for (i = 0; i < n; i++) acc += x[i] * x[i];
/* one pass; the multiply and the accumulate vectorize together */
```

The fused version eliminates the intermediate array (the dominant cost — it was
a full DRAM round-trip) *and* lets the vectorizer build a `vpmulld`+`vpaddd`
reduction loop. You did the fusion; gcc did the platform lowering. Clean
division of labor, and it only works because your stencil is loop-shaped.

---

## The vocabulary in code

Define the three axes as data. (Lua here because no-paren table calls make
constructor syntax read like a grammar; this is the schema, not the runtime.)

```lua
-- BODY is a value, not code: a pure expression tree over named inputs.
-- This is your scalar IR. Recursive sum type; depth is unbounded and free.
local body = apply.add {
  apply.mul { apply.input "a", apply.input "a" },   -- a*a
  apply.input "b",
}                                                   -- => (a*a) + b

-- A STENCIL DESCRIPTOR is just the product of the three axes.
local dot = stencil {
  producer = range1d { index_ty = i32, step = 1 },        -- (1) the loop
  accesses = { read "a", read "b" },                      --     operands
  body     = apply.mul { apply.input "a", apply.input "b" }, -- (2) interior
  sink     = sink.reduce { reducer = add_i32, identity = 0 }, -- (3) fold
}

-- Same producer + same kind of body, DIFFERENT sink => a different kernel.
-- Orthogonality is the point: you don't enumerate kernels, you compose axes.
local vadd = stencil {
  producer = range1d { index_ty = i32, step = 1 },
  accesses = { read "a", read "b", write "out" },
  body     = apply.add { apply.input "a", apply.input "b" },
  sink     = sink.store { dst = "out" },                  -- store, not fold
}
```

Now lower a descriptor to one C function. Producer becomes the loop header and
the loads; body becomes the interior expression; sink becomes the store or the
accumulator. **The facts you proved become C keywords** (`restrict` from the
no-alias proof, unsigned wrap from the integer-semantics fact) — this is what
licenses the vectorizer:

```c
/* lowered from `vadd`: producer=range1d, body=add, sink=store */
/* `restrict` is the alias FACT made syntactic — without it gcc emits a
   runtime overlap check + a scalar fallback and refuses to vectorize. */
void ml_apply2_i32_add(int32_t *restrict out,
                       const int32_t *restrict a,
                       const int32_t *restrict b,
                       int32_t n)            /* <- n is a runtime HOLE */
{
    for (int32_t i = 0; i < n; i++)
        out[i] = a[i] + b[i];               /* body + sink, fused */
}

/* lowered from `dot`: producer=range1d, body=mul, sink=reduce(add,0) */
int32_t ml_reduce2_i32_mul_add(const int32_t *restrict a,
                               const int32_t *restrict b,
                               int32_t n)
{
    int32_t acc = 0;                        /* sink init = identity */
    for (int32_t i = 0; i < n; i++)
        acc += a[i] * b[i];                 /* body=mul, sink=reduce */
    return acc;                             /* sink materializes scalar */
}
```

Compile each at `-O3 -march=native`, extract the `.text` and relocations, and
you have a stencil. The runtime-varying operands (`a`, `b`, `out`, `n`) are
**holes**: pointers and the bound. The compile-time-known parts (the body shape,
the sink kind, the schedule) *specialized the template*. That split — what's
known at bake time vs. what's patched at run time — is exactly the
producer/body/sink axes meeting copy-patch's stage boundary.

---

## The mechanical layer (the easy part — included for completeness)

Holes are relocations. The whole installer is this shape:

```c
void *page = mmap(NULL, len, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
memcpy(page, stencil.bytes, len);
for (each reloc r in stencil.relocs) {
    switch (r.kind) {
      case ABS64: *(uint64_t*)(page + r.off) = value(r);                    break;
      case ABS32: *(uint32_t*)(page + r.off) += value(r);                   break;
      case REL32: *(int32_t *)(page + r.off) = value(r) - (uintptr_t)page - r.off - 4; break;
    }
}
mprotect(page, len, PROT_READ|PROT_EXEC);
fn_ptr = (signature)page;
```

That is the entire "copy and patch." `value(r)` is a base pointer, a length, an
immediate, or the address of `memcpy`/`memmove`. The relocation kinds are the
standard ELF set. This code is identical across every copy-patch compiler ever
built. **Do not spend your innovation budget here.**

---

## What a junior plugs in to build their own

Five layers. The first and last are mechanical; the middle three are where the
vocabulary lives and where all the leverage is.

1. **Installer (mechanical, ~300 lines, solved above).** `mmap` / copy /
   relocate / `mprotect` / cast. Done.

2. **Producer set.** Start with one: `Range1D { index_ty, start, stop, step,
   order }`. That alone covers all 1D streaming. Add `RangeND { axes[] }` for
   tensors, `Window { before, after, boundary }` for convolution/finite-
   difference, `Tiled { tile_sizes[] }` for cache blocking — *only when a
   workload needs them.* Each producer is one loop-header template.

3. **Body type.** A recursive expression sum: `Input | Const | Unary(op,arg) |
   Binary(op,l,r) | Cast | Compare | Select`. This is your scalar IR, and it is
   **data, not a stencil** — you bake *one* apply template and specialize the
   body into it, so the bank does not grow with the number of distinct
   computations. Put the integer-overflow and float-mode semantics *on the body
   nodes*, because that is what drives whether you emit `a+b` or
   `(int32_t)((uint32_t)a+(uint32_t)b)`.

4. **Sink set.** Exactly three: `Store(dst, mode) | Reduce(reducer, identity) |
   Scan(reducer, mode, dst)`. Closed. Do not add a fourth; everything else is a
   composition.

5. **Facts + schedule (the part that makes it fast, not merely correct).** Each
   stencil carries proved facts — `noalias` (→ `restrict`), `alignment`,
   `trip_count multiple_of N` (→ no remainder loop), `reassociable` (→ the
   reduce may be tree-vectorized). These are **proved from your type
   system/contracts, never asserted**, because each one is a license the
   vectorizer acts on and an unsound one silently miscompiles. The schedule
   (vectorize? unroll? lanes? tail?) chooses the *shape* of the stencil before
   you bake it, but **the schedule may not invent a fact** — it can only consume
   the ones the semantics proved.

Then codegen is: producer → loop header + loads, body → interior expression,
sink → store/accumulate, with `restrict` and wrap-semantics emitted from the
facts. Compile `-O3`, extract, bank.

---

## Composition: saturate legal primitive DAGs under budget

Composition is not a second stencil product axis. It is a typed metastencil DAG
over the primitive vocabulary:

- producer nodes: `Range1D`, `RangeND`, `WindowND`, `TiledND`
- body node: `PointExpr`
- sink nodes: `Store`, `Reduce`, `Scan`, `ScatterReduce`
- graph nodes: node, port, wire, candidate, selected cover
- legality facts: same producer, compatible ABI, no intermediate
  materialization, alias/proof obligations, and typed rejects

The generator walks legal primitive DAGs with an explicit budget, selects covers
through the typed legality checker, and materializes selected covers back into
ordinary fused artifacts. The budget is a build/deployment control, not a
semantic family name.

---

## Why it works — the resolution of the three-way tension

Recall the three requirements that fought each other: **coarse** (so `-O3`
optimizes the whole body), **finite** (so you can pre-bake), **complete** (so it
covers workloads). The factoring satisfies all three because it splits them onto
different axes:

- **Coarse** is satisfied by *shape*: a stencil is a whole loop
  (producer+body+sink), so the optimizer sees the entire hot body with no seams.
- **Finite** is satisfied by *the closed axis*: the sink is exactly three, the
  producer is a small enumerated set of shapes, and the body is *data*
  specialized into one template rather than a stencil per computation. The bank
  is finite — in fact it is a small *cache* over an unbounded body-space, and a
  bank miss just synthesizes-and-bakes a new entry.
- **Complete** is satisfied by *the free axes plus budgeted legal composition*:
  producer × body × sink spans the single-pass streaming universe — pointwise
  pipelines, map-reduce, scan, windowed stencils, pooling, reductions — and the
  two things outside it (data-dependent iteration, and fusing across a collapse
  with a *large* result) go to the host language, not the stencil layer.

The deep reason it is *the* vocabulary and not merely *a* convenient one: it
found the single axis along which the stencil set is **closed** (the sink = the
three catamorphisms), separated it cleanly from the axes that vary **freely but
cheaply** (producer shape, body depth), and arranged all three so they map 1:1
onto the **syntactic regions of the generated loop** (header, interior, output).
Closed-axis ⇒ bankable. Free-axes ⇒ expressive. Loop-shaped ⇒ `-O3`-friendly.
Those are the three requirements, one per property, with no conflict left.

---

## The one-paragraph version

Copy-patch's mechanical core — copy bytes, patch relocations, `mprotect` — is
trivial and identical for everyone. The hard, unsolved part is the stencil
vocabulary: the unit of pre-compilation has to be coarse enough to vectorize,
finite enough to pre-bake, and complete enough to cover real code, and those
pull against each other. Factor every kernel as **producer × body × sink**:
the producer is the loop header and the loads, the body is a pure fused
expression tree (data, not code), and the sink is one of the primitive sink
nodes — **store, reduce, scan, scatter-reduce**. Carry proved facts (`noalias`,
alignment, trip-count, reassociability) into the emitted C as `restrict` and
friends so the vectorizer is licensed, not guessing. Compose by saturating legal
primitive metastencil DAGs under a budget, then materialize selected covers as
ordinary fused artifacts. That is the whole compiler. The stencils are the part
everyone gets wrong, and producer/body/sink plus legality-checked composition is
what they were looking for.
