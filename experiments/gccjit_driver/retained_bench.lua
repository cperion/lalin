package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local now = require("lalin.luajit_measure").now
local backend = arg[1] or "gccjit"
local terms = tonumber(arg[2]) or 500
local samples = tonumber(arg[3]) or 7
local optimization = tonumber(arg[4]) or 3
assert(backend == "gccjit" or backend == "gcc-c", "backend must be gccjit or gcc-c")
assert(terms >= 1 and terms <= 2000, "terms must be 1..2000")

local parts = { "return 1" }
for index = 2, terms do
    parts[#parts + 1] = " + "
    parts[#parts + 1] = tostring(index)
end
parts[#parts + 1] = ";"
local source = table.concat(parts)
local expected = terms * (terms + 1) / 2

local compiler
local CGcc
local c_source
if backend == "gccjit" then
    compiler = require("experiments.gccjit_driver.compiler_machine").Compiler()
else
    compiler = require("experiments.retained_compiler.machine").Compiler()
    CGcc = require("lalin.emit_c_compile")
    c_source = "#include <stdint.h>\nint64_t retained_eval(void) { return (int64_t)"
        .. table.concat(parts, "", 2, #parts - 1):gsub("^%s*", "1 ") .. "; }\n"
end

local lower_samples, backend_samples, total_samples = {}, {}, {}
local foreign_samples, driver_samples = {}, {}
for index = 1, samples do
    collectgarbage("collect")
    local total_started = now()
    local started = now()
    if backend == "gccjit" then compiler:lower(source) else compiler:compile(source) end
    local lower_elapsed = now() - started
    assert(backend == "gccjit" and compiler:lowered() or compiler:succeeded(), compiler:diagnostic_text())

    started = now()
    if backend == "gccjit" then
        compiler:cook(optimization)
        assert(compiler:succeeded(), compiler:diagnostic_text())
        assert(compiler:invoke() == expected)
        foreign_samples[index] = tonumber(compiler.metrics.compile_ns) / 1000
        driver_samples[index] = tonumber(compiler.metrics.acquire_ns + compiler.metrics.type_ns
            + compiler.metrics.function_ns + compiler.metrics.projection_ns + compiler.metrics.lookup_ns) / 1000
    else
        local session, err = CGcc.compile(c_source, {
            opt = optimization, out_dir = "target/gccjit_driver/c_gcc",
            name = "retained_eval", cache_key = tostring(index), libraries = {},
        })
        assert(session, err and err.message)
        local entry = assert(session:symbol("retained_eval", "int64_t (*)(void)"))
        assert(tonumber(entry()) == expected)
        session:free()
        foreign_samples[index], driver_samples[index] = (now() - started) * 1000000, 0
    end
    local backend_elapsed = now() - started
    lower_samples[index] = lower_elapsed * 1000000
    backend_samples[index] = backend_elapsed * 1000000
    total_samples[index] = (now() - total_started) * 1000000
end

if backend == "gccjit" then compiler:free() end
for _, values in ipairs { lower_samples, backend_samples, total_samples, foreign_samples, driver_samples } do
    table.sort(values)
end
local middle = math.floor((samples + 1) / 2)
print(("backend=%s terms=%d samples=%d opt=%d lower_us=%.3f backend_us=%.3f "
    .. "foreign_compile_us=%.3f driver_us=%.3f total_us=%.3f"):format(
    backend, terms, samples, optimization, lower_samples[middle], backend_samples[middle],
    foreign_samples[middle], driver_samples[middle], total_samples[middle]))
