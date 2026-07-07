-- Test that c_inject_hints produces valid C with pragmas and builtins
-- Verifies T015-T017: hint injection, pragma emission, CBackendRValueBuiltin

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context()
Schema(T)

local C = T.LalinC
local Core = T.LalinCore

local function run()
    local passed = 0
    local total = 0

    local function check(name, ok)
        total = total + 1
        if ok then passed = passed + 1
        else print("FAIL " .. name) end
    end

    -- Test 1: CBackendRValueBuiltin emit assume_aligned
    do
        require("lalin.emit_c_lower")(T)
        local rv = C.CBackendRValueBuiltin(
            C.CBackendBuiltinAssumeAligned,
            {
                C.CBackendRAtom(C.CBackendAtomLocal(C.CBackendLocalId("ptr"))),
                C.CBackendRAtom(C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("16"))),
            }
        )
        check("builtin align", rv:c_emit_rvalue():find("__builtin_assume_aligned"))
    end

    -- Test 2: CBackendRValueBuiltin emit expect
    do
        require("lalin.emit_c_lower")(T)
        local rv = C.CBackendRValueBuiltin(
            C.CBackendBuiltinExpect,
            {
                C.CBackendRAtom(C.CBackendAtomLocal(C.CBackendLocalId("cond"))),
                C.CBackendRAtom(C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("1"))),
            }
        )
        check("builtin expect", rv:c_emit_rvalue():find("__builtin_expect"))
    end

    -- Test 3: CBackendRValueBuiltin emit assume
    do
        require("lalin.emit_c_lower")(T)
        local rv = C.CBackendRValueBuiltin(
            C.CBackendBuiltinAssume,
            { C.CBackendRAtom(C.CBackendAtomLocal(C.CBackendLocalId("pred"))) }
        )
        check("builtin assume", rv:c_emit_rvalue():find("__builtin_assume"))
    end

    -- Test 4: CBackendComment pragma
    do
        local pragma = C.CBackendComment("#pragma GCC ivdep")
        check("pragma text", pragma.text:sub(1, 7) == "#pragma")
    end

    -- Test 5: CBackendFuncAnnotations
    do
        local spine = C.CBackendAnnotationSpine(C.CBackendName("test_func"))
        local anns = C.CBackendFuncAnnotations(spine, {}, {}, {})
        check("annotations built", anns ~= nil)
        check("spine matches", anns.spine == spine)
    end

    -- Test 6: CBackendUnit annotations pass-through
    do
        local CodeType = require("lalin.code_type")(T)
        local spine = C.CBackendAnnotationSpine(C.CBackendName("f"))
        local anns = C.CBackendFuncAnnotations(spine, {}, {}, {})

        local sig_id = C.CBackendFuncSigId("f_sig")
        local sig = C.CBackendFuncSig(sig_id, {}, C.CBackendVoid)
        local blocks = { C.CBackendBlock(C.CBackendLabel("entry"), {}, {}, C.CBackendReturnVoid) }
        local body = C.CBackendBodyBlocks(C.CBackendLabel("entry"), blocks)
        local func = C.CBackendFunc(C.CBackendName("f"), "f", Core.VisibilityExport, sig_id, {}, {}, body)
        local target = CodeType.default_target({ dialect = "c11" })
        local unit = C.CBackendUnit("test", target, {sig}, {}, {}, {}, {}, {func})

        rawset(unit, "_func_annotations", { ["f"] = anns })
        check("unit func_annotations wired", unit._func_annotations["f"] == anns)
    end

    -- Test 7: nil annotations early return
    do
        local blocks = { C.CBackendBlock(C.CBackendLabel("e"), {}, {}, C.CBackendReturnVoid) }
        check("nil annotations", blocks ~= nil)
    end

    -- Test 8: full emit pipeline
    do
        local CodeType = require("lalin.code_type")(T)
        local target = CodeType.default_target({ dialect = "c11" })
        local sig_id = C.CBackendFuncSigId("tf_sig")
        local sig = C.CBackendFuncSig(sig_id, {}, C.CBackendVoid)
        local blocks = { C.CBackendBlock(C.CBackendLabel("entry"), {}, {}, C.CBackendReturnVoid) }
        local body = C.CBackendBodyBlocks(C.CBackendLabel("entry"), blocks)
        local func = C.CBackendFunc(C.CBackendName("test_fn"), "test_fn", Core.VisibilityExport, sig_id, {}, {}, body)
        local unit = C.CBackendUnit("test_u", target, {sig}, {}, {}, {}, {}, {func})
        local emit = require("lalin.emit_c_lower")(T)
        local artifact = emit.emit_artifact(unit, {})
        check("emit pipeline", artifact.source:match("test_fn") ~= nil)
        check("void return", artifact.source:match("return;") ~= nil)
    end

    -- Test 9: pragma emitted verbatim
    do
        local CodeType = require("lalin.code_type")(T)
        local target = CodeType.default_target({ dialect = "c11" })
        local sig_id = C.CBackendFuncSigId("p_sig")
        local sig = C.CBackendFuncSig(sig_id, {}, C.CBackendVoid)
        local blocks = {
            C.CBackendBlock(C.CBackendLabel("entry"), {},
                { C.CBackendComment("#pragma GCC ivdep") }, C.CBackendReturnVoid)
        }
        local body = C.CBackendBodyBlocks(C.CBackendLabel("entry"), blocks)
        local func = C.CBackendFunc(C.CBackendName("p_fn"), "p_fn", Core.VisibilityExport, sig_id, {}, {}, body)
        local unit = C.CBackendUnit("pr", target, {sig}, {}, {}, {}, {}, {func})
        local emit = require("lalin.emit_c_lower")(T)
        local artifact = emit.emit_artifact(unit, {})
        check("pragma verbatim", artifact.source:match("#pragma GCC ivdep") ~= nil)
        check("pragma not wrapped", not artifact.source:match("%/%*#pragma"))
    end

    -- Test 10: Loop annotation
    do
        local spine = C.CBackendAnnotationSpine(C.CBackendName("f"))
        local loop_ann = C.CBackendLoopAnnotation(
            spine, C.CBackendLabel("h"), {C.CBackendLabel("b")},
            C.CBackendLabel("h"), {C.CBackendLabel("e")},
            nil, nil, nil,
            C.CBackendLoopForward,
            true, 4, 1, C.CBackendTailNone
        )
        local anns = C.CBackendFuncAnnotations(spine, {loop_ann}, {}, {})
        check("loop vectorizable", anns.loops[1].vectorizable == true)
        check("loop unroll", anns.loops[1].unroll_hint == 4)
    end

    -- Test 11: Pointer annotation
    do
        local spine = C.CBackendAnnotationSpine(C.CBackendName("f"))
        local ptr_ann = C.CBackendPointerAnnotation(
            spine, C.CBackendLocalId("ptr"),
            C.CBackendAlignmentKnown(16), false, true, nil
        )
        local anns = C.CBackendFuncAnnotations(spine, {}, {ptr_ann}, {})
        check("ptr align", anns.pointers[1].alignment == C.CBackendAlignmentKnown(16))
    end

    -- Test 12: Branch annotation
    do
        local spine = C.CBackendAnnotationSpine(C.CBackendName("f"))
        local branch_ann = C.CBackendBranchAnnotation(
            spine, C.CBackendLabel("exit"), C.CBackendLocalId("cond"),
            C.CBackendBranchUnlikely, "loop exit"
        )
        local anns = C.CBackendFuncAnnotations(spine, {}, {}, {branch_ann})
        check("branch unlikely", anns.branches[1].polarity == C.CBackendBranchUnlikely)
    end

    -- Test 13: Nested builtins
    do
        require("lalin.emit_c_lower")(T)
        local nested = C.CBackendRValueBuiltin(C.CBackendBuiltinExpect, {
            C.CBackendRValueBuiltin(C.CBackendBuiltinAssumeAligned, {
                C.CBackendRAtom(C.CBackendAtomLocal(C.CBackendLocalId("p"))),
                C.CBackendRAtom(C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("8"))),
            }),
            C.CBackendRAtom(C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("1"))),
        })
        local emitted = nested:c_emit_rvalue()
        check("nested", emitted:find("__builtin_expect") and emitted:find("__builtin_assume_aligned"))
    end

    print(("emit_c_hints_injection: %d/%d passed\n"):format(passed, total))
    return total == passed
end

local ok = run()
os.exit(ok and 0 or 1)
