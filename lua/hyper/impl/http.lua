local llbl = require("llbl")

local M = {}

local function decode_component(text)
  local parts = {}
  local i = 1
  while i <= #text do
    local byte = text:sub(i, i)
    if byte == "+" then
      parts[#parts + 1] = " "
      i = i + 1
    elseif byte == "%" then
      local hex = text:sub(i + 1, i + 2)
      if not hex:match("^%x%x$") then return false, "malformed percent escape" end
      parts[#parts + 1] = string.char(tonumber(hex, 16))
      i = i + 3
    else
      parts[#parts + 1] = byte
      i = i + 1
    end
  end
  return true, table.concat(parts)
end

local function parse_form(Http, body)
  if #body.bytes > body.limit then
    return Http.WireFormMalformed("body exceeds its declared bound")
  end
  local fields = {}
  if body.bytes == "" then return Http.WireFormParsed(Http.WireFormImage(fields)) end
  for pair in body.bytes:gmatch("[^&]+") do
    local raw_name, raw_value = pair:match("^([^=]*)=(.*)$")
    if raw_name == nil then return Http.WireFormMalformed("field has no '=' separator") end
    local name_ok, name = decode_component(raw_name)
    if not name_ok then return Http.WireFormMalformed(name) end
    local value_ok, value = decode_component(raw_value)
    if not value_ok then return Http.WireFormMalformed(value) end
    fields[#fields + 1] = Http.WireFormField(name, value)
  end
  return Http.WireFormParsed(Http.WireFormImage(fields))
end

local function decimal(Http, text)
  if not text:match("^%d+$") then return Http.WireDecimalRejected(text) end
  local value = tonumber(text)
  if value == nil then return Http.WireDecimalRejected(text) end
  return Http.WireDecimalDecoded(value)
end

local function configuration_ref(Http, H, text)
  local nonce, ordinal = text:match("^([%x]+)%.([%x]+)$")
  if nonce == nil or #nonce ~= 32 or #ordinal > 16 then
    return Http.WireConfigurationRefRejected(text)
  end
  return Http.WireConfigurationRefDecoded(H.ConfigurationRef(text))
end

function M.install(T)
  local H = T.HyperCore
  local Http = T.HyperHttp
  local counter_transition_machine = require("hyper.machine.counter_transition")
  local request_origin = H.SourceOrigin(llbl.origin("counter-http-resolution"))
  local increment = H.TransitionRef(H.CounterIncrement, counter_transition_machine, request_origin)
  local decrement = H.TransitionRef(H.CounterDecrement, counter_transition_machine, request_origin)

  function Http.BoundedBody:parse_form()
    return parse_form(Http, self)
  end

  function Http.WireFieldValueMissing:add_wire_value(value)
    return Http.WireFieldValuePresent(self.name, value)
  end

  function Http.WireFieldValuePresent:add_wire_value(_value)
    return Http.WireFieldValueDuplicate(self.name)
  end

  function Http.WireFieldValueDuplicate:add_wire_value(_value)
    return self
  end

  function Http.WireFormImage:decode_counter_form(deployment)
    local accumulator = Http.CounterFormAccumulator(
      Http.WireFieldValueMissing(deployment.configuration_field),
      Http.WireFieldValueMissing(deployment.revision_field)
    )
    for i = 1, #self.fields do
      local field = self.fields[i]
      if field.name == deployment.configuration_field then
        accumulator = Http.CounterFormAccumulator(
          accumulator.configuration:add_wire_value(field.value), accumulator.revision)
      elseif field.name == deployment.revision_field then
        accumulator = Http.CounterFormAccumulator(
          accumulator.configuration, accumulator.revision:add_wire_value(field.value))
      end
    end
    return accumulator.configuration:finish_counter_configuration_field(accumulator.revision)
  end

  function Http.WireFieldValueMissing:finish_counter_configuration_field(_revision)
    return Http.CounterFormRejected(Http.CounterFormMissingField(self.name))
  end

  function Http.WireFieldValueDuplicate:finish_counter_configuration_field(_revision)
    return Http.CounterFormRejected(Http.CounterFormDuplicateField(self.name))
  end

  function Http.WireFieldValuePresent:finish_counter_configuration_field(revision)
    return configuration_ref(Http, H, self.value)
      :finish_counter_configuration_ref(self.name, revision)
  end

  function Http.WireConfigurationRefDecoded:finish_counter_configuration_ref(_name, revision)
    return revision:finish_counter_revision_field(self.ref)
  end

  function Http.WireConfigurationRefRejected:finish_counter_configuration_ref(name, _revision)
    return Http.CounterFormRejected(
      Http.CounterFormMalformedConfigurationRef(name, self.text)
    )
  end

  function Http.WireFieldValueMissing:finish_counter_revision_field(_ref)
    return Http.CounterFormRejected(Http.CounterFormMissingField(self.name))
  end

  function Http.WireFieldValueDuplicate:finish_counter_revision_field(_ref)
    return Http.CounterFormRejected(Http.CounterFormDuplicateField(self.name))
  end

  function Http.WireFieldValuePresent:finish_counter_revision_field(ref)
    return decimal(Http, self.value):finish_counter_revision_number(self.name, ref)
  end

  function Http.WireDecimalDecoded:finish_counter_revision_number(_name, ref)
    return Http.CounterFormDecoded(ref, H.CounterRevision(self.value))
  end

  function Http.WireDecimalRejected:finish_counter_revision_number(name, _ref)
    return Http.CounterFormRejected(Http.CounterFormMalformedNumber(name, self.text))
  end

  function Http.CounterFormDecoded:to_counter_request_resolution(target)
    return Http.CounterTransitionResolved(target.transition, self.configuration_ref, self.revision)
  end

  function Http.CounterFormRejected:to_counter_request_resolution(_target)
    return Http.CounterRequestMalformed(self.reject)
  end

  function Http.WireFormParsed:resolve_counter_transition(target, deployment)
    return self.image:decode_counter_form(deployment):to_counter_request_resolution(target)
  end

  function Http.WireFormMalformed:resolve_counter_transition(_target, _deployment)
    return Http.CounterRequestMalformed(Http.CounterFormMalformedEncoding(self.reason))
  end

  function Http.CounterTransitionTargetSelected:decode_counter_request(body, deployment)
    return body:parse_form():resolve_counter_transition(self, deployment)
  end

  function Http.CounterTransitionTargetMissing:decode_counter_request(_body, _deployment)
    return Http.CounterRequestNotFound(self.target)
  end

  function H.CounterDeployment:resolve_counter_transition_target(target)
    if target.text == self.increment.text then
      return Http.CounterTransitionTargetSelected(increment)
    end
    if target.text == self.decrement.text then
      return Http.CounterTransitionTargetSelected(decrement)
    end
    return Http.CounterTransitionTargetMissing(target)
  end

  function Http.WireConfigurationRefDecoded:to_counter_configuration_resolution(_target)
    return Http.CounterConfigurationResolved(self.ref)
  end

  function Http.WireConfigurationRefRejected:to_counter_configuration_resolution(target)
    return Http.CounterRequestNotFound(target)
  end

  function H.CounterDeployment:resolve_counter_get_target(target)
    if target.text == self.entry.text then return Http.CounterEntryResolved end
    local prefix = self.configuration_prefix.text
    if target.text:sub(1, #prefix) == prefix then
      return configuration_ref(Http, H, target.text:sub(#prefix + 1))
        :to_counter_configuration_resolution(target)
    end
    return Http.CounterRequestNotFound(target)
  end

  function Http.HttpGet:resolve_counter_request(wire, deployment)
    return deployment:resolve_counter_get_target(wire.target)
  end

  function Http.HttpPost:resolve_counter_request(wire, deployment)
    return wire.content_type:resolve_counter_post(wire, deployment)
  end

  function Http.HttpFormUrlEncoded:resolve_counter_post(wire, deployment)
    return deployment:resolve_counter_transition_target(wire.target)
      :decode_counter_request(wire.body, deployment)
  end

  function Http.HttpContentTypeMissing:resolve_counter_post(_wire, _deployment)
    return Http.CounterRequestMalformed(Http.CounterFormMissingContentType)
  end

  function Http.HttpContentTypeUnsupported:resolve_counter_post(_wire, _deployment)
    return Http.CounterRequestMalformed(Http.CounterFormUnsupportedContentType(self.value))
  end

  function Http.HttpUnsupportedMethod:resolve_counter_request(_wire, _deployment)
    return Http.CounterRequestMethodRejected(self)
  end

  function Http.WireRequestImage:resolve_counter(deployment)
    return self.method:resolve_counter_request(self, deployment)
  end

  function Http.HttpStatusOk:http_status_code() return 200 end
  function Http.HttpStatusSeeOther:http_status_code() return 303 end
  function Http.HttpStatusBadRequest:http_status_code() return 400 end
  function Http.HttpStatusNotFound:http_status_code() return 404 end
  function Http.HttpStatusConflict:http_status_code() return 409 end
  function Http.HttpStatusMethodNotAllowed:http_status_code() return 405 end
  function Http.HttpStatusPayloadTooLarge:http_status_code() return 413 end
  function Http.HttpStatusInternalServerError:http_status_code() return 500 end
end

return M
