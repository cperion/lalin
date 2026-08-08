local path = arg[1]
local chunk = assert(loadfile(path))
local r = { chunk() }
for i = 1, #r do io.write(tostring(r[i])) if i < #r then io.write("\t") end end
io.write("\n")
