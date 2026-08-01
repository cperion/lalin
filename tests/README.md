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

- `asdl/` — ASDL model and builder mechanics
- `compiler_process/` — compiler package and process orchestration
- `frontend/` — syntax, parsing, expansion, RNF, and splicing
- `code_ir/` — Tree/Code IR phases and explicit LuaJIT bytecode tests
- `c_backend/` — canonical C emission and GCC execution
- `runtime/` — language-level execution and semantic behavior
- `schema/`, `schema_v2/` — schema ownership and semantic boundary tests
- `core/` — operators, types, source utilities, and standard facade
- `tooling/` — reports and planning tools
- `hyper/`, `mlui/` — active package tests
- `experiments/`, `retired/`, `ui/` — non-default or quarantined suites
- `fixtures/` — shared fixture data
- `backend/` — backend-specific focused fixtures not separately scheduled
