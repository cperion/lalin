package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local g = llbl.grammar

local Mini = llbl.dialect "CodegenMini" {
    g.role. items { kind = "array", item = "name" },
    g.role. fields { kind = "product" },
    g.role. variants { kind = "sum", payload_role = "fields" },
    g.head. decl {
        g.slot. name [g.name],
        g.slot. items [g.items],
        emit = function(n)
            return {
                tag = "decl",
                name = n.name.text,
                items = n.items,
            }
        end,
    },
    g.head. record {
        g.slot. name [g.name],
        g.slot. fields [g.fields],
        emit = function(n)
            return {
                tag = "record",
                name = n.name.text,
                fields = n.fields,
            }
        end,
    },
    g.head. union {
        g.slot. name [g.name],
        g.slot. variants [g.variants],
        emit = function(n)
            return {
                tag = "union",
                name = n.name.text,
                variants = n.variants,
            }
        end,
    },
}

assert(Mini.compiled ~= nil, "llbl.dialect should compile a dialect runtime")
assert(Mini.compiled.roles.items ~= nil, "compiled runtime should include role normalizers")
assert(Mini.compiled.spreads.items ~= nil, "compiled runtime should include role spread expanders")

local session = llbl.use(Mini, { scope = "env" })
local env = session.env
assert(rawget(env.decl, "backend") == "compiled", "dialect environment should install compiled head machines")
assert(llbl.is_curried(env.lt) and llbl.is_curried(env.ge), "default comparison exports should be curried")
assert(llbl.is_curried(env.land) and llbl.is_curried(env.lor), "default predicate composition exports should be curried")
local out = env.decl. demo { "a", "b" }
assert(out.tag == "decl", "compiled role path should preserve head emission")
assert(out.name == "demo", "compiled role path should normalize name slots")
assert(#out.items == 2 and out.items[1].text == "a" and out.items[2].text == "b", "compiled array role should normalize item roles")

local fragment = llbl.fragment("items", { llbl.name("c"), llbl.name("d") })
local spread_out = env.decl. spread_demo { llbl._(fragment), llbl._({ "e" }) }
assert(#spread_out.items == 3, "compiled spread expander should append fragment and table spreads")
assert(spread_out.items[1].text == "c" and spread_out.items[2].text == "d" and spread_out.items[3].text == "e", "compiled spread expander should preserve item order")

local T = llbl.type("T")
local field_fragment = llbl.fragment("fields", {
    { tag = "field", name = "x", type = T },
    { tag = "field", name = "y", type = T },
})
local product_out = env.record. Rec { llbl._(field_fragment), llbl._({ llbl.shared.symbols.source("z")[T] }) }
assert(#product_out.fields == 3, "compiled product role should expand product spreads")
assert(product_out.fields[1].name == "x" and product_out.fields[3].name == "z", "compiled product role should preserve spread field order")

local variant_fragment = llbl.fragment("variants", {
    { tag = "variant", name = "Some", payload = nil },
})
local sum_out = env.union. Maybe { llbl._(variant_fragment), llbl.shared.symbols.source("None") }
assert(#sum_out.variants == 2, "compiled sum role should expand variant spreads")
assert(sum_out.variants[1].name == "Some" and sum_out.variants[2].name == "None", "compiled sum role should preserve variant order")

local compiled_items = Mini.compiled.roles.items
assert(type(compiled_items.region) == "function", "compiled role should expose region form")
assert(type(compiled_items.collect) == "function", "compiled role should expose collect materializer")
local reflected = llbl.normalize_role({ dialect = Mini, reflective = true }, "items", { "x" })
local compiled = compiled_items({ dialect = Mini }, { "x" })
assert(reflected[1].text == compiled[1].text, "compiled role output should match reflective output")

local regioned = {}
llbl.gps.each(function(item) regioned[#regioned + 1] = item end, compiled_items.region({ dialect = Mini }, { "s1", "s2" }))
assert(#regioned == 2 and regioned[1].text == "s1" and regioned[2].text == "s2", "compiled role region should emit normalized items")

local spread_regioned = {}
llbl.gps.each(function(item) spread_regioned[#spread_regioned + 1] = item end, Mini.compiled.spreads.items.region({ dialect = Mini }, llbl._(fragment)))
assert(#spread_regioned == 2 and spread_regioned[1].text == "c" and spread_regioned[2].text == "d", "compiled spread region should emit fragment items")

local function pred_node(op, a, b) return { op = op, a = a, b = b } end
local gt = llbl.curried("test.gt", 2, function(a, b) return pred_node("gt", a, b) end)
local lt = llbl.curried("test.lt", 2, function(a, b) return pred_node("lt", a, b) end)
local both = llbl.curried("test.both", 2, function(a, b)
    return llbl.curried("test.both.apply", 1, function(v)
        return pred_node("and", a(v), b(v))
    end)
end)
local between = both(gt(llbl._)(10))(lt(llbl._)(20))
local pred = between("x")
assert(pred.op == "and" and pred.a.a == "x" and pred.a.b == 10 and pred.b.a == "x" and pred.b.b == 20, "curried holes should support predicate composition")
assert(llbl.describe(gt(llbl._)(10)).holes == true, "curried descriptions should report partial holes")
local unary_ok = pcall(function() return gt(1, 2) end)
assert(unary_ok == false, "curried forms should stay unary callable tables")

local event_out = llbl.collect_head_events(env.decl, {
    llbl.event(llbl.channel.index_name, llbl.name("evented"), { action = "name", argc = 1 }),
    llbl.event(llbl.channel.call_table, { "q" }, { action = "call", argc = 1 }),
})
assert(event_out.tag == "decl" and event_out.name == "evented" and event_out.items[1].text == "q", "head event region should construct through the same role materializers")

local rendered_chunks = {}
llbl.gps.each(function(chunk) rendered_chunks[#rendered_chunks + 1] = chunk end, llbl.render_region(llbl.doc.concat { "a", llbl.doc.line(), "b" }, { width = 1 }))
assert(table.concat(rendered_chunks) == "a\nb", "render_region should emit render chunks")

local formatted_chunks = {}
llbl.gps.each(function(chunk) formatted_chunks[#formatted_chunks + 1] = chunk end, llbl.format_region(llbl.name("fmt")))
assert(table.concat(formatted_chunks) == "fmt", "format_region should be the primary formatting region")

local ok = pcall(function()
    llbl.normalize_role({ dialect = Mini, reflective = true }, "items", 1)
end)
assert(ok == false, "reflective role fallback should still report bad input")

io.write("llbl codegen ok\n")
