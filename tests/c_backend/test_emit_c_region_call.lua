package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local src = [=[
struct Program
  n [i32]
end

region Program.run(self [Program]; done(code [i32]))
  entry start()
    jump done(code = self.n)
  end
end

fn main(argc [i32], argv [ptr [ptr [u8]]]) [i32]
  entry start()
    var program [Program] = Program { n = 42 }
    call Program.run(program; done = done)
  end

  block done(code [i32])
    return code - 42
  end
end
]=]

local dir = "target/test_emit_c_region_call"
local artifact = lalin.emit_c(assert(lalin.loadstring(src, "@test_emit_c_region_call.lln")), {
    name = "emit_c_region_call",
    c_path = dir .. "/main.c",
    h_path = dir .. "/main.h",
})

assert(artifact.kind == "CBackendArtifact", "region call must lower through semantic C backend")
assert(artifact.source:match("__lalin_region_call_Program_run"), "region call should generate a sealed callable region function")
assert(artifact.source:match("switch"), "caller should dispatch on the sealed region result")

if command_ok("command -v gcc >/dev/null 2>&1") then
    assert(command_ok("gcc -std=c99 -O3 " .. shell_quote(dir .. "/main.c") .. " -o " .. shell_quote(dir .. "/main_test")), "gcc should compile region-call artifact")
    assert(command_ok(shell_quote(dir .. "/main_test")), "region-call executable should return success")
end

io.write("lalin emit_c region call ok\n")
