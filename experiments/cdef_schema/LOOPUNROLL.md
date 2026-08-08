# LuaJIT CPS trace-capacity probe

`loopunroll_probe.lua` generates a cyclic CPS machine with one unique function per control block and
one exact CDEF state. It records trace events, verifies transition counts, and reports whether the
cycle closed into a loop trace.

## Run

```sh
luajit experiments/cdef_schema/loopunroll_probe.lua DEPTH LOOPUNROLL CYCLES CAP_MODE
```

`CAP_MODE` is one of:

- `default` — stock LuaJIT trace capacities;
- `wide` — 30,000 records, 10,000 constants, and 10,000 snapshots;
- `max` — capacity parameters raised near LuaJIT's hard 16-bit representations.

The `max` settings are:

```text
maxrecord  = 32700
maxirconst = 32000
maxsnap    = 65000
```

`loopunroll` is supplied separately. `2147483647` is the largest accepted value. `2147483648` is
rejected by the option parser, and zero means zero unrolling rather than unlimited unrolling.

## Depth-eight threshold

```text
loopunroll   closed loop   result
0             no           repeated loop-unroll aborts
4             no           repeated loop-unroll aborts
7             no           incomplete traces
8             yes          closes after some failed roots
15            yes          closes cleanly
2147483647    yes          closes cleanly
```

So `loopunroll` can be made practically irrelevant for ordinary composition depths, but it has no
literal uncapped mode.

## Raised-capacity sweep

With `loopunroll=2147483647` and `CAP_MODE=max`:

```text
CPS depth   closed loop
128         yes
256         yes
384         yes
448         yes
480         yes
496         yes
512         no — too many snapshots / trace too long
```

Depth 512 failed reproducibly across nine fresh processes. The exact boundary is probe-shape-specific:
this generated source resolves successors through a private global environment, so it is not a
universal maximum component depth.

The underlying hard representations are real:

- IR operands are stored as 16-bit references around `REF_BIAS = 0x8000`;
- trace snapshot counts are stored in `uint16_t`;
- trace numbers are capped at 65,535;
- machine code and register allocation impose additional architecture limits.

Raising all JIT parameters to `INT32_MAX` is actively harmful. In particular, unbounded
`instunroll`, recursion, side-trace, and retry policies let unstable recording run until trace or
snapshot exhaustion. These are safety policies, not simple storage capacities. The probe's `max` mode
raises only storage capacities and leaves behavioral safety limits intact.

If warmup does not produce a loop trace, the probe disables JIT and caps the timed execution. This
prevents a failed configuration from retrying compilation for minutes.

## Conclusion

```text
large loopunroll value  → useful and safe after measurement
uncapped trace recorder → not available
all limits at INT32_MAX → pathological
```

Real subapplication trees are expected to be far shallower than this probe. `loopunroll=1000` remains
a conservative practical setting for the measured composed machines. Deep generated graphs should
still declare, test, and inspect their trace-capacity requirement.

The reported nanoseconds per synthetic transition are not application performance results. LuaJIT can
collapse repeated updates to the same CDEF field. This probe measures trace closure and failure modes.

