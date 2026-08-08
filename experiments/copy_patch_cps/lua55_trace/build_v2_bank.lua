package.path = "./?.lua;./?/init.lua;" .. package.path

-- build_v2_bank: the Native CPS Frame V2 bank.
-- Compiles opcode_v2_core_stencils.c (the standalone V2-only source) and
-- extracts every `lua55_v2_*` and `lua55_cps_*` section. The bank contains
-- NO V1 poly, learner, or residual sections. Relocations are classified:
-- R_X86_64_PLT32 -> lua55_residual_next (addend -4) are successor edges;
-- anything else rejects the build.

local bit = require("bit")
local function q(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function run(command)
    local ok, why, status = os.execute(command)
    assert(ok, ("command failed (%s %s): %s"):format(tostring(why), tostring(status), command))
end
local function capture(command)
    local pipe = assert(io.popen(command, "r")); local value = pipe:read("*a")
    assert(pipe:close()); return value
end
local function read(path)
    local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value
end

local ROOT = "experiments/copy_patch_cps/lua55_trace"
local OUT = "target/copy_patch_cps/lua55_trace/opcode_v2"
run("mkdir -p " .. q(OUT))

local SOURCE = "opcode_v2_core_stencils.c"
local object = OUT .. "/core.o"
run(table.concat({
    "gcc -O3 -fno-pic -fno-jump-tables -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q(ROOT .. "/" .. SOURCE), "-c -o", q(object),
}, " "))

-- per-section relocations, tracked by the named relocation section
local relocs = {}
local current_reloc_section
for line in capture("readelf -rW " .. q(object)):gmatch("[^\n]+") do
    local section = line:match("^Relocation section '([^']+)'")
    if section then
        current_reloc_section = section
        relocs[section] = {}
    else
        local at, kind, symbol, sign, addend = line:match(
            "^%s*([%da-fA-F]+)%s+[%da-fA-F]+%s+(R_%S+)%s+[%da-fA-F]+%s+(%S+)%s+([+-])%s+([%da-fA-F]+)")
        if at then
            assert(current_reloc_section, "relocation row before section header")
            relocs[current_reloc_section][#relocs[current_reloc_section] + 1] = {
                at = tonumber(at, 16), kind = kind, symbol = symbol,
                addend = (sign == "-" and -1 or 1) * tonumber(addend, 16),
            }
        end
    end
end

local sections = {}
local listed = capture("readelf -SW " .. q(object))
for name in listed:gmatch("%.text%.([%w_]+)") do
    local path = OUT .. "/sec.bin"
    os.remove(path)
    run(("objcopy --dump-section %s=%s %s"):format(
        q(".text." .. name), q(path), q(object)))
    sections[name] = { code = read(path), relocs = relocs[".rela.text." .. name] or {} }
end

local function positions(code, bytes)
    local values, cursor = {}, 1
    while true do
        local at = code:find(bytes, cursor, true)
        if not at then break end
        values[#values + 1] = at - 1
        cursor = at + 1
    end
    return values
end

local patterns = {
    target_index = "\017\001\000\000",
    source_index = "\034\002\000\000",
    left_index = "\034\002\000\000",
    right_index = "\051\003\000\000",
    upvalue_index = "\051\003\000\000",
    resume = "\153\136\119\102",
    int_imm = "\024\023\022\021\020\019\018\017",
    const_tag = "\057\058\059\060",
    const_int = "\040\039\038\037\036\035\034\033",
    const_flt = "\240\222\188\154\120\086\052\018",
    const_ref = "\121\086\052\018\240\222\188\010",
    span = "\116\115\114\113",
    k = "\116\115\114\113",
    link = "\136\119\102\085\068\051\034\017",
    integer = "\136\119\102\085\068\051\034\017",
    floating = "\017\034\051\068\085\102\119\136",
    taken_link = "\013\208\254\202\013\240\173\011",
    fall_link = "\013\240\173\235\254\015\220\013",
    body_link = "\033\067\186\220\205\171\052\018",
    skip_link = "\050\084\203\237\222\188\069\035",
    call_a = "\004\003\002\001",
    call_b = "\008\007\006\005",
    call_c = "\018\017\016\009",
    call_pc = "\022\021\020\019",
    proto_index = "\016\015\014\013",
    nupvals = "\032\031\030\029",
    instack0 = "\048\047\046\045",
    idx0 = "\064\063\062\061",
    instack1 = "\080\079\078\077",
    idx1 = "\096\095\094\093",
    instack2 = "\112\111\110\109",
    idx2 = "\128\127\126\125",
    instack3 = "\144\143\142\141",
    idx3 = "\160\159\158\157",
    continuation = "\021\020\019\018\017\016\015\014",
    host_exit = "\129\112\111\094\077\060\043\026",
    tail_return = "\024\007\246\229\212\195\178\161",
    pow_addr = "\088\087\086\085\084\083\082\081",
    base_index = "\068\051\034\017",
    maxstack = "\141\124\107\090",
    numparams = "\158\141\124\107",
    is_vararg = "\175\158\141\124",
    receiver_index = "\068\004\000\000",
    key_index = "\085\005\000\000",
    object_target = "\102\006\000\000",
    int_key = "\136\119\102\085",
    key_ref = "\120\135\118\133\116\131\114\129",
    array_cap = "\013\012\011\010",
    field_cap = "\029\028\027\026",
    setlist_base = "\153\009\000\000",
    setlist_count = "\015\014\013\012",
    setlist_key = "\031\030\029\028",
    wanted = "\032\031\030\029",
    itoa_addr = "\104\103\102\101\100\099\098\097",
    dtoa_addr = "\088\087\086\085\084\083\082\081",
}

local function record(name)
    local section = assert(sections[name], "missing section " .. name)
    local code = section.code
    local holes = {}
    for kind, pattern in pairs(patterns) do
        local ats = positions(code, pattern)
        if #ats > 0 then holes[kind] = ats end
    end
    local successors = {}
    for _, reloc in ipairs(section.relocs) do
        assert(reloc.kind == "R_X86_64_PLT32" and
               reloc.symbol == "lua55_residual_next" and reloc.addend == -4,
            ("%s has unsupported relocation %s to %s"):format(
                name, reloc.kind, reloc.symbol))
        successors[#successors + 1] = reloc.at
    end
    return { code = code, holes = holes, successors = successors }
end

local v2 = {}
local function op(opcode, name) v2[opcode] = record(name) end

op(0, "lua55_v2_move")
op(1, "lua55_v2_loadi")
op(2, "lua55_v2_loadf")
op(3, "lua55_v2_loadk")
op(4, "lua55_v2_loadkx")
op(5, "lua55_v2_loadfalse")
op(6, "lua55_v2_loadfalse_skip")
op(7, "lua55_v2_loadtrue")
op(8, "lua55_v2_loadnil")
op(9, "lua55_v2_getupval")
op(10, "lua55_v2_setupval")
op(21, "lua55_v2_addi")
op(22, "lua55_v2_addk")
op(23, "lua55_v2_subk")
op(24, "lua55_v2_mulk")
op(25, "lua55_v2_modk")
op(26, "lua55_v2_powk")
op(27, "lua55_v2_divk")
op(28, "lua55_v2_idivk")
op(29, "lua55_v2_bandk")
op(30, "lua55_v2_bork")
op(31, "lua55_v2_bxork")
op(32, "lua55_v2_shli")
op(33, "lua55_v2_shri")
op(34, "lua55_v2_add")
op(35, "lua55_v2_sub")
op(36, "lua55_v2_mul")
op(37, "lua55_v2_mod")
op(38, "lua55_v2_pow")
op(39, "lua55_v2_div")
op(40, "lua55_v2_idiv")
op(41, "lua55_v2_band")
op(42, "lua55_v2_bor")
op(43, "lua55_v2_bxor")
op(44, "lua55_v2_shl")
op(45, "lua55_v2_shr")
op(49, "lua55_v2_unm")
op(50, "lua55_v2_bnot")
op(51, "lua55_v2_not")
op(52, "lua55_v2_len")
op(56, "lua55_v2_jmp")
op(57, "lua55_v2_eq")
op(58, "lua55_v2_lt")
op(59, "lua55_v2_le")
op(60, "lua55_v2_eqk")
op(61, "lua55_v2_eqi")
op(62, "lua55_v2_lti")
op(63, "lua55_v2_lei")
op(64, "lua55_v2_gti")
op(65, "lua55_v2_gei")
op(66, "lua55_v2_test")
op(67, "lua55_v2_testset")
op(73, "lua55_v2_forloop")
op(74, "lua55_v2_forprep")
op(11, "lua55_v2_gettabup")
op(12, "lua55_v2_gettable")
op(13, "lua55_v2_geti")
op(14, "lua55_v2_getfield")
op(15, "lua55_v2_settabup")
op(16, "lua55_v2_settable")
op(17, "lua55_v2_seti")
op(18, "lua55_v2_setfield")
op(19, "lua55_v2_newtable")
op(20, "lua55_v2_self")
op(78, "lua55_v2_setlist")
op(80, "lua55_v2_vararg")
op(81, "lua55_v2_getvarg")
op(75, "lua55_v2_tforprep")
op(54, "lua55_v2_close")
op(53, "lua55_v2_concat")
op(55, "lua55_v2_tbc")
op(82, "lua55_v2_errnnil")
op(76, "lua55_v2_tforcall")
op(77, "lua55_v2_tforloop")

local variants = {
    seti_const = record("lua55_v2_seti_const"),
    setfield_const = record("lua55_v2_setfield_const"),
    settable_const = record("lua55_v2_settable_const"),
}

local cps = {
    call = record("lua55_cps_call"),
    tailcall = record("lua55_cps_tailcall"),
    ret = record("lua55_cps_return"),
    ret0 = record("lua55_cps_return0"),
    ret1 = record("lua55_cps_return1"),
    closure = record("lua55_cps_closure"),
    host_exit = record("lua55_cps_host_exit"),
    host_tail_return = record("lua55_cps_host_tail_return"),
}

local bank = { v2 = v2, variants = variants, cps = cps }

local function literal(value) return string.format("%q", value) end
local function serialize(value, indent)
    indent = indent or ""
    if type(value) == "string" then return literal(value) end
    if type(value) == "number" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        local rendered = type(key) == "number" and "[" .. key .. "]" or ("[" .. string.format("%q", key) .. "]")
        parts[#parts + 1] = "\n" .. indent .. "  " .. rendered .. " = " .. serialize(value[key], indent .. "  ") .. ","
    end
    parts[#parts + 1] = "\n" .. indent .. "}"
    return table.concat(parts)
end
local file = assert(io.open(OUT .. "/bank.lua", "wb"))
file:write("return ", serialize(bank), "\n")
file:close()

local byte_count = 0
local section_count = 0
for _, item in pairs(v2) do byte_count = byte_count + #item.code; section_count = section_count + 1 end
for _, item in pairs(cps) do byte_count = byte_count + #item.code end
print(("Lua55 V2 bank: opcodes=%d cps=%d (%d bytes)"):format(
    section_count, #({ 1 }) and 8, byte_count))
