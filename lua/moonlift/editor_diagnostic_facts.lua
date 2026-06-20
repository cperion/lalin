local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local AnalysisStore = require("moonlift.mlua_document_analysis")
local Errors = require("moonlift.error")
local Format = require("moonlift.error.format")

local M = {}

local function span_start(span)
    return span and (span.start_offset or 0) or 0
end

local function span_stop(span)
    return span and (span.end_offset or span.stop_offset or span.start_offset or 0) or 0
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local H = T.MoonHost
    local O = T.MoonOpen
    local Tr = T.MoonTree
    local B = T.MoonBack
    local Pm = T.MoonParse
    local Mlua = T.MoonMlua
    local P = PositionIndex.Define(T)

    local function doc_and_index(analysis)
        local doc = analysis.parse.parts.document
        return doc, P.build_index(doc)
    end

    local function range_from_span(analysis, span)
        local doc, index = doc_and_index(analysis)
        local start_offset = span_start(span)
        local stop_offset = span_stop(span)
        if stop_offset <= start_offset then stop_offset = math.min(#doc.text, start_offset + 1) end
        return assert(P.range_from_offsets(index, start_offset, stop_offset))
    end

    local function default_range(analysis)
        local doc, index = doc_and_index(analysis)
        return assert(P.range_from_offsets(index, 0, math.min(#doc.text, 1)))
    end

    local function adjusted_range_for_issue(analysis, issue, range)
        if pvm.classof(issue) == H.HostIssueBareBoolInBoundaryStruct then
            local field_start = nil
            for i = 1, #analysis.anchors.anchors do
                local a = analysis.anchors.anchors[i]
                if a.kind == S.AnchorFieldName and a.label == issue.field_name then
                    field_start = a.range.start_offset
                    break
                end
            end
            if field_start and field_start < range.start_offset then
                local _, index = doc_and_index(analysis)
                return assert(P.range_from_offsets(index, field_start, range.stop_offset))
            end
        end
        if pvm.classof(issue) == Tr.TypeIssueExpected and issue.site == "return" then
            local text = analysis.parse.parts.document.text
            local search_start = math.max(1, range.start_offset - 80)
            local prefix = text:sub(search_start, range.start_offset)
            local rel_start, rel_stop
            local pos = 1
            while true do
                local s, e = prefix:find("%f[%w_]return%f[^%w_]", pos)
                if not s then break end
                rel_start, rel_stop = s, e
                pos = e + 1
            end
            if rel_start then
                local start_offset = search_start + rel_start - 2
                local stop_offset = search_start + rel_stop - 1
                local _, index = doc_and_index(analysis)
                return assert(P.range_from_offsets(index, start_offset, stop_offset))
            end
        end
        return range
    end

    local function anchor_for_issue(analysis, issue, range)
        local label = issue and issue.name or ""
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.label == label and a.range.start_offset == range.start_offset and a.range.stop_offset == range.stop_offset then
                return a
            end
        end
        return S.AnchorSpan(S.AnchorId("diagnostic.synthetic." .. tostring(label)), S.AnchorBindingUse, label, range)
    end

    local function binding_unresolved_origin(analysis, issue, range)
        local anchor = anchor_for_issue(analysis, issue, range)
        local use = E.BindingUseSite(anchor, E.BindingRead, E.BindingScopeId("document"))
        return E.DiagFromBindingResolution(E.BindingUnresolved(use, "unresolved binding: " .. tostring(issue.name or "?")))
    end

    local function diagnostic_code(issue, fallback)
        local cls = pvm.classof(issue)
        local kind = cls and cls.kind or ""
        if cls == Pm.ParseIssue then return "parse" end
        if cls == H.HostIssueBareBoolInBoundaryStruct then return "host.bareBoolBoundary" end
        if cls == H.HostIssueInvalidPackedAlign then return "host.invalidPackedAlign" end
        if cls == H.HostIssueDuplicateField then return "host.duplicateField" end
        if cls == H.HostIssueDuplicateDecl then return "host.duplicateDecl" end
        if cls == Tr.TypeIssueUnresolvedValue then return "binding.unresolved" end
        if cls == Tr.TypeIssueInvalidBinary then return "type.invalidBinary" end
        if cls == Tr.TypeIssueExpected then return "type.expected" end
        if cls == B.BackIssueMissingFinalize or kind == "BackIssueMissingFinalize" then return "back.missingFinalize" end
        if cls == O.IssueOpenModuleName or kind == "IssueOpenModuleName" then return "open.moduleName" end
        return fallback or "E"
    end

    local function origin_for_issue(analysis, issue, phase, range, bind_unresolved)
        local cls = pvm.classof(issue)
        if cls == Tr.TypeIssueUnresolvedValue and bind_unresolved then return binding_unresolved_origin(analysis, issue, range) end
        if phase == "parse" or cls == Pm.ParseIssue then return E.DiagFromParse(issue) end
        if phase == "host" or (cls and tostring(cls.kind or ""):match("^HostIssue")) then return E.DiagFromHost(issue) end
        if phase == "open" or (cls and tostring(cls.kind or ""):match("^Issue")) then return E.DiagFromOpen(issue) end
        if phase == "typecheck" or (cls and tostring(cls.kind or ""):match("^TypeIssue")) then return E.DiagFromType(issue) end
        if phase == "backend" or (cls and tostring(cls.kind or ""):match("^BackIssue")) then return E.DiagFromBack(issue) end
        return E.DiagFromTransport(diagnostic_code(issue, "E"), tostring(issue))
    end

    local function report_message(report, issue)
        local cls = pvm.classof(issue)
        if cls == Tr.TypeIssueInvalidBinary then
            return "invalid binary operands for `" .. tostring(issue.op or "?") .. "`"
        end
        if cls == Tr.TypeIssueExpected and issue.site == "return" then
            return "return expected " .. Format.type_name(issue.expected) .. ", got " .. Format.type_name(issue.actual)
        end
        if cls == B.BackIssueMissingFinalize or (cls and cls.kind == "BackIssueMissingFinalize") then
            return "missing finalization"
        end
        if report and report.primary and report.primary.message then return report.primary.message end
        return tostring(issue)
    end

    local function diagnostic_from_resolved(analysis, ri)
        local range = ri.span and range_from_span(analysis, ri.span) or default_range(analysis)
        range = adjusted_range_for_issue(analysis, ri.issue, range)
        local report = Errors.report_from_resolved(ri, {
            source_text = analysis.parse.parts.document.text,
            uri = analysis.parse.parts.document.uri and analysis.parse.parts.document.uri.text,
        })
        local code = diagnostic_code(ri.issue, ri.code)
        local origin = origin_for_issue(analysis, ri.issue, ri.phase, range, true)
        return E.DiagnosticFact(E.DiagnosticError, origin, code, report_message(report, ri.issue), range)
    end

    local function report_for_fallback(analysis, issue, phase, span)
        return Errors.Catalog.build_report(diagnostic_code(issue), issue, phase, {
            source_text = analysis.parse.parts.document.text,
            uri = analysis.parse.parts.document.uri and analysis.parse.parts.document.uri.text,
            resolved_span = span,
        })
    end

    local function diagnostic_from_issue(analysis, issue, phase)
        local report = report_for_fallback(analysis, issue, phase, nil)
        local range = report and report.primary and report.primary.span and range_from_span(analysis, report.primary.span) or default_range(analysis)
        range = adjusted_range_for_issue(analysis, issue, range)
        local code = diagnostic_code(issue, report and report.code)
        local origin = origin_for_issue(analysis, issue, phase, range, false)
        return E.DiagnosticFact(E.DiagnosticError, origin, code, report_message(report, issue), range)
    end

    local function append_fallback(out, analysis, xs, phase)
        for i = 1, #(xs or {}) do out[#out + 1] = diagnostic_from_issue(analysis, xs[i], phase) end
    end

    local document_diagnostics_phase = pvm.phase("moonlift_editor_diagnostic_facts", {
        [Mlua.DocumentAnalysis] = function(analysis)
            local resolved = AnalysisStore.resolved_issues(analysis)
            local out = {}
            if #resolved > 0 then
                for i = 1, #resolved do out[#out + 1] = diagnostic_from_resolved(analysis, resolved[i]) end
                return pvm.seq(out)
            end
            append_fallback(out, analysis, analysis.parse.combined.issues, "parse")
            append_fallback(out, analysis, analysis.host.report.issues, "host")
            append_fallback(out, analysis, analysis.open_report.issues, "open")
            append_fallback(out, analysis, analysis.type_issues, "typecheck")
            append_fallback(out, analysis, analysis.back_report.issues, "backend")
            return pvm.seq(out)
        end,
    }, { args_cache = "full" })

    local function diagnostics(analysis)
        return pvm.drain(document_diagnostics_phase(analysis))
    end

    return {
        document_diagnostics_phase = document_diagnostics_phase,
        diagnostics = diagnostics,
    }
end

return M
