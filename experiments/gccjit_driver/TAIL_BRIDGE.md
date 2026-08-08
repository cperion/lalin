# LuaJIT FFI and GCC required-tail bridge

This experiment distinguishes two tail-call contracts that meet at LuaJIT FFI.

## Physical declaration

```c
typedef struct {
    int64_t cursor;
    int64_t limit;
    int64_t accumulator;
    uint64_t native_transitions;
    uint32_t exit_code;
    uint32_t reserved;
} TailBridgeV1_State;

typedef int64_t (*TailBridgeV1_Entry)(TailBridgeV1_State *state);
typedef int64_t (*TailBridgeV1_Callback)(TailBridgeV1_State *state);
```

The state is 40 bytes. The sealed construction driver is 896 bytes and contains 25 `CALLT` bytecode edges.
The `gcc_jit_result` owner must outlive all entry pointers.

## Lua to native

The concrete driver operation is:

```lua
function Driver:turn(runtime)
    return self.owner.entry(runtime)
end
```

`jit.util.funcbc` confirms that the foreign invocation uses Lua bytecode `CALLT`. A non-tail wrapper would
instead contain `CALL` followed by `RET1`. This is a proper tail call in Lua semantics: no Lua driver
continuation remains after the native result is available.

When a surrounding Lua loop becomes hot, LuaJIT records the FFI function-pointer invocation as `CALLXS`.
The machine instruction is still an ABI call, not necessarily a jump, because LuaJIT must preserve its FFI
return and VM conversion boundary. The wrapper itself disappears into the trace.

## Native CPS region

Libgccjit generates three same-ABI functions:

```text
tail_bridge_entry(State *)
  → required tail call tail_bridge_run(State *)
      → retained native loop
      → required tail call tail_bridge_complete(State *)
          → exact state exit + return
```

Both successors are marked using `gcc_jit_rvalue_set_bool_require_tail_call`. `run` and `complete` are
marked `noinline` so the physical transfer remains inspectable at `-O3`. GCC 16.1.1 emits:

```asm
tail_bridge_entry:
    jmp tail_bridge_run

tail_bridge_run:
    ...
    jmp tail_bridge_complete
```

Thus the one FFI call encloses an arbitrarily long native proper-tail region without growing native CPS
frames.

## Native to Lua terminal exit

A second generated entry receives an exact callback pointer:

```c
int64_t tail_bridge_callback(TailBridgeV1_State *state,
                             TailBridgeV1_Callback callback);
```

It increments retained transition state and performs a required indirect tail call. GCC emits:

```asm
tail_bridge_callback:
    addq $1, 24(%rdi)
    jmp *%rsi
```

The target can be a stable LuaJIT FFI callback trampoline. The generated native frame is absent when Lua
executes the callback. The callback returns through the original outbound FFI boundary to the Lua caller.

This is safe as a terminal completion, rejection, suspension, or host-effect exit. It is not a basis for
unbounded Lua/native alternation. LuaJIT blacklists the hot callback call site; the callback body may trace
independently, but the callback boundary is not fused into the outbound trace. Re-entering native code from
every callback would also retain nested FFI/trampoline boundaries.

## Measured boundary cost

Representative Fedora x86-64, GCC 16.1.1, LuaJIT 2.1 results:

```text
JIT, one Driver:turn + 100 native transitions      25.584 ns
JIT, raw entry pointer + 100 native transitions    24.535 ns
JIT, native indirect tail exit to Lua callback    246.807 ns
-joff Driver:turn + 100 native transitions        378.806 ns
-joff raw entry + 100 native transitions          258.820 ns
-joff native indirect tail exit to callback       298.024 ns
```

The approximately 1 ns JIT difference between `Driver:turn` and the raw pointer shows that the concrete Lua
driver method is effectively absorbed into the traced boundary. Generated native execution is unchanged by
host JIT mode.

## Resulting architecture

```text
Lua Driver:turn
  → CALLT exact native entry
      → required native tail successors
      → required direct/indirect native successors
      → return exact outcome
         or one terminal tail-jump to a Lua callback
  → caller of Driver:turn
```

The robust rule is: one Lua FFI entry per bounded physical turn, arbitrary proper-tail control inside the
native region, and one return or terminal callback at the outer boundary.

## Run

```sh
luajit experiments/gccjit_driver/tail_bridge_test.lua
luajit -joff experiments/gccjit_driver/tail_bridge_test.lua
luajit experiments/gccjit_driver/tail_bridge_bench.lua 1000000
luajit -jdump=im experiments/gccjit_driver/tail_bridge_bench.lua 10000
```

Generated C-like context, CFG, and assembly files are written beneath `target/gccjit_driver/bridge*`.
