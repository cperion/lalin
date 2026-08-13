-- Fused lexer + recursive-descent parser as one machine.
--
-- Evaluator owns its state and its regions. `scan` is an owned inline
-- region: it advances to the next token, mutating the frame, and exposes
-- token-ready / eof / malformed as continuations. The recursive descent
-- regions (parse_primary / parse_term / parse_expr) drive the lexer inline,
-- with mutual recursion through sealed call(...) frames,
-- so tokens are never materialized in an array: lex and parse are one
-- fused control graph over the source bytes.
--
-- Token protocol: after any production, the current token sits in
-- frame.kind/value with the cursor past it. parse_primary scans past its
-- token (EOF is a valid terminator); the operator loops in parse_term and
-- parse_expr inspect the current token without consuming it, and consume
-- only when they continue.

local C = require("cblock")

local function build_parser()
    local NUM, PLUS, MINUS, MUL, DIV, LPAREN, RPAREN = 0, 1, 2, 3, 4, 5, 6

    local Evaluator = struct {
        field: source (ptr(u8)),
        field: length (i64),
        field: cursor (i64),
        field: kind (i32),
        field: value (i64),
    }

    -- Owned lexer region: advance to the next token, mutating the frame.
    -- Exits: ok()            a token is in self.kind / self.value
    --        eof()           end of input reached
    --        malformed()     a non-token character
    Evaluator.scan = region(ptr(Evaluator), cont(), cont(), cont())
        (function(p, ok, eof, malformed)
            local start, first, digit, operator

            start = block()(function()
                return if_(ge(deref(p).cursor, deref(p).length), eof(),
                    seq(store(deref(p).value, 0), first()))
            end)

            first = block()(function()
                local c = let(load(at(deref(p).source, deref(p).cursor)))
                local is_digit = let(and_(ge(c, 48), le(c, 57)))
                return if_(is_digit, digit(), operator())
            end)

            -- Consume while digits; stop (without consuming) at the first
            -- non-digit, leaving kind = NUM. operator() only runs when the
            -- scan starts on a non-digit character.
            digit = block()(function()
                local c = let(load(at(deref(p).source, deref(p).cursor)))
                local is_digit = let(and_(ge(c, 48), le(c, 57)))
                return if_(is_digit,
                    seq(
                        store(deref(p).value, deref(p).value * 10 + cast(i64, c - 48)),
                        store(deref(p).cursor, deref(p).cursor + 1),
                        digit()),
                    seq(store(deref(p).kind, NUM), ok()))
            end)

            operator = block()(function()
                -- Stash the character BEFORE advancing: value is a scratch
                -- slot, so the classification reads a stable place.
                return store(deref(p).value,
                        cast(i64, load(at(deref(p).source, deref(p).cursor)))),
                       store(deref(p).cursor, deref(p).cursor + 1),
                       if_(eq(load(deref(p).value), 43), seq(store(deref(p).kind, PLUS), ok()),
                       if_(eq(load(deref(p).value), 45), seq(store(deref(p).kind, MINUS), ok()),
                       if_(eq(load(deref(p).value), 42), seq(store(deref(p).kind, MUL), ok()),
                       if_(eq(load(deref(p).value), 47), seq(store(deref(p).kind, DIV), ok()),
                       if_(eq(load(deref(p).value), 40), seq(store(deref(p).kind, LPAREN), ok()),
                       if_(eq(load(deref(p).value), 41), seq(store(deref(p).kind, RPAREN), ok()),
                       malformed()))))))
            end)

            return start()
        end)

    local scan = Evaluator.scan

    -- Owned lookahead region: classify the character at the cursor WITHOUT
    -- advancing. Exits: ok / eof / malformed.
    Evaluator.peek = region(ptr(Evaluator), cont(), cont(), cont())
        (function(p, ok, eof, malformed)
            local start, classify
            start = block()(function()
                return if_(ge(deref(p).cursor, deref(p).length), eof(), classify())
            end)
            classify = block()(function()
                local c = let(load(at(deref(p).source, deref(p).cursor)))
                return if_(and_(ge(c, 48), le(c, 57)),
                        seq(store(deref(p).kind, NUM), ok()),
                    if_(eq(c, 43), seq(store(deref(p).kind, PLUS), ok()),
                    if_(eq(c, 45), seq(store(deref(p).kind, MINUS), ok()),
                    if_(eq(c, 42), seq(store(deref(p).kind, MUL), ok()),
                    if_(eq(c, 47), seq(store(deref(p).kind, DIV), ok()),
                    if_(eq(c, 40), seq(store(deref(p).kind, LPAREN), ok()),
                    if_(eq(c, 41), seq(store(deref(p).kind, RPAREN), ok()),
                        malformed())))))))
            end)
            return start()
        end)

    local peek = Evaluator.peek

    -- primary := number | '(' expr ')'
    -- Uses the current token (already scanned). A number returns its value
    -- without consuming; parens consume '(' and ')' via explicit advances.
    Evaluator.parse_primary = region(ptr(Evaluator), cont(i64), cont())
        (function(p, result, malformed)
            local classify, emit_value, paren, inner, close, close_check

            emit_value = block()(function()
                return result(load(deref(p).value))
            end)

            classify = block()(function()
                return if_(eq(deref(p).kind, NUM), emit_value(),
                    if_(eq(deref(p).kind, LPAREN), paren(),
                        malformed()))
            end)

            -- the '(' is already the current token; load the first inner one
            paren = block()(function()
                return scan(p)(inner, malformed, malformed)
            end)

            inner = block()(function()
                local on_value = function(v)
                    return seq(store(deref(p).value, v), close())
                end
                return call(Evaluator.parse_expr)(p)(on_value, malformed)
            end)

            close = block()(function()
                return peek(p)(close_check, malformed, malformed)
            end)

            close_check = block()(function()
                return if_(eq(deref(p).kind, RPAREN),
                    seq(store(deref(p).cursor, deref(p).cursor + 1), emit_value()),
                    malformed())
            end)

            return classify()
        end)

    -- term := primary (('*'|'/') primary)*
    -- fold peeks the next token without consuming; an operator is consumed
    -- by an explicit advance followed by a scan of its operand.
    Evaluator.parse_term = region(ptr(Evaluator), cont(i64), cont())
        (function(p, result, malformed)
            local acc = var(i64, 0)
            local fold, op, mul, div, mul_rhs, div_rhs

            fold = block()(function()
                return peek(p)(op, result(load(acc)), malformed)
            end)

            op = block()(function()
                return if_(eq(deref(p).kind, MUL), mul(),
                    if_(eq(deref(p).kind, DIV), div(),
                        result(load(acc))))
            end)

            mul = block()(function()
                return store(deref(p).cursor, deref(p).cursor + 1),
                       scan(p)(mul_rhs, malformed, malformed)
            end)
            div = block()(function()
                return store(deref(p).cursor, deref(p).cursor + 1),
                       scan(p)(div_rhs, malformed, malformed)
            end)

            mul_rhs = block()(function()
                local on_value = function(v)
                    return seq(store(acc, load(acc) * v), fold())
                end
                return call(Evaluator.parse_primary)(p)(on_value, malformed)
            end)
            div_rhs = block()(function()
                local on_value = function(v)
                    return seq(store(acc, load(acc) / v), fold())
                end
                return call(Evaluator.parse_primary)(p)(on_value, malformed)
            end)

            local on_value = function(v)
                return seq(store(acc, v), fold())
            end
                return call(Evaluator.parse_primary)(p)(on_value, malformed)
        end)

    -- expr := term (('+'|'-') term)*
    Evaluator.parse_expr = region(ptr(Evaluator), cont(i64), cont())
        (function(p, result, malformed)
            local acc = var(i64, 0)
            local fold, plus, minus, plus_rhs, minus_rhs

            fold = block()(function()
                return peek(p)(op, result(load(acc)), malformed)
            end)

            op = block()(function()
                return if_(eq(deref(p).kind, PLUS), plus(),
                    if_(eq(deref(p).kind, MINUS), minus(),
                        result(load(acc))))
            end)

            plus = block()(function()
                return store(deref(p).cursor, deref(p).cursor + 1),
                       scan(p)(plus_rhs, malformed, malformed)
            end)
            minus = block()(function()
                return store(deref(p).cursor, deref(p).cursor + 1),
                       scan(p)(minus_rhs, malformed, malformed)
            end)

            plus_rhs = block()(function()
                local on_value = function(v)
                    return seq(store(acc, load(acc) + v), fold())
                end
                return call(Evaluator.parse_term)(p)(on_value, malformed)
            end)
            minus_rhs = block()(function()
                local on_value = function(v)
                    return seq(store(acc, load(acc) - v), fold())
                end
                return call(Evaluator.parse_term)(p)(on_value, malformed)
            end)

            local on_value = function(v)
                return seq(store(acc, v), fold())
            end
                return call(Evaluator.parse_term)(p)(on_value, malformed)
        end)

    -- Entry: build the frame, scan the first lookahead, parse, require EOF.
    local run = region(ptr(u8), i64, cont(i64), cont())
        (function(source, length, result, malformed)
            local frame = var(Evaluator, Evaluator {
                source = source, length = length,
                cursor = 0, kind = 0, value = 0,
            })
            local parse, finish
            parse = block()(function()
                local on_value = function(v)
                    return seq(store(deref(address(frame)).value, v), finish())
                end
                return call(Evaluator.parse_expr)(address(frame))(on_value, malformed)
            end)
            finish = block()(function()
                return if_(ge(deref(address(frame)).cursor, deref(address(frame)).length),
                    result(load(deref(address(frame)).value)), malformed())
            end)
            return scan(address(frame))(parse, malformed, malformed)
        end)

    local run_fn = call(run)

    return {
        parser = {
            Evaluator = Evaluator,
            run = run_fn,
        },
    }
end

-- GCC path
local csrc, errors = C.compile(build_parser)
if not csrc then error(table.concat(errors, "\n")) end

local base = os.tmpname()
os.remove(base)
local cpath, exe = base .. ".c", base .. ".out"
local f = assert(io.open(cpath, "w"))
f:write(csrc, [[
#include <string.h>
int main(void) {
    int64_t out = 0; int e = 0;
    e = parser_run((uint8_t*)"12+34*2", 7, &out);
    if (e != 1 || out != 80) return 1;            /* 12 + 34*2 */
    e = parser_run((uint8_t*)"7*(3+2)", 7, &out);
    if (e != 1 || out != 35) return 2;            /* 7*(3+2) */
    e = parser_run((uint8_t*)"100-25/5+2", 10, &out);
    if (e != 1 || out != 97) return 3;            /* 100 - 5 + 2 */
    e = parser_run((uint8_t*)"12+", 3, &out);
    if (e != 2) return 4;                          /* malformed */
    e = parser_run((uint8_t*)"(2+3)*(4-1)", 11, &out);
    if (e != 1 || out != 15) return 5;
    e = parser_run((uint8_t*)"((1))", 5, &out);
    if (e != 1 || out != 1) return 6;
    return 0;
}
]])
f:close()
local ok, why, code = os.execute(("cc -std=c99 -O2 -o %s %s && %s"):format(exe, cpath, exe))
os.remove(cpath) os.remove(exe)
assert(ok == true or ok == 0, ("fused parser test failed: %s %s"):format(why, code))
print("cblock fused lexer+parser (GCC): ok")

-- Lazy TCC path from Lua
local module, runtime = C.jit(build_parser)
assert(module, runtime)

local ffi = require("ffi")
local function parse(text)
    local src = ffi.cast("uint8_t *", text)
    local exit, value = module.parser.run(src, #text)
    return exit, value and tonumber(value) or nil
end
local function expect(text, want)
    local exit, value = parse(text)
    assert(exit == 1 and value == want,
        ("parse %q: exit=%d value=%s"):format(text, exit, tostring(value)))
end
expect("12+34*2", 80)
expect("7*(3+2)", 35)
expect("100-25/5+2", 97)
expect("(2+3)*(4-1)", 15)
expect("((1))", 1)
local exit, v = parse("12+")
assert(exit == 2 and v == nil)

module:free()
print("cblock fused lexer+parser (TCC): ok")
