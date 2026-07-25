package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local hypermedia = require("hyper")
local H = hypermedia.Core

local configuration = H.CounterConfiguration(H.CounterState(0), H.CounterRevision(0))
local deployment = H.CounterDeployment(
  H.TransitionAddress("/_h/increment"),
  H.TransitionAddress("/_h/decrement"),
  "_revision"
 )

local document = configuration:render_counter()
local artifact = document:materialize_html(
  hypermedia.Html.HtmlMaterializationInput(deployment, configuration.revision)
 )

io.write(artifact.bytes, "\n")
