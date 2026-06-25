package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local g = llbl.grammar

assert(llbl.bootstrap and llbl.bootstrap.stage == "stage1", "llbl bootstrap stage1 is installed")
assert(llbl.kernel and llbl.kernel.grammar, "stage0 kernel grammar is preserved")
assert(llbl.grammar ~= llbl.kernel.grammar, "public grammar facade is bootstrapped, not stage0")
assert(llbl.self == llbl.bootstrap.dialect, "llbl.self points at the bootstrapped llbl dialect")
assert(llbl.dialects.llbl == llbl.self, "bootstrapped llbl dialect is registered")

local role_decl = g.role. items { kind = "array", item = "name" }
assert(llbl.is(role_decl, "RoleDecl") and role_decl.name == "items", "bootstrapped role head emits grammar role declarations")

local slot_decl = g.slot. value [g.name] { channel = llbl.channel.index_name }
assert(llbl.is(slot_decl, "SlotDecl") and slot_decl.name == "value" and slot_decl.role == "name", "bootstrapped slot facade emits grammar slot declarations")

local trait_ref = g.trait. named
assert(llbl.is(trait_ref, "TraitRef") and trait_ref.name == "named", "bootstrapped trait head emits trait refs")
local trait_decl = trait_ref { apply = function() end }
assert(llbl.is(trait_decl, "TraitDecl") and trait_decl.name == "named", "bootstrapped trait refs still declare traits by call")

local Mini = llbl.dialect "BootstrapMini" {
    role_decl,
    g.head. item {
        slot_decl,
        emit = function(n) return { tag = "item", value = n.value.text } end,
    },
}

local env = Mini:env()
local item = env.item. demo
assert(item.tag == "item" and item.value == "demo", "dialect definitions compile through bootstrapped grammar facade")

local normalized = llbl.region_materialize(llbl.bootstrap.machines.normalize_role, "collect", {
    dialect = Mini,
    role = "items",
}, { "a", "b" })
assert(#normalized == 2 and normalized[1].text == "a" and normalized[2].text == "b", "bootstrap normalize role machine materializes")

local rendered = llbl.region_materialize(llbl.bootstrap.machines.render_doc, "string", llbl.doc.concat { "x", llbl.doc.line(), "y" }, { width = 1 })
assert(rendered == "x\ny", "bootstrap render doc machine materializes")

local desc = llbl.bootstrap.describe()
assert(desc.tag == "LlblBootstrap" and desc.dialect.name == "llbl", "bootstrap describe exposes dialect metadata")
assert(desc.machines.normalize_role.tag == "Region", "bootstrap describe exposes region machines")

io.write("llbl bootstrap ok\n")
