package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local hypermedia = require("hyper")
local H = hypermedia.Core
local Html = hypermedia.Html
local env = hypermedia.env()

local current = H.CounterConfiguration(H.CounterState(0), H.CounterRevision(0))
local deployment = H.CounterDeployment(
  H.TransitionAddress("/"),
  H.TransitionAddress("/_h/config/"),
  H.TransitionAddress("/_h/increment"),
  H.TransitionAddress("/_h/decrement"),
  "_configuration",
  "_revision"
)
local configuration_ref = H.ConfigurationRef("00000000000000000000000000000000.1")

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
assert(llbl.is(authored.children[1].target.machine, "Region"),
  "transition references should carry an executable LLBL region machine")
assert(llbl.describe(authored.children[1].target.machine).protocol == "Hyper.CounterTransitionOutcome",
  "counter transition machine should expose its named outcome protocol")
assert(llbl.is(authored.children[1].origin.value, "Origin"),
  "indexed button should retain a typed LLBL use-site origin")

local authored_artifact = authored:materialize_html(
  Html.HtmlMaterializationInput(deployment, configuration_ref, current.revision)
)
assert(authored_artifact.bytes:find('action="/_h/decrement"', 1, true),
  "authored transition relation should materialize through its deployment binding")

local invocation = H.CounterInvocation(env.hyper.increment, current.revision)
local decision = H.CounterTransitionExecutionRequest(current, invocation):execute()
assert(H.CounterTransitionUpdate:isclassof(decision), "current invocation should choose an update")
assert(H.CounterReplacePage:isclassof(decision.update), "counter update should replace the page configuration")
local next_configuration = decision.update.next_configuration
assert(next_configuration.state.count == 1, "increment should construct next state")
assert(next_configuration.revision.value == 1, "update should advance revision")

local stale = H.CounterTransitionExecutionRequest(current,
  H.CounterInvocation(env.hyper.increment, H.CounterRevision(9))):execute()
assert(H.CounterTransitionStale:isclassof(stale), "stale invocation should be typed")

local document = next_configuration:render_counter()
local artifact = document:materialize_html(
  Html.HtmlMaterializationInput(deployment, configuration_ref, next_configuration.revision)
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
