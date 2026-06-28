# Remove LSP, DAP, Editor Schema, RPC 
Map all files and references related to LSP, debugger (DAP), editor schema/features, and RPC in the lalin codebase, so we can surgically remove them while keeping typechecking and error/diagnostics infrastructure.
**Workflow ID**: wf-remove-lsp-dap-rpc
**Started**: 2026-06-28 11:19:38
---

## Scout Output — 2026-06-28 11:21:29

I now have a complete picture. Here is the exhaustive map:

---

## Files Retrieved

### PRIMARY TARGETS (36 files to delete entirely)

**1. Root entry point**
- `/home/cedric/dev/lalin/lsp.lua` (lines 1-27) — STDIO entry point that creates DAP handler on `--debug`, then calls `rpc_stdio_loop.run()`

**2. LSP Server files**
- `lua/lalin/lsp_capabilities.lua` (lines 1-16) — generates `InitializeResult` with hardcoded capability JSON
- `lua/lalin/lsp_dispatch.lua` (lines 1-vast) — **central LSP dispatcher** that requires ALL editor_* modules, calls each to handle LSP requests
- `lua/lalin/lsp_file_scan.lua` — file-system walker for workspace files
- `lua/lalin/lsp_payload_adapt.lua` — converts between editor schema types and LSP protocol types
- `lua/lalin/lsp_uri.lua` — URI ↔ path conversion, percent-encoding
- `lua/lalin/lsp_workspace.lua` — workspace state sync after events
- `lua/lalin/schema/lsp.lua` — LSP protocol ASDL types (ProtocolPosition, ProtocolRange, Payload sum, all LSP-specific types)

**3. Editor feature files (21 files)**
- `lua/lalin/editor_binding_facts.lua`
- `lua/lalin/editor_binding_scope_facts.lua`
- `lua/lalin/editor_code_actions.lua`
- `lua/lalin/editor_completion_context.lua`
- `lua/lalin/editor_completion_items.lua`
- `lua/lalin/editor_definition.lua`
- `lua/lalin/editor_diagnostic_facts.lua`
- `lua/lalin/editor_document_highlight.lua`
- `lua/lalin/editor_folding_ranges.lua`
- `lua/lalin/editor_hover.lua`
- `lua/lalin/editor_inlay_hints.lua`
- `lua/lalin/editor_references.lua`
- `lua/lalin/editor_rename.lua`
- `lua/lalin/editor_selection_ranges.lua`
- `lua/lalin/editor_semantic_tokens.lua`
- `lua/lalin/editor_signature_help.lua`
- `lua/lalin/editor_subject_at.lua`
- `lua/lalin/editor_symbol_facts.lua`
- `lua/lalin/editor_transition.lua` (thin re-export of `editor_workspace_apply`)
- `lua/lalin/editor_workspace_apply.lua`
- `lua/lalin/schema/editor.lua` — **massive ASDL schema** defining LalinEditor types (Subject, SymbolFact, BindingFact, DiagnosticFact, ClientEvent sum type with all LSP operations, etc.)

**4. DAP/Debugger files (6 files)**
- `lua/lalin/dap_breakpoint_resolver.lua` — maps DAP source-line breakpoints to block labels
- `lua/lalin/dap_server.lua` — full DAP server protocol handler
- `lua/lalin/dap_variables.lua` — formats register values for DAP display
- `lua/lalin/debugger_core.lua` — debugger state machine (stepping, breakpoints, pause/resume)
- `lua/lalin/debug_init.lua` — creates Debugger from compiled program
- `lua/lalin/debug_interpreter.lua` — **large** (~236 lines) bytecode interpreter for debugging

**5. RPC/JSON-RPC files (6 files)**
- `lua/lalin/rpc_json_decode.lua` — JSON decoder → ASDL types
- `lua/lalin/rpc_json_encode.lua` — ASDL types → JSON encoder
- `lua/lalin/rpc_lsp_decode.lua` — decodes LSP protocol JSON into ClientEvent ASDL
- `lua/lalin/rpc_lsp_encode.lua` — encodes ASDL Outgoing into LSP protocol JSON
- `lua/lalin/rpc_stdio_loop.lua` — **main event loop** reading STDIO, dispatching to LSP or DAP
- `lua/lalin/schema/rpc.lua` — RPC ASDL types (Incoming, Outgoing, OutCommand sum)

**6. LSP presentation (error system, LSP-only)**
- `lua/lalin/error/present_lsp.lua` — renders ErrorReport → LSP Diagnostic objects

---

### CONSUMER/REFERENCER FILES (need edits, but keep the file)

**File 1: `lua/lalin/init.lua`** — lines 39, 60:
- Line 39: `M.debugger_core = require("lalin.debugger_core")` — **remove**
- Line 60: `M.lsp = require("lalin.rpc_stdio_loop")` — **remove**

**File 2: `lua/lalin/schema/init.lua`** — lines 15-43:
- Lines 28-30: `"editor"`, `"lsp"`, `"rpc"` in `SCHEMA_MODULES` — **remove 3 entries**

**File 3: `lua/lalin/error/init.lua`** — lines 33, 69, 96-106:
- Line 33: `M.LSP = require("lalin.error.present_lsp")` — **remove**
- Lines 96-106: `M.render_lsp()` function — **remove**
- (Keep all other error exports)

**File 4: `lua/lalin/error/issue_collector.lua`** — lines 119-122:
- Line 121: `local LSP = require("lalin.error.present_lsp")` in `CollectingCollector:render_lsp()` method — **remove method entirely** (lines ~119-122)
- (Keep `:render_terminal()` and all other methods)

**File 5: `tests/run.lua`** — lines 10-12, 17-18:
- Line 10: `"debug"` in default suite — **remove**
- Line 12: `"editor"` and `"lsp"` in default suite — **remove**
- Line 18: `"debug"`, `"editor"`, `"lsp"` in `all` suite — **remove**

---

### TEST FILES (delete entirely: 5 files)

- `tests/debug/test_debugger_core.lua` — tests debugger state machine
- `tests/debug/test_debug_interpreter.lua` — tests interpret step/break
- `tests/lsp/test_lsp_lua_dsl_dispatch.lua` — tests LSP dispatch pipeline
- `tests/editor/test_editor_lua_dsl_analysis.lua` — tests editor symbol/diagnostic facts
- `tests/core/test_rpc_json_codec.lua` — tests JSON-RPC encode/decode round-trip

---

### DEPENDENCY GRAPH

```
lsp.lua (entry point)
 ├── require lalin.dap_server ─────┐
 │   ├── require lalin.debugger_core ───┤
 │   │   └── require lalin.debug_interpreter  │
 │   ├── require lalin.dap_variables         │
 │   └── require lalin.dap_breakpoint_resolver─┤
 │       └── require lalin.source_position_index (KEEP)
 └── require lalin.rpc_stdio_loop ──┐
     ├── require lalin.rpc_json_decode     │
     ├── require lalin.rpc_lsp_decode      │
     ├── require lalin.rpc_lsp_encode      │
     ├── require lalin.rpc_json_encode     │
     ├── require lalin.editor_workspace_apply
     ├── require lalin.lsp_workspace ─────┤
     │   ├── require lalin.lsp_uri        │
     │   └── require lalin.lsp_file_scan  │
     ├── require lalin.lsp_dispatch ──────┤
     │   ├── require lalin.mlua_document_analysis (KEEP - compiler tool)
     │   ├── require lalin.lsp_workspace (above)
     │   ├── require lalin.lsp_payload_adapt │
     │   ├── require lalin.lsp_capabilities  │
     │   └── requires ALL 18 editor_*.lua files
     └── require lalin.dap_server (above)

lua/lalin/init.lua
 ├── M.debugger_core = require("lalin.debugger_core")
 └── M.lsp = require("lalin.rpc_stdio_loop")

lua/lalin/schema/init.lua ── registers "editor", "lsp", "rpc" schemas

lua/lalin/error/init.lua ── M.LSP = require("lalin.error.present_lsp")

lua/lalin/error/issue_collector.lua ── :render_lsp() uses present_lsp
```

---

### SURPRISING DEPENDENCIES: NONE

This is the **key finding**: no core compiler files import LSP, DAP, editor, or RPC modules. The dependency direction is strictly **LSP/DAP/Editor/RPC → core**. Removal is surgically clean:

- **Typechecking** (`tree_typecheck.lua` etc.): no references
- **Error core** (`error/catalog.lua`, `span.lua`, `report.lua`, `registry.lua`, `suggest.lua`, `span_resolvers.lua`, `cascade_filter.lua`, `present_terminal.lua`): no references
- **Source infrastructure** (`source_position_index.lua`, `source_anchor_index.lua`, `source_map.lua`, `source_analysis.lua`, `source_text_apply.lua`): no references — BUT these are **imported BY** editor/dap/rpc files. They survive removal.
- **Schema files** (all except editor, lsp, rpc): no cross-references to the removed schemas
- **`mlua_document_analysis.lua`**: required by editor_*.lua files and lsp_dispatch.lua, but is a general-purpose compiler analysis tool — **keep it**, it may be useful for compiler diagnostics

The only edits needed outside the primary targets are:
1. `lua/lalin/schema/init.lua` — remove 3 entries from SCHEMA_MODULES
2. `lua/lalin/init.lua` — remove 2 exports
3. `lua/lalin/error/init.lua` — remove 1 import and 1 function
4. `lua/lalin/error/issue_collector.lua` — remove 1 method
5. `tests/run.lua` — remove 3 test suite names

---

### SCHEMA FILES TO UPDATE/REMOVE

**DELETE:**
- `lua/lalin/schema/editor.lua` — entirely LSP/editor protocol types
- `lua/lalin/schema/lsp.lua` — entirely LSP protocol types
- `lua/lalin/schema/rpc.lua` — entirely JSON-RPC types

**EDIT:**
- `lua/lalin/schema/init.lua` — remove `"editor"`, `"lsp"`, `"rpc"` from `SCHEMA_MODULES`

All other 31 schema files are core compiler schemas and must be kept.

---

### OBSERVATIONS

1. **Clean separation**: The removal is unusually clean — no tangled dependencies going from core into the removed modules.

2. **Two non-obvious re-exports**: `editor_transition.lua` is just `return require("lalin.editor_workspace_apply")`. Both get deleted.

3. **`present_lsp.lua`** lives in the error directory but is purely LSP-format — safe to delete. The error system itself (`catalog`, `report`, `span`, `registry`, `format`, etc.) stays.

4. **`rpc_json_decode.lua`** also exports a bare `decode_lua` function (not just context-bound) — used by `rpc_json_encode.lua` at module level. Both go together.

5. **`dap_breakpoint_resolver.lua`** requires `lalin.source_position_index` and `lalin.source_anchor_index` — these core files survive the removal.

6. **`init.lua` line 39 export** (`M.debugger_core`): the debugger core IS a public API of the lalin module. Its removal is API breaking. This is expected — the task says to remove it.

7. **`debug_interpreter.lua`** is substantial (~236 lines) — it's a standalone bytecode interpreter for stepping through compiled BackCmd programs. Entirely debugger-only.

8. **Museum files** (in `museum/gps.lua/`) also contain old versions of these files — those are archived and don't need changes.
