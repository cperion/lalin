# LLBL Hypermedia Architecture

**Status:** design proposal

**Runtime target:** LuaJIT, initially hosted by Luvit

**Implementation status:** the first closed counter slice lives under `lua/hyper`.
It proves direct `head [object]` delivery through `index:host`, typed ASDL counter
transitions, leaf-owned publication, and plain HTML materialization. Luvit hosting,
page/view configuration spines, typed forms, and HTMX delivery remain subsequent
slices.

**Central decision:** the authoritative semantic hypermedia state is an immutable
`ActiveConfiguration`. The browser's current page is its client-visible
`PageRepresentation`, carrying the transitions offered from that configuration.
In the useful shorthand, "the page is the state"; in the precise architecture,
the configuration is the state, the page is its representation, and HTML/DOM is
the materialized boundary image.

This is not a route-first web framework, an HTML template library, or an HTMX
attribute builder. It is an LLBL state-machine language with hypermedia
renderers.

---

## 1. The design in one sentence

> The machine consumes an invocation offered by the current representation,
> publishes the resulting complete active configuration, and derives the next
> representation from that published state.

The repeated runtime loop is:

```text
immutable ActiveConfiguration
  -> semantic PageRepresentation with offered transitions
  -> HTML/DOM boundary image
  -> user invokes one offered transition
  -> typed input decoding and current-authority validation
  -> transition execution
  -> complete ConfigurationUpdate
  -> atomically published next ActiveConfiguration
  -> full-document or local-view materialization
```

The page is therefore not output attached to a route. It is the browser-held
representation of the current machine configuration and its available outgoing
edges.

An affordance proves that a transition was offered from one configuration. It
does not prove that execution is still authorized or conflict-free. Invocation
resolution revalidates the offer capability, mount generation, authority, and
current domain facts.

This does **not** mean that the DOM is the database. Persistent domain state,
authorization state, configuration snapshots, and shared stores remain owned by
explicit server machines. The page is the client's active interaction image: if
a transition is not represented as an affordance, the client has not been
offered that transition.

---

## 2. Design laws

1. **LLBL remains the workbench.** Do not build a second metatable DSL.
2. **Generic control remains LLBL-owned.** Machines and transitions use LLBL
   regions, protocols, processes, products, and state products.
3. **The indexed operand is the reference.** `button [transition]` receives the
   transition value through `index:host`; it does not look up a string.
4. **The active configuration is semantic state.** The page is its client-visible
   representation and carries the affordances available now.
5. **HTML is a representation language.** It is not the application state model.
6. **HTMX is a materializer.** It does not own application semantics.
7. **Semantic identities are not wire identities.** URLs, HTTP methods, form
   names, DOM IDs, selectors, and `hx-*` attributes are derived deployment facts.
8. **Transitions propose configuration updates.** One publication machine creates
   the complete next configuration before delivery planning begins.
9. **Delivery is derived after publication.** Fragment and patch plans are not
   transition semantics.
10. **Definitions and instances are different values.** A reusable page, view, or
    transition is not one active parameterized occurrence of it.
11. **Choices are typed.** ASDL leaves own stored alternatives; LLBL protocols own
    live control alternatives.
12. **No hidden web context exists.** Request, principal, revision, decoding, and
    deployment facts enter through narrow named products or region inputs.
13. **Plain HTML remains valid.** HTMX improves delivery granularity without
    changing the machine's meaning.

---

## 3. The two structures

The design has the same dual structure as the rest of Lalin.

### 3.1 Type forest

The type forest names:

- machine identity;
- page and replaceable-view definitions;
- concrete active state products;
- transition definitions and bound transition instances;
- browser-supplied input fields;
- page/view instances;
- mount occurrences;
- affordances;
- deployment addresses and invocation tokens;
- semantic representations;
- rendered documents, fragments, and patch sets;
- request images and response artifacts;
- revisions, principals, and security capabilities.

### 3.2 Control graph

The control graph names:

- initial entry resolution;
- invocation resolution;
- typed field decoding;
- authorization and stale-state decisions;
- transition execution;
- construction and publication of the complete next active configuration;
- full-document, fragment, patch-set, and external-navigation delivery;
- malformed request, missing invocation, conflict, and rejection outcomes;
- response writing and connection failure.

A web request is not dispatched by a string handler map. It enters a request
machine, resolves to a typed transition instance, and follows named protocol
edges.

---

## 4. LLBL ownership

No new generic state-machine system is introduced.

LLBL already owns:

- staged heads and slots;
- `index:host` delivery;
- role normalization and adaptation;
- symbols and generated names;
- origins and diagnostics;
- role-tagged fragments;
- namespaces and language composition;
- generic regions and protocols;
- process-shaped event machines;
- formatting, indexing, and materialization hooks.

The hypermedia member owns only hypermedia meaning:

- what counts as a page or replaceable view;
- what can be exposed as a browser affordance;
- which typed inputs a form supplies;
- what a transition invocation means;
- how an active configuration becomes a semantic representation;
- how semantic identities project to HTTP and DOM identities;
- which delivery shapes HTML and HTMX can materialize.

`region.` remains the generic LLBL control declaration. A replaceable piece of a
page is called a **view boundary** in the semantic schema so that it is not
confused with LLBL's control-region algebra. The public hypermedia dialect may
present that entity under a qualified `hyper.view` head.

Transitions are implemented by LLBL regions or process-shaped machines. They
are not callbacks stored in page nodes.

---

## 5. Fundamental semantic model

One retained `ApplicationPublicationMachine` owns active-configuration
publication, revision authority, and invalidation. Pages, views, transitions,
and affordances are normally typed values or LLBL regions owned by that machine;
they are not automatically independent child machines.

```text
ApplicationPublicationMachine
  ConfigurationStore
    immutable ActiveConfiguration
      root PageInstance
      MountSpine
      MountInstanceFacet
      AffordanceFacet
```

A genuinely long-running or independently retained child subsystem may own a
separate LLBL process, but nesting a view does not by itself create another
runtime machine.

The active configuration plus its mount topology is authoritative semantic
hypermedia state. Each rendered affordance is an outgoing edge offered from that
configuration.

A transition invocation carries enough identity to answer:

- which transition was offered;
- from which page/view mount it was offered;
- which fixed arguments were already bound;
- which browser fields remain to be decoded;
- which immutable configuration and mount generation offered it;
- which deployment and security policy encoded it.

After execution, application wiring turns domain outcomes into a typed
`ConfigurationUpdate`. The publication machine applies that update to construct
and publish a complete next configuration. Only then does a delivery planner
derive a full HTML document, local HTMX fragment, multiple replacements, or
external navigation artifact.

---

## 6. Required distinctions

### 6.1 Domain world versus browser configuration

The **domain world** contains server-owned application facts: todos, users,
permissions, inventory, or other persistent entities.

The **browser configuration** contains the currently represented page/view
state and available transitions.

They may change together, but they are not one generic `state` record. A
transition consumes only the precise application products it needs and produces
a new domain world or mutates an explicit owner machine through a typed
protocol.

### 6.2 Definition versus instance versus mount

A definition is reusable:

```text
TodoRowView
DeleteTodoTransition
EditPage
```

An instance binds typed arguments:

```text
TodoRowView(todo_17)
DeleteTodoTransition(todo_17)
EditPage(todo_17)
```

A mount is one occurrence of an instance in one active representation. The same
view instance may be displayed twice, but its two mounts need distinct DOM
addresses and invocation origins.

```text
ViewDef        reusable authored identity
ViewInstance   ViewDef plus typed bound arguments
ViewMount      one occurrence in an active representation
```

This distinction prevents duplicate DOM IDs and ambiguous replacement targets.

### 6.3 Transition definition versus transition instance

A transition definition owns a typed input product and a named outcome protocol.
A transition instance binds application arguments and leaves only declared
browser inputs unresolved.

```text
DeleteTodo                         TransitionDef
DeleteTodo(todo_17)                TransitionInstance
DeleteTodo(todo_17) from row #3    RenderedAffordance
```

The rendered URL is merely a deployment encoding of the rendered affordance.

### 6.4 Page versus view boundary

A page is a document, addressability, refresh, and browser-history boundary.

A view boundary is an independently replaceable portion of a page. It may be a
local child machine, but it does not automatically own browser history or a
public entry address.

A page is not merely called a large view because its external protocol
obligations are different.

### 6.5 Semantic state versus boundary image

`ActiveConfiguration` is the authoritative checked hypermedia state. It contains
typed page/view instances, mount topology, and offered-transition relations.

`PageRepresentation` is the client-visible semantic projection of that state.
HTML text, DOM IDs, URLs, hidden form names, headers, and signed tokens are the
boundary image. Both representation and boundary image may be discarded and
regenerated from the active configuration and deployment projection.

### 6.6 Render versus materialize

**Render** derives semantic representation content from an active typed state.

**Materialize** turns that representation into bytes and transport facts for a
specific backend.

```text
active configuration
  -> semantic representation
  -> HTML document materialization

previous/next configuration
  -> semantic replacement plan
  -> HTMX fragment materialization
```

HTMX never decides the next application state.

---

## 7. Identity-first authoring surface

The common surface should remain extremely small.

```lua
hyper.page. counter {
  html.button [decrement] { "−" },
  html.output { count },
  html.button [increment] { "+" },
}
```

The brackets are ordinary LLBL indexed slots:

```text
html.button [increment]
            ^^^^^^^^^^^
            index:host event
            normalized by the hyper.transition_ref role
```

No web-specific `__index` implementation is added beside LLBL.

### 7.1 Normative relationship shapes

```lua
html.a      [destination] { content }
html.button [transition]  { content }
html.form   [transition]  { controls }
html.input  [field]
```

The meanings are:

```text
a [destination]       expose navigation to a page or navigation transition
button [transition]   expose a zero-browser-input transition
form [transition]     expose a transition whose remaining inputs come from controls
input [field]         bind a control to one exact transition input identity
```

The expected role gives the indexed value meaning. There is no string lookup and
no generic option table.

### 7.2 What is deliberately absent

The authored language does not contain:

```lua
a { href = "/todos/17" }
form { action = "/todos", method = "post" }
button { hx_post = "/todos", hx_target = "#todos" }
transition:on_success("replace", "#todos")
router.post("/todos/:id", handler)
```

The following concepts are also absent from the common surface:

- `invoke`;
- `on_success`;
- `replace`;
- `swap`;
- `push_url`;
- `target`;
- HTTP methods;
- route patterns;
- DOM IDs and selectors.

Those facts are inferred from typed relations or assigned in lower projections.

### 7.3 Names are declarations, not references

A declaration may use LLBL's spaced-dot name channel:

```lua
hyper.page. home { ... }
```

The name supplies source identity, origins, diagnostics, indexing, and generated
address hints. Other declarations refer to the resulting value or LLBL symbol,
never to `"home"`.

Forward references use LLBL source symbols and language resolution. They do not
require string route names.

### 7.4 Page references can adapt to navigation

When an anchor's indexed role expects a navigation transition, a page instance
may adapt to a typed navigation value:

```lua
hyper.page. home {
  html.a [editing] { "Edit" },
}

hyper.page. editing {
  html.a [home] { "Cancel" },
}
```

The adaptation belongs to the role. The `a` head remains a thin staged
constructor.

### 7.5 Forms refer to exact input identities

A transition's browser inputs are entities, not wire names. The intended form is
conceptually:

```lua
html.form [save] {
  html.input [save.title],
  html.button { "Save" },
}
```

`save.title` denotes the exact field identity declared by `save`; it is not used
as a string key by the runtime. The deployment projection later assigns a form
name such as `_f3`.

The form checker verifies that:

- every required browser input is supplied;
- no control claims a field belonging to another transition;
- repeated controls are legal for the declared field cardinality;
- fixed bound arguments are not resubmitted as untrusted hidden strings;
- a button-only affordance does not expose a transition requiring browser input.

---

## 8. Transitions are LLBL machines

A transition is not a Lua callback attached to an element. Its behavior is an
LLBL region or a process-shaped machine with:

```text
input product
+ complete internal state products
+ named outcome protocol
+ transition body
```

The transition's input product separates:

- arguments bound when the transition instance is constructed;
- browser-supplied fields decoded from the invocation;
- narrow runtime capabilities explicitly required by the machine.

There is no generic request/session/context argument.

### 8.1 Consumer-owned outcomes

Transitions do not all return one universal result record. Their protocols are
shaped from the caller's needs.

A todo save transition may expose:

```text
saved(todo)
invalid_title(message)
conflict(current_revision)
unauthorized
```

Application wiring maps each outcome to a configuration operation:

```text
saved          -> ReplaceOrigin(TodoListView(next_snapshot))
invalid_title  -> ReplaceOrigin(EditTodoView(submitted_value, message))
conflict       -> Navigate(ConflictPage(current_revision))
unauthorized   -> Navigate(SignInPage(return_capability))
```

`ReplaceOrigin`, `ReplaceMount`, `Navigate`, and transactional multi-mount
updates are concrete configuration-update alternatives. Their leaf methods apply
the update to the source configuration and return a complete candidate next
configuration. They are not HTMX swap instructions.

The publication machine commits the candidate configuration with the relevant
domain-world operation and produces a `PublishedConfiguration`. HTTP and HTMX
code sees only the published state and a later delivery projection.

### 8.2 Live control versus stored alternatives

Use LLBL protocols for outcomes consumed immediately by the enclosing request
and publication machines.

Use ASDL sums where an alternative must genuinely be retained across a Lua or
asynchronous boundary, such as a configuration update, published result, delivery
plan, or decoded request image. Every concrete ASDL leaf owns its validation,
application, and materialization methods.

Do not turn a live transition protocol into:

```lua
{ ok = true, kind = "replace", target = ..., error = nil }
```

### 8.3 Safe navigation and effectful submission

Navigation and mutation are different semantic capabilities, not an HTTP method
string or boolean flag.

- A navigation transition is replayable and may be exposed by an anchor.
- An effectful transition is exposed by a form or suitable command control.
- A materializer chooses GET-like or POST-like transport from that semantic
  capability.
- A head rejects an incompatible transition through role diagnostics.

Concrete transition leaves own these operations; no selector function branches
on transition class names.

---

## 9. Active configuration and transition scope

The initial runtime policy is an explicit server-held `ConfigurationStore`. It
owns immutable configuration snapshots and resolves opaque `ConfigurationRef`
handles with generation checks. This is not a hidden session table: the store,
records, handles, resolver protocol, retention, and invalidation authority are
named parts of the application machine.

A browser document carries a capability naming one immutable configuration.
Each successful transition publishes a new configuration rather than mutating
the old snapshot. Back navigation and multiple tabs may therefore retain
different configurations. Current domain authority is still checked when an old
affordance is invoked.

Each rendered affordance records its lexical origin mount and mount generation.
This supplies precise scope without authored target syntax.

```text
button inside CounterView mount M generation G
  -> invocation offered by ConfigurationRef C at M/G
  -> transition chooses ReplaceOrigin(CounterView(next_count))
  -> publication applies the update to C and publishes C2
  -> delivery planner derives replacement of M from C -> C2
```

The authored program never says `hx-target="#counter"`. The deployment projection
knows which generated DOM identity represents mount `M`.

### 9.1 Local replacement

Local replacement is explicit semantic control: `ReplaceOrigin(next_view)` names
the invocation origin as the configuration slot to update. It is not inferred by
inspecting whether the returned view has the same class or family.

The update leaf validates the origin capability, constructs the new mount facet,
retires replaced descendants, and returns a complete candidate configuration.

### 9.2 Page replacement

`Navigate(next_page)` replaces the root page configuration and establishes the
new document/history boundary. Plain HTML later materializes a document. An
HTMX-capable delivery planner may derive boosted navigation while preserving
equivalent refresh and history behavior.

### 9.3 Multiple configuration replacements

A transition may choose a transactional configuration update containing named
entries:

```text
ConfigurationReplacement
  live mount capability
  next ViewInstance
```

The update carries `many [ConfigurationReplacement]`, never a Lua map from
selectors to HTML. Publication applies all replacements or publishes none. A
later HTMX delivery plan may materialize secondary changes as out-of-band
fragments.

### 9.4 Ancestor and sibling replacement

`ReplaceMount(capability, next_view)` is legal only when the transition outcome
carries a live reachable mount capability. A child cannot forge an ancestor
selector. The update leaf checks replacement authority and topology.

### 9.5 Nested invalidation

Replacing a parent retires its descendant mount generations. Invocation
capabilities issued by retired descendants become stale. Unchanged mounts retain
their generations, so a local update does not automatically invalidate unrelated
affordances.

### 9.6 Delivery planning

Delivery is derived from the source configuration, the published next
configuration, the selected configuration-update leaf, and renderer capability.
Transitions never produce fragment or patch sets directly. The first planner uses
the explicit update topology; a future delta planner may optimize the same
published state change.

---

## 10. Schema vocabulary

The following is a vocabulary sketch, not a commitment to one giant schema
module. Source, checked, deployment, runtime, and wire facts belong in separate
ASDL modules.

### 10.1 Source entities

```text
HyperApplication       stable language member/application identity
PageDef                authored document-state family
ViewDef                authored replaceable-state family
TransitionDef          authored LLBL transition machine identity
InputFieldDef          one browser-supplied transition input
EntryDef               externally reachable initial page capability
TriggerSite            authored element-to-transition relation
```

`PageDef`, `ViewDef`, `TransitionDef`, `InputFieldDef`, and `EntryDef` are unique
entities.

### 10.2 Generated concrete instance products

The core must not use `any`, `table`, a generic value array, or a map for bound
arguments. Each parameterized definition generates a precise instance product.

For example:

```text
TodoRowInstance
  definition: TodoRowView
  todo: TodoRef

DeleteTodoInstance
  definition: DeleteTodoTransition
  todo: TodoRef

EditTodoPageInstance
  definition: EditTodoPage
  todo: TodoRef
  revision: TodoRevision
```

Schema generation is a build/assembly stage, never a runtime side effect:

```text
LLBL member grammar + normalized application declarations
  -> application-specific ASDL schema family
  -> install generated leaves and required leaf methods
  -> close and validate the ASDL context
  -> construct authored/checked/runtime ASDL values
```

Generated page, view, transition, field, and instance leaves join their declared
parent sums before the context closes. Semantic methods do not execute until the
closed context and required-method checks succeed. Each assembled application
owns a distinct schema context; values from different application contexts do
not share semantic identity accidentally.

There is no core shape resembling:

```text
Instance(definition, args: map[string, any])
```

### 10.3 Active-configuration spine and facets

Topology has one source of truth:

```text
ConfigurationSpine
  configuration identity
  application identity
  root mount identity
  ordered MountSpineEntry values

MountSpineEntry
  mount identity
  parent mount identity when non-root
  sibling ordinal
  mount generation
```

Facts aligned to that topology live in facets:

```text
MountInstanceFacetEntry
  mount identity
  concrete PageInstance or ViewInstance

MountAffordanceFacetEntry
  mount identity
  ordered RenderedAffordance values

RenderedAffordance
  affordance identity
  transition instance
  offered mount generation
```

Parent, order, generation, and reachability are not duplicated in page/view
records. Facets align through mount identity. Derived lookup acceleration may
exist in a runtime machine, but it is rebuildable from this typed projection and
is never the semantic source of truth.

### 10.4 Deployment products

```text
EntryBinding
  EntryDef
  generated public address
  concrete PageLocatorCodec

TransitionBinding
  TransitionDef
  generated TransitionAddress
  ordered InputFieldBinding values
  concrete InvocationTokenPolicy

InputFieldBinding
  InputFieldDef
  generated WireFieldName
  concrete InputFieldCodec

MountBinding
  mount identity
  generated DomIdentity

DeploymentProjection
  application identity
  entry bindings
  transition bindings
  field bindings
  concrete HyperRendererCapability
```

`PageLocatorCodec`, `InvocationTokenPolicy`, `InputFieldCodec`, and
`HyperRendererCapability` are precise ASDL products or sums. They are not stored
callbacks. Their concrete leaves own encoding, decoding, signing, verification,
and capability checks.

Keyed relations are named entry products carried under `many`. The semantic
projection is not a route table hidden in Lua.

### 10.5 Runtime request products

```text
WireRequestImage
  bounded method bytes
  bounded target bytes
  ordered HttpHeaderField values
  bounded body bytes/chunks

InvocationEnvelope
  deployment identity
  encoded invocation identity
  ConfigurationRef
  origin mount identity
  offered mount generation
  concrete InvocationProof

DecodedInvocation
  concrete TransitionInstance
  concrete typed browser-input product
  invocation origin
```

`DecodedInvocation` is generated per transition family. It does not contain a
loose field table.

### 10.6 Configuration updates and publication

Stored update alternatives include concrete leaves such as:

```text
ReplaceOrigin
  next ViewInstance

ReplaceMount
  live MountCapability
  next ViewInstance

Navigate
  next PageInstance

ReplaceMounts
  ordered ConfigurationReplacement values
```

Each leaf owns `apply_to_configuration`. Application produces a complete
`CandidateConfiguration`, and the publication machine returns a typed outcome:

```text
published(PublishedConfiguration)
stale(CurrentMountGeneration)
conflict(DomainConflictFacts)
rejected(AuthorityReject)
```

The exact protocol remains consumer-owned; it is not one optional result record.

### 10.7 Delivery alternatives

After publication, a delivery planner may retain an ASDL delivery value with
concrete leaves such as:

```text
DeliverDocument
  PublishedConfiguration
  PageRepresentation

DeliverLocalView
  PublishedConfiguration
  origin mount identity
  ViewRepresentation

DeliverViewSet
  PublishedConfiguration
  ordered ViewDeliveryEntry values

DeliverExternalNavigation
  PublishedConfiguration
  checked ExternalLocation
```

These alternatives are derived from published semantic state. Each leaf owns its
lowering to a materialization plan.

### 10.8 Materialization alternatives

```text
HtmlDocumentArtifact
  HttpStatusIntent
  ordered HttpHeaderField values
  HtmlByteSequence

HtmxFragmentArtifact
  HttpStatusIntent
  DomIdentity
  HtmlByteSequence

HtmxViewSetArtifact
  HttpStatusIntent
  primary HtmlByteSequence
  ordered OutOfBandHtmlFragment values

ExternalNavigationArtifact
  HttpStatusIntent
  checked ExternalLocation
```

Artifacts contain precise byte/fragment products, not body-writer callbacks.
Their concrete leaves own HTTP writing behavior. The Luvit adapter does not
switch on a `kind` string.

---

## 11. Schema ownership and methods

Semantics live on the values that own them.

Representative method boundaries are:

```lua
checked = application:check()
deployment = checked:deploy(deployment_request)
representation = active_configuration:render(render_input)
decoded = field_binding:decode(field_decode_input)
resolution = deployment:resolve(wire_request)
update = invocation:execute(execution_input)
candidate = update:apply_to_configuration(configuration_input)
published = publication_machine:publish(publication_input)
delivery = published:plan_delivery(delivery_input)
artifact = delivery:materialize(materialization_input)
written = artifact:write_luvit(write_input)
```

The exact inputs and results are named ASDL products or protocols. There is no
`ctx`, `opts`, `env`, or loose result table.

For every union operation, concrete leaves own behavior:

```lua
function Hyper.DeliverDocument:materialize(input)
  ...
end

function Hyper.DeliverLocalView:materialize(input)
  ...
end
```

Forbidden shapes include:

```lua
if delivery.kind == "document" then ... end
handlers[transition.name](request)
schema.classof(node) == Hyper.FormAffordance
```

Heads only stage and normalize authored values. They do not become a second
semantic dispatcher.

---

## 12. Source, checked, and lower worlds

The world line is:

```text
LLBL grammar/member + normalized application declarations
  -> closed ApplicationSchema
  -> AuthoredHyperApplication
  -> CheckedHyperApplication
  -> DeployedHyperApplication

ActiveConfiguration
  -> PageRepresentation
  -> MaterializationPlan
  -> HttpArtifact
```

At request time:

```text
WireRequestImage
  -> ResolvedInvocation
  -> DecodedInvocation
  -> application transition protocol
  -> ConfigurationUpdate
  -> CandidateConfiguration
  -> PublishedConfiguration
  -> DeliveryPlan
  -> MaterializationPlan
  -> HttpArtifact
```

Each arrow answers one question:

- **assemble schema:** which precise application leaves and products exist?
- **check:** are all identities, roles, input bindings, and transition
  capabilities valid?
- **deploy:** what externally addressable image realizes those valid identities?
- **resolve:** which typed deployed offer capability did the request present?
- **decode:** does the wire payload construct the transition's exact input
  product?
- **execute:** which domain outcome and configuration update does the transition
  select?
- **publish:** can the complete candidate configuration and domain change become
  authoritative atomically?
- **plan delivery:** which representation projection realizes the published
  change for this client capability?
- **materialize:** how does that delivery become HTML/HTMX/HTTP facts?
- **write:** how are those facts emitted through this host runtime?

LLBL role fragments, closed application ASDL values, and executable LLBL region
machines are connected by explicit projections; they are not interchangeable
objects. No source node is mutated to accumulate later-phase addresses, DOM IDs,
codecs, revisions, or rendered strings.

---

## 13. HTML language member

HTML should be its own LLBL language member composed with hypermedia. Hypermedia
must not duplicate the HTML vocabulary.

The HTML member owns:

- element and attribute roles;
- content models;
- text and attribute escaping;
- document structure;
- semantic formatting;
- HTML byte materialization.

The hypermedia member extends the compatible HTML affordance heads with indexed
transition slots:

```text
html.a      + hyper.navigation_ref
html.button + hyper.transition_ref
html.form   + hyper.transition_ref
html.input  + hyper.input_field_ref
```

The initial HTML vocabulary should be intentionally small and concrete. New
standard or custom elements are added as dialect extensions with precise leaves.
Do not centralize semantics in a generic `{ tag: string, attrs: map }` node.

User text is escaped. Trusted markup, if eventually required, must be a precise
boundary product produced by an explicit sanitizer or trusted-source operation;
it is not a generic `Raw` escape leaf.

---

## 14. Rendering model

Rendering is pure whenever possible:

```text
active typed page/view instance
  -> semantic HTML/hypermedia tree
```

A renderer may read only facts present in its narrow render input. If rendering
depends on application data, the transition or page-resolution machine first
constructs a snapshot/product containing that data. Render methods do not query
ambient stores by convention.

### 14.1 Full HTML

A full-document materializer emits:

- document structure;
- generated entry and invocation addresses;
- generated field names;
- generated mount DOM identities;
- ordinary links/forms that work without HTMX;
- optional HTMX bootstrapping assets selected by deployment capability.

### 14.2 HTMX enhancement

The HTMX materializer derives:

- request address and method;
- target mount DOM identity;
- swap behavior implied by the replacement boundary;
- history behavior implied by page versus local-view delivery;
- out-of-band fragments for patch sets.

Authored semantic nodes never contain `hx-get`, `hx-post`, `hx-target`,
`hx-swap`, or `hx-push-url`.

### 14.3 No semantic stream layer

HTML output may be emitted incrementally, but that is a materializer or
process/GPS concern. Do not introduce a generic semantic `stream` abstraction.
A small prototype may buffer a bounded response; a later writer can consume the
same render operation region incrementally.

### 14.4 Patch planning

The first implementation derives delivery from the concrete
`ConfigurationUpdate` leaf and the published configuration:

- `Navigate` -> document delivery;
- `ReplaceOrigin` -> origin-mount view delivery;
- `ReplaceMount` -> selected-mount view delivery;
- `ReplaceMounts` -> ordered multi-view delivery.

This is not transition-authored HTMX intent. The update first changes the
semantic configuration; delivery planning then projects that published change.

The prototype does not begin with a virtual-DOM diff algorithm. A later
`RepresentationDeltaPlan` may compare stable configuration spines, but it must
remain a typed projection and an optimization of the same published transition.

---

## 15. HTTP projection

HTTP is a deployment boundary, not the authored identity model.

### 15.1 Addresses

The deployment phase assigns addresses to entries and transition families. An
address is not the identity of the page or transition.

Page addressability is an explicit semantic alternative:

```text
AddressablePage
  concrete generated PageLocator product
  PageLocatorCodec capable of reconstructing the page configuration

EphemeralPage
  retained ConfigurationRef capability
  explicit retention/expiry policy
```

Parameterized addressable pages generate precise locator products; they do not
decode a route-parameter map. Refresh, bookmarks, and browser history reconstruct
the configuration through the locator codec. Ephemeral pages use an opaque
configuration capability and are bookmarkable only for that capability's
retention lifetime.

```text
EditTodoPageLocator(todo_17)
  -> /_h/p4/a17

EditTodoTransition(todo_17)
  -> /_h/t7/a17
```

A different deployment may assign other addresses without changing authored
references or machine semantics. Public human-readable addresses are supplied by
a typed address-policy product and still bind page/transition identities.

### 15.2 HTTP methods

Methods are selected from semantic transition capabilities:

- navigation/replay-safe transitions materialize as safe retrieval;
- effectful transitions materialize as protected submission;
- external interoperability may request a precise HTTP capability at the
  deployment boundary.

The semantic transition is never selected by comparing a method string.

### 15.3 Form encoding

Each input field leaf owns wire decoding. Examples include text, integer,
boolean-control, bounded text, and application-defined identity codecs.

Decoding has named outcomes such as:

```text
decoded(value)
missing
malformed(reason)
too_large(limit)
multiple(count)
```

The transition runs only after its complete typed input product has been
constructed.

### 15.4 Status and headers

Domain outcomes do not directly equal HTTP status codes. Application wiring
chooses a representation and status intent; the HTTP materializer chooses the
wire status and required headers.

Known semantic headers receive precise products. Open external header bytes may
exist only at the terminal HTTP adapter boundary and must not become internal
semantic dispatch keys.

---

## 16. State publication, concurrency, and staleness

`ConfigurationStore` owns immutable configurations and resolves typed
`ConfigurationRef` handles. A configuration contains a mount spine whose entries
have independent generations. Rendered affordances bind:

```text
ConfigurationRef C
TransitionInstance T
origin Mount M
MountGeneration G
```

Invocation resolution checks that `M/G` was an offered live mount in `C`. A local
update creates a new configuration while preserving generations for unchanged
mounts. It therefore does not invalidate unrelated affordances merely because
some other mount changed.

Domain stores carry their own application-specific revisions or lease facts.
Transition execution revalidates those facts independently of mount liveness. An
old configuration may still be navigable while an old mutation is rejected by
current domain authority.

The `ApplicationPublicationMachine` owns atomic publication. A successful
operation commits the domain effect and inserts the complete next configuration
as one protocol operation, or uses an explicitly modeled prepare/commit protocol
when the domain store requires it. The renderer never publishes a page claiming
a domain state that was not committed.

Back navigation and multiple tabs naturally retain distinct immutable
configuration references. Retention and retirement are explicit store protocols,
not hidden session cleanup.

---

## 17. Security model

Hypermedia availability is not authorization. A transition must still validate
its principal and authority because clients can replay or forge wire requests.

The architecture requires explicit products/capabilities for:

- authenticated principal;
- transition authority;
- CSRF or invocation proof;
- configuration reference and mount generation;
- bounded request body;
- trusted external navigation;
- token signing and verification;
- deployment identity.

There is no ambient `request.user`, global session, or hidden middleware context.
A transition receives only the authority product its signature declares.

### 17.1 Invocation tokens

A rendered affordance may materialize as a signed invocation token containing or
naming:

- deployment identity;
- transition identity;
- bound argument identity;
- configuration reference;
- origin mount and offered mount generation;
- expiry/security facts required by the selected policy.

Token policies are real deployment alternatives, for example signed stateless
capabilities versus server-held opaque capabilities. They are not one product
with `signed`, `session`, and `stateless` booleans.

### 17.2 XSS and external boundaries

- Text and attribute values are escaped by default.
- Generated DOM identities and addresses are encoded by their owning leaf.
- External URLs use an explicit `ExternalLocation` value.
- External redirects require a checked external-navigation capability.
- Trusted markup requires a narrow trusted/sanitized constructor.
- Browser-submitted hidden values are untrusted wire inputs, not semantic object
  references merely because the renderer generated them.

---

## 18. Luvit runtime adapter

The currently installed runtime is suitable for the first host:

```text
luvit 2.18.1
LuaJIT + libuv + HTTP runtime
```

Luvit is an adapter, not the framework's semantic center.

### 18.1 Runtime owner

A `LuvitHyperServer` machine owns:

- the Luvit server handle;
- the deployed application projection;
- the explicit `ConfigurationStore` capability;
- the `ApplicationPublicationMachine` capability;
- request-size policy;
- connection/write capabilities;
- token verification capability.

It does not own application transition semantics. The initial Luvit deployment
uses server-held opaque `ConfigurationRef` capabilities; a signed stateless policy
is a later, distinct deployment alternative.


### 18.2 Request path

```text
Luvit request callback
  -> bounded WireRequestImage
  -> deployed application request machine
  -> typed invocation resolution and decoding
  -> application transition protocol
  -> ConfigurationUpdate
  -> atomic publication of next ActiveConfiguration
  -> derived semantic delivery
  -> HTML/HTMX artifact
  -> Luvit response writer
```

The host callback is one sealed boundary. It must not become a callback registry
indexed by paths or action names.

### 18.3 Body handling

The first prototype may buffer request bodies under a strict typed size limit.
Later, large or incremental input handling should use an LLBL process/GPS
materializer. The semantic transition still receives a completed typed input
product unless its own declared protocol is intentionally incremental.

### 18.4 Runtime acceleration

Luvit may use generated hash tables to accelerate address resolution. Such a
table is a compiled cache of `TransitionBinding` and `EntryBinding` products. It
is rebuildable, carries no independent semantic facts, and cannot become a
handler map that owns transition behavior.

---

## 19. Validation and diagnostics

The checked application must diagnose at least:

- unresolved page, view, transition, and field identities;
- an indexed value rejected by the expected role;
- a navigation control exposing an effectful-only transition;
- a button exposing a transition with unsatisfied browser fields;
- a form missing required fields;
- a control bound to another transition's field;
- illegal repeated field cardinality;
- duplicate or ambiguous mount identity;
- a replacement targeting an unreachable or unauthorized mount;
- a child replacement after its parent is retired;
- a transition outcome not wired to a configuration update;
- a page/view renderer requiring facts absent from its state product;
- a renderer incapable of materializing a requested semantic delivery;
- unsafe external navigation;
- stale invocation revision;
- malformed, missing, repeated, or oversized wire input;
- deployment address collisions;
- absent progressive-enhancement fallback where the selected deployment requires
  it.

LLBL diagnostics should report:

- affordance head and slot;
- expected role;
- indexed HostEval origin;
- transition/page/view definition origin;
- role adaptation path;
- generated deployment binding when relevant.

---

## 20. Worked interaction sketches

These sketches pin the intended indexed relationships. The counter trace also
makes definitions, state, transition instances, publication, and rendering
explicit. Exact grammar-head spelling may be refined by the first LLBL spike,
but no step may introduce string references or opaque callbacks.

### 20.1 Navigation

```lua
hyper.page. home {
  html.h1 { "Home" },
  html.a [editing] { "Edit" },
}

hyper.page. editing {
  html.h1 { "Editing" },
  html.a [home] { "Cancel" },
}
```

`home` and `editing` are `PageDef` identities. The anchor role adapts the
referenced page to a navigation transition. Plain HTML projects it to a locator;
an HTMX deployment may boost the same navigation while preserving refresh and
history semantics.

### 20.2 Complete counter model

The state product is explicit:

```text
CounterState
  count: integer
```

The transition regions are explicit and product-to-protocol shaped:

```text
increment(current: CounterState; advanced(next: CounterState))
decrement(current: CounterState; advanced(next: CounterState))
```

Application wiring maps `advanced(next)` to:

```text
ReplaceOrigin(CounterViewInstance(next))
```

The root `CounterPageInstance` mounts one generated `CounterViewInstance`. The
view instance has an exact `CounterState` field. Its render method constructs
transition instances bound to that state and uses the minimal indexed surface:

```lua
function CounterViewInstance:render(input)
  local up = increment (self.counter)
  local down = decrement (self.counter)

  return hyper.view [self] {
    html.button [down] { "−" },
    html.output { self.counter.count },
    html.button [up] { "+" },
  }
end
```

The method is shown to expose semantic ownership; the public LLBL view head will
generate the concrete view leaf and this leaf-owned render method. It must not
store the method as a callback field.

One click follows the complete chain:

```text
CounterPageInstance(CounterViewInstance(CounterState(0)))
  -> render offers IncrementInstance(CounterState(0))
  -> invocation decodes no browser fields
  -> increment selects advanced(CounterState(1))
  -> wiring creates ReplaceOrigin(CounterViewInstance(CounterState(1)))
  -> publication creates complete configuration C2
  -> delivery planner selects the changed origin mount
  -> plain HTML returns the containing document or HTMX returns the view fragment
```

No route, selector, field map, or implicit page-state capture exists.

### 20.3 Typed form

```lua
hyper.page. editing {
  html.form [save] {
    html.input [save.title],
    html.button { "Save" },
  },
}
```

`save` is a transition instance whose exact browser-input product contains the
field entity `save.title`. The renderer derives form action, method, wire field
name, invocation proof, and HTMX enhancement. Decode failure enters a named
application protocol outcome, which wires to an editing page/view instance with
typed submitted-value and diagnostic products.

### 20.4 Parameterized list row

Conceptually:

```lua
local row = todo_row (todo)
local remove = delete_todo (todo)

hyper.view [row] {
  html.span { todo.title },
  html.button [remove] { "Delete" },
}
```

`todo_row(todo)` and `delete_todo(todo)` are precise generated instance products.
On success, application wiring produces a configuration update over typed mount
capabilities. Publication constructs the complete next configuration; only then
may HTMX derive one or more fragments.

---

## 21. Progressive enhancement contract

For the default deployment profile:

1. Every navigation affordance has an ordinary address.
2. Every submission affordance has an ordinary form action and method.
3. Full-document handling and HTMX handling execute the same transition.
4. Validation and domain failures produce meaningful HTML without HTMX.
5. HTMX changes only delivery granularity.
6. Browser refresh resolves an addressable page locator or a retained ephemeral
   configuration capability, never a fragment address.
7. History entries correspond to page boundaries, not arbitrary DOM swaps.

A deployment that intentionally requires JavaScript must be a distinct typed
capability/profile, not `progressive = false` in an option bag.

---

## 22. Testing strategy

### 22.1 Schema tests

- constructors reject wrong identity types;
- generated instance products preserve exact parameter types;
- every required ASDL leaf method is installed;
- no generic map/any/table field enters semantic schemas.

### 22.2 LLBL tests

- indexed affordance heads emit `index:host` events;
- transition/page/field roles adapt valid values;
- invalid adaptation reports both use and definition origins;
- fragments compose only under compatible qualified roles;
- formatting preserves the indexed relationship syntax.

### 22.3 Machine tests

- navigation selects the expected next page;
- counter transitions construct and publish the expected complete configuration;
- form decoding constructs exact typed inputs;
- all transition protocol outcomes are wired;
- stale mount generations and unauthorized invocation take named outcomes;
- parent replacement retires child mounts.

### 22.4 Renderer tests

- HTML escaping;
- stable generated identities;
- full-page golden output;
- fragment golden output;
- out-of-band patch output;
- plain HTML and HTMX execute equivalent transitions;
- no authored string route, selector, or field name is required.

### 22.5 Luvit integration tests

- initial document request;
- link navigation;
- button transition;
- valid and invalid form submission;
- HTMX request header path;
- stale invocation;
- body-size rejection;
- malformed token;
- connection close while writing.

Tests should construct named ASDL roots and call leaf-owned methods. They should
not assert `{ kind = ... }` tables.

---

## 23. Implementation slices

### Slice 1 — language skeleton

- `html` LLBL member with a minimal concrete vocabulary;
- `hyper` LLBL member;
- page identity;
- navigation adaptation through indexed anchors;
- semantic HTML formatter;
- full-document materializer.

Success criterion: two pages navigate with no authored route strings.

### Slice 2 — transition machine

- closed application-specific schema generation;
- typed transition identity backed by an LLBL region;
- indexed button affordance;
- explicit `ConfigurationUpdate` leaves;
- immutable in-memory `ConfigurationStore`;
- counter model and complete publication loop;
- full-page transition round trip.

Success criterion: the in-process counter executes

```text
page instance -> representation -> invocation -> transition
  -> complete published configuration -> full HTML
```

without a handler map, authored URL, or HTMX.

### Slice 3 — Luvit host

- bounded request image;
- generated entry and transition bindings;
- typed server-held opaque `ConfigurationRef`;
- application publication machine integration;
- response writer;
- focused integration tests.

Success criterion: the counter runs under the installed Luvit runtime.

### Slice 4 — typed forms

- field identities and codecs;
- form/input role validation;
- typed decoding protocols;
- validation representation.

Success criterion: todo creation works with generated field names and no request
parameter table in semantic code.

### Slice 5 — view boundaries and HTMX

- view definitions, instances, and mounts;
- origin-bound affordances;
- local delivery;
- HTMX fragment materializer;
- plain HTML fallback.

Success criterion: a todo row or counter view updates locally with no authored
`hx-*` values or selector.

### Slice 6 — multi-mount delivery and retention

- multiple typed configuration replacements;
- parent/child generation invalidation;
- configuration retention and retirement protocols;
- out-of-band materialization;
- multi-tab and back-navigation tests.

### Slice 7 — deployment and security profiles

- entry/address policy;
- signed and server-held invocation capability alternatives;
- principal/authority products;
- CSRF/replay/stale-state tests;
- explicit external navigation.

---

## 24. Rejected architectures

### 24.1 Route-first MVC

```text
method + path -> controller -> template
```

Rejected because strings and handler tables become the semantic graph, while the
current page's available transitions remain invisible to the type system.

### 24.2 HTMX attribute builder

```lua
button { hx_post = "/x", hx_target = "#y" }
```

Rejected because transport encodings become authored semantics and object
identity is lost.

### 24.3 Generic virtual DOM

```text
Node(tag: string, attrs: map, children: list)
```

Rejected as the semantic center because it is stringly, open-ended, and unable
to own leaf behavior precisely. HTML may have a lower wire representation, but
source semantics use concrete vocabulary.

### 24.4 Generic page state bag

```text
Page(state, data, route, session, user, errors, options)
```

Rejected as a context bag and optional soup. Domain world, browser
configuration, principal, revision, and representation are separate named
products.

### 24.5 Callback middleware stack

Rejected as the semantic architecture. Host callbacks may seal IO boundaries,
but transition alternatives and authorization outcomes belong to typed
protocols, not callback registries.

### 24.6 Hidden session state keyed by strings

Rejected as the state model. A server-held capability store may exist as an
explicit owner machine with typed identities, generation facts, resolver
protocols, and invalidation authority.

### 24.7 HTMX-specific application outcomes

Rejected. Application transitions produce configuration updates that are
published as semantic state. HTMX-specific facts are derived by the materializer.

### 24.8 A second state-machine abstraction

Rejected. LLBL regions/processes already own generic control. Hypermedia adds
representation, invocation, mount, and transport vocabulary around that algebra.

---

## 25. Hard invariants

1. No semantic reference is a route string, field-name string, action string,
   selector, or DOM ID.
2. Every externally invocable transition has a stable typed identity.
3. Every rendered affordance refers to a transition instance, configuration,
   origin mount, and mount generation.
4. Every browser-supplied field refers to one exact input-field identity.
5. Every active mount belongs to one normalized configuration spine.
6. Every configuration update targets a typed live mount capability or page
   boundary.
7. Every successful transition publishes a complete next configuration before
   delivery planning.
8. Replacing a parent retires all descendant mount generations.
9. Every transition outcome is wired by its consumer.
10. Domain outcomes become configuration updates, never HTMX patch intent.
11. Every delivery plan derives from published semantic state.
12. Every HTML/HTMX artifact is rebuildable from published configuration plus
    deployment facts.
13. Full HTML and HTMX materializations preserve transition meaning.
14. Authorization is checked by the transition/application machine, never inferred
    solely from whether an affordance was rendered.
15. Source ASDL never accumulates deployment or wire facts.
16. Runtime lookup caches are derived acceleration, not semantic authority.
17. Application schema contexts close before semantic values or methods execute.
18. No leaf behavior is selected by class names, kind strings, or handler maps.

---

## 26. Prototype questions that must be answered by code

The architecture is fixed enough to begin, but the first three examples must
settle these narrow surface questions before the dialect is declared stable:

1. Whether a zero-browser-input `TransitionDef` adapts directly to
   `transition_ref`, or whether the page renderer always constructs an explicit
   zero-input `TransitionInstance`.
2. The lightest LLBL syntax for projecting an exact form field identity from a
   transition (`save.title` versus an indexed field projection).
3. How the `hyper.page` and `hyper.view` heads declare the exact state product
   whose generated concrete instance leaf owns rendering.
4. Which minimal HTML element vocabulary is sufficient for navigation, counter,
   and form examples without introducing a generic tag escape.

The initial persistence decision is not open: the Luvit prototype uses an
explicit server-held immutable `ConfigurationStore` with typed opaque handles.
Signed stateless capabilities may be designed later as a separate deployment
alternative after the in-process publication loop is proven.

These questions do not reopen the central design:

> LLBL owns control; `ActiveConfiguration` is authoritative state; the page is
> its client-visible representation; indexed objects are offered transitions;
> publication precedes delivery; HTML and HTMX are materializers.
