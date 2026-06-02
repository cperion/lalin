#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./experiments/lua_interpreter_vm/spongejit/src/?.lua;./experiments/lua_interpreter_vm/spongejit/src/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Foundry = require("lua_compile.lua_compile_foundry")

assert(package.loaded["src.ssa"] == nil, "LuaCompile foundry must not require old src.ssa")
assert(package.loaded["src.ssa_ir"] == nil, "LuaCompile foundry must not require old src.ssa_ir")
assert(package.loaded["src.ssa_to_stencil"] == nil, "LuaCompile foundry must not require old src.ssa_to_stencil")
assert(package.loaded["src.stencil_lower"] == nil, "LuaCompile foundry must not require old src.stencil_lower")

local windows = {
  {
    ops = { { op = "ADDI", pc = 1, a = 1, b = 1, c = 128, sc = 1 } },
    count = 3,
    fact_bundles = { { { slot = 1, predicate = "is_i64" } } },
  },
  {
    ops = { { op = "ADDK", pc = 1, a = 1, b = 1, c = 2 } },
    count = 5,
    fact_bundles = { { { slot = 1, predicate = "is_i64" }, { const = 2, predicate = "const_i64", value = 1 } } },
  },
  {
    ops = { { op = "GETTABLE", pc = 7, a = 1, b = 2, c = 3 } },
    count = 1,
    fact_bundles = { {} },
  },
}

local result = Foundry.run_windows(windows, { max_fact_combos = 4 })
assert(result.schema == "sponjit.lua_compile_foundry.v1")
assert(result.stats.windows == 3)
assert(result.stats.compiles == 3)
assert(result.stats.ok == 2)
assert(result.stats.rejected == 1)
assert(result.stats.unique_representatives == 1, "ADDI and ADDK should dedupe by LuaNF+LuaContract, not source opcode chain")
assert(result.rejection_reasons.MissingFact or result.rejection_reasons.MissingPayloadLease, "missing table evidence must be recorded structurally")

local rep = result.representatives[1]
assert(rep.normal_form_key and #rep.normal_form_key > 20, "normal-form key missing")
assert(rep.contract_key and #rep.contract_key > 20, "contract key missing")
assert(rep.representative_key:find("LuaContract", 1, true), "representative must pair LuaNF and LuaContract")
assert(rep.moonlift_source and rep.moonlift_source:match("local lua_compile_foundry_kernel = func"), "Moonlift source missing")
assert(rep.moon_out_kernel and rep.moon_out_kernel.kind == "InlineSpan", "MoonOut kernel summary missing")
assert(#rep.aliases == 2, "source opcode windows must survive as aliases")
local saw_addi, saw_addk = false, false
for _, a in ipairs(rep.aliases) do
  local op = a.source_ops and a.source_ops[1] and a.source_ops[1].op
  if op == "ADDI" then saw_addi = true end
  if op == "ADDK" then saw_addk = true end
  assert(a.count == 3 or a.count == 5)
end
assert(saw_addi and saw_addk, "aliases must preserve distinct source opcode windows")

local tmp = os.tmpname()
os.remove(tmp)
local mk_ok = os.execute("mkdir -p " .. string.format("%q", tmp))
assert(mk_ok == true or mk_ok == 0)
Foundry.write_artifacts(result, tmp)
local f = assert(io.open(tmp .. "/lua_compile_representatives.json", "rb"))
local text = f:read("*a"); f:close()
assert(text:match("lua_compile_foundry%.v1"), "artifact schema missing")
assert(text:match("moonlift_source"), "artifact must include emitted source")
assert(text:match("normal_form_key") and text:match("contract_key"), "artifact must include semantic keys")

-- Maintained worker entrypoint writes LuaCompile vocabulary artifacts.
local chunk = { schema = "sponjit.lua_compile_foundry.chunk.v1", chunk = 1, windows = windows }
Foundry.write_json(tmp .. "/lua_compile_chunk_1.json", chunk)
local cmd = "cd experiments/lua_interpreter_vm/spongejit && SPON_TMP=" .. string.format("%q", tmp) .. " MAX_FACT_COMBOS=4 luajit src/worker_compile.lua 1 >/tmp/lua_compile_foundry_worker.out 2>/tmp/lua_compile_foundry_worker.err"
local ok = os.execute(cmd)
assert(ok == true or ok == 0, "worker_compile.lua LuaCompile worker failed; see /tmp/lua_compile_foundry_worker.err")
local wf = assert(io.open(tmp .. "/lua_compile_worker_1.json", "rb"))
local worker_text = wf:read("*a"); wf:close()
assert(worker_text:match("lua_compile_foundry%.v1"), "worker artifact schema missing")
assert(worker_text:match("moonlift_source"), "worker artifact must include MoonOut emission")
assert(not package.loaded["src.ssa"], "worker test must not load old src.ssa in this process")

os.execute("rm -rf " .. string.format("%q", tmp))
print("ok - SpongeJIT LuaCompile foundry replacement")
