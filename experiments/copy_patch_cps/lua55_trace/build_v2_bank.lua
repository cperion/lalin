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

-- Mechanical ABI audit over the exact residual object. Library calls are
-- permitted only for exact POW/POWK and CONCAT formatting boundaries; guest
-- control is proper-tail CPS and therefore contains no native ret/call pair.
local assembly_audit = { exact_sections = 0, exact_calls = 0, exact_rets = 0,
    exact_conditional_branches = 0, exact_branch_sections = {},
    exact_instruction_counts = {}, stack_sections = 0, stack_tail_edges = 0,
    stack_traps = 0, field_slot_sections = 0 }
local exact_disassembly = {}
do
    local exact_section
    for line in capture("objdump --no-show-raw-insn -d " .. q(object)):gmatch("[^\n]+") do
        local section = line:match("^Disassembly of section %.text%.([%w_]+):")
        if section then
            exact_section = section:sub(1, 10) == "lua55_v2r_" and section or nil
            if exact_section then
                assembly_audit.exact_sections = assembly_audit.exact_sections + 1
                exact_disassembly[exact_section] = {}
                assembly_audit.exact_instruction_counts[exact_section] = 0
            end
        elseif exact_section then
            local at, mnemonic, operands = line:match(
                "^%s*([%da-fA-F]+):%s+([%a][%w.]*)%s*(.-)%s*$")
            if mnemonic then
                local instructions = exact_disassembly[exact_section]
                instructions[#instructions + 1] = {
                    at = tonumber(at, 16), mnemonic = mnemonic, operands = operands,
                }
                assembly_audit.exact_instruction_counts[exact_section] =
                    assembly_audit.exact_instruction_counts[exact_section] + 1
            end
            if mnemonic and mnemonic:sub(1, 3) == "ret" then
                assembly_audit.exact_rets = assembly_audit.exact_rets + 1
                error(exact_section .. " contains forbidden native " .. mnemonic, 0)
            elseif mnemonic and mnemonic:sub(1, 4) == "call" then
                local allowed = exact_section:sub(1, 17) == "lua55_v2r_concat_"
                    or exact_section:sub(1, 14) == "lua55_v2r_pow_"
                    or exact_section:sub(1, 15) == "lua55_v2r_powk_"
                assert(allowed, exact_section .. " contains forbidden native " .. mnemonic)
                assembly_audit.exact_calls = assembly_audit.exact_calls + 1
            elseif mnemonic and mnemonic:sub(1, 1) == "j"
                    and mnemonic:sub(1, 3) ~= "jmp" then
                assembly_audit.exact_conditional_branches =
                    assembly_audit.exact_conditional_branches + 1
                assembly_audit.exact_branch_sections[exact_section] =
                    (assembly_audit.exact_branch_sections[exact_section] or 0) + 1
            end
        end
    end
end

-- Prove balanced native stack state at every reachable proper-tail edge. The
-- checker follows each exact section's local CFG. A successor relocation marks
-- an external tail edge even when the unlinked rel32 happens to disassemble as
-- an address inside the current section.
local function stack_delta(section, instruction)
    local mnemonic, operands = instruction.mnemonic, instruction.operands
    if mnemonic:sub(1, 4) == "push" then return -8 end
    if mnemonic:sub(1, 3) == "pop" then return 8 end
    local immediate = operands:match("^%$0x([%da-fA-F]+),%%rsp$")
    if immediate and (mnemonic == "add" or mnemonic == "sub") then
        local amount = tonumber(immediate, 16)
        return mnemonic == "add" and amount or -amount
    end
    local sign, displacement =
        operands:match("^(-?)0x([%da-fA-F]+)%(%%rsp%),%%rsp$")
    if displacement and mnemonic == "lea" then
        local amount = tonumber(displacement, 16)
        return sign == "-" and -amount or amount
    end
    assert(not operands:match(",%%rsp$"),
        section .. " has an unsupported stack-pointer write: "
            .. mnemonic .. " " .. operands)
    return 0
end

local function exact_field_slot_hot(section)
    local name = section:match("^lua55_v2r_(.+)$")
    return name == "getfield_slot" or name == "gettabup_slot"
        or name == "self_slot"
        or (name and name:match("^setfield_.+_existing$") ~= nil)
        or (name and name:match("^settabup_.+_existing$") ~= nil)
end

for section, instructions in pairs(exact_disassembly) do
    assert(#instructions > 0, section .. " has no decoded instructions")
    local by_address, external_jump = {}, {}
    for index, instruction in ipairs(instructions) do
        by_address[instruction.at] = index
    end
    for _, relocation in ipairs(relocs[".rela.text." .. section] or {}) do
        if relocation.symbol == "lua55_residual_next" then
            local owner
            for index, instruction in ipairs(instructions) do
                local next_at = instructions[index + 1]
                    and instructions[index + 1].at or math.huge
                if instruction.at < relocation.at and relocation.at < next_at then
                    owner = index
                    break
                end
            end
            assert(owner, section .. " has an unowned successor relocation at "
                .. relocation.at)
            external_jump[owner] = true
        end
    end
    if exact_field_slot_hot(section) then
        assembly_audit.field_slot_sections = assembly_audit.field_slot_sections + 1
        local function local_successors(index)
            local instruction = instructions[index]
            local mnemonic, operands = instruction.mnemonic, instruction.operands
            if mnemonic == "jmp" then
                if external_jump[index] or operands:sub(1, 1) == "*" then return {} end
                local text = operands:match("^([%da-fA-F]+)")
                local target = text and by_address[tonumber(text, 16)] or nil
                return target and { target } or {}
            end
            if mnemonic:sub(1, 1) == "j" then
                local text = operands:match("^([%da-fA-F]+)")
                local target = text and by_address[tonumber(text, 16)] or nil
                local result = {}
                if instructions[index + 1] then result[#result + 1] = index + 1 end
                if target then result[#result + 1] = target end
                return result
            end
            if mnemonic == "ud2" or mnemonic:sub(1, 3) == "ret" then return {} end
            return instructions[index + 1] and { index + 1 } or {}
        end
        local function reaches(from, wanted)
            local pending, seen = { from }, {}
            while #pending > 0 do
                local index = pending[#pending]; pending[#pending] = nil
                if index == wanted then return true end
                if not seen[index] then
                    seen[index] = true
                    for _, successor in ipairs(local_successors(index)) do
                        pending[#pending + 1] = successor
                    end
                end
            end
            return false
        end
        for index, instruction in ipairs(instructions) do
            if instruction.mnemonic:sub(1, 1) == "j" then
                local text = instruction.operands:match("^([%da-fA-F]+)")
                local target = text and by_address[tonumber(text, 16)] or nil
                assert(not (target and target < index and reaches(target, index)),
                    section .. " contains a field-scan loop at 0x"
                        .. string.format("%x", instruction.at))
            end
        end
    end

    local states, pending = { [1] = 0 }, { 1 }
    local function enqueue(index, delta)
        local before = states[index]
        if before ~= nil then
            assert(before == delta, section .. " has conflicting stack deltas at 0x"
                .. string.format("%x", instructions[index].at))
        else
            states[index] = delta
            pending[#pending + 1] = index
        end
    end
    local function tail_edge(instruction, delta)
        assert(delta == 0, section .. " reaches tail edge at 0x"
            .. string.format("%x", instruction.at)
            .. " with stack delta " .. delta)
        assembly_audit.stack_tail_edges = assembly_audit.stack_tail_edges + 1
    end

    while #pending > 0 do
        local index = pending[#pending]
        pending[#pending] = nil
        local instruction = instructions[index]
        local delta = states[index] + stack_delta(section, instruction)
        local mnemonic, operands = instruction.mnemonic, instruction.operands
        if mnemonic == "jmp" then
            if external_jump[index] or operands:sub(1, 1) == "*" then
                tail_edge(instruction, delta)
            else
                local target = tonumber(operands:match("^([%da-fA-F]+)"), 16)
                local target_index = target and by_address[target] or nil
                if target_index then enqueue(target_index, delta)
                else tail_edge(instruction, delta) end
            end
        elseif mnemonic:sub(1, 1) == "j" then
            local target = tonumber(operands:match("^([%da-fA-F]+)"), 16)
            local target_index = target and by_address[target] or nil
            assert(target_index, section .. " has an external conditional branch at 0x"
                .. string.format("%x", instruction.at))
            assert(instructions[index + 1], section .. " ends in a conditional branch")
            enqueue(index + 1, delta)
            enqueue(target_index, delta)
        elseif mnemonic == "ud2" then
            assembly_audit.stack_traps = assembly_audit.stack_traps + 1
        elseif mnemonic:sub(1, 3) == "ret" then
            tail_edge(instruction, delta)
        else
            assert(instructions[index + 1], section .. " falls off its final instruction")
            enqueue(index + 1, delta)
        end
    end
    assembly_audit.stack_sections = assembly_audit.stack_sections + 1
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
    target_index = "\145\128\127\110",
    source_index = "\109\108\107\106",
    target_disp = "\103\086\069\052",
    receiver_disp = "\129\111\077\043",
    object_disp = "\151\117\083\049",
    source_disp = "\087\070\053\036",
    left_index = "\108\091\074\057",
    right_index = "\097\096\095\094",
    left_disp = "\071\054\037\020",
    right_disp = "\041\024\103\069",
    base_disp = "\121\091\063\029",
    array_disp = "\145\127\093\059",
    key_disp = "\223\155\087\019",
    upvalue_index = "\091\074\057\040",
    top_index = "\139\105\071\037",
    resume = "\153\136\119\102",
    int_imm = "\015\092\041\167\099\142\027\212",
    const_tag = "\057\058\059\060",
    const_int = "\040\039\038\037\036\035\034\033",
    const_flt = "\240\222\188\154\120\086\052\018",
    const_ref = "\121\086\052\018\240\222\188\010",
    span = "\119\007\000\000",
    k = "\116\115\114\113",
    link = "\011\132\230\082\157\122\031\195",
    integer = "\015\100\168\210\149\062\124\177",
    floating = "\017\034\051\068\085\102\119\136",
    taken_link = "\013\208\254\202\013\240\173\011",
    fall_link = "\013\240\173\235\254\015\220\013",
    body_link = "\033\067\186\220\205\171\052\018",
    skip_link = "\050\084\203\237\222\188\069\035",
    call_a = "\004\003\002\001",
    call_b = "\008\007\006\005",
    call_c = "\018\017\016\009",
    call_pc = "\022\021\020\019",
    arg_count = "\100\083\066\049",
    result_count = "\025\048\081\114",
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
    receiver_index = "\077\076\075\074",
    field_receiver = "\093\092\091\090",
    accum_key2 = "\113\112\111\110",
    key_index = "\049\048\047\046",
    object_target = "\102\006\000\000",
    int_key = "\136\119\102\085",
    key_ref = "\120\135\118\133\116\131\114\129",
    array_cap = "\013\012\011\010",
    field_cap = "\029\028\027\026",
    field_slot = "\150\133\116\099",
    field_layout_capacity = "\099\116\133\150",
    setlist_base = "\153\009\000\000",
    setlist_count = "\015\014\013\012",
    setlist_key = "\031\030\029\028",
    wanted = "\062\045\028\011",
    itoa_addr = "\104\103\102\101\100\099\098\097",
    dtoa_addr = "\184\169\154\139\124\109\094\079",
    need_grow_link = "\207\206\205\204\203\202\201\200",
    need_create_link = "\228\229\230\231\232\233\234\235",
    resume_link = "\217\216\215\214\213\212\211\210",
    mismatch_exit = "\176\177\178\179\180\181\182\183",
    fragment_next = "\040\057\074\091\108\125\142\159",
    source_key_ref = "\120\105\090\075\060\045\030\015",
    occ_slot = "\093\076\059\042",
    site_id = "\076\061\046\031",
}

local pattern_owner = {}
for kind, pattern in pairs(patterns) do
    assert(not pattern_owner[pattern], ("duplicate V2 hole pattern: %s and %s")
        :format(pattern_owner[pattern] or "", kind))
    pattern_owner[pattern] = kind
end

local successor_hole = { link = true, taken_link = true, fall_link = true,
    body_link = true, skip_link = true, continuation = true, tail_return = true,
    need_grow_link = true, need_create_link = true, resume_link = true,
    mismatch_exit = true, fragment_next = true }
local boundary_hole = { resume = true, host_exit = true }
local library_hole = { pow_addr = true, itoa_addr = true, dtoa_addr = true }
local function hole_role(kind)
    if successor_hole[kind] then return "successor" end
    if boundary_hole[kind] then return "boundary" end
    if library_hole[kind] then return "library" end
    return "occurrence"
end

local function record(name)
    local section = assert(sections[name], "missing section " .. name)
    local code = section.code
    local holes, hole_sites = {}, {}
    for kind, pattern in pairs(patterns) do
        local ats = positions(code, pattern)
        if #ats > 0 then
            holes[kind] = ats
            for _, at in ipairs(ats) do
                hole_sites[#hole_sites + 1] = {
                    at = at, width = #pattern, kind = kind, role = hole_role(kind),
                }
            end
        end
    end
    table.sort(hole_sites, function(a, b)
        if a.at == b.at then return a.width < b.width end
        return a.at < b.at
    end)
    for index = 2, #hole_sites do
        local before, after = hole_sites[index - 1], hole_sites[index]
        assert(before.at + before.width <= after.at,
            ("%s has overlapping hole patterns %s@%d+%d and %s@%d+%d")
                :format(name, before.kind, before.at, before.width,
                    after.kind, after.at, after.width))
    end
    local successors = {}
    for _, reloc in ipairs(section.relocs) do
        assert(reloc.kind == "R_X86_64_PLT32" and
               reloc.symbol == "lua55_residual_next" and reloc.addend == -4,
            ("%s has unsupported relocation %s to %s"):format(
                name, reloc.kind, reloc.symbol))
        assert(code:byte(reloc.at) == 0xE9,
            ("%s successor relocation is not a direct near jmp at %d")
                :format(name, reloc.at))
        successors[#successors + 1] = reloc.at
    end
    return { code = code, holes = holes, hole_sites = hole_sites,
        successors = successors, __name = name }
end

local v2 = {}
local function op(opcode, name) v2[opcode] = record(name) end

-- ---- exact residual and learning vocabularies --------------------------
-- Residual sections implement exactly one semantic shape (no tag dispatch).
-- Learning sections may classify their family's finite alternatives because
-- they are never published as final residuals. Every lua55_v2r_* section
-- must be declared in the exact vocabulary; the build rejects undeclared
-- residual sections.
local residual_vocabulary = {}
local function res(name) residual_vocabulary[name] = true; return name end

local const_values = { "nil", "false", "true", "int", "flt", "str" }
for _, v in ipairs(const_values) do
    res("settable_int_const_" .. v .. "_inbounds")
    res("settable_int_const_" .. v .. "_grow")
    res("settable_str_const_" .. v .. "_existing")
    res("settable_str_const_" .. v .. "_create")
    res("seti_const_" .. v .. "_inbounds")
    res("seti_const_" .. v .. "_grow")
    res("setfield_const_" .. v .. "_existing")
    res("setfield_const_" .. v .. "_create")
end
res("settable_int_reg_inbounds"); res("settable_int_reg_grow")
res("settable_str_reg_existing"); res("settable_str_reg_create")
res("seti_reg_inbounds"); res("seti_reg_grow")
res("setfield_reg_existing"); res("setfield_reg_create")
res("gettable_int"); res("gettable_str")
res("getfield_slot"); res("getfield_missing")
res("gettabup_slot"); res("gettabup_missing")
res("self_slot"); res("self_missing")
res("loadk_nil"); res("loadk_false"); res("loadk_true")
res("loadk_int"); res("loadk_flt"); res("loadk_str")
res("newtable")

-- batch 4: exact numeric-for protocol/sign leaves
res("forprep_int_pos"); res("forprep_int_neg")
res("forprep_flt_pos"); res("forprep_flt_neg")
res("forloop_int"); res("forloop_flt_pos"); res("forloop_flt_neg")
for _, tags in ipairs({ "iii", "iif", "ifi", "iff", "fii", "fif", "ffi", "fff" }) do
    for _, acc in ipairs({ "i", "f" }) do
        res("super_for_addi_" .. tags .. "_" .. acc .. "_pos")
        res("super_for_addi_" .. tags .. "_" .. acc .. "_neg")
        res("super_for_add_" .. tags .. "_" .. acc .. "_pos")
        res("super_for_add_" .. tags .. "_" .. acc .. "_neg")
    end
end
for _, kind in ipairs({ "nil", "false", "true", "int", "flt", "str" }) do
    res("super_for_settable_" .. kind .. "_pos")
    res("super_for_settable_" .. kind .. "_neg")
end
res("super_field_addi_int"); res("super_field_addi_flt")
for _, key in ipairs({ "int", "str" }) do
    for _, value in ipairs({ "int", "flt" }) do
        res("super_table_addi_" .. key .. "_" .. value)
    end
end
for _, key in ipairs({ "int", "str" }) do
    for _, acc in ipairs({ "int", "flt" }) do
        for _, src in ipairs({ "int", "flt" }) do
            res("super_accumulate_field_r_" .. key .. "_" .. acc .. "_" .. src)
            res("super_accumulate_field_f_" .. key .. "_" .. acc .. "_" .. src)
        end
    end
end
res("call_native_fixed_prepare"); res("call_native_fixed_arg1"); res("call_native_vararg_prepare")
res("call_fixed_arg_slot"); res("call_fixed_finish")
res("call_native_fixed_open"); res("call_native_vararg_open"); res("call_host")
for _, prefix in ipairs({
    "super_global_nil", "super_global_false", "super_global_true",
    "super_global_int", "super_global_flt", "super_global_str",
    "super_global_move", "super_method",
}) do
    res(prefix .. "_native_fixed")
    res(prefix .. "_native_vararg")
    res(prefix .. "_host")
end
res("tailcall_native_fixed_prepare"); res("tailcall_native_vararg_prepare")
res("tailcall_fixed_arg_slot"); res("tailcall_fixed_finish")
res("tailcall_native_fixed_open"); res("tailcall_native_vararg_open"); res("tailcall_host")
res("tforcall_native"); res("tforcall_host")
for i = 0, 4 do res("closure_" .. i) end
res("getvarg_int"); res("getvarg_n"); res("getvarg_mx")
res("ret_fixed_begin"); res("ret_fixed_one"); res("ret_fixed_slot"); res("ret_fixed_finish"); res("ret_all")
res("vararg_fixed_slot"); res("vararg_fixed_finish"); res("vararg_all")
for i = 1, 8 do res("loadnil_" .. i) end
res("settabup_existing"); res("settabup_create")
for _, v in ipairs({ "nil", "false", "true", "int", "flt", "str" }) do
    res("settabup_const_" .. v .. "_existing")
    res("settabup_const_" .. v .. "_create")
end
res("setlist_inbounds"); res("setlist_grow"); res("setlist_slot")

-- S10: exact CONCAT occurrence residuals are mechanically composed from
-- three type-specific measure leaves, one allocation leaf, three type-specific
-- write leaves, and one finish leaf. Width/vector products no longer exist in
-- the bank.
for _, phase in ipairs({ "measure", "write" }) do
    for _, kind in ipairs({ "str", "int", "flt" }) do
        res("concat_" .. phase .. "_" .. kind)
    end
end
res("concat_allocate"); res("concat_finish")

-- batch 3: exact arithmetic / unary / comparison operand products
local function quad(name) for _, x in ipairs({ "ii", "if", "fi", "ff" }) do res(name .. "_" .. x) end end
for _, op in ipairs({ "add", "sub", "mul", "mod", "idiv", "div", "pow",
                      "band", "bor", "bxor", "shl", "shr" }) do quad(op) end
res("addi_ii"); res("addi_fi")
res("shli_ii"); res("shli_fi")
res("shri_ii"); res("shri_fi")
for _, op in ipairs({ "addk", "subk", "mulk", "modk", "idivk", "divk", "powk",
                      "bandk", "bork", "bxork" }) do quad(op) end
res("unm_int"); res("unm_flt")
res("bnot_int"); res("bnot_flt")
res("len_str"); res("len_table")
local function cmpres(name) res(name .. "_k0"); res(name .. "_k1") end
local function cmpquad(name)
    for _, x in ipairs({ "ii", "if", "fi", "ff" }) do cmpres(name .. "_" .. x) end
end
for _, op in ipairs({ "lt", "le" }) do cmpquad(op); cmpres(op .. "_ss") end
for _, op in ipairs({ "lti", "lei", "gti", "gei" }) do
    cmpres(op .. "_ii"); cmpres(op .. "_fi")
end
cmpquad("eq")
for _, shape in ipairs({ "ss", "rr", "sp", "mx" }) do cmpres("eq_" .. shape) end
for _, shape in ipairs({ "ii", "fi", "mx" }) do cmpres("eqi_" .. shape) end
for _, shape in ipairs({ "ii", "fi", "mx" }) do cmpres("eqk_int_" .. shape) end
for _, shape in ipairs({ "if", "ff", "mx" }) do cmpres("eqk_flt_" .. shape) end
cmpres("eqk_str_ss"); cmpres("eqk_str_mx")
cmpres("eqk_nil"); cmpres("eqk_false"); cmpres("eqk_true")
cmpres("test"); cmpres("testset")

local learning = {}
local residual = {}
for name, section in pairs(sections) do
    if name:sub(1, 10) == "lua55_v2l_" then
        learning[name:sub(11)] = record(name)
    elseif name:sub(1, 10) == "lua55_v2r_" then
        local key = name:sub(11)
        if residual_vocabulary[key] then residual[key] = record(name)
        elseif key:match("^concat_[2345]_[sif]+$") == nil then
            error(("undeclared exact residual section %s (add it to the exact vocabulary)")
                :format(name), 0)
        end
    end
end

-- Representative S8 size/instruction budgets are deliberately tied to the
-- controlled GCC stencil build. They reject accidental call/return expansion
-- while leaving modest headroom for local compiler-version movement.
local hot_budgets = {
    call_native_fixed_prepare = { 960, 200 },
    call_fixed_arg_slot = { 128, 30 },
    call_fixed_finish = { 176, 42 },
    tailcall_native_fixed_prepare = { 816, 165 },
    tailcall_fixed_arg_slot = { 128, 28 },
    tailcall_fixed_finish = { 288, 64 },
    ret_fixed_begin = { 128, 34 },
    ret_fixed_slot = { 72, 20 },
    ret_fixed_finish = { 496, 116 },
}
assembly_audit.hot_budgets = {}
for name, budget in pairs(hot_budgets) do
    local exact = assert(residual[name], "missing budgeted residual " .. name)
    local section = "lua55_v2r_" .. name
    local instructions = assert(assembly_audit.exact_instruction_counts[section])
    assert(#exact.code <= budget[1], ("%s grew to %d bytes (budget %d)")
        :format(section, #exact.code, budget[1]))
    assert(instructions <= budget[2], ("%s grew to %d instructions (budget %d)")
        :format(section, instructions, budget[2]))
    assembly_audit.hot_budgets[name] = {
        bytes = #exact.code, byte_limit = budget[1],
        instructions = instructions, instruction_limit = budget[2],
    }
end

op(0, "lua55_v2_move")
op(1, "lua55_v2_loadi")
op(2, "lua55_v2_loadf")
op(3, "lua55_v2_loadk")
op(4, "lua55_v2_loadkx")
op(5, "lua55_v2_loadfalse")
op(6, "lua55_v2_loadfalse_skip")
op(7, "lua55_v2_loadtrue")
op(9, "lua55_v2_getupval")
op(10, "lua55_v2_setupval")
op(51, "lua55_v2_not")
op(56, "lua55_v2_jmp")

op(11, "lua55_v2_gettabup")
op(13, "lua55_v2_geti")
op(14, "lua55_v2_getfield")
op(20, "lua55_v2_self")
op(75, "lua55_v2_tforprep")
op(54, "lua55_v2_close")
op(55, "lua55_v2_tbc")
op(82, "lua55_v2_errnnil")
op(77, "lua55_v2_tforloop")



local cps = {
    ret0 = record("lua55_cps_return0"),
    ret1 = record("lua55_cps_return1"),
    host_exit = record("lua55_cps_host_exit"),
    specialization_mismatch = record("lua55_cps_specialization_mismatch"),
    host_tail_return = record("lua55_cps_host_tail_return"),
}


-- S1: semantic provenance for all Lua 5.5 opcode meanings. Categories describe
-- conditional control permitted in the published scalar leaf, not staging Lua.
-- The object audit above provides the mechanical per-section branch counts.
local opcode_names = {
    [0] = "MOVE", "LOADI", "LOADF", "LOADK", "LOADKX", "LOADFALSE",
    "LFALSESKIP", "LOADTRUE", "LOADNIL", "GETUPVAL", "SETUPVAL",
    "GETTABUP", "GETTABLE", "GETI", "GETFIELD", "SETTABUP", "SETTABLE",
    "SETI", "SETFIELD", "NEWTABLE", "SELF", "ADDI", "ADDK", "SUBK",
    "MULK", "MODK", "POWK", "DIVK", "IDIVK", "BANDK", "BORK", "BXORK",
    "SHLI", "SHRI", "ADD", "SUB", "MUL", "MOD", "POW", "DIV", "IDIV",
    "BAND", "BOR", "BXOR", "SHL", "SHR", "MMBIN", "MMBINI", "MMBINK",
    "UNM", "BNOT", "NOT", "LEN", "CONCAT", "CLOSE", "TBC", "JMP",
    "EQ", "LT", "LE", "EQK", "EQI", "LTI", "LEI", "GTI", "GEI",
    "TEST", "TESTSET", "CALL", "TAILCALL", "RETURN", "RETURN0",
    "RETURN1", "FORLOOP", "FORPREP", "TFORPREP", "TFORCALL", "TFORLOOP",
    "SETLIST", "CLOSURE", "VARARG", "GETVARG", "ERRNNIL", "VARARGPREP",
    "EXTRAARG",
}
local branch_provenance = {
    opcode_count = 85, forbidden_count = 0,
    category_legend = {
        [1] = "exact-shape guard to typed mismatch",
        [2] = "genuine program data",
        [3] = "mutable protocol state",
        [4] = "typed language/error/overflow outcome",
        [5] = "forbidden projection-time decision",
    },
    opcodes = {},
}
for opcode = 0, 84 do
    branch_provenance.opcodes[opcode] = {
        name = assert(opcode_names[opcode], "missing S1 opcode name " .. opcode),
        status = "published", owner = "direct", categories = {},
    }
end
local function provenance(opcodes, owner, categories, status)
    for _, opcode in ipairs(opcodes) do
        local row = assert(branch_provenance.opcodes[opcode])
        row.owner, row.status, row.categories = owner, status or "published", categories
    end
end
local function forbidden(opcodes, reason)
    for _, opcode in ipairs(opcodes) do
        local row = assert(branch_provenance.opcodes[opcode])
        assert(row.forbidden == nil, "duplicate S1 forbidden opcode " .. opcode)
        row.forbidden = reason
        branch_provenance.forbidden_count = branch_provenance.forbidden_count + 1
    end
end

provenance({ 9, 10 }, "upvalue", { 1, 3, 4 })
provenance({ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 },
    "table", { 1, 2, 3, 4 })
provenance({ 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
    35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45 },
    "arithmetic", { 1, 2, 4 })
provenance({ 46, 47, 48 }, "owned arithmetic companion", {}, "structural")
provenance({ 49, 50, 51, 52 }, "unary", { 1, 2, 4 })
provenance({ 53 }, "concat", { 1, 2, 4 })
provenance({ 54, 55 }, "close protocol", { 3, 4 })
provenance({ 56 }, "direct control", {})
provenance({ 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67 },
    "comparison", { 1, 2, 4 })
provenance({ 68, 69, 70, 71, 72 }, "call/return", { 1, 2, 3, 4 })
provenance({ 73, 74, 75, 76, 77 }, "loop protocol", { 1, 2, 3, 4 })
provenance({ 78 }, "setlist", { 1, 2, 3, 4 })
provenance({ 79 }, "closure", { 1, 3, 4 })
provenance({ 80, 81 }, "vararg", { 1, 2, 3, 4 })
provenance({ 82 }, "declared-global check", { 2, 4 })
provenance({ 83 }, "host frame setup", {}, "structural")
provenance({ 84 }, "owned companion payload", {}, "structural")


for opcode = 0, 84 do
    local row = assert(branch_provenance.opcodes[opcode])
    for _, category in ipairs(row.categories) do
        assert(category >= 1 and category <= 4,
            ("S1 opcode %d contains forbidden category %s"):format(opcode, category))
    end
end

local mismatch_audit = { sections = 0, inline_publishers = 0 }
for name, record in pairs(residual) do
    if record.holes.mismatch_exit then mismatch_audit.sections = mismatch_audit.sections + 1 end
    assert(record.holes.mismatch_exit == nil or #record.holes.mismatch_exit > 0,
        name .. " has an empty mismatch exit manifest")
end
local mismatch_disassembly = {}
do
    local active = false
    for line in capture("objdump --no-show-raw-insn -d --section=.text.lua55_cps_specialization_mismatch "
            .. q(object)):gmatch("[^\n]+") do
        if line:match("^Disassembly of section") then active = true
        elseif active then
            local at, mnemonic, operands = line:match(
                "^%s*([%da-fA-F]+):%s+([%a][%w.]*)%s*(.-)%s*$")
            if mnemonic then mismatch_disassembly[#mismatch_disassembly + 1] = {
                at = tonumber(at, 16), mnemonic = mnemonic, operands = operands,
            } end
        end
    end
end
assert(#mismatch_disassembly > 0, "typed specialization mismatch CPS exit absent")
for _, instructions in pairs(exact_disassembly) do
    for _, instruction in ipairs(instructions) do
        if instruction.operands:match("^%$0x9,0x[%da-fA-F]+%(") then
            mismatch_audit.inline_publishers = mismatch_audit.inline_publishers + 1
        end
    end
end
assert(mismatch_audit.inline_publishers == 0,
    "exact residual retained inline rejected-outcome publication")

local bank = { v2 = v2, learning = learning, residual = residual, cps = cps,
    assembly_audit = assembly_audit, branch_provenance = branch_provenance,
    mismatch_audit = mismatch_audit }

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
for _, item in pairs(residual) do byte_count = byte_count + #item.code end
for _, item in pairs(learning) do byte_count = byte_count + #item.code end
print(("Lua55 V2 bank: opcodes=%d residual=%d learning=%d cps=8 (%d bytes)"):format(
    section_count, #({ }) and (function() local n=0 for _ in pairs(residual) do n=n+1 end return n end)(),
    (function() local n=0 for _ in pairs(learning) do n=n+1 end return n end)(), byte_count))
