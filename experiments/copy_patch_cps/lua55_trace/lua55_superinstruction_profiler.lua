-- lua55_superinstruction_profiler: find the UNIVERSAL bytecode shapes the
-- fixed Lua 5.5 compiler emits, across a diverse corpus of real Lua files.
-- The vocabulary is chosen from language-level idioms (compiler emission is
-- deterministic per source construct), NOT from any single workload.
package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path
local Undump = require("experiments.lua55.undump55")

local STOCK_LUAC = "/tmp/lua-5.5.0/src/luac"
local CORPUS_DIRS = {
  "lua", "experiments", "demo", "tests", "museum",
}
local EXCLUDE = { "target" }

-- collect corpus files
local files = {}
local function walk(dir)
  local pipe = io.popen("find " .. dir .. " -name '*.lua' 2>/dev/null")
  for path in pipe:lines() do
    local skip = false
    for _, ex in ipairs(EXCLUDE) do
      if path:find("/" .. ex .. "/", 1, true) then skip = true break end
    end
    if not skip then files[#files + 1] = path end
  end
  pipe:close()
end
for _, d in ipairs(CORPUS_DIRS) do
  if io.popen("test -d " .. d .. " && echo yes"):read() == "yes" then walk(d) end
end
print("corpus files:", #files)

-- compile each file once to a temp bytecode; undump; scan.
local ok_files, fail_files = 0, 0
local bigram_files = {}    -- pattern -> set of files
local bigram_count = {}    -- pattern -> total occurrences
local bigram_hot = {}      -- pattern -> occurrences inside loop bodies
local trigram_files = {}
local trigram_count = {}
local opcode_files = {}    -- single opcode -> files (universality baseline)
local opcode_count = {}

-- read-modify-write idiom: a read (GETI/GETFIELD/GETTABLE/GETUPVAL/GETTABUP)
-- whose result feeds an arithmetic op that writes back to the SAME register
-- via SETI/SETFIELD/SETTABLE/SETUPVAL/SETTABUP within a short window.
local RMW = {}
local RMW_count = {}
local FORBODIES = {}   -- numeric-for body opcode sets (opcode -> files)
local FORBODY_OPS = {}
local CALLARGS = {}    -- arg-assembly bigrams before CALL (pattern -> files/count)

local function scan_proto(f, file, in_loop)
  local code = f.code
  local n = #code
  local hot = {}
  for i = 1, n do
    local ins = code[i]
    local name = ins.name
    opcode_files[name] = opcode_files[name] or {}
    opcode_files[name][file] = true
    opcode_count[name] = (opcode_count[name] or 0) + 1
    hot[i] = in_loop or false
    -- FORLOOP back-edge: the 17-bit Bx field holds the (positive) back
    -- distance; the VM does `pc -= Bx` after advancing, so the body is
    -- [i + 1 - Bx .. i]
    if name == "FORLOOP" then
      local target = i + 1 - ins.Bx
      if target >= 1 and target < i then
        for j = target, i do hot[j] = true end
        for j = target, i do
          local bname = code[j].name
          FORBODIES[bname] = FORBODIES[bname] or {}
          FORBODIES[bname][file] = true
          FORBODY_OPS[bname] = (FORBODY_OPS[bname] or 0) + 1
        end
      end
    end
  end
  -- read-modify-write windows
  for i = 1, n do
    local ins = code[i]
    local name = ins.name
    local rd = name == "GETI" or name == "GETFIELD" or name == "GETTABLE"
      or name == "GETUPVAL" or name == "GETTABUP"
    if rd then
      for w = i + 1, math.min(i + 6, n) do
        local wname = code[w].name
        local wr = wname == "SETI" or wname == "SETFIELD" or wname == "SETTABLE"
          or wname == "SETUPVAL" or wname == "SETTABUP"
        if wr then
          local pat = name .. "->" .. wname
          RMW[pat] = RMW[pat] or {}
          RMW[pat][file] = true
          RMW_count[pat] = (RMW_count[pat] or 0) + 1
          break
        end
        if wname == "CALL" or wname == "TAILCALL" or wname == "RETURN"
          or wname == "RETURN0" or wname == "RETURN1" then break end
      end
    end
  end
  -- call arg assembly: the ops immediately before CALL (callee at R[A])
  for i = 1, n do
    local name = code[i].name
    if name == "CALL" or name == "TAILCALL" then
      local j = i - 1
      while j >= 1 and i - j <= 3 do
        local pn = code[j].name
        if pn == "JMP" or pn == "RETURN" then break end
        CALLARGS[pn .. " CALL"] = CALLARGS[pn .. " CALL"] or {}
        CALLARGS[pn .. " CALL"][file] = true
        j = j - 1
      end
    end
  end
  for i = 1, n do
    local name = code[i].name
    if i < n then
      local b = code[i].name .. " " .. code[i + 1].name
      bigram_files[b] = bigram_files[b] or {}
      bigram_files[b][file] = true
      bigram_count[b] = (bigram_count[b] or 0) + 1
      if hot[i] then bigram_hot[b] = (bigram_hot[b] or 0) + 1 end
    end
    if i < n - 1 then
      local t = code[i].name .. " " .. code[i + 1].name .. " " .. code[i + 2].name
      trigram_files[t] = trigram_files[t] or {}
      trigram_files[t][file] = true
      trigram_count[t] = (trigram_count[t] or 0) + 1
    end
  end
  for _, p in ipairs(f.protos or {}) do scan_proto(p, file, in_loop) end
end

local tmp = "/tmp/lua55_prof.luac"
for _, path in ipairs(files) do
  local err = "/tmp/lua55_prof.err"
  os.remove(tmp); os.remove(err)
  local ok, why, status = os.execute(("%s -o %s %s 2>%s"):format(STOCK_LUAC, tmp, path, err))
  if ok and status == 0 then
    local fh = assert(io.open(tmp, "rb"))
    local bytes = fh:read("*a"); fh:close()
    local ok2, main = pcall(Undump.undump, bytes)
    if ok2 then
      scan_proto(main, path, false)
      ok_files = ok_files + 1
    else
      fail_files = fail_files + 1
    end
  else
    fail_files = fail_files + 1
  end
end
os.remove(tmp)
print(("compiled+scanned %d, failed %d"):format(ok_files, fail_files))

local function sorted(t, keyfn)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return keyfn(a, b) end)
  return out
end

-- universality score: files containing the pattern
local function nfiles(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

print("\n=== most universal single opcodes (files containing) ===")
local ops = sorted(opcode_files, function(a, b) return nfiles(opcode_files[b]) < nfiles(opcode_files[a]) end)
for i = 1, 25 do
  local op = ops[i]
  print(("%-12s files=%4d count=%6d"):format(op, nfiles(opcode_files[op]), opcode_count[op]))
end

print("\n=== most universal BIGRAMS (files containing; tie-break total) ===")
local bs = sorted(bigram_files, function(a, b)
  local fa, fb = nfiles(bigram_files[a]), nfiles(bigram_files[b])
  if fa ~= fb then return fb < fa end
  return bigram_count[b] < bigram_count[a]
end)
for i = 1, 30 do
  local b = bs[i]
  print(("%-28s files=%4d count=%6d hot=%6d"):format(b, nfiles(bigram_files[b]), bigram_count[b], bigram_hot[b] or 0))
end

print("\n=== read-modify-write idioms (read -> write within 6 ops) ===")
local rws = sorted(RMW, function(a, b)
  local fa, fb = nfiles(RMW[a]), nfiles(RMW[b])
  if fa ~= fb then return fb < fa end
  return RMW_count[b] < RMW_count[a]
end)
for i = 1, 12 do
  local r = rws[i]
  print(("%-24s files=%4d count=%6d"):format(r, nfiles(RMW[r]), RMW_count[r]))
end

print("\n=== numeric-for body ops (all opcodes appearing inside for-loop bodies) ===")
local fbs = sorted(FORBODIES, function(a, b)
  local fa, fb = nfiles(FORBODIES[a]), nfiles(FORBODIES[b])
  if fa ~= fb then return fb < fa end
  return FORBODY_OPS[b] < FORBODY_OPS[a]
end)
for i = 1, 15 do
  local b = fbs[i]
  print(("%-12s files=%4d count=%6d"):format(b, nfiles(FORBODIES[b]), FORBODY_OPS[b]))
end

print("\n=== call argument assembly (opcode immediately before CALL) ===")
local cas = sorted(CALLARGS, function(a, b) return nfiles(CALLARGS[b]) < nfiles(CALLARGS[a]) end)
for i = 1, 10 do
  local c = cas[i]
  print(("%-20s files=%4d"):format(c, nfiles(CALLARGS[c])))
end

print("\n=== hot bigrams (inside numeric-for loop bodies) ===")
local hbs = sorted(bigram_hot, function(a, b)
  local fa, fb = nfiles(bigram_files[a]), nfiles(bigram_files[b])
  if fa ~= fb then return fb < fa end
  return bigram_hot[b] < bigram_hot[a]
end)
for i = 1, 15 do
  local b = hbs[i]
  print(("%-28s files=%4d hot=%6d"):format(b, nfiles(bigram_files[b]), bigram_hot[b] or 0))
end

print("\n=== most universal TRIGRAMS (files containing; tie-break total) ===")
local ts = sorted(trigram_files, function(a, b)
  local fa, fb = nfiles(trigram_files[a]), nfiles(trigram_files[b])
  if fa ~= fb then return fb < fa end
  return trigram_count[b] < trigram_count[a]
end)
for i = 1, 25 do
  local t = ts[i]
  print(("%-42s files=%4d count=%6d"):format(t, nfiles(trigram_files[t]), trigram_count[t]))
end
