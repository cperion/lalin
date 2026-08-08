package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local schema = require("cdefschema")

local S = schema.context {
    name = "method-link-test",
    version = 3,
    prefix = "MethodLinkV3_",
}

S:cdef [[
typedef struct { int64_t value; } MethodLinkV3_Default;
typedef struct { int64_t value; } MethodLinkV3_Override;
typedef struct { uint32_t first, last; } MethodLinkV3_Span;
typedef union {
  MethodLinkV3_Default default_value;
  MethodLinkV3_Override override_value;
} MethodLinkV3_Payload;
typedef struct { uint32_t kind; MethodLinkV3_Payload payload; } MethodLinkV3_Slot;
 ]]

local Span = S:product("MethodLinkV3_Span")
local Payload = S:union("MethodLinkV3_Payload")
local Slot = S:product("MethodLinkV3_Slot")
local Machine = S:sum("Machine")
local Default = Machine:leaf("MethodLinkV3_Default")
local Override = Machine:leaf("MethodLinkV3_Override")

function Span:length() return tonumber(self.last - self.first) end
function Payload:clear() self.default_value.value = 0 end
function Machine:step()
    self.value = self.value + 1
    return self:done()
end
function Machine:done() return self.value end
function Override:step()
    self.value = self.value + 2
    return self:done()
end

local default_step = assert(Default.step)
local override_step = assert(Override.step)
local inherited_done = assert(Default.done)

S:seal()

assert(Span { first = 4, last = 11 }:length() == 7)
local default = Default { value = 0 }
local override = Override { value = 0 }
assert(tonumber(default:step()) == 1)
assert(tonumber(override:step()) == 2)
assert(default_step == Machine.step)
assert(override_step == Override.step)
assert(inherited_done == Machine.done)
assert(Machine:is(default) and Machine:is(override))

local slot = Slot()
slot.kind = 1
slot.payload.default_value.value = 10
assert(Payload:is(slot.payload))
assert(Machine:is(slot.payload.default_value))
assert(not Machine:is(slot))
assert(tonumber(slot.payload.default_value:step()) == 11)
slot.payload:clear()
assert(tonumber(slot.payload.default_value.value) == 0)
assert(Payload:is(Payload()))

local ok, message = pcall(function()
    function Override:late() return 1 end
end)
assert(not ok and message:match("after sealing"))

print("cdef schema method linker: ok")

