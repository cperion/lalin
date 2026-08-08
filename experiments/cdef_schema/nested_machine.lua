local schema = require("cdefschema")

local S = schema.context {
    name = "nested-machine",
    version = 1,
    prefix = "NestedMachineV1_",
}

S:cdef [[
typedef struct { uint32_t remaining, c1; } NestedMachineV1_Flat1;
typedef struct { uint32_t remaining, c1, c2; } NestedMachineV1_Flat2;
typedef struct { uint32_t remaining, c1, c2, c3, c4; } NestedMachineV1_Flat4;
typedef struct {
    uint32_t remaining, c1, c2, c3, c4, c5, c6, c7, c8;
} NestedMachineV1_Flat8;

typedef struct { uint32_t count; } NestedMachineV1_N1L1;
typedef struct {
    NestedMachineV1_N1L1 child;
    uint32_t remaining;
} NestedMachineV1_N1Root;

typedef struct { uint32_t count; } NestedMachineV1_N2L2;
typedef struct {
    NestedMachineV1_N2L2 child;
    uint32_t count;
} NestedMachineV1_N2L1;
typedef struct {
    NestedMachineV1_N2L1 child;
    uint32_t remaining;
} NestedMachineV1_N2Root;

typedef struct { uint32_t count; } NestedMachineV1_N4L4;
typedef struct { NestedMachineV1_N4L4 child; uint32_t count; } NestedMachineV1_N4L3;
typedef struct { NestedMachineV1_N4L3 child; uint32_t count; } NestedMachineV1_N4L2;
typedef struct { NestedMachineV1_N4L2 child; uint32_t count; } NestedMachineV1_N4L1;
typedef struct { NestedMachineV1_N4L1 child; uint32_t remaining; } NestedMachineV1_N4Root;

typedef struct { uint32_t count; } NestedMachineV1_N8L8;
typedef struct { NestedMachineV1_N8L8 child; uint32_t count; } NestedMachineV1_N8L7;
typedef struct { NestedMachineV1_N8L7 child; uint32_t count; } NestedMachineV1_N8L6;
typedef struct { NestedMachineV1_N8L6 child; uint32_t count; } NestedMachineV1_N8L5;
typedef struct { NestedMachineV1_N8L5 child; uint32_t count; } NestedMachineV1_N8L4;
typedef struct { NestedMachineV1_N8L4 child; uint32_t count; } NestedMachineV1_N8L3;
typedef struct { NestedMachineV1_N8L3 child; uint32_t count; } NestedMachineV1_N8L2;
typedef struct { NestedMachineV1_N8L2 child; uint32_t count; } NestedMachineV1_N8L1;
typedef struct { NestedMachineV1_N8L1 child; uint32_t remaining; } NestedMachineV1_N8Root;

typedef struct { uint32_t count; } NestedMachineV1_SharedChild;
typedef struct {
    NestedMachineV1_SharedChild child;
    uint32_t remaining;
} NestedMachineV1_SharedA;
typedef struct {
    NestedMachineV1_SharedChild child;
    uint32_t remaining;
} NestedMachineV1_SharedB;

typedef struct { uint32_t count; } NestedMachineV1_OwnedChildA;
typedef struct { uint32_t count; } NestedMachineV1_OwnedChildB;
typedef struct {
    NestedMachineV1_OwnedChildA child;
    uint32_t remaining;
} NestedMachineV1_OwnedA;
typedef struct {
    NestedMachineV1_OwnedChildB child;
    uint32_t remaining;
} NestedMachineV1_OwnedB;

typedef struct { uint32_t count; } NestedMachineV1_PointerChild;
typedef struct {
    NestedMachineV1_PointerChild *child;
    uint32_t remaining;
} NestedMachineV1_PointerRoot;
 ]]

local Flat1 = S:product("NestedMachineV1_Flat1")
local Flat2 = S:product("NestedMachineV1_Flat2")
local Flat4 = S:product("NestedMachineV1_Flat4")
local Flat8 = S:product("NestedMachineV1_Flat8")

local N1L1 = S:product("NestedMachineV1_N1L1")
local N1Root = S:product("NestedMachineV1_N1Root")
local N2L2 = S:product("NestedMachineV1_N2L2")
local N2L1 = S:product("NestedMachineV1_N2L1")
local N2Root = S:product("NestedMachineV1_N2Root")
local N4L4 = S:product("NestedMachineV1_N4L4")
local N4L3 = S:product("NestedMachineV1_N4L3")
local N4L2 = S:product("NestedMachineV1_N4L2")
local N4L1 = S:product("NestedMachineV1_N4L1")
local N4Root = S:product("NestedMachineV1_N4Root")
local N8L8 = S:product("NestedMachineV1_N8L8")
local N8L7 = S:product("NestedMachineV1_N8L7")
local N8L6 = S:product("NestedMachineV1_N8L6")
local N8L5 = S:product("NestedMachineV1_N8L5")
local N8L4 = S:product("NestedMachineV1_N8L4")
local N8L3 = S:product("NestedMachineV1_N8L3")
local N8L2 = S:product("NestedMachineV1_N8L2")
local N8L1 = S:product("NestedMachineV1_N8L1")
local N8Root = S:product("NestedMachineV1_N8Root")

local SharedChild = S:product("NestedMachineV1_SharedChild")
local SharedA = S:product("NestedMachineV1_SharedA")
local SharedB = S:product("NestedMachineV1_SharedB")
local OwnedChildA = S:product("NestedMachineV1_OwnedChildA")
local OwnedChildB = S:product("NestedMachineV1_OwnedChildB")
local OwnedA = S:product("NestedMachineV1_OwnedA")
local OwnedB = S:product("NestedMachineV1_OwnedB")
local PointerChild = S:product("NestedMachineV1_PointerChild")
local PointerRoot = S:product("NestedMachineV1_PointerRoot")

local n1_root_after
local n2_root_after, n2_l1_after
local n4_root_after, n4_l1_after, n4_l2_after, n4_l3_after
local n8_root_after, n8_l1_after, n8_l2_after, n8_l3_after
local n8_l4_after, n8_l5_after, n8_l6_after, n8_l7_after
local shared_a_after, shared_b_after, owned_a_after, owned_b_after
local pointer_after

function Flat1:run(steps)
    self.remaining, self.c1 = steps, 0
    return self:cycle()
end

function Flat1:cycle()
    if self.remaining == 0 then return self.c1 end
    self.remaining = self.remaining - 1
    self.c1 = self.c1 + 1
    return self:cycle()
end

function Flat2:run(steps)
    self.remaining, self.c1, self.c2 = steps, 0, 0
    return self:cycle()
end

function Flat2:cycle()
    if self.remaining == 0 then return self.c2 end
    self.remaining = self.remaining - 1
    self.c1 = self.c1 + 1
    self.c2 = self.c2 + 1
    return self:cycle()
end

function Flat4:run(steps)
    self.remaining, self.c1, self.c2, self.c3, self.c4 = steps, 0, 0, 0, 0
    return self:cycle()
end

function Flat4:cycle()
    if self.remaining == 0 then return self.c4 end
    self.remaining = self.remaining - 1
    self.c1 = self.c1 + 1
    self.c2 = self.c2 + 1
    self.c3 = self.c3 + 1
    self.c4 = self.c4 + 1
    return self:cycle()
end

function Flat8:run(steps)
    self.remaining = steps
    self.c1, self.c2, self.c3, self.c4 = 0, 0, 0, 0
    self.c5, self.c6, self.c7, self.c8 = 0, 0, 0, 0
    return self:cycle()
end

function Flat8:cycle()
    if self.remaining == 0 then return self.c8 end
    self.remaining = self.remaining - 1
    self.c1 = self.c1 + 1
    self.c2 = self.c2 + 1
    self.c3 = self.c3 + 1
    self.c4 = self.c4 + 1
    self.c5 = self.c5 + 1
    self.c6 = self.c6 + 1
    self.c7 = self.c7 + 1
    self.c8 = self.c8 + 1
    return self:cycle()
end

function N1Root:run(steps)
    self.remaining, self.child.count = steps, 0
    return self:cycle()
end

function N1Root:cycle()
    if self.remaining == 0 then return self.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, n1_root_after)
end

function N1Root:after_child() return self:cycle() end

function N1L1:run(root, completed)
    self.count = self.count + 1
    return completed(root)
end

function N2Root:run(steps)
    self.remaining = steps
    self.child.count, self.child.child.count = 0, 0
    return self:cycle()
end

function N2Root:cycle()
    if self.remaining == 0 then return self.child.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, n2_root_after)
end

function N2Root:after_child() return self:cycle() end

function N2L1:run(root, completed)
    self.count = self.count + 1
    return self.child:run(root, n2_l1_after, completed)
end

function N2L1.after_child(root, completed) return completed(root) end

function N2L2:run(root, parent_completed, root_completed)
    self.count = self.count + 1
    return parent_completed(root, root_completed)
end

function N4Root:run(steps)
    self.remaining = steps
    self.child.count = 0
    self.child.child.count = 0
    self.child.child.child.count = 0
    self.child.child.child.child.count = 0
    return self:cycle()
end

function N4Root:cycle()
    if self.remaining == 0 then return self.child.child.child.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, n4_root_after)
end

function N4Root:after_child() return self:cycle() end

function N4L1:run(root, completed)
    self.count = self.count + 1
    return self.child:run(root, n4_l1_after, completed)
end

function N4L1.after_child(root, completed) return completed(root) end

function N4L2:run(root, parent_completed, root_completed)
    self.count = self.count + 1
    return self.child:run(root, n4_l2_after, parent_completed, root_completed)
end

function N4L2.after_child(root, parent_completed, root_completed)
    return parent_completed(root, root_completed)
end

function N4L3:run(root, parent_completed, grandparent_completed, root_completed)
    self.count = self.count + 1
    return self.child:run(root, n4_l3_after, parent_completed,
        grandparent_completed, root_completed)
end

function N4L3.after_child(root, parent_completed, grandparent_completed, root_completed)
    return parent_completed(root, grandparent_completed, root_completed)
end

function N4L4:run(root, parent_completed, grandparent_completed, great_completed, root_completed)
    self.count = self.count + 1
    return parent_completed(root, grandparent_completed, great_completed, root_completed)
end

function N8Root:run(steps)
    self.remaining = steps
    self.child.count = 0
    self.child.child.count = 0
    self.child.child.child.count = 0
    self.child.child.child.child.count = 0
    self.child.child.child.child.child.count = 0
    self.child.child.child.child.child.child.count = 0
    self.child.child.child.child.child.child.child.count = 0
    self.child.child.child.child.child.child.child.child.count = 0
    return self:cycle()
end

function N8Root:cycle()
    if self.remaining == 0 then
        return self.child.child.child.child.child.child.child.child.count
    end
    self.remaining = self.remaining - 1
    return self.child:run(self, n8_root_after)
end

function N8Root:after_child() return self:cycle() end

function N8L1:run(root, k0)
    self.count = self.count + 1
    return self.child:run(root, n8_l1_after, k0)
end

function N8L1.after_child(root, k0) return k0(root) end

function N8L2:run(root, k1, k0)
    self.count = self.count + 1
    return self.child:run(root, n8_l2_after, k1, k0)
end

function N8L2.after_child(root, k1, k0) return k1(root, k0) end

function N8L3:run(root, k2, k1, k0)
    self.count = self.count + 1
    return self.child:run(root, n8_l3_after, k2, k1, k0)
end

function N8L3.after_child(root, k2, k1, k0) return k2(root, k1, k0) end

function N8L4:run(root, k3, k2, k1, k0)
    self.count = self.count + 1
    return self.child:run(root, n8_l4_after, k3, k2, k1, k0)
end

function N8L4.after_child(root, k3, k2, k1, k0) return k3(root, k2, k1, k0) end

function N8L5:run(root, k4, k3, k2, k1, k0)
    self.count = self.count + 1
    return self.child:run(root, n8_l5_after, k4, k3, k2, k1, k0)
end

function N8L5.after_child(root, k4, k3, k2, k1, k0)
    return k4(root, k3, k2, k1, k0)
end

function N8L6:run(root, k5, k4, k3, k2, k1, k0)
    self.count = self.count + 1
    return self.child:run(root, n8_l6_after, k5, k4, k3, k2, k1, k0)
end

function N8L6.after_child(root, k5, k4, k3, k2, k1, k0)
    return k5(root, k4, k3, k2, k1, k0)
end

function N8L7:run(root, k6, k5, k4, k3, k2, k1, k0)
    self.count = self.count + 1
    return self.child:run(root, n8_l7_after, k6, k5, k4, k3, k2, k1, k0)
end

function N8L7.after_child(root, k6, k5, k4, k3, k2, k1, k0)
    return k6(root, k5, k4, k3, k2, k1, k0)
end

function N8L8:run(root, k7, k6, k5, k4, k3, k2, k1, k0)
    self.count = self.count + 1
    return k7(root, k6, k5, k4, k3, k2, k1, k0)
end

function SharedChild:run(root, completed)
    self.count = self.count + 1
    return completed(root)
end

function SharedA:run(steps)
    self.remaining, self.child.count = steps, 0
    return self:cycle()
end

function SharedA:cycle()
    if self.remaining == 0 then return self.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, shared_a_after)
end

function SharedA:after_child() return self:cycle() end

function SharedB:run(steps)
    self.remaining, self.child.count = steps, 0
    return self:cycle()
end

function SharedB:cycle()
    if self.remaining == 0 then return self.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, shared_b_after)
end

function SharedB:after_child() return self:cycle() end

function OwnedChildA:run(root, completed)
    self.count = self.count + 1
    return completed(root)
end

function OwnedChildB:run(root, completed)
    self.count = self.count + 1
    return completed(root)
end

function OwnedA:run(steps)
    self.remaining, self.child.count = steps, 0
    return self:cycle()
end

function OwnedA:cycle()
    if self.remaining == 0 then return self.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, owned_a_after)
end

function OwnedA:after_child() return self:cycle() end

function OwnedB:run(steps)
    self.remaining, self.child.count = steps, 0
    return self:cycle()
end

function OwnedB:cycle()
    if self.remaining == 0 then return self.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, owned_b_after)
end

function OwnedB:after_child() return self:cycle() end

function PointerRoot:run(steps)
    self.remaining, self.child.count = steps, 0
    return self:cycle()
end

function PointerRoot:cycle()
    if self.remaining == 0 then return self.child.count end
    self.remaining = self.remaining - 1
    return self.child:run(self, pointer_after)
end

function PointerRoot:after_child() return self:cycle() end

function PointerChild:run(root, completed)
    self.count = self.count + 1
    return completed(root)
end

n1_root_after = N1Root.after_child
n2_root_after, n2_l1_after = N2Root.after_child, N2L1.after_child
n4_root_after, n4_l1_after = N4Root.after_child, N4L1.after_child
n4_l2_after, n4_l3_after = N4L2.after_child, N4L3.after_child
n8_root_after, n8_l1_after = N8Root.after_child, N8L1.after_child
n8_l2_after, n8_l3_after = N8L2.after_child, N8L3.after_child
n8_l4_after, n8_l5_after = N8L4.after_child, N8L5.after_child
n8_l6_after, n8_l7_after = N8L6.after_child, N8L7.after_child
shared_a_after, shared_b_after = SharedA.after_child, SharedB.after_child
owned_a_after, owned_b_after = OwnedA.after_child, OwnedB.after_child
pointer_after = PointerRoot.after_child

S:seal()

return {
    Flat1 = Flat1, Flat2 = Flat2, Flat4 = Flat4, Flat8 = Flat8,
    Nested1 = N1Root, Nested2 = N2Root, Nested4 = N4Root, Nested8 = N8Root,
    SharedA = SharedA, SharedB = SharedB,
    OwnedA = OwnedA, OwnedB = OwnedB,
    PointerChild = PointerChild, PointerRoot = PointerRoot,
}

