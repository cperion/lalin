-- Test basic control region lowering: block expression with yield.
-- Expected to produce a BackProgram wire that Rust backend can JIT.

local mom = require("moonlift")

-- Source: a simple block region that sums up to 4 using a counted loop.
local src = [[
func main() -> i32
    return block loop(i: i32 = 0, acc: i32 = 0)
        if i >= 4 then yield acc end
        jump loop(i = i + 1, acc = acc + 1)
    end
end
]]

-- Run the source and check result.
local chunk, err = mom.loadstring(src, "test_control", { target = "native" })
if not chunk then
    io.stderr:write("FAIL: compile error: ", err, "\n")
    os.exit(1)
end
local ok, result = pcall(chunk)
if not ok then
    io.stderr:write("FAIL: runtime error: ", result, "\n")
    os.exit(1)
end
if result ~= 4 then
    io.stderr:write("FAIL: expected 4, got ", tostring(result), "\n")
    os.exit(1)
end
print("PASS: test_mom_control_lower -- result = " .. tostring(result))
