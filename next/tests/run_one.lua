package.path = table.concat({
  "./next/lua/?.lua",
  "./next/lua/?/init.lua",
  "./next/tests/?.lua",
  "./next/tests/?/init.lua",
  package.path,
}, ";")

local spec = require("support.spec")
spec.reset()

local path = assert(arg and arg[1], "usage: luajit next/tests/run_one.lua <test-file>")
assert(io.open(path, "r")):close()
print("## " .. path)
local ok, err = xpcall(function() dofile(path) end, debug.traceback)
if not ok then spec.file_failure(path, err) end
spec.finish()
