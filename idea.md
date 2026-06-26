# Idea : use the stencil surface to extend moonlift and provide loops that maps directly to stencils

Yes — that is the right instinct.

If Moonlift/Lalin currently lacks native loops, then the feature should feel like:

```text id="u4gk96"
“we added loops”
```

not:

```text id="5f9iqd"
“we added map/reduce/scan combinators”
```

Internally, the loop still lowers to your closed stencil vocabulary:

```text id="dabv7v"
loop + store  → apply
loop + fold   → reduce
loop + prefix → scan
```

But users think in loops first. That gives you better ergonomics and a more normal language surface.

## Proposed syntax family

I would make the main head:

```lua
lln.loop. i [lln.range { 0, n }] {
  ...
}
```

or under a stencil/native namespace:

```lua
lls.loop. i [lls.range { 0, n }] {
  ...
}
```

Since this fills a core language gap, I lean toward eventually making it `lln.loop`, with stencil/native lowering as one backend mode. But for the first implementation, `lls.loop` is safer because it signals restrictions.

## Apply/store loop

```lua
lls.loop. i [lls.range { 0, n }] {
  out[i] = a[i] + b[i],
}
```

Meaning:

```text
producer = Range1D(i, 0, n, 1)
body     = a[i] + b[i]
sink     = Store(out[i])
```

The body may contain pure typed expression work. The only effect is the positional store.

## Reduce loop

Use a loop-local accumulator declaration:

```lua
lls.loop. i [lls.range { 0, n }] {
  acc [lln.i32] = lls.reduce {
    init = 0,
    by   = lls.add,
    step = a[i] * b[i],
  },
}
```

But that is a bit awkward.

I prefer this:

```lua
lls.loop. i [lls.range { 0, n }] {
  lls.fold. acc [lln.i32] {
    init = 0,
    by   = lls.add,
    step = a[i] * b[i],
  },
}
```

and the loop expression returns `acc`:

```lua
local dot = lls.loop. i [lls.range { 0, n }] [lln.i32] {
  lls.fold. acc [lln.i32] {
    init = 0,
    by   = lls.add,
    step = a[i] * b[i],
  },
}
```

Meaning:

```text
producer = Range1D(i, 0, n, 1)
body     = a[i] * b[i]
sink     = Reduce(acc, add_i32, 0)
```

I would use the user-facing word **fold**, not reduce, inside loops. People understand “fold this loop into an accumulator,” and internally it maps to reduce.

## Scan loop

```lua
lls.loop. i [lls.range { 0, n }] {
  lls.scan. acc [lln.i32] {
    init = 0,
    by   = lls.add,
    step = a[i],
    into = out[i],
  },
}
```

Meaning:

```text
producer = Range1D(i, 0, n, 1)
body     = a[i]
sink     = Scan(acc, add_i32, 0, out[i])
```

## General loop shape

The user-facing grammar could be:

```text
loop.index [producer] [optional_result_type] {
  loop_body
}
```

Where the loop body must match exactly one of these forms:

```text
store form:
  one or more positional stores

fold form:
  one fold sink

scan form:
  one scan sink

later:
  controlled compositions
```

At first, keep it strict:

```text
one loop
one producer
one sink kind
pure expression body
no arbitrary calls
no arbitrary mutation
```

That gives good diagnostics and preserves the stencil vocabulary.

## Examples

Vector add:

```lua
lls.kernel. vadd {
  out [lls.out [lln.i32[n]]],
  a   [lls.in_  [lln.i32[n]]],
  b   [lls.in_  [lln.i32[n]]],
} {
  lls.loop. i [lls.range { 0, n }] {
    out[i] = a[i] + b[i],
  },
}
```

Dot product:

```lua
lls.kernel. dot {
  a [lls.in_ [lln.i32[n]]],
  b [lls.in_ [lln.i32[n]]],
} [lln.i32] {
  lls.loop. i [lls.range { 0, n }] [lln.i32] {
    lls.fold. acc [lln.i32] {
      init = 0,
      by   = lls.add,
      step = a[i] * b[i],
    },
  },
}
```

Prefix sum:

```lua
lls.kernel. prefix_sum {
  out [lls.out [lln.i32[n]]],
  a   [lls.in_  [lln.i32[n]]],
} {
  lls.loop. i [lls.range { 0, n }] {
    lls.scan. acc [lln.i32] {
      init = 0,
      by   = lls.add,
      step = a[i],
      into = out[i],
    },
  },
}
```

Stencil body with local pure lets:

```lua
lls.loop. i [lls.range { 0, n }] {
  local x = a[i]
  local y = b[i]
  out[i] = (x * x) + y,
}
```

That should still be one apply stencil:

```text
producer = range
body     = add(mul(load a, load a), load b)
sink     = store out
```

## Why `loop` is better than `apply`

`apply` is compiler vocabulary.

`loop` is programmer vocabulary.

The compiler can still classify the sink:

```text
assignment to out[i]      → apply/store
fold accumulator          → reduce
scan accumulator + store  → scan
```

This makes the surface language feel normal while preserving your algebra.

## Important restriction

Do not make `lls.loop` a general control-flow loop on day one.

Make it a **native regular loop head**.

So this should be allowed:

```lua
lls.loop. i [lls.range { 0, n }] {
  out[i] = a[i] + b[i],
}
```

This should be rejected initially:

```lua
lls.loop. i [lls.range { 0, n }] {
  if weird_dynamic_condition() then
    print(i)
  end
}
```

Diagnostic:

```text
native loop body must be stencil-pure;
unknown call `weird_dynamic_condition` is not allowed in a copy-patch loop
```

Later, if you want general loops, add a separate head:

```lua
lln.while_ ...
lln.for_ ...
```

But keep the copy-patch loop restricted.

## Best naming

I would use:

```text
lls.loop     restricted native/stencil loop
lls.range    producer
lls.fold     reduce sink
lls.scan     scan sink
```

And allow plain assignments for apply/store.

So the model is:

```text
assignment in loop → apply
fold in loop       → reduce
scan in loop       → scan
```

That is ergonomic and still exact.

## Internal lowering

Every `lls.loop` lowers first to typed CFG:

```text
lls.loop
  → Lalin region with loop entry/backedge/exit
  → typed values and explicit effects
  → ownership/fact checking
  → stencilization
```

Then the stencilizer extracts:

```text
Producer:
  from lls.range

Body:
  from pure expression slice

Sink:
  from assignment/fold/scan shape

Facts:
  from types + ownership + requires + schedule
```

That keeps your invariant:

```text
syntax expresses intent;
typed CFG proves legality;
copy-patch only materializes.


```
