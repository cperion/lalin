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

local Code = T.MoonCode
local code_i32 = Code.CodeTyInt(32, Code.CodeSigned)
local code_sig = Code.CodeSigId("sig:add_i32")
local code_func = Code.CodeFuncId("fn:add_i32")
local code_extern = Code.CodeExternId("extern:puts")
local code_data = Code.CodeDataId("data:bytes")
local code_global = Code.CodeGlobalId("global:counter")
local code_block = Code.CodeBlockId("block:entry")
local code_value = Code.CodeValueId("value:result")
local code_origin = Code.CodeOriginGenerated("schema_core contract fixture")
local code_inst = Code.CodeInst(
    Code.CodeInstId("inst:const"),
    Code.CodeInstConst(code_value, Code.CodeConstLiteral(code_i32, C.LitInt("1"))),
    code_origin
)
assert(code_inst.id.text == "inst:const")
assert(pvm.classof(code_inst.kind) == Code.CodeInstConst)
local code_term = Code.CodeTerm(
    Code.CodeTermId("term:return"),
    Code.CodeTermReturn({ code_value }),
    code_origin
)
assert(code_term.id.text == "term:return")
local code_block_node = Code.CodeBlock(code_block, "entry", {}, { code_inst }, code_term, code_origin)
assert(code_block_node.term.id == code_term.id)
local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, code_i32, 4, Code.CodeMayTrap, false, nil)
assert(access.mode == Code.CodeMemoryRead)
local reloc = Code.CodeReloc(Code.CodeRelocId("reloc:fn"), 0, Code.CodeGlobalRefFunc(code_func), 0, code_origin)
local data = Code.CodeData(code_data, "bytes", Code.CodeLinkageLocal, 8, 8, { Code.CodeDataReloc(reloc) }, code_origin)
local global = Code.CodeGlobal(code_global, "counter", code_i32, Code.CodeLinkageLocal, 4, 4, {}, code_origin)
local direct_call = Code.CodeCallDirect(code_func)
local extern_call = Code.CodeCallExtern(code_extern)
local indirect_call = Code.CodeCallIndirect(Code.CodeValueId("value:callee"), code_sig)
local closure_call = Code.CodeCallClosure(Code.CodeValueId("value:closure"), code_sig)
assert(direct_call.func == code_func)
assert(extern_call.extern == code_extern)
assert(indirect_call.sig == code_sig)
assert(closure_call.sig == code_sig)
local module = Code.CodeModule(
    Code.CodeModuleId("module:test"),
    { Code.CodeSig(code_sig, { code_i32, code_i32 }, { code_i32 }) },
    { Code.CodeTypeDecl(Code.CodeTypeId("type:i32"), "i32", code_i32, code_origin) },
    { data },
    { global },
    { Code.CodeExtern(code_extern, "puts", "puts", code_sig, code_origin) },
    { Code.CodeFunc(code_func, "add_i32", Code.CodeLinkageExport, code_sig, {}, {}, code_block, { code_block_node }, code_origin) },
    code_origin
)
assert(module.id.text == "module:test")
assert(module.data[1].id == code_data)

io.write("moonlift schema_core ok\n")
