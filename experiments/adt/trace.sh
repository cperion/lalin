#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

N="${N:-300001}"
DEPTH="${DEPTH:-17}"
REPS="${REPS:-4}"
OUT="${OUT:-target/adt-traces}"
mkdir -p "$OUT"

trace() {
  local backend="$1" mode="$2" size="$3"
  local stem="$OUT/${backend}-${mode}"
  echo "## $backend $mode"
  luajit -jv experiments/adt/trace.lua "$backend" "$mode" "$size" "$REPS" \
    >"$stem.out" 2>"$stem.jv"
  cat "$stem.out"
  printf 'trace events=%s aborts=%s\n' \
    "$(grep -Ec '^\[TRACE +[0-9]' "$stem.jv" || true)" \
    "$(grep -c '^\[TRACE ---' "$stem.jv" || true)"
  cat "$stem.jv"
}

trace arena construct "$N"
trace table_graph construct "$N"
trace arena direct "$N"
trace table_bucket direct "$N"
trace arena mutate "$N"
trace table_bucket mutate "$N"
trace arena eval "$DEPTH"
trace arena eval_scalar "$DEPTH"
trace arena eval_vtable "$DEPTH"
trace table_graph eval_vtable "$DEPTH"
trace arena walk "$DEPTH"
trace table_graph walk "$DEPTH"
