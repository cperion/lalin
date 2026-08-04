#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

N="${N:-3000001}"
DEPTH="${DEPTH:-18}"
DIRECT_REPS="${DIRECT_REPS:-300}"
EVAL_REPS="${EVAL_REPS:-100}"
OUT="${OUT:-target/adt-profiles}"
mkdir -p "$OUT"

profile() {
  local backend="$1" mode="$2" size="$3" reps="$4"
  local file="$OUT/${backend}-${mode}.profile"
  echo "## $backend $mode"
  ADT_PROFILE=vf luajit experiments/adt/trace.lua \
    "$backend" "$mode" "$size" "$reps" | tee "$file"
}

# The profiler starts only after population construction and one unmeasured warmup.
profile arena direct "$N" "$DIRECT_REPS"
profile table_bucket direct "$N" "$DIRECT_REPS"
profile arena eval "$DEPTH" "$EVAL_REPS"
profile arena eval_scalar "$DEPTH" "$EVAL_REPS"
profile arena eval_vtable "$DEPTH" "$EVAL_REPS"
profile table_graph eval_vtable "$DEPTH" "$EVAL_REPS"
