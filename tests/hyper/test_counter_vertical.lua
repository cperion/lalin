package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local hypermedia = require("hyper")
local H = hypermedia.Core
local Html = hypermedia.Html
local env = hypermedia.env()

local current = H.CounterConfiguration(H.CounterState(0), H.CounterRevision(0))
local deployment = H.CounterDeployment(
  H.TransitionAddress("/_h/increment"),
  H.TransitionAddress("/_h/decrement"),
  "_revision"
)

-- This is the normative authored relation: the indexed object is the exact
-- transition reference, delivered through index:host and normalized by its role.
local authored = env.html.document {
  env.html.button [env.hyper.decrement] { "−" },
  env.html.output { current.state.count },
  env.html.button [env.hyper.increment] { "+" },
}

assert(Html.HtmlDocument:isclassof(authored), "document head should produce typed HTML")
assert(authored.children[1].target == env.hyper.decrement,
  "indexed button should retain the exact transition reference")
assert(llbl.is(authored.children[1].origin.value, "Origin"),
  "indexed button should retain a typed LLBL use-site origin")

local authored_artifact = authored:materialize_html(
  Html.HtmlMaterializationInput(deployment, current.revision)
)
assert(authored_artifact.bytes:find('action="/_h/decrement"', 1, true),
  "authored transition relation should materialize through its deployment binding")

local invocation = H.CounterInvocation(env.hyper.increment, current.revision)
local publication = H.CounterPublicationRequest(current, invocation):publish()
assert(H.CounterPublished:isclassof(publication), "current invocation should publish")
assert(publication.configuration.state.count == 1, "increment should construct next state")
assert(publication.configuration.revision.value == 1, "publication should advance revision")

local stale = H.CounterPublicationRequest(current,
  H.CounterInvocation(env.hyper.increment, H.CounterRevision(9))):publish()
assert(H.CounterPublicationStale:isclassof(stale), "stale invocation should be typed")

local document = publication.configuration:render_counter()
local artifact = document:materialize_html(
  Html.HtmlMaterializationInput(deployment, publication.configuration.revision)
)

assert(Html.HtmlDocumentArtifact:isclassof(artifact), "materializer should return typed artifact")
assert(artifact.bytes:find("<output>1</output>", 1, true), "artifact should render counter")
assert(artifact.bytes:find('action="/_h/increment"', 1, true), "increment address should be projected")
assert(artifact.bytes:find('name="_revision" value="1"', 1, true), "revision should be projected")
assert(not artifact.bytes:find("hx-", 1, true), "core semantics should not emit HTMX attributes")

local wrong = {}
local ok, err = pcall(function() return env.html.button [wrong] { "bad" } end)
assert(not ok and tostring(err):match("E_HYPER_TRANSITION_REF"),
  "button should reject an untyped indexed target")

io.write("hyper counter vertical slice ok\n")
