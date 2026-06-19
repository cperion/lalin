package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local pvm = require("moonlift.pvm")

-- An unrelated fragment in the same Lua session must not become an ambient
-- compile dependency.
local unrelated = moon.region [[
unrelated(x: i32; ok(y: i32))
entry start()
    jump ok(y = x - 1000)
end
end
]]
assert(unrelated)

local inner = moon.region [[
inner(x: i32; ok(y: i32))
entry start()
    jump ok(y = x + 1)
end
end
]]

local outer = moon.region { inner = inner } [[
outer(x: i32; ok(y: i32))
entry start()
    emit @{inner}(x; ok = done)
end
block done(y: i32)
    jump ok(y = y)
end
end
]]

local run = moon.func { outer = outer } [[
func run(x: i32): i32
    return region: i32
    entry start()
        emit @{outer}(x; ok = done)
    end
    block done(y: i32)
        yield y
    end
    end
end
]]

local bundle = moon.bundle("explicit_region_dependency_closure")
bundle:pack(run)
local module = bundle:to_asdl()
local names = {}
local Tr = bundle.session.T.MoonTree
local O = bundle.session.T.MoonOpen
for i = 1, #module.items do
    local item = module.items[i]
    if pvm.classof(item) == Tr.ItemRegionFrag then
        local name = item.frag.name
        if pvm.classof(name) == O.NameRefText then name = name.text end
        names[name] = true
    end
end
assert(names.inner and names.outer, "bundle should contain explicit inner and outer region deps as module items")
assert(not names.unrelated, "bundle must not contain unrelated ambient region deps")

local compiled = run:compile()
assert(compiled(40) == 41)
compiled:free()

return "explicit region dependency closure ok"
