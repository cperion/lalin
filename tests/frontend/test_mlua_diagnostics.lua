package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local SourceMap = require("moonlift.source_map")
local Run = require("moonlift.mlua_run")

-- Source index basics.
do
    local idx = SourceMap.index("a\nxyz\n")
    local l, c = SourceMap.line_col(idx, 3) -- 'x'
    assert(l == 2 and c == 1)
    local sn = SourceMap.snippet(idx, 2, 1)
    assert(sn:find("2 | xyz", 1, true) ~= nil)
end

-- End-to-end: parse island errors keep the .mlua source name and concrete parser message.
do
    local bad = "local r = region bad\nentry start()\n  jump x()\n"
    local fn = assert(Run.loadstring(bad, "=(diag_test.mlua)"))
    local ok, err = pcall(fn)
    assert(not ok)
    local text = tostring(err)
    assert(text:find("diag_test.mlua", 1, true) ~= nil)
    assert(text:find("expected", 1, true) ~= nil)
end

-- Parse errors inside transformed .mlua islands must point at the original
-- island source, not the generated Lua quote call line.
do
    local bad = [[
local ok1 = struct A
    x: i32,
end

local bad_region = region bad_region(;
    rendered(view: ptr(u8))
  | missing)
end
]]
    local fn = assert(Run.loadstring(bad, "diag_bad_view.mlua"))
    local ok, err = pcall(fn)
    assert(not ok)
    local text = tostring(err)
    assert(text:find("diag_bad_view.mlua:6:14", 1, true) ~= nil, text)
    assert(text:find("expected continuation arg name, got 'view'", 1, true) ~= nil, text)
end

print("test_mlua_diagnostics ok")
