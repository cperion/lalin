local U = require("experiments.lua55.undump55")
local path = arg[1] or (debug.getinfo(1, "S").source:match("^@(.*/)") or "") .. "sample_5.5.luac"
local f = io.open(path, "rb")
assert(f, "cannot open " .. path)
local bytes = f:read("*a"); f:close()
local ok, main, consumed, total = pcall(U.undump, bytes)
if not ok then print("ERROR:", main) os.exit(1) end
print(("parsed %d/%d bytes  (%s)"):format(consumed, total, consumed==total and "COMPLETE" or "INCOMPLETE"))
local function dump(p, name, ind)
  ind = ind or ""
  print(("%s%s: params=%d stack=%d code=%d k=%d up=%d protos=%d src=%s")
    :format(ind, name, p.numparams, p.maxstacksize, #p.code, #p.k, #p.upvals, #p.protos, tostring(p.source)))
  for i,ins in ipairs(p.code) do
    print(("%s  %3d  %-12s A=%-3d B=%-3d C=%-3d k=%d"):format(ind, i-1, ins.name, ins.A, ins.B, ins.C, ins.k))
  end
  for i,k in ipairs(p.k) do print(("%s  K[%d] = %s %s"):format(ind, i-1, k.t, tostring(k.v))) end
  for i,q in ipairs(p.protos) do dump(q, "proto#"..i, ind.."    ") end
end
dump(main, "main")
