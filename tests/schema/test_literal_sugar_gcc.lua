package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Minimal literal sugar: ExprBinary/ExprCompare adapt an ExprLit operand to the
-- other side's pinned scalar type, and ExprCast types its inner literal against
-- the cast target. So `as [u64](bx) << as [u64](4)` and `bits | as [u64](3)`
-- can be written `bx << 4` / `bits | 3` with identical semantics.
--
-- This test pins the sugar with a real GCC cook, modeled on the lead's spec:
--   let x [u64] = 42; x << 4; y | 3; z == (y | 3); returns 672.
-- It also asserts the ExprLit-with-cast form (`as [u64](1) << 4`) still compiles
-- (no regression) and that the emitted C adapts the literals to u64.

local bit = require("bit")
local lalin = require("lalin")

local src = [=[
fn sugar_main() [i32]
  entry start()
    var x [u64] = 42
    -- `4` is a bare literal; x pins u64 so the shift stays in u64 (672).
    let z [u64] = x << 4
    var y [u64] = 42
    -- comparison sugar: `(y | 3)` pins the literal 3 to u64; `z == ...` compares
    -- 672 against 43 (false), selecting the else branch that returns z = 672.
    if z == (y | 3) then
      jump done(v = as [u64](0))
    else
      jump done(v = z)
    end
  end

  block done(v [u64])
    -- cast-with-literal sugar: the literal 1 types against the cast target u64
    -- (`as [u64](1) << 4`); the u64 -> i32 narrowing cast on the return is
    -- semantically required and kept.  `tag` is deliberately unused so it only
    -- proves the cast form still typechecks and compiles.
    let tag [u64] = as [u64](1) << 4
    return as [i32](v)
  end
end
]=]

local decls = assert(lalin.loadstring(src, "@literal_sugar.lln"))
local session, source = lalin.compile_c_gcc("literal_sugar", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_literal_sugar_gcc" },
})

-- Emitted C must contain the u64 arithmetic without literal casts: the shift of
-- x by the literal 4 and the OR with literal 3 must emit the literals as u64
-- constants (adapted from the pinned operand type, no source-level casts), and
-- the cast-with-literal form must still emit its u64 literal.
assert(source:find("= ((uint64_t)4)", 1, true),
  "emitted C must adapt the pinned literal 4 to u64")
assert(source:find("= ((uint64_t)3)", 1, true),
  "emitted C must adapt the pinned literal 3 to u64")
assert(source:find("= ((uint64_t)1)", 1, true),
  "emitted C must keep the cast-with-literal u64 literal")

local sugar_main = assert(session:symbol("sugar_main", "int32_t (*)(void)"))
local status = tonumber(sugar_main())
assert(status == 672,
  "literal-sugar program must return x << 4 = 672 (got " .. tostring(status) .. ")")

session:free()
print("literal sugar gcc ok: x << 4 | 3 comparison returns 672 with literal-only casts elided")
