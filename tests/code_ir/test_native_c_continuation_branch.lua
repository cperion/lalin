package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
    io.write("skip native C continuation branch: requires x64 non-Windows little-endian 64-bit host\n")
    os.exit(0)
end

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Support = require("lalin.native_template_support")(T)

local dir = "target/test_artifacts/test_native_c_continuation_branch"
assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))
local manifest_path = dir .. "/manifest.lua"
local mf = assert(io.open(manifest_path, "wb"))
mf:write([=[
return function(T)
  local N = T.LalinNative
  local Code = T.LalinCode
  local Support = require('lalin.native_template_support')(T)
  local target = Support.host_target()
  local scalar = Support.scalar_i32()
  local protocol = Support.protocol_for_scalar_frame(scalar)
  local void_protocol = Support.protocol_void_none()
  local first = Support.first_continuation_symbol()
  local next = Support.next_continuation_symbol()
  local then_sym = Support.then_continuation_symbol()
  local else_sym = Support.else_continuation_symbol()
  local function family(id, role, protocol_value)
    return N.NativeTemplateFamily(
      N.NativeTemplateFamilyId(id),
      role,
      { N.NativeAxisTarget(target), N.NativeAxisRegisterProtocol(N.NativeRegisterProtocolNone) },
      protocol_value
    )
  end
  local entry_family = family('native.test.branch.entry', N.NativeRoleCodeFunc, protocol)
  local branch_family = family('native.test.branch.branch', N.NativeRoleCodeTerm, void_protocol)
  local true_family = family('native.test.branch.true', N.NativeRoleCodeInst, void_protocol)
  local false_family = family('native.test.branch.false', N.NativeRoleCodeInst, void_protocol)
  local terminal_family = family('native.test.branch.terminal', N.NativeRoleCodeTerm, void_protocol)
  local entry_c = [[
#include <stdint.h>
extern void lalin_native_cont_first(uint8_t *frame);
int32_t lalin_test_branch_entry(int32_t cond, int32_t ignored) {
    (void)ignored;
    uint8_t frame[32];
    *(int32_t *)(void *)(frame + 0) = cond;
    lalin_native_cont_first(frame);
    return *(int32_t *)(void *)(frame + 4);
}
]]
  local branch_c = [[
#include <stdint.h>
extern void lalin_native_cont_then(uint8_t *frame);
extern void lalin_native_cont_else(uint8_t *frame);
void lalin_test_branch(uint8_t *frame) {
    if (*(int32_t *)(void *)(frame + 0) != 0) {
        lalin_native_cont_then(frame);
    } else {
        lalin_native_cont_else(frame);
    }
}
]]
  local true_c = [[
#include <stdint.h>
extern void lalin_native_cont_next(uint8_t *frame);
void lalin_test_branch_true(uint8_t *frame) {
    *(int32_t *)(void *)(frame + 4) = 1;
    lalin_native_cont_next(frame);
}
]]
  local false_c = [[
#include <stdint.h>
extern void lalin_native_cont_next(uint8_t *frame);
void lalin_test_branch_false(uint8_t *frame) {
    *(int32_t *)(void *)(frame + 4) = 2;
    lalin_native_cont_next(frame);
}
]]
  local terminal_c = [[
#include <stdint.h>
void lalin_test_branch_terminal(uint8_t *frame) { (void)frame; return; }
]]
  return N.NativeTemplateBankRequest(N.NativeBankId('native-test-branch-bank'), target, Support.empty_runtime(), {
    N.NativeTemplateSource(N.NativeTemplateId('native.test.branch.entry'), entry_family, N.NativeExtractEntryCallable(N.NativePatchFrameSize(32), first), 'lalin_test_branch_entry', entry_c, {}),
    N.NativeTemplateSource(N.NativeTemplateId('native.test.branch.branch'), branch_family, N.NativeExtractContinuationFragment({ then_sym, else_sym }), 'lalin_test_branch', branch_c, {}),
    N.NativeTemplateSource(N.NativeTemplateId('native.test.branch.true'), true_family, N.NativeExtractContinuationFragment({ next }), 'lalin_test_branch_true', true_c, {}),
    N.NativeTemplateSource(N.NativeTemplateId('native.test.branch.false'), false_family, N.NativeExtractContinuationFragment({ next }), 'lalin_test_branch_false', false_c, {}),
    N.NativeTemplateSource(N.NativeTemplateId('native.test.branch.terminal'), terminal_family, N.NativeExtractTerminalContinuation, 'lalin_test_branch_terminal', terminal_c, {}),
  })
end
]=])
mf:close()

local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local lua_path = dir .. "/bank.lua"
local cmd = table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(c_path),
    shell_quote(h_path),
    shell_quote(lua_path),
    shell_quote(manifest_path),
    ">", shell_quote(dir .. "/generator.out"),
    "2>", shell_quote(dir .. "/generator.log"),
}, " ")
assert(command_ok(cmd), "native branch continuation bank should build")

local embedded = dofile(lua_path)(T)
local imported = Native.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, Native.NativeEmbeddedBankImported), tostring(imported))
local bank = imported.bank

local function entry(family_id)
    for _, candidate in ipairs(bank.entries) do
        if candidate.family.id.text == family_id then return candidate end
    end
    error("missing family " .. family_id)
end

local entry_node_id = Native.NativeTemplateNodeId("branch.node.entry")
local branch_node_id = Native.NativeTemplateNodeId("branch.node.branch")
local true_node_id = Native.NativeTemplateNodeId("branch.node.true")
local false_node_id = Native.NativeTemplateNodeId("branch.node.false")
local terminal_node_id = Native.NativeTemplateNodeId("branch.node.terminal")
local graph = Native.NativeTemplateGraph(
    Support.host_target(),
    Native.NativeCallReturnScalar(Support.scalar_i32()),
    Native.NativeFrameLayout({
        Native.NativeFrameSlot(Native.NativeFrameSlotId("branch.frame.cond"), Support.scalar_i32(), 0, 4, 4),
        Native.NativeFrameSlot(Native.NativeFrameSlotId("branch.frame.result"), Support.scalar_i32(), 4, 4, 4),
    }, 32, 16),
    {
        Native.NativeTemplateNode(entry_node_id, entry("native.test.branch.entry"), {}, {}, {}),
        Native.NativeTemplateNode(branch_node_id, entry("native.test.branch.branch"), {}, {}, {}),
        Native.NativeTemplateNode(true_node_id, entry("native.test.branch.true"), {}, {}, {}),
        Native.NativeTemplateNode(false_node_id, entry("native.test.branch.false"), {}, {}, {}),
        Native.NativeTemplateNode(terminal_node_id, entry("native.test.branch.terminal"), {}, {}, {}),
    },
    {
        Native.NativeContinuationEdge(entry_node_id, branch_node_id, Support.first_continuation_symbol()),
        Native.NativeContinuationEdge(branch_node_id, true_node_id, Support.then_continuation_symbol()),
        Native.NativeContinuationEdge(branch_node_id, false_node_id, Support.else_continuation_symbol()),
        Native.NativeContinuationEdge(true_node_id, terminal_node_id, Support.next_continuation_symbol()),
        Native.NativeContinuationEdge(false_node_id, terminal_node_id, Support.next_continuation_symbol()),
    },
    {},
    entry_node_id,
    { terminal_node_id }
)
local plan = graph:select_native_copy_plan(Native.NativeCopyPlanSelectionInput(Support.host_target(), Support.empty_runtime()))
local install = plan:install_native(Native.NativeInstallInput(Support.host_target(), Support.empty_runtime(), Native.NativeExecutableAllocatorMmap))
assert(asdl.isa(install, Native.NativeInstallSucceeded), tostring(install))
local true_call = graph.protocol:call_native_executable(Native.NativeExecutableCallInput(install.executable, { Native.NativeCallArgI32(1), Native.NativeCallArgI32(0) }))
assert(asdl.isa(true_call, Native.NativeCallReturnedI32) and true_call.value == 1, "then continuation should be patched and executed")
local false_call = graph.protocol:call_native_executable(Native.NativeExecutableCallInput(install.executable, { Native.NativeCallArgI32(0), Native.NativeCallArgI32(0) }))
assert(asdl.isa(false_call, Native.NativeCallReturnedI32) and false_call.value == 2, "else continuation should be patched and executed")

io.write("native C continuation branch ok\n")
