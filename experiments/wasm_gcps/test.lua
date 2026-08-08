package.path = "./?.lua;./?/init.lua;" .. package.path

local Owner = require("experiments.wasm_gcps.cps_owner")

local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local wasm_path = os.tmpname() .. ".wasm"
local command = ("wat2wasm %q -o %q"):format(base .. "sample.wat", wasm_path)
local status = os.execute(command)
assert(status == true or status == 0, "wat2wasm failed")

local exports, module, artifact = Owner.loadfile(wasm_path)
local prepared_exports, prepared_module, prepared = Owner.loadfile(wasm_path)
os.remove(wasm_path)

assert(#module.functions == 2 and #prepared_module.functions == 2)
assert(type(exports.sum) == "function" and type(exports.mixed) == "function")

local cold = artifact:projection()
assert(cold.stats.compiled == 0)
assert(cold.stats.private_clones == 2) -- Private public entries, but no opcode occurrences.

assert(exports.sum(10) == 55)
local partly_ready = artifact:projection()
assert(partly_ready.stats.compiled == #module.functions[1].instructions - 2)
assert(partly_ready.stats.compiled <
    #module.functions[1].instructions + #module.functions[2].instructions)

for n = 0, 1000 do
    local expected_sum = n * (n + 1) / 2
    assert(exports.sum(n) == expected_sum)
    assert(exports.mixed(n) == 1.5 * expected_sum)
end

local projection = artifact:projection()
local instruction_count = #module.functions[1].instructions + #module.functions[2].instructions
local reached_count = instruction_count - 4 -- Two structural ENDs follow a BR in each function.
assert(#projection.functions == reached_count)
assert(#projection.compile_order == reached_count)
assert(projection.stats.compiled == reached_count)
assert(projection.stats.private_clones == reached_count + #module.functions)
assert(projection.stats.private_dump_bytes > 0)
assert(#projection.rejections == 0)

local previous_function, previous_pc = -1, -1
local listing = {}
for _, record in ipairs(projection.functions) do
    assert(record.status == "ready")
    assert(record.key and record.label and record.source)
    assert(projection.by_key[record.key] == record)
    if record.function_index ~= previous_function then
        assert(record.function_index > previous_function)
        previous_function, previous_pc = record.function_index, -1
    end
    assert(record.pc > previous_pc)
    previous_pc = record.pc
    listing[#listing + 1] = record.source
end
listing = table.concat(listing, "\n")
assert(listing:find(
    "pc_12_i32_add = function(self, v1, v2) " ..
    "return pc_13_local_set(self, bit.tobit(v1 + v2)) end", 1, true))
assert(listing:find("pc_18_br", 1, true))
assert(listing:find("function(self, v1, v2)", 1, true))
assert(not listing:find("...", 1, true))
assert(not listing:find("self.stack", 1, true))
assert(not listing:find("self.sp", 1, true))

assert(prepared:projection().stats.compiled == 0)
prepared:prepare()
assert(prepared:projection().stats.compiled == reached_count)
assert(prepared_exports.sum(1000) == 500500)
assert(prepared_exports.mixed(1000) == 750750)

print("Wasm lazy-owner CPS machine: ok")

