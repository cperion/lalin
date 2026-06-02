#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'ERROR: build_stencils.sh belongs to the retired SSA/stencil path name.' >&2
printf '%s\n' 'Use ./build_lua_compile_foundry.sh or make lua-compile-foundry.' >&2
exit 2
