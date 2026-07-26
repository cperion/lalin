local Schema = require("hyper.schema")
local H = Schema.Core

local Store = {}
Store.__index = Store

local function random_nonce()
  local source = assert(io.open("/dev/urandom", "rb"),
    "configuration store requires /dev/urandom")
  local bytes = assert(source:read(16), "configuration store could not read entropy")
  source:close()
  return (bytes:gsub(".", function(byte) return string.format("%02x", string.byte(byte)) end))
end

function Store.new(initial_configuration, retention)
  local self = setmetatable({
    state = H.ConfigurationStoreState(
      H.ConfigurationRefIssuerState(random_nonce(), 1), retention, {}
    ),
  }, Store)
  local initial = self:publish(initial_configuration)
  self.initial_ref = initial.record.ref
  return self
end

function Store:lookup(ref)
  return self.state:lookup_configuration(ref)
end

function Store:publish(configuration)
  local published = H.ConfigurationPublishRequest(
    self.state, configuration
  ):publish_configuration()
  self.state = published.state
  return published
end

return Store
