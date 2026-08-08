package.path = table.concat({
  "./next/lua/?.lua",
  "./next/lua/?/init.lua",
  "./next/tests/?.lua",
  "./next/tests/?/init.lua",
  package.path,
}, ";")

local spec = require("support.spec")
spec.reset()

local function discover(pattern)
  local out = {}
  local pipe = assert(io.popen(pattern))
  for path in pipe:lines() do
    if not path:match("/_") and not path:match("^next/tests/compiler/spec/") then
      out[#out + 1] = path
    end
  end
  pipe:close()
  table.sort(out)
  return out
end

local files = {
  "next/tests/asdl/test_runtime.lua",
  "next/tests/compiler/test_schema.lua",
}

for _, path in ipairs(discover("find next/tests -type f -name '*_spec.lua' 2>/dev/null")) do
  files[#files + 1] = path
end

local filter = arg and arg[1]

if filter == "coverage" then
  local coverage = require("compiler.support.coverage")
  coverage.report("next/tests/compiler/spec", "next/tests/compiler/fixtures")
  spec.finish()
  return
end
local matched = 0
for _, path in ipairs(files) do
  if not filter or path:find(filter, 1, true) then
    matched = matched + 1
    print("## " .. path)
    local ok, err = xpcall(function() dofile(path) end, debug.traceback)
    if not ok then spec.file_failure(path, err) end
  end
end

if filter and matched == 0 then
  io.stderr:write("no tests matched filter: " .. tostring(filter) .. "\n")
  os.exit(2)
end

spec.finish()
