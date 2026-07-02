package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local modules = Schema.modules_for_test()
local saw_native = false
for _, name in ipairs(modules) do
    assert(name ~= "residual", "default schema modules must not load LalinResidual")
    if name == "native" then saw_native = true end
end
assert(saw_native, "default schema modules should load LalinNative")

local T = asdl.context()
Schema(T)
assert(T.LalinNative ~= nil, "LalinNative schema should be defined")
assert(T.LalinResidual == nil, "LalinResidual should not be part of the default schema projection")

require("lalin.native_mc")(T)
local N = T.LalinNative
local Code = T.LalinCode
local target = N.NativeTarget(
    N.NativeTargetId("schema-native-target"),
    N.NativeArchX64,
    N.NativeOsLinux,
    N.NativeAbiSysV,
    64,
    N.NativeLittleEndian
)
local runtime = N.NativeRuntime({})
local scalar_i32 = N.NativeScalarInt(32, Code.CodeSigned)
local register = N.NativeRegister(
    N.NativeRegisterId("schema-native-register:x64:eax"),
    target,
    N.NativeRegisterClassGpr,
    scalar_i32,
    "eax"
)
local value_id = N.NativeTemplateValueId("schema-native-value")
local register_location = N.NativeValueRegisterLocation(register)
local value_placement = N.NativeValuePlacement(value_id, scalar_i32, register_location)
local param_placement = N.NativeAbiParamPlacement(0, scalar_i32, register_location, N.NativeSignExtend)
local result_placement = N.NativeAbiResultPlacement(0, scalar_i32, register_location, N.NativePreserveLowerBits)
local support_domain = N.NativeTemplateSupportDomain(
    N.NativeTemplateSupportDomainId("schema-native-support-domain"),
    target,
    runtime,
    { N.NativeScalarSupport(scalar_i32, Code.CodeTyInt(32, Code.CodeSigned), N.NativeSignExtend) },
    { N.NativeRegisterSupport(register, { scalar_i32 }, { N.NativeRegisterUseParam, N.NativeRegisterUseResult }) },
    { N.NativeAbiScalarConvention(scalar_i32, { param_placement }, { result_placement }) },
    { N.NativeCallReturnScalar(scalar_i32) },
    { N.NativeRegisterProtocolX64SysV },
    { N.NativeScratchInteger },
    { N.NativeAccumulatorInteger },
    { 1 },
    { 1 },
    { 1 }
)
assert(support_domain.scalars[1].scalar == scalar_i32, "support domain must carry typed scalar facts")
local protocol = N.NativeTemplateProtocol(N.NativeCallReturnI32, N.NativeRegisterProtocolNone)
local family = N.NativeTemplateFamily(
    N.NativeTemplateFamilyId("schema.native.family"),
    N.NativeRoleRuntimeCall,
    { N.NativeAxisTarget(target) },
    protocol
)
local embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("schema-native-bank"),
    target,
    {
        N.NativeEmbeddedTemplate(
            family,
            N.NativeTextSection(N.NativeTemplateBytes(string.char(0xC3), 1), 1),
            { N.NativeSymbol("schema_native_entry", 0, 1) },
            {},
            {}
        ),
    }
)
local imported = N.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, N.NativeEmbeddedBankImported), tostring(imported))
assert(#imported.bank.entries == 1, "embedded native bank should import as NativeTemplateBank")

local node_id = N.NativeTemplateNodeId("schema-native-node")
local frame_slot = N.NativeFrameSlot(N.NativeFrameSlotId("schema-native-frame-slot"), scalar_i32, 0, 4, 4)
local frame_layout = N.NativeFrameLayout({ frame_slot }, 16, 16)
local graph = N.NativeTemplateGraph(
    target,
    N.NativeCallReturnScalar(scalar_i32),
    frame_layout,
    { N.NativeTemplateNode(node_id, imported.bank.entries[1], { value_placement }, { value_placement }, {}) },
    {},
    { N.NativeRegisterValueEdge(value_id, node_id, node_id, scalar_i32, register) },
    node_id,
    { node_id }
)
assert(graph.protocol.scalar == scalar_i32, "NativeTemplateGraph should carry graph-level call protocol")
assert(graph.nodes[1].inputs[1].location.register == register, "NativeTemplateNode inputs should carry typed value placements")
assert(graph.value_edges[1].register == register, "NativeValueEdge should carry typed register values, not register strings")

io.write("lalin schema_native ok\n")
