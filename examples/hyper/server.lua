local luvit_http = require("http")
package.loaded.http = luvit_http
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local hypermedia = require("hyper")
require("hyper.host.luvit")

local H = hypermedia.Core
local Http = hypermedia.Http

local port = tonumber(os.getenv("HYPER_PORT")) or 8080
local deployment = H.CounterDeployment(
  H.TransitionAddress("/"),
  H.TransitionAddress("/_h/config/"),
  H.TransitionAddress("/_h/increment"),
  H.TransitionAddress("/_h/decrement"),
  "_configuration",
  "_revision"
)

local application = Http.CounterApplicationStart(
  deployment,
  H.CounterConfiguration(H.CounterState(0), H.CounterRevision(0)),
  H.ConfigurationRetainBounded(128)
):start()

Http.LuvitServerStart(
  application,
  Http.LuvitListenConfig("127.0.0.1", port, 4096)
):listen_luvit()

io.stdout:write("hyper counter listening on http://127.0.0.1:", port, "\n")
io.stdout:flush()
