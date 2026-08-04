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
    emit Program.run(program; done = done)
  end
  block done(code [i32])
    if code == 42 then
      return 0
    end
    return 1
  end
end
]=]

local dir = "target/test_emit_c_region_main"
local artifact = lalin.emit_c(assert(lalin.loadstring(src, "@test_emit_c_region_main.lln")), {
    name = "emit_c_region_main",
    c_path = dir .. "/main.c",
    h_path = dir .. "/main.h",
})

assert(artifact.kind == "CBackendArtifact", "region main must use semantic C backend")
assert(artifact.source:match("Program_run%(") ~= nil, "region seal must materialize its callable artifact")
assert(artifact.source:match("ctl_lln_emit_"), "open region emit must still lower to generated control blocks")

if command_ok("command -v gcc >/dev/null 2>&1") then
    assert(command_ok("gcc -std=c99 -O3 " .. shell_quote(dir .. "/main.c") .. " -o " .. shell_quote(dir .. "/main_test")), "gcc should compile region-main artifact")
    assert(command_ok(shell_quote(dir .. "/main_test")), "region-main executable should return success")
end

io.write("lalin emit_c region main (sealed callable + open emit) ok\n")
