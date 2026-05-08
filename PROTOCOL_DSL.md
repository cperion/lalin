# Protocol DSL — A Type System for Control Flow

## The problem

ASDL gives us a type system for data. Sum types, product types, tagged unions,
structs. We can describe every shape data can take.

Protocols give us a type system for control flow. Where can execution go?
What does it carry? How do control fragments compose?

A protocol is to a region what an ASDL type is to a value. It describes the
shape of possible exits without saying how to reach them.

---

## Part 1: Protocol declarations

A protocol declares the control-flow interface of a fragment:

```
protocol Scanner(in: ptr(u8), in: i32) {
    hit(pos: i32)
    miss()
}
```

- `in:` — runtime parameters flowing in
- `{ ... }` — named continuation exits, each with typed parameters

A protocol is a first-class type. You can name it, reference it, compose it:

```
protocol Parser(in: ptr(u8), in: i32) {
    ok(value: i32, next: i32)
    err(pos: i32, code: i32)
    eof()
}

protocol Validator(in: i32) {
    valid()
    invalid(reason: i32)
}

protocol NumberDecoder(in: ptr(u8)) {
    int(value: i64)
    float(value: f64)
    error(offset: i32)
}
```

Protocols are pure declarations. No bodies. No blocks. No jumps. They say
"what exits exist" and "what each exit carries."

---

## Part 2: Regions implement protocols

A region body satisfies a protocol:

```
region scan_until: Scanner(p, n)
entry start(i: i32 = 0)
    if i >= n then jump miss() end
    if p[i] == target then jump hit(pos = i) end
    jump start(i = i + 1)
end
end
```

The compiler checks:
- Every exit used in the body is declared in the protocol
- Every exit declared in the protocol is reachable (optional lint)
- Exit parameters match the protocol declaration types

```
region parse_number: NumberDecoder(p)
entry start(i: i32 = 0, sign: i64 = 1)
    if i >= n then jump error(offset = i) end
    if p[i] == 45 then jump start(i = i + 1, sign = -1) end
    ... -- digit parsing
    jump int(value = result * sign)
end
end
```

---

## Part 3: Protocol composition

Protocols compose via wiring. This is the control-graph equivalent of an
ASDL type constructor:

```
compose PacketDecoder = Scanner >> Validate(p, n) {
    Scanner.hit    → Validate.entry
    Scanner.miss   → PacketDecoder.miss
    Validate.valid → PacketDecoder.ok
    Validate.invalid → PacketDecoder.err
}
```

Key properties:
- Every exit from every sub-protocol is wired
- Every parameter type is checked at the wiring point
- Exits can be forwarded up to the parent protocol
- Protocols without bodies can still be used as composition targets

A composite protocol can itself be implemented or further composed:

```
compose RichDecoder = PacketDecoder >> NumberParser {
    PacketDecoder.ok → NumberParser.entry
    PacketDecoder.miss → RichDecoder.miss
    PacketDecoder.err → RichDecoder.err
    NumberParser.int → RichDecoder.value
    NumberParser.float → RichDecoder.value(convert_float_to_int = true)
    NumberParser.error → RichDecoder.err
}
```

Protocol composition IS the control graph. Each arrow is a jump. Each node
is a fragment. The graph is closed, typed, and checkable.

---

## Part 4: Higher-order protocols

Protocols can be parameterized by other protocols:

```
protocol Choice(in: u8) {
    A(in: T)  // T is the parameter protocol
    B(in: T)
}
```

Composition can pipe data through protocol transformers:

```
compose ValidatedParser = Scanner >> Validate {
    Scanner.hit → Validate.entry
    Scanner.miss → ValidatedParser.miss
    Validate.valid → ValidatedParser(forward_hit = true)
    Validate.invalid(reason = 0) → ValidatedParser.err
}
```

---

## Part 5: The complete view

A Moonlift program has three declaration kinds:

```
-- 1. ASDL — data types
struct User { id: i32, age: i32 }
type Result = ok(i32) | err(i32)
type Request = get(path: ptr(u8)) | post(path: ptr(u8), body: ptr(u8))

-- 2. Protocols — control flow types
protocol Parser(in: ptr(u8), in: i32) {
    ok(value: i32)
    err(pos: i32)
}

protocol Handler(in: Request) {
    success(response: ptr(u8))
    not_found()
    error(code: i32)
}

-- 3. Regions — bodies that implement protocols
region parse_int: Parser(p, n)
entry start(i: i32 = 0)
    ...
    jump ok(value = result)
end
end

-- 4. Composition — wiring protocols together
compose RequestHandler = ParseRequest >> Route >> Execute {
    ParseRequest.ok → Route.entry
    ParseRequest.err → RequestHandler.error
    Route.matched → Execute.entry
    Route.no_match → RequestHandler.not_found
    Execute.success → RequestHandler.success
    Execute.failed → RequestHandler.error
}
```

---

## Part 6: What this enables

**Protocols are documentation.** Reading a protocol declaration tells you
exactly what a fragment does — what it needs, how it can exit, what each
exit carries. No need to read the body.

**Protocols are contracts.** A region implementing a protocol is guaranteed
to only exit through the declared continuations. A composition wiring
protocols together is guaranteed to handle every exit. The compiler checks
the whole graph.

**Protocols are first-class values.** You can pass a protocol to a Lua region
factory. You can inspect a protocol's exits at compile time. You can generate
wiring code from protocol declarations. Protocols are data about control flow.

**Protocol composition is the control graph.** The wiring `>>` notation
describes the graph declaratively. Nodes are protocols. Edges are exit-to-entry
mappings. The graph is closed (every exit wired) and typed (every parameter
match checked).

**Protocols separate concerns.** A protocol describes what. A region body
describes how. Composition describes wiring. Each concern has its own syntax,
its own type checking, its own compilation phase.

---

## Part 7: Integration with the existing Moonlift surface

Protocols don't replace regions — they type them:

```
-- Current syntax (implicit protocol):
region parse(p: ptr(u8), n: i32;
    ok: cont(value: i32), err: cont(pos: i32))
entry start() ... end
end

-- With explicit protocol (backward-compatible shorthand):
region parse: Parser(p, n)
entry start() ... end
end
```

The `region name: Protocol(args)` syntax is sugar. The compiler extracts the
exit signatures from the protocol and checks the body against them. Existing
inline continuation declarations still work — they define an anonymous protocol
on the spot.

---

## Part 8: The type system architecture

```
Layer 1 — ASDL types       struct, union, enum, tagged union
                            "What IS the data?"

Layer 2 — Protocol types    protocol declarations and exit signatures
                            "What CAN happen?"

Layer 3 — Region bodies     blocks, jumps, emits, switch
                            "How does it happen?"

Layer 4 — Composition       wiring protocols together
                            "How do the pieces fit?"
```

Each layer is typed. Each layer is checked. Each layer composes.

---

## Summary

| ASDL | Protocols |
|------|-----------|
| Describes data shapes | Describes control flow shapes |
| `struct`, `union`, `enum` | `protocol`, `in:`, `{ exit(T) }` |
| `type Result = ok(i32) \| err(i32)` | `protocol P { ok(value: i32), err() }` |
| Sum types = "this OR that" | Exit protocol = "succeed OR fail OR timeout" |
| Fields are typed | Exit parameters are typed |
| `match` checks exhaustiveness | Compiler checks every exit is wired |
| Type constructors compose | Protocol composition `>>` composes |
| Values are data | Regions are bodies |
