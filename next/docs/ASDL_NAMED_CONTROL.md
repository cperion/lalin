# Compiler Organization with Terra ASDL and Named Control

**Status:** design basis for the frozen `next` compiler schema. This document defines
organization and control style; the authoritative schema is
`next/lua/lalin/compiler/schema.lua`. It does not authorize wiring `next/` into the
active compiler.

## 1. Authorities

The redesign starts from two direct sources:

1. Terra's `asdl.lua` implementation and its documented programming style.
2. `values_machines_named_control.md` for named-exit continuation passing.

The current `docs/ASDL_GUIDE.md` is binding doctrine. The archived pre-`next`
compiler-model documents under `docs/archive/compiler-model/` are behavioral
evidence only; no type, inventory, restriction, or abstraction transfers
automatically into the frozen schema.

## 2. The model

Keep three parts distinct:

```text
ASDL values     durable data and semantic alternatives
Lua objects     one computation in progress
named methods   value behavior or nodes in a static control graph
```

ASDL describes values. Ordinary Lua methods add behavior to ASDL classes. A narrow Lua
object holds the live state of one computation. Stable named exit methods implement
continuation passing without a continuation object or control runtime.

The compiler is not one universal machine. Each machine exists only when one concrete
computation has state that must survive calls.

## 3. Use Terra ASDL directly

Create one context:

```lua
local asdl = require 'asdl'
local Compiler = asdl.NewContext()
```

Define products, sums, sequences, optionals, namespaces, external types, and unique
constructors with the syntax implemented by Terra:

```lua
Compiler:Define [[
module Resolution {
  Subject = Name(string name)

  Binding = Local(string name, number slot)
          | Upvalue(string name, number index)
          | Global(string name)

  Scope = (Binding* bindings)
  Entry = (Subject subject, Binding binding)
  Publication = (Entry* entries)

  Rejection = Missing(Subject subject)
}
 ]]
```

Use the runtime as it exists:

- calling a class constructs a checked value;
- products are classes;
- sum constructors with fields are classes;
- a constructor without `()` is a singleton value, not a public class;
- `*` fields contain Terra `List` values;
- `?` fields accept the declared type or `nil`;
- `module` creates a namespace;
- `Extern` registers an exact predicate for a foreign type;
- `unique` memoizes construction by Lua equality;
- `.kind` exists on sum values;
- `isclassof` checks concrete or parent membership.

`unique` gives canonical constructor identity. It does not by itself define authored,
generated, or physical entity identity. Those identities must be modeled when the domain
requires them.

Use `.kind` for inspection, diagnostics, serialization, or a singleton operation when it
is the honest Terra representation. Prefer leaf methods when behavior differs by a
constructor class. If a nullary alternative needs its own method, write `Plus()` rather
than the singleton form `Plus`.

## 4. Put ASDL and its methods together

A concern file defines its ASDL family and then attaches ordinary methods directly. It
does not export a schema fragment for a later installer.

```lua
local Compiler = require('lalin.compiler.context')
local List = require('terralist')

Compiler:Define [[
module Resolution {
  Subject = Name(string name)

  Binding = Local(string name, number slot)
          | Upvalue(string name, number index)
          | Global(string name)

  Scope = (Binding* bindings)
  Entry = (Subject subject, Binding binding)
  Publication = (Entry* entries)
  Rejection = Missing(Subject subject)
}
 ]]

local Resolution = Compiler.Resolution

-- Parent methods must be defined before child overrides.
function Resolution.Binding:name_equals(name)
  return self.name == name
end

function Resolution.Binding:publish(subject, cc, on_resolved)
  return on_resolved(cc, Resolution.Entry(subject, self))
end

function Resolution.Scope:lookup(
    subject, cc, on_resolved, on_rejected)
  for _, binding in ipairs(self.bindings) do
    if binding:name_equals(subject.name) then
      return binding:publish(subject, cc, on_resolved)
    end
  end

  return on_rejected(cc, Resolution.Missing(subject))
end

function Resolution.Name:resolve(
    scope, cc, on_resolved, on_rejected)
  return scope:lookup(subject, cc, on_resolved, on_rejected)
end
```

The final method above should use `self`, not a hidden subject variable:

```lua
function Resolution.Name:resolve(
    scope, cc, on_resolved, on_rejected)
  return scope:lookup(self, cc, on_resolved, on_rejected)
end
```

The erroneous form is shown deliberately: ordinary local code remains ordinary code and
must be tested. ASDL does not replace normal Lua correctness checks.

Terra copies a parent method into the concrete member classes when the parent slot is
assigned. Therefore:

1. define parent methods first;
2. define leaf overrides second;
3. set a parent metamethod to `nil` before replacing an existing metamethod.

No `install`, visitor, handler map, method registry, or generated wrapper is necessary.
The Lua method definition is the implementation.

## 5. Organize context loading directly

Use one small context module:

```lua
-- lalin/compiler/context.lua
local asdl = require 'asdl'
local Compiler = asdl.NewContext()

Compiler:Extern('Origin', function(value)
  return Origin:isclassof(value)
end)

return Compiler
```

Each concern module requires that context, calls `Define`, adds methods, and returns its
ordinary public surface. The compiler root requires concern modules in dependency order:

```lua
local Compiler = require('lalin.compiler.context')

local Source = require('lalin.compiler.source')
local Resolution = require('lalin.compiler.resolution')
local Types = require('lalin.compiler.types')
local Code = require('lalin.compiler.code')
local Analysis = require('lalin.compiler.analysis')
local Lower = require('lalin.compiler.lower')
local Backend = require('lalin.compiler.backend')

return {
  asdl = Compiler,
  source = Source,
  resolution = Resolution,
  types = Types,
  code = Code,
  analysis = Analysis,
  lower = Lower,
  backend = Backend,
}
```

This is ordinary Lua module loading, not a pass manager or plugin registry.

One `Define` call can contain mutually recursive declarations because Terra declares all
names from that call before it resolves their fields. A later `Define` call can refer to
types that already exist in the context. Therefore:

- load files in schema-dependency order;
- place a mutually recursive family in one `Define` call;
- do not invent deferred installers to hide a real schema cycle.

Attaching methods while modules load is safe. Semantic computation does not begin until
the root module has finished loading.

## 6. Named-exit continuation passing

A value or service operation with immediate alternatives receives:

1. its exact input;
2. the exact running machine as `cc`;
3. one stable unbound method for each peer exit.

```lua
return subject:resolve(
  input,
  machine,
  ResolutionMachine.resolved,
  ResolutionMachine.rejected)
```

The producer selects exactly one exit and tail-calls it:

```lua
return on_resolved(cc, entry)
```

The producer does not inspect `cc`. It only forwards the exact object supplied by the
caller. The answer returned by the selected exit is not a semantic result value.

This is continuation passing at the operation boundary. It is not continuation threading
through the machine graph.

## 7. Machines are ordinary Lua objects

A machine belongs in the same concern file when it owns that concern's running
computation:

```lua
local ResolutionMachine = {}
ResolutionMachine.__index = ResolutionMachine

function ResolutionMachine.new(input, subjects)
  return setmetatable({
    input = input,
    subjects = subjects,
    entries = List(),
    cursor = 1,
  }, ResolutionMachine)
end

function ResolutionMachine:advance()
  local subject = self.subjects[self.cursor]
  if not subject then
    return self:freeze()
  end

  return subject:resolve(
    self.input,
    self,
    ResolutionMachine.resolved,
    ResolutionMachine.rejected)
end

function ResolutionMachine:resolved(entry)
  self.entries:insert(entry)
  self.cursor = self.cursor + 1
  return self:advance()
end

function ResolutionMachine:rejected(reason)
  return self:publish_rejection(reason)
end

function ResolutionMachine:freeze()
  local publication = Compiler.Resolution.Publication(self.entries)
  return self:publish_resolution(publication)
end
```

The machine fields are exactly the computation in progress. The methods are named graph
nodes. The strict tail calls are graph edges.

A machine method names its successor directly. It does not receive or forward another
continuation parameter. Store a stable named method in a machine field only when a join,
suspension, or resumption destination genuinely varies.

Reentrancy allocates another machine object. There is no universal compiler machine,
machine hierarchy, scheduler, or control runtime.

## 8. Classify operation lifetimes

Before adding a result type or an exit, classify the lifetime:

| Situation | Form |
|---|---|
| One ordinary output | direct Lua return of the exact value |
| Immediate alternatives | named peer exits |
| State survives calls | narrow named machine |
| Variable join or resumption | stable named method stored on that machine |
| Alternative survives production | ASDL sum or product |
| Public or physical boundary | precise sealed ASDL or foreign value |

Do not create an ASDL result union only because an operation can choose its next control
edge. Do not use named exits when the alternative itself must be stored, traversed,
compared, serialized, or consumed later.

## 9. Suggested compiler layout

The exact names will follow the new schema. The organizational shape is:

```text
lua/lalin/compiler/
  context.lua
  base.lua
  source.lua
  resolution.lua
  types.lua
  code.lua
  topology.lua
  memory.lua
  kernel.lua
  fusion.lua
  materialization.lua
  backend.lua
  host.lua
  init.lua
```

A file should normally contain, in this order:

1. shared-context and prerequisite imports;
2. one coherent `Compiler:Define [[...]]` block;
3. local namespace aliases;
4. parent methods;
5. concrete leaf methods;
6. a narrow machine class when a computation needs one;
7. a public constructor or start function;
8. the returned module surface.

Split a machine into its own file only when it coordinates several already independent
value families. That machine owns sequencing and live state only. It does not become the
semantic authority for the values it carries.

## 10. What the redesign does not assume

The new schema does not automatically retain:

- the active compiler schema;
- the archived O/A/B/C/S/F inventories;
- a fixed number of spines or facets;
- result unions created for immediate branches;
- compiler contexts, worlds, phase objects, or control-state values;
- operation descriptors or authority registries;
- compatibility layers;
- a universal compiler machine.

Existing schemas and implementation code are evidence of required behavior. They are not
the foundation of the new type model.

The architectural terms entity, variant, projection, spine, and facet remain useful. They
are roles built from Terra's small formal vocabulary, not mandatory layers that every
compiler concern must contain.

## 11. Schema reconstruction procedure

The new schema will be designed in this order:

1. List the compiler's observable source, semantic, lower, backend, and host behaviors.
2. Identify values that must survive their producer.
3. Define the smallest Terra ASDL products, sums, sequences, references, and identities
   for those values.
4. Attach behavior directly to the classes that own it.
5. Identify immediate alternatives and name their peer exits.
6. Identify computations whose state survives calls and name the smallest machines that
   own that state.
7. Identify true variable joins or suspension points. Store named methods only there.
8. Keep direct value operations in direct style.
9. Keep semantic rejection distinct from host and physical failure.
10. Add focused constructor, membership, leaf-method, exit, and machine-transition tests.
11. Review the complete schema before authorizing implementation or migration.

Do not begin by translating old result sums or old pass APIs. Begin with values and
observable behavior.

## 12. Expected simplification

If the model is correct, the compiler should become smaller because it no longer needs
parallel control representations. The likely deletions include:

- temporary result leaves inspected immediately;
- continuation wrapper objects;
- generic context and state bags;
- phase and pass registries;
- callback tables and handler maps;
- control schema IR;
- result-to-callback adapters;
- duplicated publication carriers;
- universal coordinators.

These are expected consequences, not deletion quotas. Each deletion must follow from the
new schema and behavior audit.

## 13. Completion conditions

The design is ready for schema transcription when:

- every proposed ASDL declaration names a value that survives production;
- every semantic variant is represented directly by Terra ASDL;
- every class-specific behavior has an owning method;
- every immediate alternative has an exact peer-exit signature;
- every machine names one coherent computation and exact live fields;
- every static successor is visible as a named method call;
- every variable destination is justified by a real join or suspension;
- no installation framework or control registry is required;
- existing compiler behavior has a clear destination in the new model;
- no runtime migration has begun.

The next artifact after this document is the new compiler value schema written directly
in Terra ASDL syntax.
