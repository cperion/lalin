local Tempdir = {}

local function shell_quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

function Tempdir.create(prefix)
  prefix = prefix or "lalin-next"
  local template = string.format("/tmp/%s.XXXXXX", prefix)
  local pipe = assert(io.popen("mktemp -d " .. shell_quote(template)))
  local path = pipe:read("*l")
  local ok = pipe:close()
  assert(ok and path and path ~= "", "mktemp failed")
  return { path = path }
end

function Tempdir.write(dir, name, content)
  local path = dir.path .. "/" .. name
  local file = assert(io.open(path, "w"))
  file:write(content or "")
  file:close()
  return path
end

function Tempdir.read(path)
  local file = assert(io.open(path, "r"))
  local content = file:read("*a")
  file:close()
  return content
end

function Tempdir.remove(dir)
  if dir and dir.path then
    os.execute("rm -rf " .. shell_quote(dir.path))
  end
end

return Tempdir
