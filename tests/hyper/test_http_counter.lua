package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local hypermedia = require("hyper")
local H = hypermedia.Core
local Http = hypermedia.Http

local deployment = H.CounterDeployment(
  H.TransitionAddress("/"),
  H.TransitionAddress("/_h/config/"),
  H.TransitionAddress("/_h/increment"),
  H.TransitionAddress("/_h/decrement"),
  "_configuration",
  "_revision"
)

local capability = Http.CounterApplicationStart(
  deployment,
  H.CounterConfiguration(H.CounterState(0), H.CounterRevision(0)),
  H.ConfigurationRetainBounded(2)
):start()

local application = capability.machine

local function request(method, target, body, content_type)
  return application:handle_wire(Http.WireRequestImage(
    method,
    Http.BoundedTarget(target),
    content_type or Http.HttpFormUrlEncoded,
    Http.BoundedBody(body or "", 1024)
  ))
end

local function header(artifact, name)
  for i = 1, #artifact.headers do
    if artifact.headers[i].name == name then return artifact.headers[i].value end
  end
  return false
end

local initial_ref = application.store.initial_ref
local initial_location = deployment:configuration_address(initial_ref).text
assert(#initial_ref.value >= 34, "configuration references should carry opaque entropy")

local entry = request(Http.HttpGet, "/")
assert(entry.status == Http.HttpStatusSeeOther)
assert(header(entry, "Location") == initial_location)

local initial = request(Http.HttpGet, initial_location)
assert(initial.status == Http.HttpStatusOk)
assert(initial.body:find("<output>0</output>", 1, true))
assert(initial.body:find('name="_configuration" value="' .. initial_ref.value .. '"', 1, true))

local increment = request(Http.HttpPost, "/_h/increment",
  "_configuration=" .. initial_ref.value .. "&_revision=0")
assert(increment.status == Http.HttpStatusSeeOther)
assert(#application.store.state.records == 2,
  "publication should retain both immutable configurations")
local next_ref = application.store.state.records[2].ref
local next_location = deployment:configuration_address(next_ref).text
assert(header(increment, "Location") == next_location)

local next_document = request(Http.HttpGet, next_location)
assert(next_document.status == Http.HttpStatusOk)
assert(next_document.body:find("<output>1</output>", 1, true))
assert(next_document.body:find('name="_configuration" value="' .. next_ref.value .. '"', 1, true))

local retained_publication = request(Http.HttpPost, "/_h/increment",
  "_configuration=" .. next_ref.value .. "&_revision=1")
assert(retained_publication.status == Http.HttpStatusSeeOther)
assert(#application.store.state.records == 2, "bounded retention should cap stored configurations")
local retired_initial = request(Http.HttpGet, initial_location)
assert(retired_initial.status == Http.HttpStatusNotFound,
  "bounded retention should retire the oldest opaque reference")

local stale = request(Http.HttpPost, "/_h/increment",
  "_configuration=" .. next_ref.value .. "&_revision=9")
assert(stale.status == Http.HttpStatusConflict)
assert(#application.store.state.records == 2,
  "stale publication must not insert a configuration")

local malformed = request(Http.HttpPost, "/_h/increment",
  "_configuration=" .. next_ref.value .. "&_configuration=" .. next_ref.value .. "&_revision=1")
assert(malformed.status == Http.HttpStatusBadRequest)
local malformed_encoding = request(Http.HttpPost, "/_h/increment",
  "_configuration=%A?&_revision=1")
assert(malformed_encoding.status == Http.HttpStatusBadRequest)

local unsupported_content = request(Http.HttpPost, "/_h/increment",
  "_configuration=" .. next_ref.value .. "&_revision=1",
  Http.HttpContentTypeUnsupported("application/json"))
assert(unsupported_content.status == Http.HttpStatusBadRequest)

local missing = request(Http.HttpGet, "/_h/config/00000000000000000000000000000000.dead")
assert(missing.status == Http.HttpStatusNotFound)

local unknown = request(Http.HttpGet, "/not-an-entry")
assert(unknown.status == Http.HttpStatusNotFound)

local unsupported = request(Http.HttpUnsupportedMethod("DELETE"), "/")
assert(unsupported.status == Http.HttpStatusMethodNotAllowed)
assert(header(unsupported, "Allow") == "GET, POST")

io.write("hyper typed HTTP counter ok\n")
