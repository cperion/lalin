# Native complete-bank closure architecture 
Architecture workflow to close the native copy-patch complete-bank design. Goal: produce a binding target architecture where the full Lalin language-surface native bank is finite, generated from closed micro-op families, and free of sampled support-domain scope reductions or unbounded/program-specific bank axes.
**Workflow ID**: wf-native-complete-bank-closure
**Started**: 2026-07-05 06:00:42
---

## Scout Output — 2026-07-05 06:05:26

## Files Retrieved

1. `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` (lines 344-463, 700-809, 1793-1892) - Complete-bank closure target, forbidden bank axes, acceptable closed axes, manifest-first requirements, runtime/build split.
2. `lua/lalin/schema/native.lua` (lines 1-2700) - Native ASDL schema: `NativeTemplateSupportDomain`, `NativeTemplateFamily`, axes, Code/Kernel/Stencil source-shape products/unions.
3. `lua/lalin/schema/native.lua` (lines 2701-2879) - Patch coordinates/holes, call protocols, install/call results.
4. `lua/lalin/native_template_support.lua` (lines 1-1384) - Support-domain helper constructors; host scalar support domains; finite helper defaults and arbitrary support-domain fields.
5. `lua/lalin/native_template_sources.lua` (lines 1-260, 1360-1620, 1950-2718, 2940-4338, 4339-4772) - Source/manifest builder methods, family id construction, Code/Kernel/Stencil/ABI source generation, manifest matching.
6. `lua/lalin/native_code_methods.lua` (lines 1388-1478, grep hits around 1856-3037) - Code graph builder family selection, public ABI adapter family, Code inst/term family construction from program facts.
7. `lua/lalin/native_kernel_methods.lua` (lines 1-900) - Kernel projection/source-shape derivation and graph-lowering selection.
8. `lua/lalin/native_stencil_methods.lua` (grep hits around lines 40-368) - Stencil projection/source-shape derivation from producers/accesses/points/sinks/schedules.
9. `lua/lalin/native.lua` (lines 225-1385) - Template selection, equality for families/axes/source shapes, manifest entry equality.
10. `lua/lalin/native_backend.lua` (grep hits lines 32-242) - Runtime native bank/import requirements and manifest cardinality checks.
11. `lua/lalin/init.lua` (grep hits lines 644-880) - Public compile/native option handling; no runtime builders/fallbacks.
12. `lua/lalin/native_mc.lua` (lines 1-220) - Embedded bank import/copy-patch machinery and patch binding by hole/ordinal.
13. `tools/gen_lalin_mc_bank.lua` (lines 1-1000+) - Offline bank generator; manifest loading, C compilation, object parsing,

## Worker Output — 2026-07-05 12:37:37

## Completed
- Implemented T001 and T002 for `wf-native-complete-bank-closure/main`.
- Added ASDL complete-bank capability root and closed class/micro-op vocabularies.
- Added support/source helpers so complete-bank manifest/request generation starts from `NativeCompleteBankCapability`, separate from subset/test `NativeTemplateSupportDomain`.

## Files Changed
- `lua/lalin/schema/native.lua` - added `NativeCompleteBankCapability*`, closed value/location/runtime/frame/constant/atomic classes, and Code/ABI/Kernel/Stencil micro-op shape vocabularies.
- `lua/lalin/native_template_support.lua` - added complete-bank capability constructors, default target capability construction, IDs, and closed micro-op class list helpers.
- `lua/lalin/native_template_sources.lua` - added `NativeCompleteBankCapability:native_template_manifest`, `native_template_sources`, and `native_template_bank_request`.

## Checks
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema`
- `luajit tests/code_ir/test_native_template_sources.lua`
- Ad-hoc complete capability construction smoke
- Ad-hoc empty complete-bank request smoke

## Notes
- T003/T004/T005 remain ready. I did not claim another task after completing T002.

## Worker Output — 2026-07-05 13:39:42

## Completed
- Completed T003–T006 for `wf-native-complete-bank-closure/main`.
- Added closed complete-bank micro-op axes and source generation for Code, ABI, Kernel, and Stencil.
- Added first-class complete native bank manifest and Makefile target.
- Added generator/test coverage for complete-bank micro-op families and forbidden-axis checks.
- Marked all claimed edit-plan tasks done; no ready tasks remain.

## Files Changed
- `lua/lalin/schema/native.lua` - added complete-bank micro-op axes/roles.
- `lua/lalin/native.lua` - added equality handling for new micro-op axes.
- `lua/lalin/native_template_support.lua` - added family helpers and refined complete micro-op enumeration.
- `lua/lalin/native_template_sources.lua` - added Code/ABI/Kernel/Stencil complete-bank source builders.
- `tools/lalin_complete_native_bank_manifest.lua` - new complete-bank manifest entrypoint.
- `Makefile` - added `native-complete-bank` target.
- `tests/code_ir/test_native_template_sources.lua` - added forbidden-axis complete-bank assertions.
- `tests/code_ir/test_native_bank_generator.lua` - added complete-bank generator/import/compile smoke.

## Notes
Checks run:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/run.lua schema`
- `luajit tests/run.lua code_ir` — 50 passed, 1 skipped
- Ad-hoc `host_complete_bank_request()` smoke: 7804 sources/manifest entries
- `make -n native-complete-bank` verified target command.
