local C = require("cblock")

local csrc, errors = C.compile(function()
    local VM = struct {
        field: value (i64),
        field: steps (i64),
        field: budget (i64),
    }

    VM: classify (
        cont: halted (VM),
        cont: even (VM),
        cont: odd (VM),
        cont: trapped (VM)
    )(function(p, c)
        local self = p.self
        local halted, even, odd, trapped =
            c.halted, c.even, c.odd, c.trapped
        return if_(le(self.value, 0), trapped(self),
            if_(eq(self.value, 1), halted(self),
                if_(le(self.budget, 0), trapped(self),
                    if_(eq(self.value % 2, 0), even(self), odd(self)))))
    end)

    VM: even_instruction () (VM) (function(p)
        local self = p.self
        return VM {
            value = self.value / 2,
            steps = self.steps + 1,
            budget = self.budget - 1,
        }
    end)

    VM: odd_instruction () (VM) (function(p)
        local self = p.self
        return VM {
            value = self.value * 3 + 1,
            steps = self.steps + 1,
            budget = self.budget - 1,
        }
    end)

    -- the VM is an alternative-exit protocol: a region, sealed once
    local hailstone = region(
        param: input (i64),
        cont: halted (i64),
        cont: trapped (i64)
    )(function(p, c)
            local input = p.input
            local halted, trapped = c.halted, c.trapped
            local dispatch, execute_even, execute_odd

            dispatch = block(VM)(function(state)
                local on_halted  = function(done) return halted(done.steps) end
                local on_trapped = function(stuck) return trapped(stuck.value) end
                return state:classify() {
                    halted = on_halted, even = execute_even,
                    odd = execute_odd, trapped = on_trapped,
                }
            end)

            execute_even = block(VM)(function(state)
                return dispatch(state:even_instruction())
            end)

            execute_odd = block(VM)(function(state)
                return dispatch(state:odd_instruction())
            end)

            return dispatch(VM { value = input, steps = 0, budget = 1024 })
        end)

    local hailstone_fn = call(hailstone)

    return {
        vm = {
            State = VM,
            hailstone = hailstone_fn,
        },
    }
end)

if not csrc then error(table.concat(errors, "\n")) end

local f = assert(io.open("hailstone_vm.c", "w"))
f:write(csrc, [[

#include <stdio.h>
#include <stdint.h>
#include <time.h>

static int64_t native_hailstone(int64_t value) {
    int64_t steps = 0;
    while (value > 1) {
        value = value % 2 == 0 ? value / 2 : value * 3 + 1;
        ++steps;
    }
    return steps;
}

static double seconds(void) {
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

int main(void) {
    int64_t result = 0;
    int64_t trapped = 0;

    for (int64_t input = 1; input <= 100000; ++input) {
        int exit = vm_hailstone(input, &result, &trapped);
        if (exit != 1 || result != native_hailstone(input)) {
            fprintf(stderr, "mismatch at %lld: exit=%d vm=%lld native=%lld\n",
                (long long)input, exit, (long long)result,
                (long long)native_hailstone(input));
            return 1;
        }
    }

    if (vm_hailstone(0, &result, &trapped) != 2 || trapped != 0) return 2;

    const int64_t runs = 1000000;
    int64_t checksum = 0;
    double begin = seconds();
    for (int64_t input = 1; input <= runs; ++input) {
        if (vm_hailstone(input, &result, &trapped) != 1) return 3;
        checksum += result;
    }
    double vm_elapsed = seconds() - begin;

    int64_t native_checksum = 0;
    begin = seconds();
    for (int64_t input = 1; input <= runs; ++input)
        native_checksum += native_hailstone(input);
    double native_elapsed = seconds() - begin;
    if (native_checksum != checksum) return 4;

    printf("direct-threaded hailstone VM\n");
    printf("  runs:         %lld\n", (long long)runs);
    printf("  transitions:  %lld\n", (long long)checksum);
    printf("  VM:           %.3f ms, %.1f M transitions/s\n",
        vm_elapsed * 1000.0, (double)checksum / vm_elapsed / 1000000.0);
    printf("  raw C:        %.3f ms, %.1f M transitions/s\n",
        native_elapsed * 1000.0,
        (double)checksum / native_elapsed / 1000000.0);
    printf("  VM / raw C:   %.3fx\n", vm_elapsed / native_elapsed);
    return 0;
}
]])
f:close()

if os.getenv("CBLOCK_EMIT_ONLY") then
    print(("generated hailstone_vm.c: %d bytes"):format(#csrc))
    return
end

assert(os.execute("cc -std=c99 -O3 -o hailstone_vm hailstone_vm.c && ./hailstone_vm"))
