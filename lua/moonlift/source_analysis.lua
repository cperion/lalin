local M = {}

local function source_text_from_origin(src, origin)
    local source = origin and origin.__moonlift_source
    return (source and (source.source_text or source.text)) or src or ""
end

local function uri_from_origin(origin, fallback)
    local source = origin and origin.__moonlift_source
    return (source and source.uri) or fallback or "?"
end

local function base_offset_from_origin(origin)
    return (origin and origin.start_offset) or 0
end

function M.build(T, parsed, src, origin, opts)
    opts = opts or {}
    local S = T.MoonSource
    local Parse = require("moonlift.parse")
    local PositionIndex = require("moonlift.source_position_index").Define(T)

    local source_text = source_text_from_origin(src, origin)
    local uri = uri_from_origin(origin, opts.uri or opts.chunk_name or opts.name)
    local base_offset = base_offset_from_origin(origin)
    local doc = S.DocumentSnapshot(S.DocUri(uri), S.DocVersion(1), S.LangMoonlift, source_text)
    local index = PositionIndex.build_index(doc)
    local scan = parsed and parsed.scan
    if not scan or not scan.toks then
        scan = Parse.scan_document(src or "")
    end
    local toks = scan and scan.toks
    local n = (toks and toks.n) or 0
    local anchors = {}
    local counter = 0
    local function aid(prefix) counter = counter + 1; return prefix .. "." .. counter end
    local function token_start(i)
        return base_offset + ((toks.start[i] or 1) - 1)
    end
    local function token_stop(i)
        return base_offset + (toks.stop[i] or ((toks.start[i] or 1) - 1))
    end
    local function add_anchor(prefix, kind, label, start, stop)
        local range = PositionIndex.range_from_offsets(index, start, stop)
        if range then
            anchors[#anchors + 1] = S.AnchorSpan(S.AnchorId(aid(prefix)), kind, label, range)
        end
    end

    local keyword_set = {
        ["func"]=true,["region"]=true,["expr"]=true,["struct"]=true,["union"]=true,["handle"]=true,["extern"]=true,
        ["entry"]=true,["block"]=true,["if"]=true,["then"]=true,["elseif"]=true,["else"]=true,
        ["switch"]=true,["case"]=true,["default"]=true,["do"]=true,["end"]=true,
        ["return"]=true,["yield"]=true,["jump"]=true,["emit"]=true,["call"]=true,
        ["let"]=true,["var"]=true,["as"]=true,["select"]=true,
        ["assert"]=true,["len"]=true,["view"]=true,["lease"]=true,["invalid"]=true,
        ["noescape"]=true,["invalidate"]=true,["preserve"]=true,
        ["and"]=true,["or"]=true,["not"]=true,
    }
    local opaque_set = {
        ["+"]=true,["-"]=true,["*"]=true,["/"]=true,["%"]=true,["="]=true,
        ["=="]=true,["~="]=true,["<"]=true,["<="]=true,[">"]=true,[">="]=true,
        ["&"]=true,["|"]=true,["^"]=true,["~"]=true,["<<"]=true,[">>"]=true,[">>>"]=true,
        ["["]=true, ["]"]=true, ["("]=true, [")"]=true, ["."]=true, [","]=true, [":"]=true,
    }

    local TK = Parse.TK
    local function add_emit_use_anchor(i, start)
        local j = i + 1
        while j <= n and toks.kind[j] == TK.nl do j = j + 1 end
        if j > n then return end
        local frag = (toks.kind[j] == TK.hole) and "nil" or tostring(toks.text[j] or "")
        while j <= n and toks.kind[j] ~= TK.lparen do j = j + 1 end
        if j > n then return end
        local depth = 0
        while j <= n do
            if toks.kind[j] == TK.lparen then
                depth = depth + 1
            elseif toks.kind[j] == TK.rparen then
                depth = depth - 1
                if depth == 0 then
                    add_anchor("emit-use", S.AnchorOpaque("emit-use"), "emit." .. frag .. "." .. tostring(j + 1), start, token_stop(j))
                    return
                end
            end
            j = j + 1
        end
    end

    local after_decl = nil
    local def_next = nil
    for i = 1, n do
        local text = toks.text[i]
        if text and text ~= "" then
            local start = token_start(i)
            local stop = token_stop(i)
            if keyword_set[text] then
                add_anchor("kw", S.AnchorKeyword, text, start, stop)
                if text == "emit" or text == "call" then add_emit_use_anchor(i, start) end
                if text == "func" then after_decl = S.AnchorFunctionName
                elseif text == "region" then after_decl = S.AnchorRegionName
                elseif text == "expr" then after_decl = S.AnchorExprName
                elseif text == "struct" or text == "handle" then after_decl = S.AnchorStructName
                elseif text == "block" or text == "entry" then after_decl = S.AnchorContinuationName
                elseif text == "let" or text == "var" then def_next = S.AnchorLocalName
                end
            elseif text:match("^[_%a][_%w]*$") then
                local nxt = toks.text[i + 1]
                local prv = toks.text[i - 1]
                local kind = S.AnchorBindingUse
                if after_decl then
                    kind = after_decl
                    after_decl = nil
                elseif def_next then
                    kind = def_next
                    def_next = nil
                elseif prv == "emit" or nxt == "(" then
                    kind = S.AnchorFunctionUse
                end
                add_anchor("tok", kind, text, start, stop)
                if nxt == "=" then
                    add_anchor("field", S.AnchorFieldName, text, start, stop)
                elseif prv == "." then
                    add_anchor("field-use", S.AnchorFieldUse, text, start, stop)
                end
            elseif opaque_set[text] then
                add_anchor("op", S.AnchorOpaque("operator"), text, start, stop)
            end
        end
    end

    return {
        uri = uri,
        source_text = source_text,
        source_cache = { [uri] = source_text },
        anchors = anchors,
        document = doc,
    }
end

function M.merge_into(dst, src)
    if not src then return dst end
    dst = dst or {}
    dst.source_cache = dst.source_cache or {}
    if src.source_cache then
        for uri, text in pairs(src.source_cache) do dst.source_cache[uri] = text end
    elseif src.uri and src.source_text then
        dst.source_cache[src.uri] = src.source_text
    end
    if dst.source_text == nil and src.source_text ~= nil then dst.source_text = src.source_text end
    if dst.uri == nil and src.uri ~= nil then dst.uri = src.uri end
    dst.anchors = dst.anchors or {}
    local anchors = src.anchors or {}
    for i = 1, #anchors do dst.anchors[#dst.anchors + 1] = anchors[i] end
    if dst.document == nil and src.document ~= nil then dst.document = src.document end
    if src.item_analyses then
        dst.item_analyses = dst.item_analyses or {}
        for name, analysis in pairs(src.item_analyses) do dst.item_analyses[name] = analysis end
    end
    return dst
end

return M
