package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local AsdlParser = require("moonlift.asdl_parser")
local AsdlText = require("moonlift.asdl_text")

assert(Schema.assert_schema_directory_sources())
local ok_builder, err_builder = pcall(Schema.assert_schema_directory_sources, { "core.asdl", "init.lua", "legacy.lua" })
assert(not ok_builder and tostring(err_builder):match("Lua schema builder modules are forbidden"))
local ok_asdl, err_asdl = pcall(Schema.assert_schema_directory_sources, { "core.asdl", "init.lua", "surprise.asdl" })
assert(not ok_asdl and tostring(err_asdl):match("unexpected ASDL source"))
local ok_parse, err_parse = pcall(AsdlParser.parse, "module Bad { X = (i32 }", "bad_source.asdl")
assert(not ok_parse and tostring(err_parse):match("bad_source%.asdl:%d+:%d+: ASDL parse error"))

local function with_embedded_schema_only(body)
    local saved = {}
    for _, name in ipairs(Schema.schema_asdl_modules_for_test()) do
        local preload_name = "moonlift.schema." .. name .. "_asdl"
        local path = "lua/moonlift/schema/" .. name .. ".asdl"
        local text = assert(AsdlText.read_file(path))
        saved[#saved + 1] = {
            preload_name = preload_name,
            preload = package.preload[preload_name],
            loaded = package.loaded[preload_name],
        }
        package.loaded[preload_name] = nil
        package.preload[preload_name] = function() return text end
    end
    local ok, err = pcall(function()
        AsdlText.with_read_file_for_test(function(path)
            error("filesystem ASDL read disabled: " .. tostring(path), 0)
        end, body)
    end)
    for _, item in ipairs(saved) do
        package.preload[item.preload_name] = item.preload
        package.loaded[item.preload_name] = item.loaded
    end
    if not ok then error(err, 0) end
end

with_embedded_schema_only(function()
    local embedded_T = pvm.context()
    local embedded_schema = Schema.schema(embedded_T)
    assert(pvm.classof(embedded_schema) == embedded_T.MoonAsdl.Schema)
    assert(embedded_schema.modules[1].name == "MoonCore")
end)

local T = pvm.context()
local schema = Schema.schema(T)
assert(pvm.classof(schema) == T.MoonAsdl.Schema)
assert(#schema.modules >= 16)
assert(schema.modules[1].name == "MoonCore")
assert(schema.modules[2].name == "MoonBack")

-- Define directly from schema data (no text round-trip).
Schema.Define(T)

local C = T.MoonCore
assert(C.Id("x") == C.Id("x"))
assert(C.Path({ C.Name("a"), C.Name("b") }) == C.Path({ C.Name("a"), C.Name("b") }))
assert(C.ScalarI32.kind == "ScalarI32")
assert(C.ScalarInfo(C.ScalarFamilySignedInt, C.ScalarBits(32)).bits.bits == 32)
assert(C.LitInt("7") == C.LitInt("7"))
assert(C.LitBool(true).value == true)
assert(C.VisibilityExport.kind == "VisibilityExport")
assert(C.MachineCastSToF.kind == "MachineCastSToF")
assert(C.ExternSym("extern:puts", "puts", "puts").symbol == "puts")

local B = T.MoonBack
local sig = B.BackSigId("sig:add_i32")
local func = B.BackFuncId("add_i32")
local entry = B.BackBlockId("entry")
local a = B.BackValId("a")
local b = B.BackValId("b")
local r = B.BackValId("r")
local program = B.BackProgram({
    B.CmdCreateSig(sig, { B.BackI32, B.BackI32 }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { a, b }),
    B.CmdIntBinary(r, B.BackIntAdd, B.BackI32, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), a, b),
    B.CmdReturnValue(r),
    B.CmdSealBlock(entry),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
assert(#program.cmds == 11)

local Ty = T.MoonType
local i32 = Ty.TScalar(C.ScalarI32)
assert(i32.scalar == C.ScalarI32)

io.write("moonlift schema_core ok\n")
