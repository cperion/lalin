package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local N = T.LalinNative

local function target(id)
    return N.NativeTarget(
        N.NativeTargetId(id),
        N.NativeArchX64,
        N.NativeOsLinux,
        N.NativeAbiSysV,
        64,
        N.NativeLittleEndian
    )
end

local function family(target_value, id)
    return N.NativeTemplateFamily(
        N.NativeTemplateFamilyId(id),
        N.NativeRoleRuntimeCall,
        { N.NativeAxisTarget(target_value) },
        N.NativeTemplateProtocol(N.NativeCallReturnI32, N.NativeRegisterProtocolNone)
    )
end

local target_a = target("native-mc-target-a")
local target_b = target("native-mc-target-b")
local family_a = family(target_a, "native.mc.return_i32")
local hole_id = N.NativePatchHoleId("imm32:return")
local hole = N.NativeHoleLayout(hole_id, "return_imm", 1, 4, N.NativePatchImm32)
local bytes = N.NativeTextSection(N.NativeTemplateBytes(string.char(0xB8, 0, 0, 0, 0, 0xC3), 6), 16)
local embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("native-mc-bank"),
    target_a,
    {
        N.NativeEmbeddedTemplate(
            family_a,
            bytes,
            { N.NativeSymbol("native_mc_return_i32", 0, 6) },
            {},
            { hole }
        ),
    }
)

local imported = N.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, N.NativeEmbeddedBankImported), tostring(imported))
assert(#imported.bank.entries == 1, "expected one native template bank entry")

local selected = imported.bank:select_native_template(N.NativeTemplateSelectionInput(target_a, family_a))
assert(asdl.isa(selected, N.NativeTemplateSelected), tostring(selected))

local mismatch = imported.bank:select_native_template(N.NativeTemplateSelectionInput(target_b, family_a))
assert(asdl.isa(mismatch, N.NativeTemplateSelectionRejected), tostring(mismatch))
assert(asdl.isa(mismatch.rejects[1], N.NativeSelectionRejectTargetMismatch), tostring(mismatch.rejects[1]))

local missing_family = family(target_a, "native.mc.missing")
local missing = imported.bank:select_native_template(N.NativeTemplateSelectionInput(target_a, missing_family))
assert(asdl.isa(missing, N.NativeTemplateSelectionRejected), tostring(missing))
assert(asdl.isa(missing.rejects[1], N.NativeSelectionRejectMissingBankEntry), tostring(missing.rejects[1]))

local node_id = N.NativeTemplateNodeId("node:return")
local frame_layout = N.NativeFrameLayout({}, 0, 1)
local function graph_with_bindings(bindings)
    return N.NativeTemplateGraph(
        target_a,
        N.NativeCallReturnI32,
        frame_layout,
        { N.NativeTemplateNode(node_id, selected.entry, {}, {}, bindings) },
        {},
        {},
        node_id,
        { node_id }
    )
end

local copy_plan = graph_with_bindings({ N.NativePatchBinding(hole_id, N.NativePatchImmediateI32(77)) })
    :select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
assert(copy_plan.layout.size == 6, "copy plan should lay out template bytes")
assert(copy_plan.layout.alignment == 16, "copy plan should preserve template alignment")
assert(asdl.isa(copy_plan.protocol, N.NativeCallReturnI32), "copy plan should preserve entry family call protocol")
local install = copy_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(install, N.NativeInstallSucceeded), tostring(install))
local call = copy_plan.protocol:call_native_executable(N.NativeExecutableCallInput(install.executable, {}))
assert(asdl.isa(call, N.NativeCallReturnedI32), tostring(call))
assert(call.value == 77, "patched native executable should return the imm32 coordinate")

local missing_binding_plan = graph_with_bindings({})
    :select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local missing_binding_install = missing_binding_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(missing_binding_install, N.NativeInstallRejected), tostring(missing_binding_install))
assert(asdl.isa(missing_binding_install.rejects[1], N.NativeInstallRejectMissingBinding), tostring(missing_binding_install.rejects[1]))

local duplicate_plan = graph_with_bindings({
    N.NativePatchBinding(hole_id, N.NativePatchImmediateI32(1)),
    N.NativePatchBinding(hole_id, N.NativePatchImmediateI32(2)),
}):select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local duplicate_install = duplicate_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(duplicate_install, N.NativeInstallRejected), tostring(duplicate_install))
assert(asdl.isa(duplicate_install.rejects[1], N.NativeInstallRejectDuplicateBinding), tostring(duplicate_install.rejects[1]))

local wrong_coordinate_plan = graph_with_bindings({ N.NativePatchBinding(hole_id, N.NativePatchPointer64(0)) })
    :select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local wrong_coordinate_install = wrong_coordinate_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(wrong_coordinate_install, N.NativeInstallRejected), tostring(wrong_coordinate_install))
assert(asdl.isa(wrong_coordinate_install.rejects[1], N.NativeInstallRejectWrongCoordinate), tostring(wrong_coordinate_install.rejects[1]))

local bad_embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("native-mc-bad-bank"),
    target_a,
    {
        N.NativeEmbeddedTemplate(
            family_a,
            N.NativeTextSection(N.NativeTemplateBytes(string.char(0xC3), 1), 1),
            {},
            {},
            { N.NativeHoleLayout(N.NativePatchHoleId("bad"), "bad", 1, 4, N.NativePatchImm32) }
        ),
    }
)
local bad_import = N.NativeEmbeddedBankImportRequest(bad_embedded):import_native_bank()
assert(asdl.isa(bad_import, N.NativeEmbeddedBankRejected), tostring(bad_import))
assert(asdl.isa(bad_import.rejects[1], N.NativeBuildRejectHoleOutOfRange), tostring(bad_import.rejects[1]))

io.write("lalin native_mc import ok\n")
