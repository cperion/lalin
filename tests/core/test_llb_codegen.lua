package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llb = require("llb")
local g = llb.grammar

local Mini = llb.define "CodegenMini" {
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

assert(Mini.compiled ~= nil, "llb.define should compile a language runtime")
assert(Mini.compiled.roles.items ~= nil, "compiled runtime should include role normalizers")
assert(Mini.compiled.spreads.items ~= nil, "compiled runtime should include role spread expanders")

local session = llb.use(Mini, { scope = "env" })
local env = session.env
assert(rawget(env.decl, "backend") == "compiled", "language environment should install compiled head machines")
local out = env.decl. demo { "a", "b" }
assert(out.tag == "decl", "compiled role path should preserve head emission")
assert(out.name == "demo", "compiled role path should normalize name slots")
assert(#out.items == 2 and out.items[1].text == "a" and out.items[2].text == "b", "compiled array role should normalize item roles")

local fragment = llb.fragment("items", { llb.name("c"), llb.name("d") })
local spread_out = env.decl. spread_demo { llb._(fragment), llb._({ "e" }) }
assert(#spread_out.items == 3, "compiled spread expander should append fragment and table spreads")
assert(spread_out.items[1].text == "c" and spread_out.items[2].text == "d" and spread_out.items[3].text == "e", "compiled spread expander should preserve item order")

local T = llb.type("T")
local field_fragment = llb.fragment("fields", {
    { tag = "field", name = "x", type = T },
    { tag = "field", name = "y", type = T },
})
local product_out = env.record. Rec { llb._(field_fragment), llb._({ llb.symbol("z")[T] }) }
assert(#product_out.fields == 3, "compiled product role should expand product spreads")
assert(product_out.fields[1].name == "x" and product_out.fields[3].name == "z", "compiled product role should preserve spread field order")

local variant_fragment = llb.fragment("variants", {
    { tag = "variant", name = "Some", payload = nil },
})
local sum_out = env.union. Maybe { llb._(variant_fragment), llb.symbol("None") }
assert(#sum_out.variants == 2, "compiled sum role should expand variant spreads")
assert(sum_out.variants[1].name == "Some" and sum_out.variants[2].name == "None", "compiled sum role should preserve variant order")

local compiled_items = Mini.compiled.roles.items
local reflected = llb.normalize_role({ lang = Mini, reflective = true }, "items", { "x" })
local compiled = compiled_items({ lang = Mini }, { "x" })
assert(reflected[1].text == compiled[1].text, "compiled role output should match reflective output")

local ok = pcall(function()
    llb.normalize_role({ lang = Mini, reflective = true }, "items", 1)
end)
assert(ok == false, "reflective role fallback should still report bad input")

io.write("llb codegen ok\n")
