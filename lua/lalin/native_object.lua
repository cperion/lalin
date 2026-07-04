local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_object ~= nil then return T._lalin_api_cache.native_object end

    local Native = T.LalinNative
    local api = {}

    local U32 = 4294967296

    local function reject_malformed(source, reason)
        return Native.NativeBuildRejectMalformedObject(source, reason)
    end

    local function reject_format(source, format, reason)
        return Native.NativeBuildRejectUnsupportedObjectFormat(source, format, reason)
    end

    local function byte_at(bytes, offset0)
        return bytes:byte(offset0 + 1) or 0
    end

    local function have(bytes, offset0, size)
        return offset0 >= 0 and size >= 0 and offset0 + size <= #bytes
    end

    local function u16le(bytes, offset0)
        return byte_at(bytes, offset0) + byte_at(bytes, offset0 + 1) * 256
    end

    local function u32le(bytes, offset0)
        return byte_at(bytes, offset0)
            + byte_at(bytes, offset0 + 1) * 256
            + byte_at(bytes, offset0 + 2) * 65536
            + byte_at(bytes, offset0 + 3) * 16777216
    end

    local function u64le(bytes, offset0)
        local lo = u32le(bytes, offset0)
        local hi = u32le(bytes, offset0 + 4)
        return hi * U32 + lo
    end

    local function s32le(bytes, offset0)
        local value = u32le(bytes, offset0)
        if value >= 2147483648 then return value - U32 end
        return value
    end

    local function s64le(bytes, offset0)
        local lo = u32le(bytes, offset0)
        local hi = u32le(bytes, offset0 + 4)
        if hi >= 2147483648 then hi = hi - U32 end
        return hi * U32 + lo
    end

    local function string_at(strtab, offset0)
        if offset0 == 0 then return "" end
        if offset0 < 0 or offset0 >= #strtab then return nil end
        local start = offset0 + 1
        local stop = strtab:find("\0", start, true)
        if stop == nil then return nil end
        return strtab:sub(start, stop - 1)
    end

    local function section_id(source, index, name)
        local suffix = tostring(name or "")
        if suffix == "" then suffix = "section" end
        suffix = suffix:gsub("[^%w_%.%-]", "_")
        return Native.NativeObjectSectionId(source.text .. ".object.section." .. tostring(index) .. "." .. suffix)
    end

    local function symbol_id(source, index, name)
        local suffix = tostring(name or "")
        if suffix == "" then suffix = "symbol" end
        suffix = suffix:gsub("[^%w_%.%-]", "_")
        return Native.NativeObjectSymbolId(source.text .. ".object.symbol." .. tostring(index) .. "." .. suffix)
    end

    local function relocation_id(source, section_index, index)
        return Native.NativeObjectRelocationId(source.text .. ".object.relocation." .. tostring(section_index) .. "." .. tostring(index))
    end

    local function section_flags(sh_type, flags)
        local out = {}
        if flags % 2 >= 1 then out[#out + 1] = Native.NativeObjectSectionWritable end
        if math.floor(flags / 2) % 2 >= 1 then out[#out + 1] = Native.NativeObjectSectionAlloc end
        if math.floor(flags / 4) % 2 >= 1 then out[#out + 1] = Native.NativeObjectSectionExecutable end
        if sh_type == 4 or sh_type == 9 then out[#out + 1] = Native.NativeObjectSectionRelocations end
        return out
    end

    local function symbol_binding(bind, shndx)
        if shndx == 0 then return Native.NativeObjectSymbolExtern end
        if bind == 0 then return Native.NativeObjectSymbolLocal end
        if bind == 1 then return Native.NativeObjectSymbolGlobal end
        if bind == 2 then return Native.NativeObjectSymbolWeak end
        return Native.NativeObjectSymbolGlobal
    end

    local function symbol_kind(kind)
        if kind == 1 then return Native.NativeObjectSymbolObject end
        if kind == 2 then return Native.NativeObjectSymbolFunction end
        if kind == 3 then return Native.NativeObjectSymbolSection end
        if kind == 4 then return Native.NativeObjectSymbolFile end
        return Native.NativeObjectSymbolNoType
    end

    local function relocation_kind(reloc_type)
        if reloc_type == 2 then return Native.NativeObjectRelocX64Pc32, "R_X86_64_PC32" end
        if reloc_type == 4 then return Native.NativeObjectRelocX64Plt32, "R_X86_64_PLT32" end
        if reloc_type == 1 then return Native.NativeObjectRelocX64Abs64, "R_X86_64_64" end
        if reloc_type == 10 then return Native.NativeObjectRelocX64Abs32, "R_X86_64_32" end
        if reloc_type == 11 then return Native.NativeObjectRelocX64Abs32S, "R_X86_64_32S" end
        return nil, "R_X86_64_" .. tostring(reloc_type)
    end

    local function relocation_implicit_addend(bytes, target_raw, r_offset, kind)
        if target_raw == nil then return nil, "REL relocation target section is missing" end
        local offset = target_raw.offset + r_offset
        if asdl.isa(kind, Native.NativeObjectRelocX64Abs64) then
            if not have(bytes, offset, 8) then return nil, "REL64 addend is out of range" end
            return s64le(bytes, offset), nil
        end
        if not have(bytes, offset, 4) then return nil, "REL32 addend is out of range" end
        return s32le(bytes, offset), nil
    end

    function api.parse_elf64_x64_object(source, target, template_bytes)
        local bytes = template_bytes.bytes or ""
        local rejects = {}

        if template_bytes.size ~= #bytes then
            rejects[#rejects + 1] = reject_malformed(source, "NativeTemplateBytes.size does not match byte string length")
            return nil, rejects
        end
        if not have(bytes, 0, 64) then
            rejects[#rejects + 1] = reject_malformed(source, "ELF64 header is truncated")
            return nil, rejects
        end
        if bytes:sub(1, 4) ~= "\127ELF" then
            rejects[#rejects + 1] = reject_format(source, "not-elf", "object bytes do not start with ELF magic")
            return nil, rejects
        end
        if byte_at(bytes, 4) ~= 2 then
            rejects[#rejects + 1] = reject_format(source, "elf", "only ELFCLASS64 objects are supported")
            return nil, rejects
        end
        if byte_at(bytes, 5) ~= 1 then
            rejects[#rejects + 1] = reject_format(source, "elf64", "only little-endian ELF objects are supported")
            return nil, rejects
        end
        if byte_at(bytes, 6) ~= 1 then
            rejects[#rejects + 1] = reject_format(source, "elf64", "unsupported ELF version")
            return nil, rejects
        end

        local e_type = u16le(bytes, 16)
        local e_machine = u16le(bytes, 18)
        local e_version = u32le(bytes, 20)
        local e_shoff = u64le(bytes, 40)
        local e_ehsize = u16le(bytes, 52)
        local e_shentsize = u16le(bytes, 58)
        local e_shnum = u16le(bytes, 60)
        local e_shstrndx = u16le(bytes, 62)

        if e_type ~= 1 then
            rejects[#rejects + 1] = reject_format(source, "elf64", "only ET_REL relocatable objects are supported")
            return nil, rejects
        end
        if e_machine ~= 62 then
            rejects[#rejects + 1] = reject_format(source, "elf64", "only EM_X86_64 objects are supported")
            return nil, rejects
        end
        if e_version ~= 1 or e_ehsize < 64 then
            rejects[#rejects + 1] = reject_malformed(source, "unsupported or malformed ELF64 header version/size")
            return nil, rejects
        end
        if e_shentsize < 64 then
            rejects[#rejects + 1] = reject_malformed(source, "ELF64 section-header entry size is too small")
            return nil, rejects
        end
        if e_shnum == 0 then
            rejects[#rejects + 1] = reject_malformed(source, "extended ELF section counts are not yet supported")
            return nil, rejects
        end
        if e_shstrndx >= e_shnum then
            rejects[#rejects + 1] = reject_malformed(source, "ELF section-name string table index is out of range")
            return nil, rejects
        end
        if not have(bytes, e_shoff, e_shentsize * e_shnum) then
            rejects[#rejects + 1] = reject_malformed(source, "ELF section-header table is truncated")
            return nil, rejects
        end

        local raw_sections = {}
        for index = 0, e_shnum - 1 do
            local off = e_shoff + index * e_shentsize
            raw_sections[index] = {
                index = index,
                name_offset = u32le(bytes, off),
                sh_type = u32le(bytes, off + 4),
                flags = u64le(bytes, off + 8),
                offset = u64le(bytes, off + 24),
                size = u64le(bytes, off + 32),
                link = u32le(bytes, off + 40),
                info = u32le(bytes, off + 44),
                align = u64le(bytes, off + 48),
                entsize = u64le(bytes, off + 56),
            }
        end

        local shstr = raw_sections[e_shstrndx]
        if shstr == nil or not have(bytes, shstr.offset, shstr.size) then
            rejects[#rejects + 1] = reject_malformed(source, "ELF section-name string table is truncated")
            return nil, rejects
        end
        local shstr_bytes = bytes:sub(shstr.offset + 1, shstr.offset + shstr.size)

        local sections = {}
        local section_by_index = {}
        for index = 0, e_shnum - 1 do
            local raw = raw_sections[index]
            local name = string_at(shstr_bytes, raw.name_offset)
            if name == nil then
                rejects[#rejects + 1] = reject_malformed(source, "section " .. tostring(index) .. " has an invalid name offset")
                return nil, rejects
            end
            local section_bytes = ""
            if raw.sh_type ~= 8 and raw.size > 0 then
                if not have(bytes, raw.offset, raw.size) then
                    rejects[#rejects + 1] = reject_malformed(source, "section " .. tostring(index) .. " bytes are out of range")
                    return nil, rejects
                end
                section_bytes = bytes:sub(raw.offset + 1, raw.offset + raw.size)
            end
            local section = Native.NativeObjectSection(
                section_id(source, index, name),
                name,
                Native.NativeTemplateBytes(section_bytes, #section_bytes),
                raw.offset,
                raw.size,
                raw.align == 0 and 1 or raw.align,
                section_flags(raw.sh_type, raw.flags)
            )
            sections[#sections + 1] = section
            section_by_index[index] = section
            raw.name = name
            raw.id = section.id
        end

        local symbols = {}
        local symbol_by_index = {}
        for sec_index = 0, e_shnum - 1 do
            local raw = raw_sections[sec_index]
            if raw.sh_type == 2 or raw.sh_type == 11 then
                if raw.entsize ~= 24 then
                    rejects[#rejects + 1] = reject_malformed(source, "symbol table " .. tostring(sec_index) .. " has invalid entry size")
                    return nil, rejects
                end
                if raw.link >= e_shnum then
                    rejects[#rejects + 1] = reject_malformed(source, "symbol table " .. tostring(sec_index) .. " has invalid string-table link")
                    return nil, rejects
                end
                local str_raw = raw_sections[raw.link]
                if str_raw == nil or not have(bytes, str_raw.offset, str_raw.size) then
                    rejects[#rejects + 1] = reject_malformed(source, "symbol string table for section " .. tostring(sec_index) .. " is truncated")
                    return nil, rejects
                end
                local strtab = bytes:sub(str_raw.offset + 1, str_raw.offset + str_raw.size)
                local count = raw.size / raw.entsize
                if count ~= math.floor(count) then
                    rejects[#rejects + 1] = reject_malformed(source, "symbol table " .. tostring(sec_index) .. " size is not a multiple of entry size")
                    return nil, rejects
                end
                for i = 0, count - 1 do
                    local off = raw.offset + i * raw.entsize
                    local st_name = u32le(bytes, off)
                    local st_info = byte_at(bytes, off + 4)
                    local st_shndx = u16le(bytes, off + 6)
                    local st_value = u64le(bytes, off + 8)
                    local st_size = u64le(bytes, off + 16)
                    local name = string_at(strtab, st_name)
                    if name == nil then
                        rejects[#rejects + 1] = reject_malformed(source, "symbol " .. tostring(i) .. " has an invalid name offset")
                        return nil, rejects
                    end
                    local kind_num = st_info % 16
                    local bind_num = math.floor(st_info / 16)
                    local section = nil
                    if st_shndx ~= 0 and st_shndx < e_shnum then
                        section = section_by_index[st_shndx]
                        if section == nil then
                            rejects[#rejects + 1] = reject_malformed(source, "symbol " .. tostring(i) .. " section index is out of range")
                            return nil, rejects
                        end
                        if kind_num == 3 and name == "" then name = section.name end
                    elseif st_shndx ~= 0 and st_shndx < 0xff00 then
                        rejects[#rejects + 1] = reject_malformed(source, "symbol " .. tostring(i) .. " section index is out of range")
                        return nil, rejects
                    end
                    local symbol = Native.NativeObjectSymbol(
                        symbol_id(source, i, name),
                        name,
                        symbol_binding(bind_num, st_shndx),
                        symbol_kind(kind_num),
                        section and section.id or nil,
                        st_value,
                        st_size
                    )
                    symbols[#symbols + 1] = symbol
                    symbol_by_index[i] = symbol
                end
            end
        end

        local relocations = {}
        for sec_index = 0, e_shnum - 1 do
            local raw = raw_sections[sec_index]
            if raw.sh_type == 4 or raw.sh_type == 9 then
                local rela = raw.sh_type == 4
                local expected = rela and 24 or 16
                if raw.entsize ~= expected then
                    rejects[#rejects + 1] = reject_malformed(source, "relocation section " .. tostring(sec_index) .. " has invalid entry size")
                    return nil, rejects
                end
                if raw.info >= e_shnum or section_by_index[raw.info] == nil then
                    rejects[#rejects + 1] = reject_malformed(source, "relocation section " .. tostring(sec_index) .. " has invalid target section")
                    return nil, rejects
                end
                local count = raw.size / raw.entsize
                if count ~= math.floor(count) then
                    rejects[#rejects + 1] = reject_malformed(source, "relocation section " .. tostring(sec_index) .. " size is not a multiple of entry size")
                    return nil, rejects
                end
                for i = 0, count - 1 do
                    local off = raw.offset + i * raw.entsize
                    local r_offset = u64le(bytes, off)
                    local r_type = u32le(bytes, off + 8)
                    local r_sym = u32le(bytes, off + 12)
                    local kind, name = relocation_kind(r_type)
                    if kind == nil then
                        rejects[#rejects + 1] = Native.NativeBuildRejectUnsupportedRelocation(
                            source,
                            r_offset,
                            name,
                            "unsupported x64 ELF relocation in object parser"
                        )
                    else
                        local addend = rela and s64le(bytes, off + 16) or nil
                        if addend == nil then
                            local reason
                            addend, reason = relocation_implicit_addend(bytes, raw_sections[raw.info], r_offset, kind)
                            if reason ~= nil then
                                rejects[#rejects + 1] = reject_malformed(source, "relocation " .. tostring(i) .. " " .. reason)
                            end
                        end
                        local symbol = symbol_by_index[r_sym]
                        if symbol == nil then
                            rejects[#rejects + 1] = reject_malformed(source, "relocation " .. tostring(i) .. " references an invalid symbol index")
                        elseif addend ~= nil then
                            relocations[#relocations + 1] = Native.NativeObjectRelocation(
                                relocation_id(source, sec_index, i),
                                section_by_index[raw.info].id,
                                r_offset,
                                kind,
                                symbol.id,
                                addend
                            )
                        end
                    end
                end
            end
        end

        if #rejects > 0 then return nil, rejects end

        return Native.NativeObjectFile(
            Native.NativeObjectFormatElf64X64,
            target,
            template_bytes,
            sections,
            symbols,
            relocations
        ), nil
    end

    function Native.NativeTemplateBytes:parse_native_object(source, target)
        return api.parse_elf64_x64_object(source, target, self)
    end

    T._lalin_api_cache.native_object = api
    return api
end

return bind_context
