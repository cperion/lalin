package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path
local moon = require('moonlift')

local chunk = moon.loadstring([==[
local r = region(x: i32; ok(y: i32))
entry start()
  jump ok(y = x + 1)
end
end

local h = func(x: i32): i32 end
local f = h({ r = r })[[
  return region: i32
  entry start()
    emit @{r}(x; ok = ok)
  end
  block ok(y: i32)
    yield y
  end
  end
]]
return f
]==], 'func_header_body_region_splices.mlua')

local f = chunk()
local c = f:compile()
assert(c(41) == 42)
c:free()
print('ok func header body region splices')
