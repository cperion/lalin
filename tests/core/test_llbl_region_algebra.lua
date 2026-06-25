package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local region = llbl.region

local proto = llbl.protocol("RegionTestPull", {
  exits = {
    item = { class = "resumable", payload = { "value" }, next = { "state" } },
    done = { class = "terminal" },
  },
})
local pdesc = llbl.describe(proto)
assert(pdesc.tag == "Protocol", "protocol is inspectable")
assert(#pdesc.exits == 2, "protocol records typed exits")

local r = llbl.region. scan_test {
  input = { "src" },
  state = { "i" },
  protocol = proto,
  lowerings = { gps = { kind = "plan" } },
  materializers = { array = { kind = "collect-array" } },
}
local rdesc = llbl.describe(r)
assert(rdesc.tag == "Region", "region is inspectable")
assert(rdesc.name == "scan_test", "region head captures name")
assert(rdesc.protocol == "RegionTestPull", "region records protocol")
assert(rdesc.lowerings[1].target == "gps", "region records lowerings")
assert(rdesc.materializers[1].name == "array", "region records materializers")

local staged = llbl.region. staged_region { "x" } { ok = { "value" }, err = {} } { "body" }
local sdesc = llbl.describe(staged)
assert(sdesc.tag == "Region", "staged region head builds a descriptor")
assert(sdesc.protocol == "staged_region.protocol", "staged region creates a protocol from exits")

local plan = llbl.gps.plan {
  name = "region-test-plan",
  protocol = proto,
  source = llbl.gps.spec.array({ 1, 2, 3 }),
  ops = { llbl.gps.op.map(function(v) return v + 1 end) },
}
assert(llbl.gps.describe(plan).protocol == "RegionTestPull", "gps plans carry protocol identity")

llbl.process. region_probe {} (function(ctx)
  return llbl.gps.raw(llbl.gps.from.array({
    ctx:event("seen", { value = 1 }),
  }))
end)
local process_desc = llbl.describe_process("region_probe")
assert(process_desc.region.protocol == "process", "processes expose process protocol regions")

local g = llbl.grammar
local Mini = llbl.dialect "RegionMini" {
  g.role .items { kind = "array", item = "string" },
  g.head .box { g.slot .items [g.items] },
}
assert(Mini.compiled.roles.items.descriptor.protocol_name == "role_items", "array role uses item protocol")

local env = llbl.core_language():env()
assert(env.region == llbl.region, "LLBL language exports bare region head")
local env_region = env.region. env_region { input = { "x" }, protocol = "pull" }
assert(llbl.describe(env_region).protocol == "pull", "bare region head works from language env")

local lalin = require("lalin")
local chunk = lalin.dsl.loadstring([[
return region. scan { x [i32] } { hit { pos [i32] }, miss } {
  entry. start {} {
    jump. hit { pos = x },
  },
}
]], "region_algebra_lalin.lua")
local generic_region = chunk()
assert(llbl.is(generic_region, "Region"), "bare region head creates a generic LLBL region")
local unit = lalin.dsl.to_unit("RegionAlgebra", { generic_region })
assert(unit.kind == "unit", "Lalin projection wraps generic region declaration in a unit")
assert(unit.body[1].kind == "region", "Lalin consumes generic LLBL regions")

io.write("llbl region_algebra ok\n")
