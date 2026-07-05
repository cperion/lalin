package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
  io.write("skip native backend benchmark: requires x64 non-Windows little-endian 64-bit host\n")
  os.exit(0)
end

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function command_ok(cmd)
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local function monotime()
  return os.clock()
end

local function bench_loop(label, iterations, fn)
  collectgarbage("collect")
  local start = monotime()
  local checksum = fn(iterations)
  local elapsed = monotime() - start
  local ns = elapsed * 1e9 / iterations
  return { label = label, elapsed = elapsed, ns = ns, mops = iterations / elapsed / 1e6, checksum = checksum }
end

local function print_row(row)
  io.write(string.format("%-24s %10.2f ns/call %9.2f Mcall/s  checksum=%s\n", row.label, row.ns, row.mops, tostring(row.checksum)))
end

local out_dir = "target/bench_native_backend"
assert(command_ok("mkdir -p " .. shell_quote(out_dir)))

local bank_lua = os.getenv("LALIN_NATIVE_BENCH_BANK_LUA") or "target/lalin_binary/lalin_complete_native_template_bank.lua"
local bank_so = os.getenv("LALIN_NATIVE_BENCH_BANK_SO") or "target/lalin_binary/lalin_complete_native_template_bank.so"
if not file_exists(bank_lua) or not file_exists(bank_so) then
  io.write("complete C-owned native bank not found; building native-complete-bank first\n")
  assert(command_ok("make native-complete-bank"), "make native-complete-bank failed")
  if not file_exists(bank_so) then
    assert(command_ok("gcc -shared -fPIC " .. shell_quote("target/lalin_binary/lalin_complete_native_template_bank.c") .. " -o " .. shell_quote(bank_so)), "failed to build complete bank shared object")
  end
end

local iterations = tonumber(os.getenv("LALIN_NATIVE_BENCH_ITERS") or arg[1]) or 10000000
local dump_disasm = os.getenv("LALIN_NATIVE_BENCH_DISASM") ~= "0"

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local Backend = require("lalin.native_backend")(T)

local artifact = dofile(bank_lua)(T)
local target = Backend.host_target()
local bank = Backend.require_native_bank(artifact, target, artifact.manifest, bank_so)
local runtime = Backend.empty_runtime()
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool8 = Code.CodeTyBool8
local f64 = Code.CodeTyFloat(64)

local function int_semantics()
  return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
end

local function inst(id, op)
  return Code.CodeInst(Code.CodeInstId(id), op, origin)
end

local function block(id, params, insts, term)
  return Code.CodeBlock(Code.CodeBlockId(id), id:match("[^%.]+$") or id, params or {}, insts or {}, Code.CodeTerm(Code.CodeTermId(id .. ".term"), term, origin), origin)
end

local function func(name, sig, params, blocks, entry)
  return Code.CodeFunc(Code.CodeFuncId(name), name:gsub("[^%w_]", "_"), Code.CodeLinkageExport, sig.id, params or {}, {}, entry, blocks, origin)
end

local function sig(id, params, results)
  return Code.CodeSig(Code.CodeSigId(id), params or {}, results or {})
end

local function const_i32_func()
  local dst = Code.CodeValueId("bench.const.dst")
  local s = sig("bench.const.sig", {}, { i32 })
  local b = block("bench.const.entry", {}, { inst("bench.const.inst", Code.CodeInstConst(dst, Code.CodeConstLiteral(i32, Core.LitInt("42")))) }, Code.CodeTermReturn({ dst }))
  return func("bench.const", s, {}, { b }, b.id), s, "int32_t (*)(void)"
end

local function i32_binary_func(name, op)
  local a, b, dst = Code.CodeValueId(name .. ".a"), Code.CodeValueId(name .. ".b"), Code.CodeValueId(name .. ".dst")
  local s = sig(name .. ".sig", { i32, i32 }, { i32 })
  local blk = block(name .. ".entry", {}, { inst(name .. ".inst", Code.CodeInstBinary(dst, op, i32, int_semantics(), a, b)) }, Code.CodeTermReturn({ dst }))
  return func(name, s, { Code.CodeParam(a, "a", i32, origin), Code.CodeParam(b, "b", i32, origin) }, { blk }, blk.id), s, "int32_t (*)(int32_t, int32_t)"
end

local function i32_mul_add_func()
  local a, b = Code.CodeValueId("bench.mul_add.a"), Code.CodeValueId("bench.mul_add.b")
  local mul, c5, dst = Code.CodeValueId("bench.mul_add.mul"), Code.CodeValueId("bench.mul_add.c5"), Code.CodeValueId("bench.mul_add.dst")
  local s = sig("bench.mul_add.sig", { i32, i32 }, { i32 })
  local blk = block("bench.mul_add.entry", {}, {
    inst("bench.mul_add.mul", Code.CodeInstBinary(mul, Core.BinMul, i32, int_semantics(), a, b)),
    inst("bench.mul_add.c5", Code.CodeInstConst(c5, Code.CodeConstLiteral(i32, Core.LitInt("5")))),
    inst("bench.mul_add.add", Code.CodeInstBinary(dst, Core.BinAdd, i32, int_semantics(), mul, c5)),
  }, Code.CodeTermReturn({ dst }))
  return func("bench.mul_add", s, { Code.CodeParam(a, "a", i32, origin), Code.CodeParam(b, "b", i32, origin) }, { blk }, blk.id), s, "int32_t (*)(int32_t, int32_t)"
end

local function f64_add_func()
  local a, b, dst = Code.CodeValueId("bench.f64_add.a"), Code.CodeValueId("bench.f64_add.b"), Code.CodeValueId("bench.f64_add.dst")
  local s = sig("bench.f64_add.sig", { f64, f64 }, { f64 })
  local blk = block("bench.f64_add.entry", {}, { inst("bench.f64_add.inst", Code.CodeInstFloatBinary(dst, Core.BinAdd, f64, Code.CodeFloatStrict, a, b)) }, Code.CodeTermReturn({ dst }))
  return func("bench.f64_add", s, { Code.CodeParam(a, "a", f64, origin), Code.CodeParam(b, "b", f64, origin) }, { blk }, blk.id), s, "double (*)(double, double)"
end

local function branch_func()
  local lhs = Code.CodeValueId("bench.branch.lhs")
  local rhs = Code.CodeValueId("bench.branch.rhs")
  local cond = Code.CodeValueId("bench.branch.cond")
  local true_dst = Code.CodeValueId("bench.branch.true.value")
  local false_dst = Code.CodeValueId("bench.branch.false.value")
  local s = sig("bench.branch.sig", { i32, i32 }, { i32 })
  local entry = block("bench.branch.entry", {}, {
    inst("bench.branch.cmp", Code.CodeInstCompare(cond, Core.CmpLt, i32, lhs, rhs)),
  }, Code.CodeTermBranch(cond, Code.CodeBlockId("bench.branch.true"), {}, Code.CodeBlockId("bench.branch.false"), {}))
  local true_block = block("bench.branch.true", {}, { inst("bench.branch.true.const", Code.CodeInstConst(true_dst, Code.CodeConstLiteral(i32, Core.LitInt("11")))) }, Code.CodeTermReturn({ true_dst }))
  local false_block = block("bench.branch.false", {}, { inst("bench.branch.false.const", Code.CodeInstConst(false_dst, Code.CodeConstLiteral(i32, Core.LitInt("22")))) }, Code.CodeTermReturn({ false_dst }))
  return func("bench.branch", s, { Code.CodeParam(lhs, "lhs", i32, origin), Code.CodeParam(rhs, "rhs", i32, origin) }, { entry, true_block, false_block }, entry.id), s, "int32_t (*)(int32_t, int32_t)"
end

local function switch_func()
  local key = Code.CodeValueId("bench.switch.key")
  local function const_block(id, value)
    local dst = Code.CodeValueId(id .. ".value")
    return block(id, {}, { inst(id .. ".const", Code.CodeInstConst(dst, Code.CodeConstLiteral(i32, Core.LitInt(tostring(value))))) }, Code.CodeTermReturn({ dst }))
  end
  local s = sig("bench.switch.sig", { i32 }, { i32 })
  local entry = block("bench.switch.entry", {}, {}, Code.CodeTermSwitch(key, {
    Code.CodeSwitchCase(Core.LitInt("1"), Code.CodeBlockId("bench.switch.one"), {}),
    Code.CodeSwitchCase(Core.LitInt("2"), Code.CodeBlockId("bench.switch.two"), {}),
  }, Code.CodeBlockId("bench.switch.default"), {}))
  local one, two, default = const_block("bench.switch.one", 10), const_block("bench.switch.two", 20), const_block("bench.switch.default", 99)
  return func("bench.switch", s, { Code.CodeParam(key, "key", i32, origin) }, { entry, one, two, default }, entry.id), s, "int32_t (*)(int32_t)"
end

local scenarios = {
  { name = "const_i32", build = const_i32_func, native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn() end; return acc end, lua_loop = function(n) local acc=0; for i=1,n do acc = acc + 42 end; return acc end },
  { name = "i32_add", build = function() return i32_binary_func("bench.i32_add", Core.BinAdd) end, native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i, 7) end; return acc end, lua_loop = function(n) local acc=0; for i=1,n do acc = acc + (i + 7) end; return acc end },
  { name = "i32_mul", build = function() return i32_binary_func("bench.i32_mul", Core.BinMul) end, native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 1024, 13) end; return acc end, lua_loop = function(n) local acc=0; for i=1,n do acc = acc + ((i % 1024) * 13) end; return acc end },
  { name = "i32_mul_add", build = i32_mul_add_func, native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 1024, 13) end; return acc end, lua_loop = function(n) local acc=0; for i=1,n do acc = acc + ((i % 1024) * 13 + 5) end; return acc end },
  { name = "f64_add", build = f64_add_func, native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i * 0.25, 1.5) end; return string.format("%.3f", acc) end, lua_loop = function(n) local acc=0; for i=1,n do acc = acc + (i * 0.25 + 1.5) end; return string.format("%.3f", acc) end },
  { name = "branch", build = branch_func, native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 4, 2) end; return acc end, lua_loop = function(n) local acc=0; for i=1,n do if (i % 4) < 2 then acc = acc + 11 else acc = acc + 22 end end; return acc end },
  { name = "switch", build = switch_func, native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 4) end; return acc end, lua_loop = function(n) local acc=0; for i=1,n do local k=i%4; if k==1 then acc=acc+10 elseif k==2 then acc=acc+20 else acc=acc+99 end end; return acc end },
}

io.write(string.format("native backend benchmark: iterations=%d bank=%s\n", iterations, bank_so))
io.write("compile/install summary:\n")

local compiled = {}
for _, scenario in ipairs(scenarios) do
  local f, s, ffi_sig = scenario.build()
  local t0 = monotime()
  local graph = f:plan_native_copy(Native.NativePlanInput(target, runtime, bank), nil, s)
  local t1 = monotime()
  local install_plan = graph:select_native_bank_install_plan(Native.NativeBankInstallPlanSelectionInput(target, runtime))
  local install = Native.NativeBankInstallRequest(bank, install_plan, Native.NativeExecutableAllocatorMmap):install_native()
  local t2 = monotime()
  if not asdl.isa(install, Native.NativeInstallSucceeded) then
    io.write(string.format("  %-12s SKIP install rejected\n", scenario.name))
    for _, reject in ipairs(install.rejects or {}) do io.write("    " .. tostring(reject) .. "\n") end
  else
  local exe = install.executable
  local fn = ffi.cast(ffi_sig, exe.entry_address)
  compiled[#compiled + 1] = { scenario = scenario, graph = graph, executable = exe, fn = fn, ffi_sig = ffi_sig, plan_s = t1 - t0, compile_s = t2 - t1 }
  io.write(string.format("  %-12s nodes=%2d code=%4dB plan=%7.3fms install=%7.3fms entry=0x%x\n", scenario.name, #graph.nodes, exe.size, (t1 - t0) * 1e3, (t2 - t1) * 1e3, exe.entry_address))
  if dump_disasm then
    local bin_path = out_dir .. "/" .. scenario.name .. ".bin"
    local asm_path = out_dir .. "/" .. scenario.name .. ".asm"
    local bytes = ffi.string(ffi.cast("const char *", exe.base_address), exe.size)
    local bf = assert(io.open(bin_path, "wb")); bf:write(bytes); bf:close()
    os.execute("objdump -D -b binary -m i386:x86-64 -M intel " .. shell_quote(bin_path) .. " > " .. shell_quote(asm_path) .. " 2>/dev/null")
  end
  end
end

io.write("\nruntime throughput (direct FFI call to native entry vs LuaJIT loop baseline):\n")
for _, item in ipairs(compiled) do
  local scenario = item.scenario
  -- Warm up both loops so LuaJIT traces the benchmark harness where possible.
  scenario.native_loop(item.fn, math.min(iterations, 10000))
  scenario.lua_loop(math.min(iterations, 10000))
  print_row(bench_loop("native " .. scenario.name, iterations, function(n) return scenario.native_loop(item.fn, n) end))
  print_row(bench_loop("lua    " .. scenario.name, iterations, scenario.lua_loop))
end

if dump_disasm then
  io.write("\nassembly dumps written to " .. out_dir .. "/*.asm\n")
end
