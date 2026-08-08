package.path = "./?.lua;./?/init.lua;" .. package.path

-- Self-selecting (polymorphic) bank: one residual per opcode whose internal
-- tag dispatch IS the selection. No learners, no per-shape quotes. The
-- runner builds function arenas from these records directly (no recording,
-- no install, no Lua-side selection). Compiled from the modified stencil
-- files (the lua55_poly_* sections) plus the finish and the link terminals.

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
local OUT = "target/copy_patch_cps/lua55_trace/opcode_poly"
run("mkdir -p " .. q(OUT))

local SOURCES = {
    "opcode_00_08_stencils.c", "opcode_arith_stencils.c", "opcode_compare_stencils.c",
    "opcode_unary_stencils.c", "opcode_jmp_stencils.c", "opcode_pow_stencils.c",
    "opcode_closure_stencils.c", "opcode_call_stencils.c", "opcode_for_stencils.c",
    "opcode_link_stencils.c",
    -- the V2-only core provides the cps boundary sections (host_exit) used
    -- by the legacy poly reject paths
    "opcode_v2_core_stencils.c",
}

-- compile each source separately; collect the per-section relocations + code
local sections = {}      -- section name -> { code = ..., relocs = {...} }
local section_relocs = {} -- section name -> reloc list
for _, source in ipairs(SOURCES) do
    local object = OUT .. "/" .. source:gsub("%.c$", ".o")
    run(table.concat({
        "gcc -O3 -fno-pic -fno-jump-tables -ffunction-sections -fno-stack-protector",
        "-fno-asynchronous-unwind-tables -fno-unwind-tables",
        q(ROOT .. "/" .. source), "-c -o", q(object),
    }, " "))
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
    -- extract every .text.<section> from this object
    local listed = capture("readelf -SW " .. q(object))
    for name in listed:gmatch("%.text%.([%w_]+)") do
        local path = OUT .. "/sec.bin"
        os.remove(path)
        run(("objcopy --dump-section %s=%s %s"):format(
            q(".text." .. name), q(path), q(object)))
        sections[name] = { code = read(path), relocs = relocs[".rela.text." .. name] or {} }
    end
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
    target_pc = "\064\048\032\016",
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
    maxstack = "\141\124\107\090",
    numparams = "\158\141\124\107",
    is_vararg = "\175\158\141\124",
    base_index = "\068\051\034\017",
    back_edge = "\136\119\102\085",
    fallthrough = "\204\187\170\153",
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

local polys = {}
local function poly(opcode, name) polys[opcode] = record(name) end

poly(0, "lua55_poly_move")
poly(1, "lua55_poly_loadi")
poly(2, "lua55_poly_loadf")
poly(3, "lua55_poly_loadk")
poly(4, "lua55_poly_loadkx")
poly(5, "lua55_poly_loadfalse")
poly(6, "lua55_poly_loadfalse_skip")
poly(7, "lua55_poly_loadtrue")
poly(8, "lua55_poly_loadnil")
poly(9, "lua55_poly_getupval")
poly(10, "lua55_poly_setupval")
poly(21, "lua55_poly_addi")
poly(22, "lua55_poly_addk")
poly(23, "lua55_poly_subk")
poly(24, "lua55_poly_mulk")
poly(25, "lua55_poly_modk")
poly(26, "lua55_poly_powk")
poly(27, "lua55_poly_divk")
poly(28, "lua55_poly_idivk")
poly(29, "lua55_poly_bandk")
poly(30, "lua55_poly_bork")
poly(31, "lua55_poly_bxork")
poly(32, "lua55_poly_shli")
poly(33, "lua55_poly_shri")
poly(34, "lua55_poly_add")
poly(35, "lua55_poly_sub")
poly(36, "lua55_poly_mul")
poly(37, "lua55_poly_mod")
poly(38, "lua55_poly_pow")
poly(39, "lua55_poly_div")
poly(40, "lua55_poly_idiv")
poly(41, "lua55_poly_band")
poly(42, "lua55_poly_bor")
poly(43, "lua55_poly_bxor")
poly(44, "lua55_poly_shl")
poly(45, "lua55_poly_shr")
poly(49, "lua55_poly_unm")
poly(50, "lua55_poly_bnot")
poly(51, "lua55_poly_not")
poly(52, "lua55_poly_len")
poly(56, "lua55_poly_jmp")
poly(57, "lua55_poly_eq")
poly(58, "lua55_poly_lt")
poly(59, "lua55_poly_le")
poly(60, "lua55_poly_eqk")
poly(61, "lua55_poly_eqi")
poly(62, "lua55_poly_lti")
poly(63, "lua55_poly_lei")
poly(64, "lua55_poly_gti")
poly(65, "lua55_poly_gei")
poly(66, "lua55_poly_test")
poly(67, "lua55_poly_testset")
poly(68, "lua55_poly_call")
poly(69, "lua55_poly_tailcall")
poly(70, "lua55_poly_return")
poly(71, "lua55_poly_return0")
poly(72, "lua55_poly_return1")
poly(73, "lua55_poly_forloop")
poly(74, "lua55_poly_forprep")
poly(79, "lua55_poly_closure")

local quotes = {
    [65000] = record("lua55_residual_jmp_link"),
    [65001] = record("lua55_residual_forloop_link"),
}

local finish_section = assert(sections["lua55_opcode_finish"], "finish section absent")
local finish = { code = finish_section.code, resume = positions(finish_section.code, patterns.resume)[1] }

-- the link terminals (65000/65001) and the finish live in the base banks;
-- the poly bank contributes the polymorphic residuals only
-- the link terminals (65000/65001) and the finish live in the base banks;
-- the poly bank contributes the polymorphic residuals only
local cps = {
    call = record("lua55_cps_call"),
    tailcall = record("lua55_cps_tailcall"),
    ret = record("lua55_cps_return"),
    ret0 = record("lua55_cps_return0"),
    ret1 = record("lua55_cps_return1"),
    closure = record("lua55_cps_closure"),
    host_exit = record("lua55_cps_host_exit"),
}

local extension = { polys = polys, learners = {}, quotes = {}, cps = cps }

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
file:write("return ", serialize(extension), "\n")
file:close()
local byte_count = 0
for _, item in pairs(polys) do byte_count = byte_count + #item.code end
print(("Lua55 poly bank: polys=%d (%d bytes) quotes=%d finish=%d bytes"):format(
    #({ 1 }) and 0, byte_count, #({ 1 }) and 0, #finish.code))
