package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local c = require("llbl.c")
c.use()

local function exec_ok(cmd)
    local r = os.execute(cmd)
    return r == true or r == 0
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function compile_run(source, std)
    if not exec_ok("command -v cc >/dev/null 2>&1") then return "skip" end
    os.execute("mkdir -p target/c_backend")
    local c_path = "target/c_backend/test_llbl_c_generated.c"
    local exe = "target/c_backend/test_llbl_c_generated"
    write_file(c_path, source)
    assert(exec_ok("cc -std=" .. (std or "gnu99") .. " -Wall -Wextra " .. c_path .. " -o " .. exe), "generated llbl.c source must compile")
    assert(exec_ok(exe), "generated llbl.c executable must pass")
end

local Pair = c.type.Pair
local generated_body = { c.decl. acc [c.i32] (0) }
for i = 0, 3 do
    generated_body[#generated_body + 1] = c.assign(acc, acc + i)
end
generated_body[#generated_body + 1] = c.return_(acc)

local unit = c.unit. demo {
    c.include "stdint.h",
    c.include "stddef.h",
    c.define. PAIR_MAGIC(7),

    c.typedef_struct. Pair {
        left [c.i32],
        right [c.i32],
        items [c.array [c.i32] [4]],
    },

    c.static_inline_fn. sum_pair { p [Pair] } [c.i32] {
        c.return_ (p.left + p.right),
    },

    c.static_inline_fn. generated_sum {} [c.i32] {
        _(generated_body),
    },

    c.fn. feature_probe {
        seed [c.i32],
        out [c.restrict [c.ptr [c.i32]]],
    } [c.i32] {
        c.decl. p [Pair] (c.compound [Pair] {
            c.init.left(seed),
            c.init.right(PAIR_MAGIC),
            c.init.items(c.list { 1, 2, 3, 4 }),
        }),
        c.assign(out[0], sum_pair { p }),
        c.assign(out[1], c.cast [c.i32] (p.items[2])),
        c.if_ (c.gt (out[0])(10)) {
            c.assign(out[2], 9),
        },
        c.auto. aligned(c.cast [c.ptr [c.i32]] (c.builtin.assume_aligned { out, 4 })),
        c.decl. vec [c.vector [c.u32] (16)] (c.list { 1, 2, 3, 4 }),
        c.decl. vec_copy [c.typeof [vec]] (vec),
        c.assign(aligned[3], c.cast [c.i32] (vec_copy[3])),
        c.assign(out[2], c.stmt_expr {
            c.decl. tmp [c.typeof [c.i32]] (out[2] + aligned[3]),
            c.expr(tmp),
        }),
        c.for_ { c.decl. i [c.i32] (0), c.lt (i)(4), c.assign(i, i + 1) } {
            c.assign(out[3], out[3] + i),
        },
        c.return_ (out[0]),
    },

    c.fn. main {} [c.i32] {
        c.decl. out [c.array [c.i32] [4]] (c.list { 0, 0, 0, 0 }),
        c.if_ (c.ne (feature_probe { 5, out })(12)) { c.return_(1) },
        c.if_ (c.ne (out[1])(3)) { c.return_(2) },
        c.if_ (c.ne (out[2])(13)) { c.return_(3) },
        c.if_ (c.ne (out[3])(10)) { c.return_(4) },
        c.if_ (c.ne (generated_sum {})(6)) { c.return_(5) },
        c.return_(0),
    },
}

local src = c.emit_unit(unit)
local formatted = c.format(unit, { width = 80 })
assert(formatted:match("c%.unit%. demo"), "llbl.c formatter should render spaced-dot unit names")
assert(formatted:match("c%.fn%. main"), "llbl.c formatter should render spaced-dot function names")
assert(formatted:match("c%.decl%. acc"), "llbl.c formatter should render spaced-dot declaration names")
assert(not formatted:match("c%.fn%.main"), "llbl.c formatter must not collapse head/name spacing")

local expected = [[#include <stdint.h>

#include <stddef.h>

#define PAIR_MAGIC 7

typedef struct Pair {
    int32_t left;
    int32_t right;
    int32_t items[4];
} Pair;

static inline int32_t sum_pair(Pair p) {
    return p.left + p.right;
}

static inline int32_t generated_sum(void) {
    int32_t acc = 0;
    acc = acc + 0;
    acc = acc + 1;
    acc = acc + 2;
    acc = acc + 3;
    return acc;
}

int32_t feature_probe(int32_t seed, int32_t * __restrict out) {
    Pair p = (Pair){.left = seed, .right = PAIR_MAGIC, .items = { 1, 2, 3, 4 }};
    out[0] = sum_pair(p);
    out[1] = (int32_t)(p.items[2]);
    if (out[0] > 10) {
        out[2] = 9;
    }
    __auto_type aligned = (int32_t *)(__builtin_assume_aligned(out, 4));
    uint32_t __attribute__((vector_size(16))) vec = { 1, 2, 3, 4 };
    __typeof__(vec) vec_copy = vec;
    aligned[3] = (int32_t)(vec_copy[3]);
    out[2] = ({
    __typeof__(int32_t) tmp = out[2] + aligned[3];
    tmp;
});
    for (int32_t i = 0; i < 4; i = i + 1) {
        out[3] = out[3] + i;
    }
    return out[0];
}

int32_t main(void) {
    int32_t out[4] = { 0, 0, 0, 0 };
    if (feature_probe(5, out) != 12) {
        return 1;
    }
    if (out[1] != 3) {
        return 2;
    }
    if (out[2] != 13) {
        return 3;
    }
    if (out[3] != 10) {
        return 4;
    }
    if (generated_sum() != 6) {
        return 5;
    }
    return 0;
}]]
assert(src == expected, "llbl.c emitted shape changed:\n" .. src)
compile_run(src, "gnu99")

local portable = c.unit. portable {
    c.include "stdint.h",
    c.typedef_struct. PortablePair {
        left [c.i32],
        right [c.i32],
    },
    c.fn. portable_sum {
        ppairs [c.restrict [c.ptr [c.const [c.type.PortablePair]]]],
        n [c.i32],
    } [c.i32] {
        c.decl. acc [c.i32] (0),
        c.for_ { c.decl. i [c.i32] (0), c.lt (i)(n), c.assign(i, i + 1) } {
            c.assign(acc, acc + ppairs[i].left),
            c.assign(acc, acc + ppairs[i].right),
        },
        c.return_(acc),
    },
    c.fn. main {} [c.i32] {
        c.decl. ppairs [c.array [c.type.PortablePair] [2]] (c.list { c.list { 1, 2 }, c.list { 3, 4 } }),
        c.return_(c.ne (portable_sum { ppairs, 2 })(10)),
    },
}

local portable_src = c.emit_unit(portable, { dialect = "c11" })
assert(portable_src:match("PortablePair const %* restrict ppairs"), "C11 dialect should use standard restrict")
compile_run(portable_src, "c11")

local ok_c11, err_c11 = pcall(function() c.emit_unit(unit, { dialect = "c11" }) end)
assert(not ok_c11 and tostring(err_c11):match("requires GNU C dialect"), "C11 dialect must reject GNU-only fragments")

local ok, err = pcall(function()
    c.fn. bad { c.return_() } [c.void] {}
end)
assert(not ok and tostring(err):match("product entries must be typed names or spreads"), "role mismatch should reject statement as parameter")

ok, err = pcall(function()
    c.typedef_struct. Bad { c.return_() }
end)
assert(not ok and tostring(err):match("product entries must be typed names or spreads"), "role mismatch should reject statement as field")

io.write("llbl.c ok\n")
