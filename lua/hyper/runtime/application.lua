local Schema = require("hyper.schema")
local Store = require("hyper.runtime.store")

local H = Schema.Core
local Html = Schema.Html
local Http = Schema.Http

local Application = {}
Application.__index = Application

local function html_headers()
  return { Http.HttpHeaderField("Content-Type", "text/html; charset=utf-8") }
end

local function text_artifact(status, text)
  return Http.HttpArtifact(status, {
    Http.HttpHeaderField("Content-Type", "text/plain; charset=utf-8"),
  }, text)
end

function Application.new(deployment, initial_configuration, retention)
  local self = setmetatable({
    __hyper_counter_application_machine = true,
    deployment = deployment,
    store = Store.new(initial_configuration, retention),
  }, Application)
  self.capability = Http.CounterApplicationCapability(self)
  return self
end

function Http.CounterApplicationStart:start()
  return Application.new(
    self.deployment, self.initial_configuration, self.retention
  ).capability
end


function Application:document_artifact(record)
  local document = record.configuration:render_counter()
  local rendered = document:materialize_html(Html.HtmlMaterializationInput(
    self.deployment, record.ref, record.configuration.revision
  ))
  return Http.HttpArtifact(Http.HttpStatusOk, html_headers(), rendered.bytes)
end

function Application:redirect_artifact(ref)
  local address = self.deployment:configuration_address(ref)
  return Http.HttpArtifact(Http.HttpStatusSeeOther, {
    Http.HttpHeaderField("Location", address.text),
    Http.HttpHeaderField("Cache-Control", "no-store"),
  }, "")
end

function Application:handle_wire(wire)
  local resolved = wire:resolve_counter(self.deployment)
  return resolved:serve_counter(Http.CounterServeInput(self.capability))
end

function Application:serve_configuration(ref)
  return self.store:lookup(ref):serve_counter_document(self.capability)
end

function Application:serve_transition(request)
  return self.store:lookup(request.configuration_ref):serve_counter_transition(
    Http.CounterTransitionServeInput(self.capability, request)
  )
end

function Http.CounterEntryResolved:serve_counter(input)
  return input.capability.machine:redirect_artifact(
    input.capability.machine.store.initial_ref
  )
end

function Http.CounterConfigurationResolved:serve_counter(input)
  return input.capability.machine:serve_configuration(self.configuration_ref)
end

function Http.CounterTransitionResolved:serve_counter(input)
  return input.capability.machine:serve_transition(self)
end

function Http.CounterRequestNotFound:serve_counter(_input)
  return text_artifact(Http.HttpStatusNotFound, "not found\n")
end

function Http.CounterRequestMethodRejected:serve_counter(_input)
  return Http.HttpArtifact(Http.HttpStatusMethodNotAllowed, {
    Http.HttpHeaderField("Allow", "GET, POST"),
    Http.HttpHeaderField("Content-Type", "text/plain; charset=utf-8"),
  }, "method not allowed\n")
end

function Http.CounterRequestMalformed:serve_counter(_input)
  return text_artifact(Http.HttpStatusBadRequest, "malformed request\n")
end

function H.ConfigurationFound:serve_counter_document(capability)
  return capability.machine:document_artifact(self.record)
end

function H.ConfigurationMissing:serve_counter_document(_capability)
  return text_artifact(Http.HttpStatusNotFound, "configuration not found\n")
end

function H.ConfigurationFound:serve_counter_transition(input)
  local request = input.request
  local invocation = H.CounterInvocation(request.transition, request.expected_revision)
  return H.CounterTransitionExecutionRequest(
    self.record.configuration, invocation
  ):execute():commit_counter_http(input.capability)
end

function H.ConfigurationMissing:serve_counter_transition(_input)
  return text_artifact(Http.HttpStatusNotFound, "configuration not found\n")
end

function H.CounterTransitionUpdate:commit_counter_http(capability)
  return self.update:commit_counter_http(capability)
end

function H.CounterReplacePage:commit_counter_http(capability)
  local stored = capability.machine.store:publish(self.next_configuration)
  return capability.machine:redirect_artifact(stored.record.ref)
end

function H.CounterTransitionStale:commit_counter_http(_capability)
  return text_artifact(Http.HttpStatusConflict, "stale configuration\n")
end

return Application
