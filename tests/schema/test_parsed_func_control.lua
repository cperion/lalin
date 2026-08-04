package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema")
require("lalin.impl.tree_region")
local Document = require("lalin.syntax.document")

local P, Tr = T.LalinParse, T.LalinTree

local protocol_source = [=[
region Protocol.leaf(x [i32]; done(value [i32]))
  entry start()
    jump done(value = x)
  end
end

region Protocol.outer(x [i32]; done(value [i32]))
  entry start()
    emit Protocol.leaf(x; done = done)
  end
end

region Protocol.pair(x [i32], y [i32]; done(left [i32], right [i32]))
  entry start()
    jump done(left = x, right = y)
  end
end

fn nested_protocol(x [i32]) [i32]
  entry start()
    emit Protocol.outer(x; done = finished)
  end
  block finished(value [i32])
    return value + 1
  end
end

fn target_application(x [i32], y [i32]) [i32]
  entry start()
    emit Protocol.pair(x, y; done = finished(extra = 7, left, right))
  end
  block finished(extra [i32], left [i32], right [i32])
    return extra + left + right
  end
end
]=]

-- ─────────────────────────────────────────────────────────────
-- 1. ParsedFuncBody union: control form preserves entry/block structure
-- ─────────────────────────────────────────────────────────────

local doc = Document.parse(protocol_source, "@func-control.lln")
assert(#doc.body == 5)
local nested, applied = doc.body[4], doc.body[5]

assert(asdl.classof(nested) == P.ParsedFunc)
local body = nested.body
assert(asdl.classof(body) == P.ParsedFuncBodyControl, "control form must use ParsedFuncBodyControl")
assert(body.region_id and body.region_id:match("^lln%.fn%.[0-9]+$"),
  "region id must derive from the fn source site: " .. tostring(body.region_id))
assert(body.entry.name == "start" and #body.entry.state == 0)
assert(#body.blocks == 1 and body.blocks[1].name == "finished")
assert(body.blocks[1].state[1].name == "value" and body.blocks[1].state[1].ty ==
  T.LalinType.TScalar(T.LalinCore.ScalarI32))

-- The entry emit keeps its deterministic source-site invoke id and its wire
-- to the function block; bodies are NOT flattened into a linear list.
local entry_emit = body.entry.body[1].stmt
assert(asdl.classof(entry_emit) == Tr.StmtRegionEmit)
assert(entry_emit.invoke_id:match("^lln%.emit%.[0-9]+$"), entry_emit.invoke_id)
assert(entry_emit.wiring[1].name == "done")
assert(asdl.classof(entry_emit.wiring[1].target) == Tr.RegionWireBlock)
assert(entry_emit.wiring[1].target.label.name == "finished")
assert(asdl.classof(body.blocks[1].body[1].stmt) == Tr.StmtReturnValue)
assert(nested.body ~= applied.body, "each function owns its body")

-- target_application: named + positional wire payload on the block target.
local app_body = applied.body
assert(asdl.classof(app_body) == P.ParsedFuncBodyControl)
assert(#app_body.blocks[1].state == 3)
assert(app_body.blocks[1].state[1].name == "extra")
local app_emit = app_body.entry.body[1].stmt
assert(asdl.classof(app_emit) == Tr.StmtRegionEmit)
assert(#app_emit.wiring[1].target.args == 3)
assert(app_emit.wiring[1].target.args[1].name == "extra")
assert(app_emit.wiring[1].target.args[1].value.value.raw == "7")

-- Linear form is a distinct typed leaf (no has_control boolean).
local linear_doc = Document.parse([=[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]=], "@func-linear.lln")
assert(asdl.classof(linear_doc.body[1].body) == P.ParsedFuncBodyLinear)
assert(linear_doc.body[1].has_control == nil, "has_control boolean must be removed")

-- Malformed control forms reject at the parse boundary.
local function bad(src)
  return not pcall(Document.parse, src, "@bad-fn-control.lln")
end
assert(bad([=[fn g() [i32]
  block only()
    return 0
  end
end]=]), "control form without an entry block must reject")
assert(bad([=[fn g() [i32]
  entry a()
    return 0
  end
  entry b()
    return 1
  end
end]=]), "duplicate entry blocks must reject")

-- ─────────────────────────────────────────────────────────────
-- 2. Lowering: control form -> StmtControl(ControlStmtRegion)
-- ─────────────────────────────────────────────────────────────

local module = Document.to_module(doc, "func_control")
assert(#module.items == 5)
local function func_item(i)
  return module.items[i].func
end
local nested_func = func_item(4)
assert(asdl.classof(nested_func) == Tr.FuncLocal)
assert(#nested_func.body == 1)
local control = nested_func.body[1]
assert(asdl.classof(control) == Tr.StmtControl)
local region = control.region
assert(asdl.classof(region) == Tr.ControlStmtRegion)
assert(region.region_id == doc.body[4].body.region_id,
  "lowered region id must match the parsed source-site id")
assert(region.entry.label.name == "start")
assert(#region.blocks == 1 and region.blocks[1].label.name == "finished")
assert(#region.blocks[1].params == 1 and region.blocks[1].params[1].name == "value")
assert(asdl.classof(region.entry.body[1]) == Tr.StmtRegionEmit)
assert(asdl.classof(region.blocks[1].body[1]) == Tr.StmtReturnValue)

local applied_func = func_item(5)
local app_region = applied_func.body[1].region
assert(#app_region.blocks[1].params == 3 and app_region.blocks[1].params[1].name == "extra")

-- ─────────────────────────────────────────────────────────────
-- 3. Deterministic source-site region ids across parses
-- ─────────────────────────────────────────────────────────────

local doc2 = Document.parse(protocol_source, "@func-control.lln")
assert(doc2.body[4].body.region_id == doc.body[4].body.region_id)
assert(doc2.body[5].body.region_id == doc.body[5].body.region_id)
local module2 = Document.to_module(doc2, "func_control")
assert(module2.items[4].func.body[1].region.region_id ==
  module.items[4].func.body[1].region.region_id)

-- Two control functions in one module must not share a region id.
assert(module.items[4].func.body[1].region.region_id ~=
  module.items[5].func.body[1].region.region_id)

print("schema parsed function entry/block control preservation ok")
