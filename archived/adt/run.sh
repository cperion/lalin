#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

N="${N:-1000001}"
DEPTH="${DEPTH:-18}"
REPS="${REPS:-7}"

run() {
  luajit experiments/adt/bench.lua "$@"
}

echo "# construction + full GC (graph-only table is the ordinary AST baseline)"
run arena construct "$N" 1
run table_graph construct "$N" 1

echo
echo "# direct constructor-local sweeps (bucketed tables are the stronger baseline)"
run arena direct "$N" "$REPS"
run table_bucket direct "$N" "$REPS"
run arena mutate "$N" "$REPS"
run table_bucket mutate "$N" "$REPS"

echo
echo "# mixed recursive tree work (no sweep advantage)"
run arena eval "$DEPTH" "$REPS"
run arena eval_scalar "$DEPTH" "$REPS"
run arena eval_vtable "$DEPTH" "$REPS"
run table_graph eval_vtable "$DEPTH" "$REPS"
run arena walk "$DEPTH" "$REPS"
run table_graph walk "$DEPTH" "$REPS"
