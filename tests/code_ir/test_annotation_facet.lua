-- Test: CBackend annotation facet population
-- Verifies that CBackendFuncAnnotations, CBackendLoopAnnotation,
-- CBackendPointerAnnotation, and CBackendBranchAnnotation construct
-- and key correctly to CBackend block labels.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context()
Schema(T)

local C = T.LalinC
local Core = T.LalinCore

-- Test 1: CBackendAnnotationSpine construction
do
    local name = C.CBackendName("test_func")
    local spine = C.CBackendAnnotationSpine(name)
    assert(spine.func_name.text == "test_func", "spine func_name should be test_func")
    print("OK: CBackendAnnotationSpine constructs with func_name")
end

-- Test 2: CBackendLoopAnnotation with all fields
do
    local spine = C.CBackendAnnotationSpine(C.CBackendName("fn"))
    local header = C.CBackendLabel("loop_header")
    local body1 = C.CBackendLabel("loop_body_1")
    local body2 = C.CBackendLabel("loop_body_2")
    local back = C.CBackendLabel("loop_back")
    local exit1 = C.CBackendLabel("loop_exit_1")
    local exit2 = C.CBackendLabel("loop_exit_2")
    local induction_id = C.CBackendLocalId("i")
    local induction_ty = C.CBackendIndex

    local trip_count = C.CBackendRAtom(C.CBackendAtomLocal(C.CBackendLocalId("n")))

    local loop_ann = C.CBackendLoopAnnotation(
        spine,
        header,
        { body1, body2 },
        back,
        { exit1, exit2 },
        induction_id,
        induction_ty,
        trip_count,
        C.CBackendLoopForward,
        true,    -- vectorizable
        4,       -- unroll_hint
        2,       -- interleave_hint
        C.CBackendTailScalar
    )

    assert(loop_ann.spine.func_name.text == "fn", "spine identity preserved")
    assert(loop_ann.header_label.text == "loop_header", "header label correct")
    assert(#loop_ann.body_labels == 2, "2 body blocks")
    assert(loop_ann.body_labels[1].text == "loop_body_1")
    assert(loop_ann.body_labels[2].text == "loop_body_2")
    assert(loop_ann.back_edge_label.text == "loop_back", "back edge label correct")
    assert(#loop_ann.exit_labels == 2, "2 exit blocks")
    assert(loop_ann.induction_local.text == "i", "induction local id")
    assert(loop_ann.vectorizable == true, "vectorizable")
    assert(loop_ann.unroll_hint == 4, "unroll hint")
    assert(loop_ann.interleave_hint == 2, "interleave hint")
    assert(asdl.class_basename(loop_ann.tail_plan) == "CBackendTailScalar", "tail plan scalar")
    print("OK: CBackendLoopAnnotation fully populated")
end

-- Test 3: CBackendLoopAnnotation minimal (unknown direction, no hints)
do
    local spine = C.CBackendAnnotationSpine(C.CBackendName("fn_min"))
    local header = C.CBackendLabel("h")
    local loop_ann = C.CBackendLoopAnnotation(
        spine, header, { header }, header, {},
        nil, nil, nil,
        C.CBackendLoopUnknown,
        false, nil, nil,
        C.CBackendTailNone
    )
    assert(loop_ann.direction == C.CBackendLoopUnknown)
    assert(loop_ann.vectorizable == false)
    assert(loop_ann.unroll_hint == nil)
    assert(loop_ann.interleave_hint == nil)
    assert(loop_ann.tail_plan == C.CBackendTailNone)
    print("OK: CBackendLoopAnnotation minimal (unknown, no hints)")
end

-- Test 4: CBackendPointerAnnotation with various alignment facts
do
    local spine = C.CBackendAnnotationSpine(C.CBackendName("ptr_fn"))
    local local_id = C.CBackendLocalId("base_ptr")
    local ptr_ann = C.CBackendPointerAnnotation(
        spine,
        local_id,
        C.CBackendAlignmentKnown(16),
        true,   -- restrict
        true,   -- non_trapping
        nil     -- no bounds
    )
    assert(ptr_ann.local_ptr.text == "base_ptr", "local id preserved")
    assert(asdl.class_basename(ptr_ann.alignment) == "CBackendAlignmentKnown", "alignment known")
    assert(ptr_ann.alignment.bytes == 16, "16 byte alignment")
    assert(ptr_ann.restrict == true, "restrict")
    assert(ptr_ann.non_trapping == true, "non_trapping")
    print("OK: CBackendPointerAnnotation with Known(16)")
end

-- Test 5: CBackendPointerAnnotation with alignment unknown
do
    local spine = C.CBackendAnnotationSpine(C.CBackendName("ptr_fn2"))
    local ptr_ann = C.CBackendPointerAnnotation(
        spine, C.CBackendLocalId("p"),
        C.CBackendAlignmentUnknown,
        false, false, nil
    )
    assert(ptr_ann.alignment == C.CBackendAlignmentUnknown, "alignment unknown")
    print("OK: CBackendPointerAnnotation with alignment unknown")
end

-- Test 6: CBackendBranchAnnotation with polarity
do
    local spine = C.CBackendAnnotationSpine(C.CBackendName("br_fn"))
    local block = C.CBackendLabel("exit_block")
    local cond = C.CBackendLocalId("loop_cond")
    local br_ann = C.CBackendBranchAnnotation(
        spine, block, cond,
        C.CBackendBranchUnlikely,
        "loop exit is cold"
    )
    assert(br_ann.block_label.text == "exit_block", "block label correct")
    assert(br_ann.condition_local.text == "loop_cond", "condition local correct")
    assert(br_ann.polarity == C.CBackendBranchUnlikely, "polarity unlikely")
    assert(br_ann.reason == "loop exit is cold", "reason preserved")

    -- Likely polarity
    local br2 = C.CBackendBranchAnnotation(
        spine, block, nil,
        C.CBackendBranchLikely,
        "back-edge"
    )
    assert(br2.polarity == C.CBackendBranchLikely, "polarity likely")
    print("OK: CBackendBranchAnnotation with polarity")
end

-- Test 7: CBackendFuncAnnotations aggregate
do
    local spine = C.CBackendAnnotationSpine(C.CBackendName("full_fn"))
    local loop1 = C.CBackendLoopAnnotation(
        spine, C.CBackendLabel("h1"), {}, C.CBackendLabel("b1"), {},
        nil, nil, nil, C.CBackendLoopForward, false, nil, nil, C.CBackendTailNone
    )
    local loop2 = C.CBackendLoopAnnotation(
        spine, C.CBackendLabel("h2"), {}, C.CBackendLabel("b2"), {},
        nil, nil, nil, C.CBackendLoopBackward, true, 8, nil, C.CBackendTailPeel(3)
    )
    local ptr1 = C.CBackendPointerAnnotation(
        spine, C.CBackendLocalId("ptr"), C.CBackendAlignmentKnown(32), true, true, nil
    )
    local br1 = C.CBackendBranchAnnotation(
        spine, C.CBackendLabel("exit"), C.CBackendLocalId("c"),
        C.CBackendBranchUnlikely, "rare exit"
    )

    local func_ann = C.CBackendFuncAnnotations(
        spine,
        { loop1, loop2 },
        { ptr1 },
        { br1 }
    )

    assert(#func_ann.loops == 2, "2 loops")
    assert(#func_ann.pointers == 1, "1 pointer")
    assert(#func_ann.branches == 1, "1 branch")
    assert(func_ann.spine.func_name.text == "full_fn", "spine identity preserved")
    assert(func_ann.loops[1].direction == C.CBackendLoopForward)
    assert(func_ann.loops[2].direction == C.CBackendLoopBackward)
    assert(func_ann.loops[2].unroll_hint == 8)
    assert(asdl.class_basename(func_ann.loops[2].tail_plan) == "CBackendTailPeel")
    assert(func_ann.loops[2].tail_plan.count == 3)
    assert(func_ann.pointers[1].restrict == true)
    assert(func_ann.branches[1].polarity == C.CBackendBranchUnlikely)
    print("OK: CBackendFuncAnnotations aggregate")
end

-- Test 8: CBackendUnitAnnotations module-level container
do
    local spine1 = C.CBackendAnnotationSpine(C.CBackendName("fn_a"))
    local spine2 = C.CBackendAnnotationSpine(C.CBackendName("fn_b"))
    local fa1 = C.CBackendFuncAnnotations(spine1, {}, {}, {})
    local fa2 = C.CBackendFuncAnnotations(spine2, {}, {}, {})

    local unit_ann = C.CBackendUnitAnnotations("test_module", { fa1, fa2 })
    assert(unit_ann.module_name == "test_module", "module name preserved")
    assert(#unit_ann.funcs == 2, "2 func annotations")
    assert(unit_ann.funcs[1].spine.func_name.text == "fn_a")
    assert(unit_ann.funcs[2].spine.func_name.text == "fn_b")
    print("OK: CBackendUnitAnnotations module container")
end

-- Test 9: Annotations key correctly to CBackend block labels
-- Loop annotation's header_label should match the CBackendBlock.label
do
    local label = C.CBackendLabel("entry_block")
    local spine = C.CBackendAnnotationSpine(C.CBackendName("key_fn"))
    local loop_ann = C.CBackendLoopAnnotation(
        spine, label, {}, label, {},
        nil, nil, nil, C.CBackendLoopForward, false, nil, nil, C.CBackendTailNone
    )

    -- A corresponding CBackendBlock with that label
    local block = C.CBackendBlock(
        label,
        {},
        {},
        C.CBackendReturnVoid
    )
    assert(block.label.text == loop_ann.header_label.text, "annotation header_label matches block label")
    print("OK: annotation header_label matches block label")
end

print("lalin annotation_facet ok")
