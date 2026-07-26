local http = require("http")
local Schema = require("hyper.schema")

local Http = Schema.Http

local function decode_method(spelling)
  if spelling == "GET" then return Http.HttpGet end
  if spelling == "POST" then return Http.HttpPost end
  return Http.HttpUnsupportedMethod(tostring(spelling or ""))
end

local function decode_content_type(headers)
  local value = headers and (headers["content-type"] or headers["Content-Type"])
  if value == nil then return Http.HttpContentTypeMissing end
  local normalized = tostring(value):lower()
  if normalized == "application/x-www-form-urlencoded"
      or normalized:match("^application/x%-www%-form%-urlencoded%s*;") then
    return Http.HttpFormUrlEncoded
  end
  return Http.HttpContentTypeUnsupported(tostring(value))
end

local function write_artifact(response, artifact)
  response.statusCode = artifact.status:http_status_code()
  for i = 1, #artifact.headers do
    local header = artifact.headers[i]
    response:setHeader(header.name, header.value)
  end
  response:finish(artifact.body)
end

local function internal_error(message)
  io.stderr:write("hyper Luvit request failure: ", tostring(message), "\n")
  return Http.HttpArtifact(Http.HttpStatusInternalServerError, {
    Http.HttpHeaderField("Content-Type", "text/plain; charset=utf-8"),
  }, "internal server error\n")
end

local function oversized_artifact()
  return Http.HttpArtifact(Http.HttpStatusPayloadTooLarge, {
    Http.HttpHeaderField("Content-Type", "text/plain; charset=utf-8"),
  }, "request body too large\n")
end

function Http.LuvitServerStart:listen_luvit()
  local application = self.application.machine
  local config = self.config
  local server = http.createServer(function(request, response)
    local chunks = {}
    local size = 0
    local oversized = false

    request:on("data", function(chunk)
      size = size + #chunk
      if size > config.request_body_limit then
        oversized = true
      else
        chunks[#chunks + 1] = chunk
      end
    end)

    request:on("end", function()
      if oversized then
        write_artifact(response, oversized_artifact())
        return
      end

      local wire = Http.WireRequestImage(
        decode_method(request.method),
        Http.BoundedTarget(request.url or "/"),
        decode_content_type(request.headers),
        Http.BoundedBody(table.concat(chunks), config.request_body_limit)
      )
      local ok, artifact = pcall(function() return application:handle_wire(wire) end)
      if not ok then artifact = internal_error(artifact) end
      write_artifact(response, artifact)
    end)
  end)
  server:listen(config.port, config.host)
  return server
end

return Http
