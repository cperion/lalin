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

local function path_newer(path, than_path)
  if not file_exists(path) then return false end
  if not file_exists(than_path) then return true end
  return command_ok("[ " .. shell_quote(path) .. " -nt " .. shell_quote(than_path) .. " ]")
end

local function lua_sources_newer_than(path)
  if not file_exists(path) then return true end
  return command_ok("find lua -name '*.lua' -newer " .. shell_quote(path) .. " -print -quit | grep -q .")
end

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local function write_file(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
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
  io.write(string.format("%-32s %10.2f ns/call %9.2f Mcall/s  checksum=%s\n", row.label, row.ns, row.mops, tostring(row.checksum)))
end

local out_dir = "target/bench_native_backend"
assert(command_ok("mkdir -p " .. shell_quote(out_dir)))

local default_bank_lua = "target/lalin_binary/lalin_complete_native_template_bank.lua"
local default_bank_c = "target/lalin_binary/lalin_complete_native_template_bank.c"
local bank_lua = os.getenv("LALIN_NATIVE_BENCH_BANK_LUA") or default_bank_lua
local bank_so = os.getenv("LALIN_NATIVE_BENCH_BANK_SO") or "target/lalin_binary/lalin_complete_native_template_bank.so"
if bank_lua == default_bank_lua and (not file_exists(bank_lua) or not command_ok("make -q native-complete-bank >/dev/null 2>&1")) then
  io.write("complete C-owned native bank is missing or stale; building native-complete-bank first\n")
  assert(command_ok("make native-complete-bank"), "make native-complete-bank failed")
elseif not file_exists(bank_lua) then
  error("complete C-owned native bank Lua artifact not found: " .. bank_lua)
end
if bank_lua == default_bank_lua and (not file_exists(bank_so) or path_newer(default_bank_c, bank_so)) then
  io.write("compiling complete C-owned native bank shared object\n")
  assert(command_ok("gcc -shared -fPIC " .. shell_quote(default_bank_c) .. " -o " .. shell_quote(bank_so)), "failed to build complete bank shared object")
elseif not file_exists(bank_so) then
  error("complete C-owned native bank shared object not found: " .. bank_so)
end

local fast_bank_manifest = os.getenv("LALIN_NATIVE_BENCH_FAST_MANIFEST") or "benchmarks/native_fast_region_bench_bank_manifest.lua"
local fast_bank_c = os.getenv("LALIN_NATIVE_BENCH_FAST_BANK_C") or (out_dir .. "/lalin_fast_region_bench_bank.c")
local fast_bank_h = os.getenv("LALIN_NATIVE_BENCH_FAST_BANK_H") or (out_dir .. "/lalin_fast_region_bench_bank.h")
local fast_bank_lua = os.getenv("LALIN_NATIVE_BENCH_FAST_BANK_LUA") or (out_dir .. "/lalin_fast_region_bench_bank.lua")
local fast_bank_so = os.getenv("LALIN_NATIVE_BENCH_FAST_BANK_SO") or (out_dir .. "/lalin_fast_region_bench_bank.so")
if not file_exists(fast_bank_lua) or not file_exists(fast_bank_c) or not file_exists(fast_bank_h)
    or path_newer(fast_bank_manifest, fast_bank_lua) or path_newer("tools/gen_lalin_mc_bank.lua", fast_bank_lua) or lua_sources_newer_than(fast_bank_lua) then
  io.write("fast-region benchmark bank missing or stale; generating " .. fast_bank_lua .. "\n")
  assert(command_ok(table.concat({
    "LALIN_NATIVE_BANK_ID=lalin.native.fast-region.bench",
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(fast_bank_c), shell_quote(fast_bank_h), shell_quote(fast_bank_lua), shell_quote(fast_bank_manifest),
  }, " ")), "failed to generate fast-region benchmark bank")
end
if not file_exists(fast_bank_so) or path_newer(fast_bank_c, fast_bank_so) then
  io.write("compiling fast-region benchmark bank shared object\n")
  assert(command_ok("gcc -shared -fPIC " .. shell_quote(fast_bank_c) .. " -o " .. shell_quote(fast_bank_so)), "failed to build fast-region benchmark bank shared object")
end

local iterations = tonumber(os.getenv("LALIN_NATIVE_BENCH_ITERS") or arg[1]) or 10000000
local dump_disasm = os.getenv("LALIN_NATIVE_BENCH_DISASM") ~= "0"
local progress_enabled = os.getenv("LALIN_NATIVE_BENCH_PROGRESS") == "1"
local function progress(msg)
  if progress_enabled then io.stderr:write(msg .. "\n") end
end
local have_objdump = command_ok("command -v objdump >/dev/null 2>&1")
if dump_disasm and not have_objdump then
  error("LALIN_NATIVE_BENCH_DISASM requested but objdump is not available")
end

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local Backend = require("lalin.native_backend")(T)
local Support = require("lalin.native_template_support")(T)

local artifact = dofile(bank_lua)(T)
local target = Backend.host_target()
local bank = Backend.require_native_bank(artifact, target, artifact.manifest, bank_so)
local fast_artifact
local fast_bank
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
  local f = func("bench.const", s, {}, { b }, b.id)
  return f, s, "int32_t (*)(void)", { params = {}, result = "i32" }
end

local function i32_binary_func(name, op)
  local a, b, dst = Code.CodeValueId(name .. ".a"), Code.CodeValueId(name .. ".b"), Code.CodeValueId(name .. ".dst")
  local s = sig(name .. ".sig", { i32, i32 }, { i32 })
  local blk = block(name .. ".entry", {}, { inst(name .. ".inst", Code.CodeInstBinary(dst, op, i32, int_semantics(), a, b)) }, Code.CodeTermReturn({ dst }))
  local f = func(name, s, { Code.CodeParam(a, "a", i32, origin), Code.CodeParam(b, "b", i32, origin) }, { blk }, blk.id)
  return f, s, "int32_t (*)(int32_t, int32_t)", { params = { a, b }, result = "i32" }
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
  local f = func("bench.mul_add", s, { Code.CodeParam(a, "a", i32, origin), Code.CodeParam(b, "b", i32, origin) }, { blk }, blk.id)
  return f, s, "int32_t (*)(int32_t, int32_t)", { params = { a, b }, result = "i32" }
end

local function f64_add_func()
  local a, b, dst = Code.CodeValueId("bench.f64_add.a"), Code.CodeValueId("bench.f64_add.b"), Code.CodeValueId("bench.f64_add.dst")
  local s = sig("bench.f64_add.sig", { f64, f64 }, { f64 })
  local blk = block("bench.f64_add.entry", {}, { inst("bench.f64_add.inst", Code.CodeInstFloatBinary(dst, Core.BinAdd, f64, Code.CodeFloatStrict, a, b)) }, Code.CodeTermReturn({ dst }))
  local f = func("bench.f64_add", s, { Code.CodeParam(a, "a", f64, origin), Code.CodeParam(b, "b", f64, origin) }, { blk }, blk.id)
  return f, s, "double (*)(double, double)", { params = { a, b }, result = "f64" }
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
  local f = func("bench.branch", s, { Code.CodeParam(lhs, "lhs", i32, origin), Code.CodeParam(rhs, "rhs", i32, origin) }, { entry, true_block, false_block }, entry.id)
  return f, s, "int32_t (*)(int32_t, int32_t)", { params = { lhs, rhs }, result = "i32" }
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
  local f = func("bench.switch", s, { Code.CodeParam(key, "key", i32, origin) }, { entry, one, two, default }, entry.id)
  return f, s, "int32_t (*)(int32_t)", { params = { key }, result = "i32" }
end

local function cptr(frame)
  return ffi.cast("uint8_t *", frame)
end

local function i32_at(frame, offset)
  return ffi.cast("int32_t *", cptr(frame) + offset)
end

local function f64_at(frame, offset)
  return ffi.cast("double *", cptr(frame) + offset)
end

local function slot_offset(layout, id_text)
  for _, slot in ipairs(layout.slots or {}) do
    if slot.id.text == id_text then return slot.offset end
  end
  error("missing frame slot " .. id_text)
end

local function frame_offsets(graph, f, meta)
  local offsets = { params = {}, result = slot_offset(graph.frame_layout, "native.frame.result." .. f.id.text .. ".direct") }
  for i, value in ipairs(meta.params or {}) do
    offsets.params[i] = slot_offset(graph.frame_layout, "native.frame.slot." .. value.text .. ".param" .. tostring(i - 1))
  end
  return offsets
end

local function frame_buffer(layout)
  return ffi.new("uint8_t[?]", math.max(layout.size or 0, 1))
end

function Native.NativeRegionTransfer:bench_native_retarget_fast_entry(_redirects)
  return self
end
function Native.NativeRegionFallthrough:bench_native_retarget_fast_entry(redirects)
  return Native.NativeRegionFallthrough(redirects[self.to] or self.to)
end
function Native.NativeRegionJump:bench_native_retarget_fast_entry(redirects)
  return Native.NativeRegionJump(redirects[self.to] or self.to)
end
function Native.NativeRegionBranch:bench_native_retarget_fast_entry(redirects)
  return Native.NativeRegionBranch(self.condition, redirects[self.then_to] or self.then_to, redirects[self.else_to] or self.else_to)
end
function Native.NativeRegionSwitch:bench_native_retarget_fast_entry(redirects)
  local cases = {}
  for i, case in ipairs(self.cases or {}) do
    cases[i] = Native.NativeRegionSwitchCase(case.key, redirects[case.to] or case.to)
  end
  return Native.NativeRegionSwitch(self.key, self.step_shape, cases, redirects[self.default] or self.default)
end

local function installable_fast_region_plan(plan, func)
  local redirects, skip = {}, {}
  for _, region in ipairs(plan.regions or {}) do
    if asdl.isa(region.origin, Native.NativeCodeBlockRegion)
        and asdl.isa(region.body, Native.NativeFrameMicroOpRegion)
        and asdl.isa(region.transfer, Native.NativeRegionFallthrough) then
      redirects[region.id] = region.transfer.to
      skip[region.id] = true
    end
  end
  local regions = {}
  for _, region in ipairs(plan.regions or {}) do
    if not skip[region.id] then
      local transfer = region.transfer:bench_native_retarget_fast_entry(redirects)
      if asdl.isa(region.body, Native.NativeFrameMicroOpRegion) and asdl.isa(transfer, Native.NativeRegionFallthrough) then
        transfer = Native.NativeRegionJump(transfer.to)
      end
      local outputs = region.outputs
      if asdl.isa(transfer, Native.NativeRegionReturn) and #(region.outputs or {}) == 1 then
        local direct = nil
        local direct_id = "native.frame.result." .. func.id.text .. ".direct"
        for _, slot in ipairs(plan.frame_layout.slots or {}) do
          if slot.id.text == direct_id then direct = slot end
        end
        if direct ~= nil then
          local output = region.outputs[1]
          outputs = { Native.NativeRegionValueBinding(output.value, output.scalar, Native.NativeResidenceFrameSlot(direct)) }
        end
      end
      regions[#regions + 1] = Native.NativeFastRegion(
        region.id,
        region.origin,
        region.body,
        region.inputs,
        outputs,
        transfer
      )
    end
  end
  local entry = redirects[plan.entry] or plan.entry
  return Native.NativeFastRegionPlan(plan.target, plan.public_protocol, regions, entry, plan.exits, plan.frame_layout)
end

local scenarios = {
  {
    name = "const_i32", build = const_i32_func,
    native_loop = function(fn, n) local acc=0; for _=1,n do acc = acc + fn() end; return acc end,
    fast_loop = function(fn, frame, offsets, n) local acc=0; for _=1,n do fn(cptr(frame)); acc = acc + i32_at(frame, offsets.result)[0] end; return acc end,
    lua_loop = function(n) local acc=0; for _=1,n do acc = acc + 42 end; return acc end,
  },
  {
    name = "i32_add", build = function() return i32_binary_func("bench.i32_add", Core.BinAdd) end,
    native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i, 7) end; return acc end,
    fast_loop = function(fn, frame, offsets, n) local acc=0; for i=1,n do i32_at(frame, offsets.params[1])[0]=i; i32_at(frame, offsets.params[2])[0]=7; fn(cptr(frame)); acc = acc + i32_at(frame, offsets.result)[0] end; return acc end,
    lua_loop = function(n) local acc=0; for i=1,n do acc = acc + (i + 7) end; return acc end,
  },
  {
    name = "i32_mul", build = function() return i32_binary_func("bench.i32_mul", Core.BinMul) end,
    native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 1024, 13) end; return acc end,
    fast_loop = function(fn, frame, offsets, n) local acc=0; for i=1,n do i32_at(frame, offsets.params[1])[0]=i%1024; i32_at(frame, offsets.params[2])[0]=13; fn(cptr(frame)); acc = acc + i32_at(frame, offsets.result)[0] end; return acc end,
    lua_loop = function(n) local acc=0; for i=1,n do acc = acc + ((i % 1024) * 13) end; return acc end,
  },
  {
    name = "i32_mul_add", build = i32_mul_add_func,
    native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 1024, 13) end; return acc end,
    fast_loop = function(fn, frame, offsets, n) local acc=0; for i=1,n do i32_at(frame, offsets.params[1])[0]=i%1024; i32_at(frame, offsets.params[2])[0]=13; fn(cptr(frame)); acc = acc + i32_at(frame, offsets.result)[0] end; return acc end,
    lua_loop = function(n) local acc=0; for i=1,n do acc = acc + ((i % 1024) * 13 + 5) end; return acc end,
  },
  {
    name = "f64_add", build = f64_add_func,
    native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i * 0.25, 1.5) end; return string.format("%.3f", acc) end,
    fast_loop = function(fn, frame, offsets, n) local acc=0; for i=1,n do f64_at(frame, offsets.params[1])[0]=i*0.25; f64_at(frame, offsets.params[2])[0]=1.5; fn(cptr(frame)); acc = acc + f64_at(frame, offsets.result)[0] end; return string.format("%.3f", acc) end,
    lua_loop = function(n) local acc=0; for i=1,n do acc = acc + (i * 0.25 + 1.5) end; return string.format("%.3f", acc) end,
  },
  {
    name = "branch", build = branch_func,
    native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 4, 2) end; return acc end,
    fast_loop = function(fn, frame, offsets, n) local acc=0; for i=1,n do i32_at(frame, offsets.params[1])[0]=i%4; i32_at(frame, offsets.params[2])[0]=2; fn(cptr(frame)); acc = acc + i32_at(frame, offsets.result)[0] end; return acc end,
    lua_loop = function(n) local acc=0; for i=1,n do if (i % 4) < 2 then acc = acc + 11 else acc = acc + 22 end end; return acc end,
  },
  {
    name = "switch", build = switch_func,
    native_loop = function(fn, n) local acc=0; for i=1,n do acc = acc + fn(i % 4) end; return acc end,
    fast_loop = function(fn, frame, offsets, n) local acc=0; for i=1,n do i32_at(frame, offsets.params[1])[0]=i%4; fn(cptr(frame)); acc = acc + i32_at(frame, offsets.result)[0] end; return acc end,
    lua_loop = function(n) local acc=0; for i=1,n do local k=i%4; if k==1 then acc=acc+10 elseif k==2 then acc=acc+20 else acc=acc+99 end end; return acc end,
  },
}

local function disasm_executable(label, exe, force)
  if not (dump_disasm or force) then return nil end
  assert(have_objdump, "objdump is required for native benchmark disassembly")
  assert(exe.base_address ~= nil and exe.base_address ~= 0, "native executable has no base address for " .. label)
  assert(exe.size ~= nil and exe.size > 0 and exe.size < 1024 * 1024, "native executable has suspicious size for " .. label .. ": " .. tostring(exe.size))
  local bin_path = out_dir .. "/" .. label .. ".bin"
  local asm_path = out_dir .. "/" .. label .. ".asm"
  local bytes = ffi.string(ffi.cast("const char *", exe.base_address), exe.size)
  write_file(bin_path, bytes)
  assert(command_ok("objdump -D -b binary -m i386:x86-64 -M intel " .. shell_quote(bin_path) .. " > " .. shell_quote(asm_path)), "objdump failed for " .. label)
  return read_file(asm_path)
end

local function analyze_asm(asm)
  local mnemonics = {}
  local has_imul, has_add_like, has_ret, has_stack_spill = false, false, false, false
  for line in tostring(asm):gmatch("[^\n]+") do
    local mnemonic = line:match("^%s*[%da-fA-F]+:%s+[%da-fA-F ]+%s+([%a%.]+)")
    if mnemonic ~= nil then
      mnemonics[#mnemonics + 1] = mnemonic
      if mnemonic == "imul" then has_imul = true end
      if mnemonic == "add" or mnemonic == "lea" then has_add_like = true end
      if mnemonic == "ret" or mnemonic == "retq" then has_ret = true end
    end
    if line:find("%[rsp", 1, false) or line:find("%[rbp", 1, false) then has_stack_spill = true end
  end
  return {
    mnemonics = mnemonics,
    instruction_count = #mnemonics,
    has_imul = has_imul,
    has_add_like = has_add_like,
    has_ret = has_ret,
    has_stack_spill = has_stack_spill,
    compact_mul_add = has_imul and has_add_like and has_ret and not has_stack_spill and #mnemonics <= 8,
  }
end

local function install_graph(bank_for_graph, graph)
  local install_plan = graph:select_native_bank_install_plan(Native.NativeBankInstallPlanSelectionInput(target, runtime))
  return Native.NativeBankInstallRequest(bank_for_graph, install_plan, Native.NativeExecutableAllocatorMmap):install_native()
end

local function reject_text(install)
  local out = {}
  for _, reject in ipairs(install.rejects or {}) do out[#out + 1] = tostring(reject) end
  return table.concat(out, "; ")
end

io.write(string.format("native backend benchmark: iterations=%d baseline_bank=%s fast_bank=%s\n", iterations, bank_so, fast_bank_so))
io.write("compile/install/disassembly summary:\n")

local compiled = {}
local compact_report
for _, scenario in ipairs(scenarios) do
  progress("baseline build " .. scenario.name)
  local f, s, ffi_sig, meta = scenario.build()
  local t0 = monotime()
  progress("baseline plan " .. scenario.name)
  local baseline_graph = f:plan_native_copy(Native.NativePlanInput(target, runtime, bank), nil, s)
  local t1 = monotime()
  progress("baseline install " .. scenario.name)
  local baseline_install = install_graph(bank, baseline_graph)
  local t2 = monotime()
  if not asdl.isa(baseline_install, Native.NativeInstallSucceeded) then
    error("baseline install rejected for " .. scenario.name .. ": " .. reject_text(baseline_install))
  end
  local baseline_exe = baseline_install.executable
  progress("baseline disasm " .. scenario.name)
  disasm_executable("baseline_" .. scenario.name, baseline_exe, false)
  progress("baseline cast " .. scenario.name)
  local baseline_fn = ffi.cast(ffi_sig, baseline_exe.entry_address)
  local smoke_n = math.min(iterations, 1000)
  local expected = scenario.lua_loop(smoke_n)
  assert(tostring(scenario.native_loop(baseline_fn, smoke_n)) == tostring(expected), "baseline checksum mismatch for " .. scenario.name)
  compiled[#compiled + 1] = {
    scenario = scenario,
    func = f,
    signature = s,
    ffi_sig = ffi_sig,
    meta = meta,
    baseline = { install = baseline_install, graph = baseline_graph, executable = baseline_exe, fn = baseline_fn, plan_s = t1 - t0, install_s = t2 - t1 },
  }
end

-- The generated banks intentionally export the same small C ABI symbol names.
-- Install all baseline micro-op graphs before dlopening the fast-region bank so
-- symbol interposition cannot route a complete-bank install through the bench
-- fast-bank bridge on platforms that load those symbols globally.
fast_artifact = dofile(fast_bank_lua)(T)
fast_bank = Backend.require_native_bank(fast_artifact, target, fast_artifact.manifest, fast_bank_so)

for _, item in ipairs(compiled) do
  local scenario, f, s, ffi_sig, meta = item.scenario, item.func, item.signature, item.ffi_sig, item.meta
  local t3 = monotime()
  local raw_fast_plan = f:plan_native_fast_regions(Native.NativePlanInput(target, runtime, fast_bank), nil, s)
  local fast_plan = installable_fast_region_plan(raw_fast_plan, f)
  local fast_graph = fast_plan:lower_native_template_graph()
  local t4 = monotime()
  local fast_install = install_graph(fast_bank, fast_graph)
  local t5 = monotime()
  if not asdl.isa(fast_install, Native.NativeInstallSucceeded) then
    error("fast-region install rejected for " .. scenario.name .. ": " .. reject_text(fast_install))
  end
  local fast_exe = fast_install.executable
  progress(string.format("fast exe %s base=0x%x entry=0x%x size=%d", scenario.name, fast_exe.base_address, fast_exe.entry_address, fast_exe.size))
  disasm_executable("fast_region_" .. scenario.name, fast_exe, false)
  local fast_fn = ffi.cast("void (*)(uint8_t *)", fast_exe.entry_address)
  local fast_frame = frame_buffer(fast_graph.frame_layout)
  local fast_offsets = frame_offsets(fast_graph, f, meta)
  progress("fast result offset " .. scenario.name .. " = " .. tostring(fast_offsets.result))

  local public_fast
  if scenario.name == "i32_mul_add" then
    local public_graph = f:plan_native_copy(Native.NativePlanInput(target, runtime, fast_bank), nil, s)
    local public_install = install_graph(fast_bank, public_graph)
    if not asdl.isa(public_install, Native.NativeInstallSucceeded) then
      error("fast public i32_mul_add install rejected: " .. reject_text(public_install))
    end
    local public_exe = public_install.executable
    local asm = disasm_executable("fast_public_i32_mul_add", public_exe, true)
    local analysis = analyze_asm(asm)
    if #public_graph.nodes ~= 1 then
      error("fast public i32_mul_add should lower to one fused node, got " .. tostring(#public_graph.nodes))
    end
    if not analysis.compact_mul_add then
      error("fast public i32_mul_add is not compact/no-spill; mnemonics=" .. table.concat(analysis.mnemonics, ","))
    end
    compact_report = string.format("  fast_public_i32_mul_add nodes=%d code=%dB insns=%d mnemonics=%s", #public_graph.nodes, public_exe.size, analysis.instruction_count, table.concat(analysis.mnemonics, ","))
    public_fast = { install = public_install, graph = public_graph, executable = public_exe, fn = ffi.cast(ffi_sig, public_exe.entry_address) }
  end

  local smoke_n = math.min(iterations, 1000)
  local expected = scenario.lua_loop(smoke_n)
  local fast_smoke = scenario.fast_loop(fast_fn, fast_frame, fast_offsets, smoke_n)
  assert(tostring(fast_smoke) == tostring(expected), "fast-region checksum mismatch for " .. scenario.name .. ": got " .. tostring(fast_smoke) .. " expected " .. tostring(expected))
  if public_fast ~= nil then
    local public_smoke = scenario.native_loop(public_fast.fn, smoke_n)
    assert(tostring(public_smoke) == tostring(expected), "fast public checksum mismatch for " .. scenario.name .. ": got " .. tostring(public_smoke) .. " expected " .. tostring(expected))
  end

  item.fast = { install = fast_install, graph = fast_graph, executable = fast_exe, fn = fast_fn, frame = fast_frame, offsets = fast_offsets, plan_s = t4 - t3, install_s = t5 - t4 }
  item.public_fast = public_fast
  io.write(string.format("  %-12s baseline nodes=%2d code=%4dB plan=%7.3fms install=%7.3fms | fast-region regions=%2d nodes=%2d code=%4dB plan=%7.3fms install=%7.3fms\n",
    scenario.name,
    #item.baseline.graph.nodes, item.baseline.executable.size, item.baseline.plan_s * 1e3, item.baseline.install_s * 1e3,
    #raw_fast_plan.regions, #fast_graph.nodes, fast_exe.size, (t4 - t3) * 1e3, (t5 - t4) * 1e3))
end

if compact_report then
  io.write("compact fused a*b+5 verification:\n" .. compact_report .. "\n")
end

io.write("\nruntime throughput (baseline public ABI, fast-region frame ABI, LuaJIT loop baseline):\n")
for _, item in ipairs(compiled) do
  local scenario = item.scenario
  scenario.native_loop(item.baseline.fn, math.min(iterations, 10000))
  scenario.fast_loop(item.fast.fn, item.fast.frame, item.fast.offsets, math.min(iterations, 10000))
  scenario.lua_loop(math.min(iterations, 10000))
  print_row(bench_loop("baseline native " .. scenario.name, iterations, function(n) return scenario.native_loop(item.baseline.fn, n) end))
  print_row(bench_loop("fast-region  " .. scenario.name, iterations, function(n) return scenario.fast_loop(item.fast.fn, item.fast.frame, item.fast.offsets, n) end))
  if item.public_fast ~= nil then
    scenario.native_loop(item.public_fast.fn, math.min(iterations, 10000))
    print_row(bench_loop("fast-public  " .. scenario.name, iterations, function(n) return scenario.native_loop(item.public_fast.fn, n) end))
  end
  print_row(bench_loop("lua          " .. scenario.name, iterations, scenario.lua_loop))
end

if dump_disasm then
  io.write("\nassembly dumps written to " .. out_dir .. "/baseline_*.asm, fast_region_*.asm, and fast_public_*.asm\n")
else
  io.write("\ncompact fast_public_i32_mul_add disassembly written to " .. out_dir .. "/fast_public_i32_mul_add.asm\n")
end
