# Native iterators: pairs / ipairs / next

Frozen matrix for the standard iterators over the closed guest tables.

## Builtin markers

`Lua55GuestBuiltinV1 { header, builtin_id }` bumps from the heap's native
region; ids: 1 = next, 2 = ipairs-iter, 3 = pairs, 4 = ipairs. The
markers are closure-tagged values (tag 8) held in a guest `_ENV` table
under "pairs"/"ipairs"/"next", read by the native `GETTABUP`.

## Host dispatch

- `pairs(t)` (marker 3): produces `(next_marker, t, nil)`.
- `ipairs(t)` (marker 4): produces `(ipairs_iter_marker, t, 0)`.
- `next(t, k)` (marker 1, direct call): runs the native next.
- `TFORCALL` with the next marker: runs the native next; with the
  ipairs-iter marker: runs the native ipairs-iter.

## Native next

Walks the guest table: the array part (keys 1..capacity, skipping nil
gaps) then the field part (in field order). `k = nil` starts from the
beginning; an integer continues after `k`; a string continues after that
field; any other key rejects ("invalid key"). Produces `(key, value)` or
`(nil)` when exhausted — deterministic for the closed subset.

## Native ipairs-iter

`(t, i)`: reads `t[i+1]`; non-nil → `(i+1, value)`, else `(nil)` — stops
at the first nil (the array prefix).

## Learner/residual summary

- 2 learners (`lua55_learn_next_iter`, `lua55_learn_ipairs_iter`), 2
  residuals; fixed registers (R0=t, R1=k, R2=key, R3=value).
- MOVE now carries table (variant 8) and closure (9) values; the
  generic-table GETTABUP carries closure values (variant 17) — the env
  markers.
