package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_all(path)
  local file = assert(io.open(path, "rb"))
  local value = file:read("*a") or ""
  file:close()
  return value
end

local port_pipe = assert(io.popen([[python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()']], "r"))
local port = assert(tonumber(port_pipe:read("*l")))
port_pipe:close()

local prefix = os.tmpname()
os.remove(prefix)
local log_path = prefix .. ".log"
local headers_path = prefix .. ".headers"
local body_path = prefix .. ".body"
local upload_path = prefix .. ".upload"

local launch = string.format(
  "HYPER_PORT=%d luvit examples/hyper/server.lua >%s 2>&1 & echo $!",
  port, shell_quote(log_path)
)
local process = assert(io.popen(launch, "r"))
local pid = assert(tonumber(process:read("*l")))
process:close()

local function cleanup()
  os.execute("kill " .. tostring(pid) .. " >/dev/null 2>&1")
  os.execute("wait " .. tostring(pid) .. " >/dev/null 2>&1")
  os.remove(log_path)
  os.remove(headers_path)
  os.remove(body_path)
  os.remove(upload_path)
end

local function curl(args)
  local command = string.format(
    "curl -sS --max-time 2 -D %s -o %s %s http://127.0.0.1:%d%s 2>/dev/null",
    shell_quote(headers_path), shell_quote(body_path), args.options or "", port, args.path
  )
  local status = os.execute(command)
  if status ~= 0 and status ~= true then return false, "", "" end
  return true, read_all(headers_path), read_all(body_path)
end

local function run()
  local ready = false
  for _ = 1, 50 do
    local ok = curl { path = "/" }
    if ok then ready = true; break end
    os.execute("sleep 0.1")
  end
  assert(ready, "Luvit server did not start:\n" .. read_all(log_path))

  local _, entry_headers = curl { path = "/" }
  assert(entry_headers:match("HTTP/1%.1 303"))
  local initial_location = assert(entry_headers:match("Location: ([^\r\n]+)"))
  local initial_ref = assert(initial_location:match("^/_h/config/(.+)$"))
  assert(initial_ref:match("^[%x]+%.[%x]+$"), "configuration URL should carry an opaque reference")

  local _, initial_headers, initial_body = curl { path = initial_location }
  assert(initial_headers:match("HTTP/1%.1 200"))
  assert(initial_body:find("<output>0</output>", 1, true))
  assert(initial_body:find('name="_configuration" value="' .. initial_ref .. '"', 1, true))

  local _, post_headers = curl {
    path = "/_h/increment",
    options = "-X POST --data " .. shell_quote(
      "_configuration=" .. initial_ref .. "&_revision=0"
    ),
  }
  assert(post_headers:match("HTTP/1%.1 303"))
  local next_location = assert(post_headers:match("Location: ([^\r\n]+)"))
  assert(next_location ~= initial_location, "publication should issue a fresh configuration reference")

  local _, next_headers, next_body = curl { path = next_location }
  assert(next_headers:match("HTTP/1%.1 200"))
  assert(next_body:find("<output>1</output>", 1, true))

  local upload = assert(io.open(upload_path, "wb"))
  upload:write(string.rep("x", 5000))
  upload:close()
  local _, large_headers = curl {
    path = "/_h/increment",
    options = "-X POST --data-binary @" .. shell_quote(upload_path),
  }
  assert(large_headers:match("HTTP/1%.1 413"))

  local _, method_headers = curl {
    path = "/",
    options = "-X DELETE",
  }
  assert(method_headers:match("HTTP/1%.1 405"))
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then error(err, 0) end

io.write("hyper Luvit counter integration ok\n")
