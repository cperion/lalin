local asdl = require("lalin.asdl")
local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then ffi = nil end

local ffi_declared = false

local function require_ffi(operation)
    if ffi == nil then error("lalin.native_mc: ffi is required for " .. operation, 3) end
    return ffi
end

local function declare_ffi()
    local f = require_ffi("C-owned native bank runtime")
    if ffi_declared then return f end
    f.cdef [[
        void *mmap(void *addr, size_t length, int prot, int flags, int fd, int64_t offset);

        typedef enum LalinNativeSelectionStatus {
          LALIN_NATIVE_SELECT_OK = 0,
          LALIN_NATIVE_SELECT_INVALID = 1,
          LALIN_NATIVE_SELECT_TARGET_MISMATCH = 2,
          LALIN_NATIVE_SELECT_MISSING = 3,
          LALIN_NATIVE_SELECT_AMBIGUOUS = 4
        } LalinNativeSelectionStatus;

        typedef enum LalinNativeInstallStatus {
          LALIN_NATIVE_INSTALL_OK = 0,
          LALIN_NATIVE_INSTALL_REJECTED = 1,
          LALIN_NATIVE_INSTALL_ALLOCATION_FAILED = 2
        } LalinNativeInstallStatus;

        typedef enum LalinNativePatchCoordinateKind {
          LALIN_NATIVE_COORD_NONE = 0,
          LALIN_NATIVE_COORD_IMMEDIATE_I32 = 1,
          LALIN_NATIVE_COORD_IMMEDIATE_I64 = 2,
          LALIN_NATIVE_COORD_POINTER64 = 3,
          LALIN_NATIVE_COORD_FIELD_OFFSET = 4,
          LALIN_NATIVE_COORD_COMPONENT_INDEX = 5,
          LALIN_NATIVE_COORD_STRIDE = 6,
          LALIN_NATIVE_COORD_AFFINE_COEFF = 7,
          LALIN_NATIVE_COORD_AFFINE_OFFSET = 8,
          LALIN_NATIVE_COORD_WINDOW_OFFSET = 9,
          LALIN_NATIVE_COORD_BRANCH_TARGET = 10,
          LALIN_NATIVE_COORD_CALL_TARGET = 11,
          LALIN_NATIVE_COORD_CODE_DATA_ADDRESS = 12,
          LALIN_NATIVE_COORD_CODE_GLOBAL_ADDRESS = 13,
          LALIN_NATIVE_COORD_CODE_FUNC_ADDRESS = 14,
          LALIN_NATIVE_COORD_CODE_EXTERN_ADDRESS = 15,
          LALIN_NATIVE_COORD_FRAME_OFFSET = 16,
          LALIN_NATIVE_COORD_FRAME_SIZE = 17,
          LALIN_NATIVE_COORD_SCALAR_CONST = 18,
          LALIN_NATIVE_COORD_CONSTANT_POOL_ENTRY = 19,
          LALIN_NATIVE_COORD_MODULE_ADDRESS = 20
        } LalinNativePatchCoordinateKind;

        typedef enum LalinNativeInstallControlEdgeKind {
          LALIN_NATIVE_INSTALL_EDGE_FALLTHROUGH = 1,
          LALIN_NATIVE_INSTALL_EDGE_CONDITIONAL_BRANCH = 2,
          LALIN_NATIVE_INSTALL_EDGE_LOOP_BACKEDGE = 3,
          LALIN_NATIVE_INSTALL_EDGE_EXIT = 4,
          LALIN_NATIVE_INSTALL_EDGE_CONTINUATION = 5,
          LALIN_NATIVE_INSTALL_EDGE_RUNTIME_CALL_RETURN = 6
        } LalinNativeInstallControlEdgeKind;

        typedef enum LalinNativeModuleAddressKind {
          LALIN_NATIVE_MODULE_ADDRESS_DATA = 1,
          LALIN_NATIVE_MODULE_ADDRESS_GLOBAL = 2,
          LALIN_NATIVE_MODULE_ADDRESS_FUNC = 3,
          LALIN_NATIVE_MODULE_ADDRESS_EXTERN = 4
        } LalinNativeModuleAddressKind;

        typedef struct LalinNativeTemplateSelectorEntry {
          const char *target_id;
          const char *family_id;
          size_t template_ordinal;
        } LalinNativeTemplateSelectorEntry;

        typedef struct LalinNativeTemplate {
          size_t ordinal;
          const char *template_id;
          const char *family_id;
          const char *extraction_kind;
          const char *signature_frame_scalar_kind;
          const unsigned char *text;
          size_t text_size;
          size_t text_alignment;
          const void *symbols;
          size_t symbol_count;
          const void *relocations;
          size_t relocation_count;
          const void *holes;
          size_t hole_count;
          const void *hole_ordinals;
          size_t hole_ordinal_count;
          const void *constant_pool_entries;
          size_t constant_pool_entry_count;
          size_t constant_pool_size;
          size_t constant_pool_alignment;
        } LalinNativeTemplate;

        typedef struct LalinNativeBankArtifact {
          const char *bank_id;
          const char *target_id;
          const char *api_symbol;
          const char *selector_symbol;
          const char *installer_symbol;
          const LalinNativeTemplate *templates;
          size_t template_count;
          const LalinNativeTemplateSelectorEntry *selectors;
          size_t selector_count;
          size_t manifest_total_count;
        } LalinNativeBankArtifact;

        typedef struct LalinNativeTemplateSelectorKey {
          const char *target_id;
          const char *family_id;
        } LalinNativeTemplateSelectorKey;

        typedef struct LalinNativeTemplateHandle {
          const LalinNativeBankArtifact *bank;
          const LalinNativeTemplate *template_entry;
          size_t ordinal;
        } LalinNativeTemplateHandle;

        typedef struct LalinNativeTemplateSelection {
          LalinNativeSelectionStatus status;
          LalinNativeTemplateHandle handle;
          const LalinNativeTemplateSelectorEntry *matches;
          size_t match_count;
        } LalinNativeTemplateSelection;

        typedef struct LalinNativePatchCoordinate {
          LalinNativePatchCoordinateKind kind;
          int64_t signed_value;
          uint64_t unsigned_value;
          const char *primary_id;
          const char *secondary_id;
          size_t index;
          const unsigned char *bytes;
          size_t byte_size;
          size_t byte_alignment;
        } LalinNativePatchCoordinate;

        typedef struct LalinNativeInstallBinding {
          const char *node_id;
          const char *instance_id;
          const char *hole_id;
          const char *hole_ordinal_id;
          int has_hole_ordinal_index;
          size_t hole_ordinal_index;
          LalinNativePatchCoordinate coordinate;
        } LalinNativeInstallBinding;

        typedef struct LalinNativeInstallNode {
          const char *node_id;
          const char *instance_id;
          const char *key_target_id;
          const char *family_id;
          const LalinNativeInstallBinding *bindings;
          size_t binding_count;
        } LalinNativeInstallNode;

        typedef struct LalinNativeInstallControlEdge {
          LalinNativeInstallControlEdgeKind kind;
          const char *from_node_id;
          const char *to_node_id;
          const char *then_node_id;
          const char *then_symbol;
          const char *else_node_id;
          const char *else_symbol;
          const char *symbol;
          const char *runtime_symbol_id;
          const char *return_symbol;
        } LalinNativeInstallControlEdge;

        typedef struct LalinNativeRuntimeSymbolAddress {
          const char *symbol_id;
          uint64_t address;
        } LalinNativeRuntimeSymbolAddress;

        typedef struct LalinNativeModuleAddress {
          LalinNativeModuleAddressKind kind;
          const char *id;
          uint64_t address;
        } LalinNativeModuleAddress;

        typedef void *(*LalinNativeExecutableAllocFn)(size_t size, size_t alignment, void *userdata);

        typedef struct LalinNativeInstallRequest {
          const char *target_id;
          const LalinNativeInstallNode *nodes;
          size_t node_count;
          const LalinNativeInstallControlEdge *control_edges;
          size_t control_edge_count;
          const LalinNativeRuntimeSymbolAddress *runtime_symbols;
          size_t runtime_symbol_count;
          const LalinNativeModuleAddress *module_addresses;
          size_t module_address_count;
          const char *entry_node_id;
          LalinNativeExecutableAllocFn allocate_executable;
          void *allocator_userdata;
        } LalinNativeInstallRequest;

        typedef enum LalinNativeInstallRejectKind {
          LALIN_NATIVE_INSTALL_REJECT_GENERIC = 0,
          LALIN_NATIVE_INSTALL_REJECT_FALLTHROUGH_LAYOUT = 1
        } LalinNativeInstallRejectKind;

        typedef struct LalinNativeInstallReject {
          LalinNativeInstallRejectKind kind;
          const char *node_id;
          const char *to_node_id;
          const char *hole_id;
          const char *reason;
        } LalinNativeInstallReject;

        typedef struct LalinNativeInstallResult {
          LalinNativeInstallStatus status;
          void *base_address;
          void *entry_address;
          size_t size;
          const LalinNativeInstallReject *rejects;
          size_t reject_count;
        } LalinNativeInstallResult;

        const LalinNativeBankArtifact *lalin_native_bank_artifact(void);
        const LalinNativeTemplate *lalin_native_bank_template(const LalinNativeBankArtifact *bank, size_t ordinal);
        LalinNativeSelectionStatus lalin_native_bank_select(const LalinNativeBankArtifact *bank, const LalinNativeTemplateSelectorKey *key, LalinNativeTemplateSelection *out);
        LalinNativeInstallResult lalin_native_bank_install(const LalinNativeBankArtifact *bank, const LalinNativeInstallRequest *request);
    ]]
    ffi_declared = true
    return f
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_mc ~= nil then return T._lalin_api_cache.native_mc end

    require("lalin.native")(T)
    require("lalin.native_template_sources")(T)

    local Native = T.LalinNative
    local Support = require("lalin.native_template_support")(T)
    local api = {}
    local loaded_libraries = {}

    local PROT_READ = 0x1
    local PROT_WRITE = 0x2
    local PROT_EXEC = 0x4
    local MAP_PRIVATE = 0x02
    local MAP_ANON_LINUX = 0x20
    local MAP_ANON_DARWIN = 0x1000

    local function mmap_failed_pointer()
        return ffi.cast("void *", -1)
    end

    local function map_anon_flag()
        if jit and jit.os == "OSX" then return MAP_ANON_DARWIN end
        if jit and jit.os == "Linux" then return MAP_ANON_LINUX end
        error("lalin.native_mc: mmap allocator is not modeled for host OS " .. tostring(jit and jit.os), 3)
    end

    local function cstr(keepalive, value)
        if value == nil then return nil end
        local s = tostring(value)
        keepalive[#keepalive + 1] = s
        return s
    end

    local function text_id(value)
        return value and value.text or nil
    end

    local function target_id(target)
        return target and target.id and target.id.text or nil
    end

    local function family_id(family)
        return family and family.id and family.id.text or nil
    end

    local function symbol_name(symbol)
        return symbol and symbol.name or nil
    end

    local function executable_id_for_plan(plan)
        return Native.NativeExecutableId("native-executable:" .. plan.entry.text)
    end

    local function bank_pointer(bank)
        local f = declare_ffi()
        if bank.handle_address == nil or bank.handle_address == 0 then return nil end
        return f.cast("const LalinNativeBankArtifact *", bank.handle_address)
    end

    local function bank_library(bank)
        local f = declare_ffi()
        return loaded_libraries[bank.handle_address] or f.C
    end

    local function reject_summary(rejects)
        local count = #(rejects or {})
        if count == 0 then return "no typed rejects supplied" end
        return tostring(count) .. " typed reject(s); first reject: " .. tostring(rejects[1])
    end

    local function library_for_request(request)
        local f = declare_ffi()
        if request.shared_object_path ~= nil then
            local lib = f.load(request.shared_object_path)
            loaded_libraries[request.artifact] = lib
            return lib
        end
        return f.C
    end

    local function require_generated_symbols(artifact)
        if artifact.api_symbol ~= "lalin_native_bank_artifact" then
            return Native.NativeBankRejectMissingSymbol(artifact.api_symbol)
        end
        if artifact.selector_symbol ~= "lalin_native_bank_select" then
            return Native.NativeBankRejectMissingSymbol(artifact.selector_symbol)
        end
        if artifact.installer_symbol ~= "lalin_native_bank_install" then
            return Native.NativeBankRejectMissingSymbol(artifact.installer_symbol)
        end
        return nil
    end

    local function selection_reject(status, input)
        if status == 2 then
            return Native.NativeTemplateSelectionRejected({
                Native.NativeSelectionRejectTargetMismatch(input.key.target, input.bank.artifact.target),
            })
        end
        if status == 3 then
            return Native.NativeTemplateSelectionRejected({
                Native.NativeSelectionRejectMissingBankEntry(input.key.family),
            })
        end
        return Native.NativeTemplateSelectionRejected({
            Native.NativeSelectionRejectMissingBankEntry(input.key.family),
        })
    end

    local function selected_template_handle(input, c_handle)
        local template = c_handle.template_entry
        return Native.NativeTemplateHandle(
            input.bank.artifact.id,
            tonumber(c_handle.ordinal),
            input.key.family,
            tonumber(template.text_size),
            tonumber(template.text_alignment),
            tonumber(template.constant_pool_size),
            tonumber(template.constant_pool_alignment)
        )
    end

    local function c_coordinate(keepalive)
        local f = declare_ffi()
        local coord = f.new("LalinNativePatchCoordinate")
        keepalive[#keepalive + 1] = coord
        return coord
    end

    local function put_bytes(row, keepalive, bytes_value, alignment)
        if bytes_value == nil then return end
        local bytes = bytes_value.bytes or ""
        keepalive[#keepalive + 1] = bytes
        row.bytes = ffi.cast("const unsigned char *", bytes)
        row.byte_size = bytes_value.size or #bytes
        row.byte_alignment = alignment or 1
    end

    function Native.NativeRuntimeAddressCapability:native_runtime_address()
        return nil
    end

    function Native.NativeRuntimeAddressSupplied:native_runtime_address()
        return self.address
    end

    function Native.NativeRuntimeAddressLinkerSymbol:native_runtime_address()
        return nil
    end

    function Native.NativeBankLoadRejected:required_native_bank()
        error("lalin.native_mc: native bank load rejected: " .. reject_summary(self.rejects), 3)
    end

    function Native.NativeBankLoaded:required_native_bank()
        return self.bank
    end

    function Native.NativeBankLoadRequest:load_native_bank()
        local f = declare_ffi()
        local reject = require_generated_symbols(self.artifact)
        if reject ~= nil then return Native.NativeBankLoadRejected({ reject }) end
        local ok, lib_or_err = pcall(library_for_request, self)
        if not ok then return Native.NativeBankLoadRejected({ Native.NativeBankRejectLoadFailed(tostring(lib_or_err)) }) end
        local lib = lib_or_err
        local ok_call, ptr_or_err = pcall(function() return lib.lalin_native_bank_artifact() end)
        if not ok_call or ptr_or_err == nil then
            return Native.NativeBankLoadRejected({ Native.NativeBankRejectMissingSymbol(self.artifact.api_symbol) })
        end
        local c_bank = ptr_or_err
        local handle_address = tonumber(ffi.cast("uintptr_t", c_bank))
        loaded_libraries[handle_address] = lib
        if c_bank.bank_id ~= nil and ffi.string(c_bank.bank_id) ~= self.artifact.id.text then
            return Native.NativeBankLoadRejected({ Native.NativeBankRejectInvalidHandle("bank id does not match NativeBankArtifact descriptor") })
        end
        if c_bank.target_id ~= nil and ffi.string(c_bank.target_id) ~= self.artifact.target.id.text then
            return Native.NativeBankLoadRejected({ Native.NativeBankRejectInvalidHandle("target id does not match NativeBankArtifact descriptor") })
        end
        return Native.NativeBankLoaded(Native.NativeLoadedBank(self.artifact, handle_address))
    end

    function Native.NativeBankArtifact:load_native_bank(shared_object_path)
        return Native.NativeBankLoadRequest(self, shared_object_path):load_native_bank()
    end

    function Native.NativeTemplateSelectionRejected:required_template_handle()
        error("lalin.native_mc: native template selection rejected: " .. reject_summary(self.rejects), 3)
    end

    function Native.NativeTemplateSelectionAmbiguous:required_template_handle()
        error("lalin.native_mc: native template selection ambiguous for " .. self.key.family.id.text, 3)
    end

    function Native.NativeTemplateSelected:required_template_handle()
        return self.handle
    end

    function Native.NativeLoadedBank:select_native_template(input)
        local f = declare_ffi()
        if input.bank ~= self then error("lalin.native_mc: NativeTemplateSelectionInput bank does not match receiver", 3) end
        local c_bank = bank_pointer(self)
        if c_bank == nil then
            return Native.NativeTemplateSelectionRejected({ Native.NativeSelectionRejectMissingBankEntry(input.key.family) })
        end
        if self.artifact.target ~= input.key.target then
            return Native.NativeTemplateSelectionRejected({ Native.NativeSelectionRejectTargetMismatch(input.key.target, self.artifact.target) })
        end
        local keepalive = {}
        local key = f.new("LalinNativeTemplateSelectorKey")
        key.target_id = cstr(keepalive, target_id(input.key.target))
        key.family_id = cstr(keepalive, family_id(input.key.family))
        local out = f.new("LalinNativeTemplateSelection")
        local lib = bank_library(self)
        local status = lib.lalin_native_bank_select(c_bank, key, out)
        if status == 0 then return Native.NativeTemplateSelected(selected_template_handle(input, out.handle)) end
        if status == 4 then
            local handles = {}
            for i = 0, tonumber(out.match_count) - 1 do
                local ordinal = tonumber(out.matches[i].template_ordinal)
                local template = lib.lalin_native_bank_template(c_bank, ordinal)
                handles[#handles + 1] = Native.NativeTemplateHandle(
                    self.artifact.id,
                    ordinal,
                    input.key.family,
                    tonumber(template.text_size),
                    tonumber(template.text_alignment),
                    tonumber(template.constant_pool_size),
                    tonumber(template.constant_pool_alignment)
                )
            end
            return Native.NativeTemplateSelectionAmbiguous(input.key, handles)
        end
        return selection_reject(tonumber(status), input)
    end

    function Native.NativeTemplateSelectionInput:select_native_template()
        return self.bank:select_native_template(self)
    end

    function Native.NativePatchBindingHoleId:native_c_binding_target(row, keepalive)
        row.hole_id = cstr(keepalive, self.hole.text)
    end

    function Native.NativePatchBindingHoleOrdinal:native_c_binding_target(row, keepalive)
        row.hole_ordinal_id = cstr(keepalive, self.ordinal.text)
    end

    function Native.NativePatchBindingHoleOrdinalIndex:native_c_binding_target(row, _keepalive)
        row.has_hole_ordinal_index = 1
        row.hole_ordinal_index = self.ordinal
    end

    function Native.NativeBankPatchCoordinate:native_c_patch_coordinate(_row, _keepalive)
        error("lalin.native_mc: missing C projection for " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeBankPatchImmediateI32:native_c_patch_coordinate(row, _keepalive)
        row.kind = 1
        row.signed_value = self.value
    end

    function Native.NativeBankPatchImmediateI64:native_c_patch_coordinate(row, _keepalive)
        row.kind = 2
        row.signed_value = self.value
    end

    function Native.NativeBankPatchPointer64:native_c_patch_coordinate(row, _keepalive)
        row.kind = 3
        row.unsigned_value = self.address
    end

    function Native.NativeBankPatchFieldOffset:native_c_patch_coordinate(row, keepalive)
        row.kind = 4
        row.signed_value = self.offset
        row.primary_id = cstr(keepalive, self.field_name)
    end

    function Native.NativeBankPatchComponentIndex:native_c_patch_coordinate(row, keepalive)
        row.kind = 5
        row.signed_value = self.component_index
        row.primary_id = cstr(keepalive, self.field_name)
    end

    function Native.NativeBankPatchStride:native_c_patch_coordinate(row, _keepalive)
        row.kind = 6
        row.signed_value = self.stride
    end

    function Native.NativeBankPatchWindowOffset:native_c_patch_coordinate(row, _keepalive)
        row.kind = 9
        row.index = self.axis_index
        row.signed_value = self.offset
    end

    function Native.NativeBankPatchBranchTarget:native_c_patch_coordinate(row, keepalive)
        row.kind = 10
        row.primary_id = cstr(keepalive, self.node.text)
    end

    function Native.NativeBankPatchCallTarget:native_c_patch_coordinate(row, keepalive)
        row.kind = 11
        row.primary_id = cstr(keepalive, self.symbol.text)
    end

    function Native.NativeBankCodeDataAddress:native_c_module_address_kind()
        return 1, self.data.text, self.address
    end

    function Native.NativeBankCodeGlobalAddress:native_c_module_address_kind()
        return 2, self.global.text, self.address
    end

    function Native.NativeBankCodeFuncAddress:native_c_module_address_kind()
        return 3, self.func.text, self.address
    end

    function Native.NativeBankCodeExternAddress:native_c_module_address_kind()
        return 4, self.extern.text, self.address
    end

    function Native.NativeBankPatchModuleAddress:native_c_patch_coordinate(row, keepalive)
        local _kind, id, address = self.address:native_c_module_address_kind()
        row.kind = 20
        row.primary_id = cstr(keepalive, id)
        row.unsigned_value = address
    end

    function Native.NativeBankPatchFrameOffset:native_c_patch_coordinate(row, _keepalive)
        row.kind = 16
        row.signed_value = self.offset
    end

    function Native.NativeBankPatchFrameSize:native_c_patch_coordinate(row, _keepalive)
        row.kind = 17
        row.signed_value = self.size
    end

    function Native.NativeBankPatchScalarBytes:native_c_patch_coordinate(row, keepalive)
        row.kind = 18
        put_bytes(row, keepalive, self.bytes, self.bytes and self.bytes.size or 1)
    end

    function Native.NativeBankPatchConstantPoolEntry:native_c_patch_coordinate(row, keepalive)
        row.kind = 19
        row.primary_id = cstr(keepalive, self.entry.text)
        put_bytes(row, keepalive, self.bytes, self.bytes and self.bytes.size or 1)
    end

    function Native.NativePatchCoordinate:native_bank_patch_coordinate(_input)
        error("lalin.native_mc: native patch coordinate cannot be projected to C bank install ABI: " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativePatchImmediateI32:native_bank_patch_coordinate(_input) return Native.NativeBankPatchImmediateI32(self.value) end
    function Native.NativePatchImmediateI64:native_bank_patch_coordinate(_input) return Native.NativeBankPatchImmediateI64(self.value) end
    function Native.NativePatchPointer64:native_bank_patch_coordinate(_input) return Native.NativeBankPatchPointer64(self.address) end
    function Native.NativePatchFieldOffset:native_bank_patch_coordinate(_input) return Native.NativeBankPatchFieldOffset(self.field_name, self.offset) end
    function Native.NativePatchComponentIndex:native_bank_patch_coordinate(_input) return Native.NativeBankPatchComponentIndex(self.field_name, self.component_index) end
    function Native.NativePatchStride:native_bank_patch_coordinate(_input) return Native.NativeBankPatchStride(self.stride) end
    function Native.NativePatchWindowOffset:native_bank_patch_coordinate(_input) return Native.NativeBankPatchWindowOffset(self.axis_index, self.offset) end
    function Native.NativePatchBranchTarget:native_bank_patch_coordinate(_input) return Native.NativeBankPatchBranchTarget(self.node) end
    function Native.NativePatchCallTarget:native_bank_patch_coordinate(_input) return Native.NativeBankPatchCallTarget(self.symbol) end
    function Native.NativePatchFrameOffset:native_bank_patch_coordinate(_input) return Native.NativeBankPatchFrameOffset(self.offset) end
    function Native.NativePatchFrameSize:native_bank_patch_coordinate(_input) return Native.NativeBankPatchFrameSize(self.size) end
    function Native.NativePatchScalarConst:native_bank_patch_coordinate(_input)
        error("lalin.native_mc: NativePatchScalarConst must be lowered to NativeBankPatchScalarBytes before C bank install", 3)
    end
    function Native.NativePatchConstantPoolEntry:native_bank_patch_coordinate(_input)
        return Native.NativeBankPatchConstantPoolEntry(self.entry, self.bytes, self.ty)
    end

    function Native.NativeCodeAddressCapability:native_bank_patch_coordinate(_input, _coordinate)
        error("lalin.native_mc: native code address capability cannot be projected to C bank patch coordinate: " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeCodeAddressRuntimeSymbol:native_bank_patch_coordinate(_input, _coordinate)
        return Native.NativeBankPatchCallTarget(self.symbol)
    end

    function Native.NativePatchCodeExternAddress:native_bank_patch_coordinate(input)
        local projection = self:native_module_address_projection(input)
        if projection == nil then
            error("lalin.native_mc: NativePatchCodeExternAddress has no NativeModuleAddressPlan extern projection for " .. self.extern.text, 3)
        end
        return projection.capability:native_bank_patch_coordinate(input, self)
    end

    local function append_runtime_symbols(out, runtime)
        for _, symbol in ipairs((runtime and runtime.symbols) or {}) do
            local address = symbol.address and symbol.address:native_runtime_address() or nil
            if address ~= nil then out[#out + 1] = Native.NativeBankRuntimeSymbolAddress(symbol.id, address) end
        end
    end

    local function append_module_addresses(_out, _addresses)
        -- Module-address projections that depend on executable layout are C-bank-owned
        -- and must be expressed as NativeBankPatchBranchTarget/ConstantPoolEntry or
        -- concrete NativeBankModuleAddress values by the graph builder. There is no
        -- sound Lua-side address to compute here before C has selected and laid out
        -- templates.
    end

    local function fast_region_node_id(region_id)
        return Native.NativeTemplateNodeId("native.fast.node." .. region_id.text)
    end

    local function fast_region_instance_id(node_id)
        return Native.NativeTemplateInstanceId("native.fast.instance." .. node_id.text)
    end

    local function scalar_value_representation(scalar)
        return Native.NativeScalarValueRepresentation(scalar)
    end

    function Native.NativeRegionBoundaryResidence:native_fast_value_location(_binding)
        error("lalin.native_mc: fast-region residence cannot be projected to a graph value location: " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeResidenceFrameSlot:native_fast_value_location(_binding)
        return Native.NativeValueFrameSlotLocation(self.slot)
    end

    function Native.NativeResidenceImmediate:native_fast_value_location(_binding)
        return Native.NativeValuePatchCoordinateLocation(self.coordinate)
    end

    function Native.NativeResidenceConstantPool:native_fast_value_location(binding)
        return Native.NativeValueConstantPoolLocation(self.entry, scalar_value_representation(binding.scalar))
    end

    function Native.NativeResidenceRuntimeSymbol:native_fast_value_location(_binding)
        return Native.NativeValuePatchCoordinateLocation(Native.NativePatchCallTarget(self.symbol))
    end

    function Native.NativeRegionBoundaryResidence:native_fast_patch_coordinate(_binding)
        error("lalin.native_mc: fast-region residence cannot be projected to a patch coordinate: " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeResidenceFrameSlot:native_fast_patch_coordinate(_binding)
        return Native.NativePatchFrameOffset(self.slot.offset)
    end

    function Native.NativeResidenceImmediate:native_fast_patch_coordinate(_binding)
        return self.coordinate
    end

    function Native.NativeResidenceRuntimeSymbol:native_fast_patch_coordinate(_binding)
        return Native.NativePatchCallTarget(self.symbol)
    end

    function Native.NativeResidenceDiscard:native_fast_patch_coordinate(_binding)
        return nil
    end

    function Native.NativeRegionValueBinding:native_fast_value_placement()
        return Native.NativeValuePlacement(self.value, scalar_value_representation(self.scalar), self.residence:native_fast_value_location(self))
    end

    local function append_fast_region_binding(out, node_id, instance, ordinal, binding)
        local coordinate = binding.residence:native_fast_patch_coordinate(binding)
        if coordinate == nil then return ordinal end
        out[#out + 1] = Native.NativePatchBinding(node_id, instance, Native.NativePatchBindingHoleOrdinalIndex(ordinal), coordinate)
        return ordinal + 1
    end

    local function append_fast_region_bindings(node_id, instance, inputs, outputs)
        local out = {}
        local ordinal = 0
        for _, binding in ipairs(inputs or {}) do ordinal = append_fast_region_binding(out, node_id, instance, ordinal, binding) end
        for _, binding in ipairs(outputs or {}) do ordinal = append_fast_region_binding(out, node_id, instance, ordinal, binding) end
        return out
    end

    local function fast_code_expr_family(input, shape)
        local token = shape:native_fast_expr_token()
        return Native.NativeTemplateFamily(
            Native.NativeTemplateFamilyId("native.fast.code.expr." .. token),
            Native.NativeRoleCodeTerm,
            {
                Support.axis_target(input.target),
                Support.axis_machine_scalar(shape:native_fast_expr_result_scalar()),
                Support.axis_fast_code_expr(shape),
            },
            Support.protocol_void_none()
        )
    end

    function Native.NativeFastRegionBody:native_fast_template_family(_input)
        error("lalin.native_mc: fast-region body cannot be lowered to a template family: " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeFrameMicroOpRegion:native_fast_template_family(_input)
        return self.family
    end

    function Native.NativeCodeExprRegion:native_fast_template_family(input)
        return fast_code_expr_family(input, self.shape)
    end

    function Native.NativeCodeCompareBranchRegion:native_fast_template_family(_input)
        error("lalin.native_mc: NativeCodeCompareBranchRegion graph lowering requires generated compare-branch template family ASDL axes/sources", 3)
    end

    function Native.NativeFastRegion:native_template_node(input)
        local node_id = fast_region_node_id(self.id)
        local instance = fast_region_instance_id(node_id)
        local inputs = {}
        local outputs = {}
        for _, binding in ipairs(self.inputs or {}) do inputs[#inputs + 1] = binding:native_fast_value_placement() end
        for _, binding in ipairs(self.outputs or {}) do outputs[#outputs + 1] = binding:native_fast_value_placement() end
        return Native.NativeTemplateNode(
            node_id,
            instance,
            self.body:native_fast_template_family(input),
            inputs,
            outputs,
            append_fast_region_bindings(node_id, instance, self.inputs, self.outputs)
        )
    end

    function Native.NativeRegionTransfer:append_native_fast_control_edges(_edges, _from)
        error("lalin.native_mc: fast-region transfer cannot be lowered to graph control edges: " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeRegionFallthrough:append_native_fast_control_edges(edges, from)
        edges[#edges + 1] = Native.NativeFallthroughEdge(from, fast_region_node_id(self.to), Support.next_continuation_symbol())
    end

    function Native.NativeRegionJump:append_native_fast_control_edges(edges, from)
        edges[#edges + 1] = Native.NativeContinuationEdge(from, fast_region_node_id(self.to), Support.next_continuation_symbol())
    end

    function Native.NativeRegionBranch:append_native_fast_control_edges(edges, from)
        edges[#edges + 1] = Native.NativeConditionalBranchEdge(from, fast_region_node_id(self.then_to), Support.then_continuation_symbol(), fast_region_node_id(self.else_to), Support.else_continuation_symbol(), self.condition)
    end

    function Native.NativeRegionSwitch:append_native_fast_control_edges(_edges, _from)
        error("lalin.native_mc: NativeRegionSwitch graph lowering requires a typed NativeSwitchEdge graph/install edge", 3)
    end

    function Native.NativeRegionCallReturn:append_native_fast_control_edges(edges, from)
        edges[#edges + 1] = Native.NativeRuntimeCallReturnEdge(from, fast_region_node_id(self.return_to), self.call_symbol, Support.next_continuation_symbol())
    end

    function Native.NativeRegionReturn:append_native_fast_control_edges(_edges, _from)
    end

    function Native.NativeRegionTrap:append_native_fast_control_edges(_edges, _from)
    end

    function Native.NativeFastRegionPlan:lower_native_template_graph(addresses)
        local nodes = {}
        local edges = {}
        for _, region in ipairs(self.regions or {}) do
            local node = region:native_template_node(self)
            nodes[#nodes + 1] = node
            region.transfer:append_native_fast_control_edges(edges, node.id)
        end
        local exits = {}
        for _, exit in ipairs(self.exits or {}) do exits[#exits + 1] = fast_region_node_id(exit) end
        return Native.NativeTemplateGraph(
            self.target,
            self.public_protocol,
            self.frame_layout,
            nodes,
            edges,
            {},
            addresses or Native.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
            fast_region_node_id(self.entry),
            exits
        )
    end

    function Native.NativeControlEdge:native_bank_install_control_edge()
        error("lalin.native_mc: missing bank install edge projection for " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeFallthroughEdge:native_bank_install_control_edge()
        return Native.NativeBankFallthroughEdge(self.from, self.to, self.symbol)
    end

    function Native.NativeConditionalBranchEdge:native_bank_install_control_edge()
        return Native.NativeBankConditionalBranchEdge(self.from, self.then_to, self.then_symbol, self.else_to, self.else_symbol)
    end

    function Native.NativeLoopBackedgeEdge:native_bank_install_control_edge()
        return Native.NativeBankLoopBackedgeEdge(self.from, self.to, self.symbol)
    end

    function Native.NativeExitEdge:native_bank_install_control_edge()
        return Native.NativeBankExitEdge(self.from, self.symbol)
    end

    function Native.NativeContinuationEdge:native_bank_install_control_edge()
        return Native.NativeBankContinuationEdge(self.from, self.to, self.symbol)
    end

    function Native.NativeRuntimeCallReturnEdge:native_bank_install_control_edge()
        return Native.NativeBankRuntimeCallReturnEdge(self.from, self.to, self.runtime_symbol, self.return_symbol)
    end

    function Native.NativeTemplateGraph:select_native_bank_install_plan(input)
        if self.target ~= input.target then
            error("lalin.native_mc: NativeTemplateGraph target does not match bank install plan selection target", 3)
        end
        local nodes = {}
        local patch_input = Native.NativeBankPatchProjectionInput(input.target, input.runtime, self.addresses)
        for _, node in ipairs(self.nodes or {}) do
            local key = Native.NativeTemplateSelectorKey(input.target, node.family)
            local bindings = {}
            for _, binding in ipairs(node.bindings or {}) do
                bindings[#bindings + 1] = Native.NativeBankInstallBinding(
                    binding.node,
                    binding.instance,
                    binding.target,
                    binding.coordinate:native_bank_patch_coordinate(patch_input)
                )
            end
            nodes[#nodes + 1] = Native.NativeBankInstallNode(node.id, node.instance, key, bindings)
        end
        local edges = {}
        for _, edge in ipairs(self.control_edges or {}) do
            edges[#edges + 1] = edge:native_bank_install_control_edge()
        end
        local runtime_symbols = {}
        append_runtime_symbols(runtime_symbols, input.runtime)
        local module_addresses = {}
        append_module_addresses(module_addresses, self.addresses)
        return Native.NativeBankInstallPlan(
            input.target,
            self.protocol,
            self.frame_layout,
            nodes,
            edges,
            runtime_symbols,
            module_addresses,
            self.entry,
            self.exits
        )
    end

    function Native.NativeBankInstallControlEdge:native_c_control_edge(_row, _keepalive)
        error("lalin.native_mc: missing C control-edge projection for " .. tostring(asdl.class_basename(self)), 3)
    end

    function Native.NativeBankFallthroughEdge:native_c_control_edge(row, keepalive)
        row.kind = 1
        row.from_node_id = cstr(keepalive, self.from.text)
        row.to_node_id = cstr(keepalive, self.to.text)
        row.symbol = cstr(keepalive, symbol_name(self.symbol))
    end

    function Native.NativeBankConditionalBranchEdge:native_c_control_edge(row, keepalive)
        row.kind = 2
        row.from_node_id = cstr(keepalive, self.from.text)
        row.then_node_id = cstr(keepalive, self.then_to.text)
        row.then_symbol = cstr(keepalive, symbol_name(self.then_symbol))
        row.else_node_id = cstr(keepalive, self.else_to.text)
        row.else_symbol = cstr(keepalive, symbol_name(self.else_symbol))
    end

    function Native.NativeBankLoopBackedgeEdge:native_c_control_edge(row, keepalive)
        row.kind = 3
        row.from_node_id = cstr(keepalive, self.from.text)
        row.to_node_id = cstr(keepalive, self.to.text)
        row.symbol = cstr(keepalive, symbol_name(self.symbol))
    end

    function Native.NativeBankExitEdge:native_c_control_edge(row, keepalive)
        row.kind = 4
        row.from_node_id = cstr(keepalive, self.from.text)
        row.symbol = cstr(keepalive, symbol_name(self.symbol))
    end

    function Native.NativeBankContinuationEdge:native_c_control_edge(row, keepalive)
        row.kind = 5
        row.from_node_id = cstr(keepalive, self.from.text)
        row.to_node_id = cstr(keepalive, self.to.text)
        row.symbol = cstr(keepalive, symbol_name(self.symbol))
    end

    function Native.NativeBankRuntimeCallReturnEdge:native_c_control_edge(row, keepalive)
        row.kind = 6
        row.from_node_id = cstr(keepalive, self.from.text)
        row.to_node_id = cstr(keepalive, self.to.text)
        row.runtime_symbol_id = cstr(keepalive, self.runtime_symbol.text)
        row.return_symbol = cstr(keepalive, symbol_name(self.return_symbol))
    end

    local function c_array(ctype, values, fill)
        local f = declare_ffi()
        if #(values or {}) == 0 then return nil, 0, {} end
        local keepalive = {}
        local arr = f.new(ctype .. "[?]", #values)
        keepalive[#keepalive + 1] = arr
        for i, value in ipairs(values) do fill(arr[i - 1], value, keepalive) end
        return arr, #values, keepalive
    end

    local function c_bindings(bindings)
        return c_array("LalinNativeInstallBinding", bindings, function(row, binding, keepalive)
            row.node_id = cstr(keepalive, binding.node.text)
            row.instance_id = cstr(keepalive, binding.instance.text)
            binding.target:native_c_binding_target(row, keepalive)
            binding.coordinate:native_c_patch_coordinate(row.coordinate, keepalive)
        end)
    end

    local function c_nodes(nodes, outer_keepalive)
        return c_array("LalinNativeInstallNode", nodes, function(row, node, keepalive)
            row.node_id = cstr(keepalive, node.id.text)
            row.instance_id = cstr(keepalive, node.instance.text)
            row.key_target_id = cstr(keepalive, target_id(node.key.target))
            row.family_id = cstr(keepalive, family_id(node.key.family))
            local bindings, binding_count, binding_keepalive = c_bindings(node.bindings)
            row.bindings = bindings
            row.binding_count = binding_count
            outer_keepalive[#outer_keepalive + 1] = binding_keepalive
        end)
    end

    local function c_edges(edges)
        return c_array("LalinNativeInstallControlEdge", edges, function(row, edge, keepalive)
            edge:native_c_control_edge(row, keepalive)
        end)
    end

    local function c_runtime_symbols(symbols)
        return c_array("LalinNativeRuntimeSymbolAddress", symbols, function(row, symbol, keepalive)
            row.symbol_id = cstr(keepalive, symbol.symbol.text)
            row.address = symbol.address
        end)
    end

    local function c_module_addresses(addresses)
        return c_array("LalinNativeModuleAddress", addresses, function(row, address, keepalive)
            local kind, id, value = address:native_c_module_address_kind()
            row.kind = kind
            row.id = cstr(keepalive, id)
            row.address = value
        end)
    end

    local function c_reject_to_native(reject, status)
        local reason = reject ~= nil and reject.reason ~= nil and ffi.string(reject.reason) or "native bank install rejected"
        local node = reject ~= nil and reject.node_id ~= nil and Native.NativeTemplateNodeId(ffi.string(reject.node_id)) or nil
        local hole = reject ~= nil and reject.hole_id ~= nil and Native.NativePatchHoleId(ffi.string(reject.hole_id)) or nil
        if status == 2 then return Native.NativeInstallRejectAllocation(reason) end
        local to_node = reject ~= nil and reject.to_node_id ~= nil and Native.NativeTemplateNodeId(ffi.string(reject.to_node_id)) or nil
        if tonumber(reject ~= nil and reject.kind or 0) == 1 and node ~= nil and to_node ~= nil then
            return Native.NativeInstallRejectFallthroughLayout(node, to_node, reason)
        end
        if hole ~= nil and reason == "missing binding" then return Native.NativeInstallRejectMissingBinding(hole) end
        if hole ~= nil and reason == "duplicate binding" then return Native.NativeInstallRejectDuplicateBinding(hole) end
        return Native.NativeInstallRejectBankRejected(node, hole, reason)
    end

    local function install_rejects(c_result)
        local rejects = {}
        local count = tonumber(c_result.reject_count)
        for i = 0, count - 1 do
            rejects[#rejects + 1] = c_reject_to_native(c_result.rejects[i], tonumber(c_result.status))
        end
        if #rejects == 0 then rejects[1] = c_reject_to_native(nil, tonumber(c_result.status)) end
        return rejects
    end

    function Native.NativeExecutableAllocatorMmap:native_c_allocator()
        local f = declare_ffi()
        local callback = f.cast("LalinNativeExecutableAllocFn", function(size, _alignment, _userdata)
            if tonumber(size) <= 0 then return nil end
            local ptr = f.C.mmap(nil, size, PROT_READ + PROT_WRITE + PROT_EXEC, MAP_PRIVATE + map_anon_flag(), -1, 0)
            if ptr == mmap_failed_pointer() then return nil end
            return ptr
        end)
        return callback, nil
    end

    function Native.NativeExecutableAllocatorVirtualAlloc:native_c_allocator()
        error("lalin.native_mc: NativeExecutableAllocatorVirtualAlloc is not modeled for this C-owned bank installer", 3)
    end

    function Native.NativeBankInstallRequest:install_native()
        local f = declare_ffi()
        local c_bank = bank_pointer(self.bank)
        if c_bank == nil then return Native.NativeInstallRejected({ Native.NativeInstallRejectAllocation("native bank handle is not loaded") }) end

        local keepalive = {}
        local nodes, node_count, node_keepalive = c_nodes(self.plan.nodes or {}, keepalive)
        local edges, edge_count, edge_keepalive = c_edges(self.plan.control_edges or {})
        local runtime_symbols, runtime_symbol_count, runtime_keepalive = c_runtime_symbols(self.plan.runtime_symbols or {})
        local module_addresses, module_address_count, module_keepalive = c_module_addresses(self.plan.module_addresses or {})
        keepalive[#keepalive + 1] = node_keepalive
        keepalive[#keepalive + 1] = edge_keepalive
        keepalive[#keepalive + 1] = runtime_keepalive
        keepalive[#keepalive + 1] = module_keepalive

        local allocator_cb, allocator_userdata = self.allocator:native_c_allocator()
        keepalive[#keepalive + 1] = allocator_cb

        local request = f.new("LalinNativeInstallRequest")
        keepalive[#keepalive + 1] = request
        request.target_id = cstr(keepalive, target_id(self.plan.target))
        request.nodes = nodes
        request.node_count = node_count
        request.control_edges = edges
        request.control_edge_count = edge_count
        request.runtime_symbols = runtime_symbols
        request.runtime_symbol_count = runtime_symbol_count
        request.module_addresses = module_addresses
        request.module_address_count = module_address_count
        request.entry_node_id = cstr(keepalive, self.plan.entry.text)
        request.allocate_executable = allocator_cb
        request.allocator_userdata = allocator_userdata

        local result = bank_library(self.bank).lalin_native_bank_install(c_bank, request)
        if tonumber(result.status) ~= 0 then return Native.NativeInstallRejected(install_rejects(result)) end
        return Native.NativeInstallSucceeded(Native.NativeExecutable(
            executable_id_for_plan(self.plan),
            self.plan.target,
            tonumber(f.cast("uintptr_t", result.base_address)),
            tonumber(f.cast("uintptr_t", result.entry_address)),
            tonumber(result.size),
            self.plan.protocol
        ))
    end

    T._lalin_api_cache.native_mc = api
    return api
end

return bind_context
