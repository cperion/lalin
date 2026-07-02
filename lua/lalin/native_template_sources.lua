local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_template_sources ~= nil then return T._lalin_api_cache.native_template_sources end

    local Native = T.LalinNative
    local Code = T.LalinCode
    local Core = T.LalinCore
    local Support = require("lalin.native_template_support")(T)
    local api = {}

    local FRAME_PARAM0_OFFSET = 0
    local FRAME_PARAM1_OFFSET = 16
    local FRAME_RESULT_OFFSET = 32
    local FRAME_BYTES = 256

    local MARK_LHS = "0x11111111u"
    local MARK_RHS = "0x22222222u"
    local MARK_DST = "0x33333333u"
    local MARK_SRC = "0x44444444u"
    local MARK_IMM32 = "0x55555555u"
    local MARK_IMM64 = "0x1122334455667788ULL"

    local function internal_error(message)
        error("lalin.native_template_sources: " .. message, 3)
    end

    local function require_value(value, name)
        if value == nil then internal_error("missing " .. name) end
        return value
    end

    local function source_id(text)
        return Native.NativeTemplateId("native.source." .. require_value(text, "source id text"))
    end

    local function symbol_fragment(text)
        return tostring(text):gsub("[^%w_]", "_")
    end

    local function concat_lines(lines)
        lines[#lines + 1] = ""
        return table.concat(lines, "\n")
    end

    local function c_prelude()
        return {
            "#include <stdint.h>",
            "#include <stddef.h>",
        }
    end

    function api.template_source_id(text)
        return source_id(text)
    end

    function api.c_source(id_text, family, extraction, entry_symbol, c_text, holes)
        return Native.NativeTemplateSource(
            source_id(id_text),
            require_value(family, "NativeTemplateFamily"),
            require_value(extraction, "NativeTemplateExtraction"),
            require_value(entry_symbol, "entry symbol"),
            require_value(c_text, "C source text"),
            holes or {}
        )
    end

    function api.append_source(out, source)
        require_value(out, "source output list")
        if not asdl.isa(source, Native.NativeTemplateSource) then
            internal_error("source builder produced non-NativeTemplateSource value")
        end
        out[#out + 1] = source
        return source
    end

    function api.assert_unique_source_ids(sources)
        local seen = {}
        for _, source in ipairs(sources or {}) do
            local key = source.id.text
            if seen[key] ~= nil then internal_error("duplicate NativeTemplateSource id: " .. tostring(key)) end
            seen[key] = true
        end
        return true
    end

    function api.assert_unique_family_ids(sources)
        local seen = {}
        for _, source in ipairs(sources or {}) do
            local key = source.family.id.text
            if seen[key] ~= nil then internal_error("duplicate NativeTemplateFamily id in source set: " .. tostring(key)) end
            seen[key] = true
        end
        return true
    end

    function api.bank_request_from_sources(bank_id, target, runtime, sources)
        api.assert_unique_source_ids(sources or {})
        api.assert_unique_family_ids(sources or {})
        return Native.NativeTemplateBankRequest(
            require_value(bank_id, "NativeBankId"),
            require_value(target, "NativeTarget"),
            require_value(runtime, "NativeRuntime"),
            sources or {}
        )
    end

    local function require_x64_sysv_target(target)
        target = require_value(target, "NativeTarget")
        if not asdl.isa(target.arch, Native.NativeArchX64)
            or not asdl.isa(target.abi, Native.NativeAbiSysV)
            or not asdl.isa(target.endian, Native.NativeLittleEndian)
            or target.pointer_bits ~= 64 then
            internal_error("native scalar template sources are currently authored for x64/sysv/little-endian/64-bit support")
        end
        return target
    end

    local function int_wrap_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
    end

    local function float_mode()
        return Code.CodeFloatStrict
    end

    local function c_int_type(bits, signedness)
        local prefix = signedness == Code.CodeSigned and "int" or "uint"
        return prefix .. tostring(bits) .. "_t"
    end

    local function c_uint_type(bits)
        return "uint" .. tostring(bits) .. "_t"
    end

    function Code.CodeTyBool8:native_c_scalar_type()
        return "uint8_t"
    end

    function Code.CodeTyInt:native_c_scalar_type()
        return c_int_type(self.bits, self.signedness)
    end

    function Code.CodeTyIndex:native_c_scalar_type()
        return "intptr_t"
    end

    function Code.CodeTyDataPtr:native_c_scalar_type()
        return "uintptr_t"
    end

    function Code.CodeTyFloat:native_c_scalar_type()
        if self.bits == 32 then return "float" end
        return "double"
    end

    function Native.NativeScalarBool8:native_c_scalar_type()
        return "uint8_t"
    end

    function Native.NativeScalarInt:native_c_scalar_type()
        return c_int_type(self.bits, self.signedness)
    end

    function Native.NativeScalarIndex:native_c_scalar_type()
        return "intptr_t"
    end

    function Native.NativeScalarPointer:native_c_scalar_type()
        return "uintptr_t"
    end

    function Native.NativeScalarFloat:native_c_scalar_type()
        if self.bits == 32 then return "float" end
        return "double"
    end

    function Native.NativeScalarBool8:native_c_unsigned_type()
        return "uint8_t"
    end

    function Native.NativeScalarInt:native_c_unsigned_type()
        return c_uint_type(self.bits)
    end

    function Native.NativeScalarIndex:native_c_unsigned_type()
        return "uintptr_t"
    end

    function Native.NativeScalarPointer:native_c_unsigned_type()
        return "uintptr_t"
    end

    function Native.NativeScalarFloat:native_c_unsigned_type()
        return nil
    end

    function Native.NativeScalarBool8:native_size_bytes() return 1 end
    function Native.NativeScalarInt:native_size_bytes() return self.bits / 8 end
    function Native.NativeScalarIndex:native_size_bytes() return self.bits / 8 end
    function Native.NativeScalarPointer:native_size_bytes() return self.bits / 8 end
    function Native.NativeScalarFloat:native_size_bytes() return self.bits / 8 end

    function Native.NativeMachineScalarRep:native_frame_alignment()
        local size = self:native_size_bytes()
        if size > 8 then return 8 end
        if size < 1 then return 1 end
        return size
    end

    local function frame_offset_hole(id, marker)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            marker,
            -1,
            4,
            Native.NativePatchFrameOffset32
        )
    end

    local function imm32_hole(id, marker)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            marker,
            -1,
            4,
            Native.NativePatchImm32
        )
    end

    local function imm64_hole(id, marker)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            marker,
            -1,
            8,
            Native.NativePatchImm64
        )
    end

    local function frame_load(c_type, marker)
        return "*(" .. c_type .. " *)(void *)(frame + " .. marker .. ")"
    end

    local function frame_store(c_type, marker, expr)
        return "    *(" .. c_type .. " *)(void *)(frame + " .. marker .. ") = " .. expr .. ";"
    end

    local function continuation_extern(symbol)
        return "extern void " .. symbol.name .. "(uint8_t *frame);"
    end

    function Core.BinAdd:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")((" .. u .. ")(" .. lhs .. ") + (" .. u .. ")(" .. rhs .. "))", "add"
    end

    function Core.BinSub:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")((" .. u .. ")(" .. lhs .. ") - (" .. u .. ")(" .. rhs .. "))", "sub"
    end

    function Core.BinMul:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")((" .. u .. ")(" .. lhs .. ") * (" .. u .. ")(" .. rhs .. "))", "mul"
    end

    function Core.BinBitAnd:native_integer_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " & " .. rhs .. ")", "and" end
    function Core.BinBitOr:native_integer_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " | " .. rhs .. ")", "or" end
    function Core.BinBitXor:native_integer_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " ^ " .. rhs .. ")", "xor" end

    function Core.BinShl:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local mask = tostring(scalar.bits - 1)
        return "(" .. scalar:native_c_scalar_type() .. ")((" .. u .. ")(" .. lhs .. ") << ((" .. u .. ")(" .. rhs .. ") & " .. mask .. "))", "shl"
    end

    function Core.BinLShr:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local mask = tostring(scalar.bits - 1)
        return "(" .. scalar:native_c_scalar_type() .. ")((" .. u .. ")(" .. lhs .. ") >> ((" .. u .. ")(" .. rhs .. ") & " .. mask .. "))", "lshr"
    end

    function Core.BinAShr:native_integer_c_expr(scalar, lhs, rhs)
        local mask = tostring(scalar.bits - 1)
        return "(" .. lhs .. " >> (" .. rhs .. " & " .. mask .. "))", "ashr"
    end

    function Core.BinAdd:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " + " .. rhs .. ")", "add" end
    function Core.BinSub:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " - " .. rhs .. ")", "sub" end
    function Core.BinMul:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " * " .. rhs .. ")", "mul" end
    function Core.BinDiv:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " / " .. rhs .. ")", "div" end

    function Core.UnaryNeg:native_integer_c_expr(scalar, value)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")(-(" .. u .. ")(" .. value .. "))", "neg"
    end

    function Core.UnaryBitNot:native_integer_c_expr(_scalar, value)
        return "(~" .. value .. ")", "bitnot"
    end

    function Core.UnaryNot:native_integer_c_expr(_scalar, value)
        return "(" .. value .. " == 0)", "not"
    end

    function Core.CmpEq:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " == " .. rhs .. ")", "eq" end
    function Core.CmpNe:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " != " .. rhs .. ")", "ne" end
    function Core.CmpLt:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " < " .. rhs .. ")", "lt" end
    function Core.CmpLe:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " <= " .. rhs .. ")", "le" end
    function Core.CmpGt:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " > " .. rhs .. ")", "gt" end
    function Core.CmpGe:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " >= " .. rhs .. ")", "ge" end

    function Core.BinAdd:native_binary_family_name() return "add" end
    function Core.BinSub:native_binary_family_name() return "sub" end
    function Core.BinMul:native_binary_family_name() return "mul" end
    function Core.BinBitAnd:native_binary_family_name() return "and" end
    function Core.BinBitOr:native_binary_family_name() return "or" end
    function Core.BinBitXor:native_binary_family_name() return "xor" end
    function Core.BinShl:native_binary_family_name() return "shl" end
    function Core.BinLShr:native_binary_family_name() return "lshr" end
    function Core.BinAShr:native_binary_family_name() return "ashr" end
    function Core.BinDiv:native_binary_family_name() return "div" end

    function Core.CmpEq:native_compare_family_name() return "eq" end
    function Core.CmpNe:native_compare_family_name() return "ne" end
    function Core.CmpLt:native_compare_family_name() return "lt" end
    function Core.CmpLe:native_compare_family_name() return "le" end
    function Core.CmpGt:native_compare_family_name() return "gt" end
    function Core.CmpGe:native_compare_family_name() return "ge" end

    local function append_entry_source(out, input, param_scalar, result_scalar)
        local param_token = param_scalar:native_scalar_token()
        local result_token = result_scalar:native_scalar_token()
        local family_name = "entry." .. param_token .. ".return." .. result_token
        local family = Support.code_func_frame_family(family_name, input.domain.target, param_scalar, result_scalar)
        local entry = "lalin_native_code_func_" .. symbol_fragment(family_name)
        local param_c = param_scalar:native_c_scalar_type()
        local result_c = result_scalar:native_c_scalar_type()
        local first = Support.first_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(first)
        lines[#lines + 1] = result_c .. " " .. entry .. "(" .. param_c .. " a, " .. param_c .. " b) {"
        lines[#lines + 1] = "    uint8_t frame[" .. tostring(FRAME_BYTES) .. "];"
        lines[#lines + 1] = "    *(" .. param_c .. " *)(void *)(frame + " .. tostring(FRAME_PARAM0_OFFSET) .. ") = a;"
        lines[#lines + 1] = "    *(" .. param_c .. " *)(void *)(frame + " .. tostring(FRAME_PARAM1_OFFSET) .. ") = b;"
        lines[#lines + 1] = "    " .. first.name .. "(frame);"
        lines[#lines + 1] = "    return *(" .. result_c .. " *)(void *)(frame + " .. tostring(FRAME_RESULT_OFFSET) .. ");"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.func." .. family_name,
            family,
            Native.NativeExtractEntryCallable(Native.NativePatchFrameSize(FRAME_BYTES), first),
            entry,
            concat_lines(lines),
            {}
        ))
    end

    local function append_terminal_source(out, input, scalar)
        local token = scalar:native_scalar_token()
        local ty = scalar:native_code_type()
        local axis = Native.NativeCodeTermReturnAxis({ ty })
        local family = Support.code_term_frame_family("return." .. token, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_term_return_" .. symbol_fragment(token)
        local lines = c_prelude()
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    (void)frame;"
        lines[#lines + 1] = "    return;"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.term.return." .. token,
            family,
            Native.NativeExtractTerminalContinuation,
            entry,
            concat_lines(lines),
            {}
        ))
    end

    function Native.NativeCodeInstBinaryAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local lhs = frame_load(c_type, MARK_LHS)
        local rhs = frame_load(c_type, MARK_RHS)
        local expr, name = self.op:native_integer_c_expr(scalar, lhs, rhs)
        local token = scalar:native_scalar_token()
        local family = Support.code_inst_frame_family("binary." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_binary_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " lhs = " .. lhs .. ";"
        lines[#lines + 1] = "    " .. c_type .. " rhs = " .. rhs .. ";"
        lines[#lines + 1] = frame_store(c_type, MARK_DST, expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.inst.binary." .. token .. "." .. name,
            family,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            concat_lines(lines),
            {
                frame_offset_hole("native.hole.code.inst.binary." .. token .. "." .. name .. ".lhs", MARK_LHS),
                frame_offset_hole("native.hole.code.inst.binary." .. token .. "." .. name .. ".rhs", MARK_RHS),
                frame_offset_hole("native.hole.code.inst.binary." .. token .. "." .. name .. ".dst", MARK_DST),
            }
        ))
    end

    function Native.NativeCodeInstFloatBinaryAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local lhs = frame_load(c_type, MARK_LHS)
        local rhs = frame_load(c_type, MARK_RHS)
        local expr, name = self.op:native_float_c_expr(scalar, lhs, rhs)
        local token = scalar:native_scalar_token()
        local family = Support.code_inst_frame_family("float_binary." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_float_binary_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " lhs = " .. lhs .. ";"
        lines[#lines + 1] = "    " .. c_type .. " rhs = " .. rhs .. ";"
        lines[#lines + 1] = frame_store(c_type, MARK_DST, expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.inst.float_binary." .. token .. "." .. name,
            family,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            concat_lines(lines),
            {
                frame_offset_hole("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".lhs", MARK_LHS),
                frame_offset_hole("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".rhs", MARK_RHS),
                frame_offset_hole("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".dst", MARK_DST),
            }
        ))
    end

    function Native.NativeCodeInstUnaryAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local src = frame_load(c_type, MARK_SRC)
        local expr, name = self.op:native_integer_c_expr(scalar, src)
        local result_type = name == "not" and "uint8_t" or c_type
        local result_scalar = name == "not" and Support.scalar_bool8() or scalar
        local token = scalar:native_scalar_token()
        local family = Support.code_inst_frame_family("unary." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_unary_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " src = " .. src .. ";"
        lines[#lines + 1] = frame_store(result_type, MARK_DST, expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.inst.unary." .. token .. "." .. name,
            family,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            concat_lines(lines),
            {
                frame_offset_hole("native.hole.code.inst.unary." .. token .. "." .. name .. ".src", MARK_SRC),
                frame_offset_hole("native.hole.code.inst.unary." .. token .. "." .. name .. ".dst", MARK_DST),
            }
        ))
        return result_scalar
    end

    function Native.NativeCodeInstCompareAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local lhs = frame_load(c_type, MARK_LHS)
        local rhs = frame_load(c_type, MARK_RHS)
        local expr, name = self.cmp:native_c_compare_expr(scalar, lhs, rhs)
        local token = scalar:native_scalar_token()
        local family = Support.code_inst_frame_family("compare." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_compare_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " lhs = " .. lhs .. ";"
        lines[#lines + 1] = "    " .. c_type .. " rhs = " .. rhs .. ";"
        lines[#lines + 1] = frame_store("uint8_t", MARK_DST, expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.inst.compare." .. token .. "." .. name,
            family,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            concat_lines(lines),
            {
                frame_offset_hole("native.hole.code.inst.compare." .. token .. "." .. name .. ".lhs", MARK_LHS),
                frame_offset_hole("native.hole.code.inst.compare." .. token .. "." .. name .. ".rhs", MARK_RHS),
                frame_offset_hole("native.hole.code.inst.compare." .. token .. "." .. name .. ".dst", MARK_DST),
            }
        ))
    end

    function Native.NativeCodeInstAliasAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local token = scalar:native_scalar_token()
        local family = Support.code_inst_frame_family("alias." .. token, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_alias_" .. symbol_fragment(token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " src = " .. frame_load(c_type, MARK_SRC) .. ";"
        lines[#lines + 1] = frame_store(c_type, MARK_DST, "src")
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.inst.alias." .. token,
            family,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            concat_lines(lines),
            {
                frame_offset_hole("native.hole.code.inst.alias." .. token .. ".src", MARK_SRC),
                frame_offset_hole("native.hole.code.inst.alias." .. token .. ".dst", MARK_DST),
            }
        ))
    end

    function Core.LitInt:native_patch_coordinate_for_scalar(scalar)
        local value = tonumber(self.raw)
        if scalar.bits and scalar.bits > 32 then return Native.NativePatchImmediateI64(value) end
        return Native.NativePatchImmediateI32(value)
    end

    function Core.LitBool:native_patch_coordinate_for_scalar(_scalar)
        return Native.NativePatchImmediateI32(self.value and 1 or 0)
    end

    function Native.NativeCodeConstLiteralAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local token = scalar:native_scalar_token()
        local c_type = scalar:native_c_scalar_type()
        local family = Support.code_const_frame_family("literal." .. token, input.domain.target, scalar, self)
        local entry = "lalin_native_code_const_literal_" .. symbol_fragment(token)
        local next_symbol = Support.next_continuation_symbol()
        local marker = (scalar.bits and scalar.bits > 32) and MARK_IMM64 or MARK_IMM32
        local hole = (scalar.bits and scalar.bits > 32)
            and imm64_hole("native.hole.code.const.literal." .. token .. ".imm64", marker)
            or imm32_hole("native.hole.code.const.literal." .. token .. ".imm32", marker)
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = frame_store(c_type, MARK_DST, "(" .. c_type .. ")" .. marker)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source(
            "code.const.literal." .. token,
            family,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            concat_lines(lines),
            {
                frame_offset_hole("native.hole.code.const.literal." .. token .. ".dst", MARK_DST),
                hole,
            }
        ))
    end

    local function append_integer_sources(out, input)
        local scalar = input.support.scalar
        local ty = input.support.code_type
        append_entry_source(out, input, scalar, scalar)
        append_entry_source(out, input, scalar, Support.scalar_bool8())
        for _, op in ipairs({
            Core.BinAdd, Core.BinSub, Core.BinMul,
            Core.BinBitAnd, Core.BinBitOr, Core.BinBitXor,
            Core.BinShl, Core.BinLShr, Core.BinAShr,
        }) do
            Native.NativeCodeInstBinaryAxis(op, ty, int_wrap_semantics()):append_native_template_sources(out, input)
        end
        for _, op in ipairs({ Core.UnaryNeg, Core.UnaryBitNot }) do
            Native.NativeCodeInstUnaryAxis(op, ty):append_native_template_sources(out, input)
        end
        for _, cmp in ipairs({ Core.CmpEq, Core.CmpNe, Core.CmpLt, Core.CmpLe, Core.CmpGt, Core.CmpGe }) do
            Native.NativeCodeInstCompareAxis(cmp, ty):append_native_template_sources(out, input)
        end
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        if not scalar.bits or scalar.bits >= 32 then
            Native.NativeCodeConstLiteralAxis(ty):append_native_template_sources(out, input)
        end
        append_terminal_source(out, input, scalar)
    end

    function Native.NativeScalarBool8:append_native_template_sources(out, input)
        local ty = input.support.code_type
        append_entry_source(out, input, self, self)
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        Native.NativeCodeInstUnaryAxis(Core.UnaryNot, ty):append_native_template_sources(out, input)
        Native.NativeCodeInstCompareAxis(Core.CmpEq, ty):append_native_template_sources(out, input)
        Native.NativeCodeInstCompareAxis(Core.CmpNe, ty):append_native_template_sources(out, input)
        append_terminal_source(out, input, self)
    end

    function Native.NativeScalarInt:append_native_template_sources(out, input)
        append_integer_sources(out, input)
    end

    function Native.NativeScalarIndex:append_native_template_sources(out, input)
        append_integer_sources(out, input)
    end

    function Native.NativeScalarPointer:append_native_template_sources(out, input)
        local ty = input.support.code_type
        append_entry_source(out, input, self, self)
        append_entry_source(out, input, self, Support.scalar_bool8())
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        Native.NativeCodeConstLiteralAxis(ty):append_native_template_sources(out, input)
        append_terminal_source(out, input, self)
        Native.NativeCodeInstCompareAxis(Core.CmpEq, ty):append_native_template_sources(out, input)
        Native.NativeCodeInstCompareAxis(Core.CmpNe, ty):append_native_template_sources(out, input)
    end

    function Native.NativeScalarFloat:append_native_template_sources(out, input)
        local ty = input.support.code_type
        local scalar = input.support.scalar
        append_entry_source(out, input, scalar, scalar)
        for _, op in ipairs({ Core.BinAdd, Core.BinSub, Core.BinMul, Core.BinDiv }) do
            Native.NativeCodeInstFloatBinaryAxis(op, ty, float_mode()):append_native_template_sources(out, input)
        end
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        append_terminal_source(out, input, scalar)
    end

    function Native.NativeTemplateSupportDomain:native_template_sources()
        require_x64_sysv_target(self.target)
        local input = Native.NativeTemplateSourceBuildInput(self)
        local out = {}
        for _, scalar_support in ipairs(self.scalars) do
            scalar_support:append_native_template_sources(out, input)
        end
        return out
    end

    function Native.NativeTemplateSupportDomain:native_template_bank_request(bank_id)
        local sources = self:native_template_sources()
        return api.bank_request_from_sources(
            bank_id or Support.bank_id_for_support_domain(self),
            self.target,
            self.runtime,
            sources
        )
    end

    function Native.NativeScalarSupport:append_native_template_sources(out, input)
        return self.scalar:append_native_template_sources(
            out,
            Native.NativeScalarTemplateSourceBuildInput(input.domain, self)
        )
    end

    function api.bank_request_for_support_domain(domain, bank_id)
        return domain:native_template_bank_request(bank_id)
    end

    function api.host_scalar_bank_request()
        local domain = Support.host_scalar_support_domain()
        return api.bank_request_for_support_domain(domain, Support.bank_id_for_support_domain(domain))
    end

    function api.host_scalar_i32_bank_request()
        return api.bank_request_for_support_domain(
            Support.host_scalar_i32_support_domain(),
            Support.host_scalar_i32_bank_id()
        )
    end

    function api.append_host_scalar_i32_sources(out, target, runtime)
        local domain = Native.NativeTemplateSupportDomain(
            Native.NativeTemplateSupportDomainId("native.template.support.explicit-scalar-i32"),
            require_x64_sysv_target(target),
            require_value(runtime, "NativeRuntime"),
            { Support.scalar_support(Support.scalar_i32()) },
            Support.register_support(target, Support.scalar_i32()),
            { Support.abi_scalar_convention(target, Support.scalar_i32()) },
            { Support.native_call_return_scalar(Support.scalar_i32()) },
            { Support.register_none() },
            { Native.NativeScratchGeneral },
            { Native.NativeAccumulatorGeneral },
            { 1 },
            { 1 },
            { 1 }
        )
        for _, source in ipairs(domain:native_template_sources()) do
            api.append_source(out, source)
        end
    end

    function api.append_RuntimeCallReturnI32_sources(out, target, runtime)
        api.append_host_scalar_i32_sources(out, target, runtime)
    end

    T._lalin_api_cache.native_template_sources = api
    return api
end

return bind_context
