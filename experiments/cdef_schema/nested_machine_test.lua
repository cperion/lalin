package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Nested = require("experiments.cdef_schema.nested_machine")

local steps = 10000

local flat1, nested1 = Nested.Flat1(), Nested.Nested1()
local flat2, nested2 = Nested.Flat2(), Nested.Nested2()
local flat4, nested4 = Nested.Flat4(), Nested.Nested4()
local flat8, nested8 = Nested.Flat8(), Nested.Nested8()

assert(tonumber(flat1:run(steps)) == steps)
assert(tonumber(nested1:run(steps)) == steps)
assert(nested1.child.count == steps)

assert(tonumber(flat2:run(steps)) == steps)
assert(tonumber(nested2:run(steps)) == steps)
assert(nested2.child.count == steps)
assert(nested2.child.child.count == steps)

assert(tonumber(flat4:run(steps)) == steps)
assert(tonumber(nested4:run(steps)) == steps)
assert(nested4.child.count == steps)
assert(nested4.child.child.count == steps)
assert(nested4.child.child.child.count == steps)
assert(nested4.child.child.child.child.count == steps)

assert(tonumber(flat8:run(steps)) == steps)
assert(tonumber(nested8:run(steps)) == steps)
assert(nested8.child.count == steps)
assert(nested8.child.child.count == steps)
assert(nested8.child.child.child.count == steps)
assert(nested8.child.child.child.child.count == steps)
assert(nested8.child.child.child.child.child.count == steps)
assert(nested8.child.child.child.child.child.child.count == steps)
assert(nested8.child.child.child.child.child.child.child.count == steps)
assert(nested8.child.child.child.child.child.child.child.child.count == steps)

assert(ffi.sizeof(flat1) == ffi.sizeof(nested1))
assert(ffi.sizeof(flat2) == ffi.sizeof(nested2))
assert(ffi.sizeof(flat4) == ffi.sizeof(nested4))
assert(ffi.sizeof(flat8) == ffi.sizeof(nested8))

local shared_a, shared_b = Nested.SharedA(), Nested.SharedB()
local owned_a, owned_b = Nested.OwnedA(), Nested.OwnedB()
assert(tonumber(shared_a:run(steps)) == steps)
assert(tonumber(shared_b:run(steps)) == steps)
assert(tonumber(owned_a:run(steps)) == steps)
assert(tonumber(owned_b:run(steps)) == steps)

local pointer_child = Nested.PointerChild()
local pointer_root = Nested.PointerRoot { child = pointer_child }
assert(tonumber(pointer_root:run(steps)) == steps)
assert(pointer_child.count == steps)

print("nested by-value CPS machines: ok")

