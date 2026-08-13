#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."

LUA55_V2_SCALAR_ONLY=1 luajit experiments/copy_patch_cps/lua55_trace/run55_native_v2_diff_test.lua scalar >/tmp/lua55-v2-scalar-diff-jit.log
tail -1 /tmp/lua55-v2-scalar-diff-jit.log
LUA55_V2_SCALAR_ONLY=1 luajit -joff experiments/copy_patch_cps/lua55_trace/run55_native_v2_diff_test.lua scalar >/tmp/lua55-v2-scalar-diff-joff.log
tail -1 /tmp/lua55-v2-scalar-diff-joff.log
luajit experiments/copy_patch_cps/lua55_trace/run55_native_v2_exact_test.lua >/tmp/lua55-v2-exact-jit.log
tail -1 /tmp/lua55-v2-exact-jit.log
luajit -joff experiments/copy_patch_cps/lua55_trace/run55_native_v2_exact_test.lua >/tmp/lua55-v2-exact-joff.log
tail -1 /tmp/lua55-v2-exact-joff.log
luajit experiments/copy_patch_cps/lua55_trace/run55_native_v2_scalar_perf_gate.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/run55_native_v2_scalar_perf_gate.lua
git diff --check

echo "lua55 v2 scalar completion gate: ok"
