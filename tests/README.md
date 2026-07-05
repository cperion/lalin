# Test Layout

Tests are grouped by compiler boundary instead of living in one flat directory.
Run them from the repository root.

```sh
make                              # builds repo-local LuaJIT if needed
luajit tests/run.lua              # stable default suite
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua all          # includes optional/retired compiler suites
```

Directories:

- `asdl/` - ASDL model and builder mechanics
- `compiler_process/` - compiler process/package orchestration tests
- `frontend/` - syntax, parsing, open expansion, RNF, splicing
- `code_ir/` - Tree/Code IR phases, validation, facts, lowering plans, explicit LuaJIT bytecode backend, and native copy-patch template/source/object/install tests
- `c_backend/` - C emission/AOT path
- `host/` - hosted Lua builder/value APIs
- `runtime/` - language-level execution and semantic behavior
- `schema/` - schema smoke tests
- `editor/` and `lsp/` - editor facts and LSP integration
- `core/` - core operators, types, source utilities, std facade
- `tooling/` - reports, explainer coverage, link planning
- `debug/` - debug interpreter/debugger and ELF parser tests
- `ui/` - retired SDL/UI tests; not in aggregate suites
- `experiments/` - experiment/spongejit tests; may require experiment modules
- `fixtures/` - fixture data consumed by tests
