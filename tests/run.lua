#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local suite = arg and arg[1] or "default"

local suites = {
    default = {
        "c_backend", "code_ir", "core", "frontend",
        "asdl", "compiler_process", "runtime", "schema", "tooling",
    },
    optional = { "experiments", "retired" },
    all = {
        "c_backend", "code_ir", "core",
        "experiments", "frontend",
        "asdl", "compiler_process", "retired", "runtime", "schema", "tooling",
    },
}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function collect(dir, out)
    local cmd = "find " .. shell_quote("tests/" .. dir) .. " -type f -name 'test_*.lua' | sort"
    local p = assert(io.popen(cmd, "r"))
    for path in p:lines() do
        out[#out + 1] = path
    end
    p:close()
end

local dirs = suites[suite]
if dirs == nil then
    local probe = io.open("tests/" .. suite, "r")
    if probe == nil then
        io.stderr:write("unknown test suite or directory: ", tostring(suite), "\n")
        os.exit(2)
    end
    probe:close()
    dirs = { suite }
end

local tests = {}
for i = 1, #dirs do
    collect(dirs[i], tests)
end
if #tests == 0 then
    io.stderr:write("no test files found for suite: ", tostring(suite), "\n")
    os.exit(2)
end

local passed, skipped, failed = 0, 0, 0
local run_slow = os.getenv("LALIN_RUN_SLOW") == "1" or os.getenv("LALIN_RUN_SLOW") == "true"
local slow_tests = {
    ["tests/code_ir/test_lalin_binary.lua"] = "builds and links the full embedded single binary",
}
for i = 1, #tests do
    local path = tests[i]
    if slow_tests[path] ~= nil and not run_slow then
        io.write("SKIP ", path, " (slow: ", slow_tests[path], "; set LALIN_RUN_SLOW=1 to run)\n")
        skipped = skipped + 1
    else
        io.write("RUN  ", path, "\n")
        io.flush()
        local ok = os.execute("luajit " .. shell_quote(path))
        if ok == true or ok == 0 then
            passed = passed + 1
        else
            failed = failed + 1
            io.stderr:write("FAIL ", path, "\n")
        end
    end
end

io.write(string.format("tests: %d passed, %d skipped, %d failed\n", passed, skipped, failed))
if failed ~= 0 then os.exit(1) end
