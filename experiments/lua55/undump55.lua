-- undump55.lua -- read Lua 5.5 precompiled chunks, on LuaJIT.
--
-- This is the frontend for a 5.5 -> CPS -> LuaJIT pipeline. It is NOT a
-- bytecode-to-bytecode conversion: LuaJIT cannot load a 5.5 chunk, the two
-- instruction sets are unrelated. What this buys is prototypes, constants and
-- upvalue descriptors already resolved, so no 5.5 parser is needed.
--
-- Format per ldump.c (5.5.0):
--   header: "\x1bLua" VERSION(0x55) FORMAT(0) "\x19\x93\r\n\x1a\n"
--           sizeof(int) + LUAC_INT(-0x5678)
--           sizeof(Instruction) + LUAC_INST(0x12345678)
--           sizeof(lua_Integer) + LUAC_INT
--           sizeof(lua_Number) + LUAC_NUM(-370.5)
--   then: sizeupvalues byte, then the main Proto
--
-- Integers are MSB varints. Code and abslineinfo are alignment-padded.

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[ typedef struct { const uint8_t *p; int32_t i, len; } Rd; ]]

local OPNAMES = {
  [0]="MOVE","LOADI","LOADF","LOADK","LOADKX","LOADFALSE","LFALSESKIP","LOADTRUE",
  "LOADNIL","GETUPVAL","SETUPVAL","GETTABUP","GETTABLE","GETI","GETFIELD",
  "SETTABUP","SETTABLE","SETI","SETFIELD","NEWTABLE","SELF","ADDI","ADDK","SUBK",
  "MULK","MODK","POWK","DIVK","IDIVK","BANDK","BORK","BXORK","SHLI","SHRI","ADD",
  "SUB","MUL","MOD","POW","DIV","IDIV","BAND","BOR","BXOR","SHL","SHR","MMBIN",
  "MMBINI","MMBINK","UNM","BNOT","NOT","LEN","CONCAT","CLOSE","TBC","JMP","EQ",
  "LT","LE","EQK","EQI","LTI","LEI","GTI","GEI","TEST","TESTSET","CALL","TAILCALL",
  "RETURN","RETURN0","RETURN1","FORLOOP","FORPREP","TFORPREP","TFORCALL","TFORLOOP",
  "SETLIST","CLOSURE","VARARG","GETVARG","ERRNNIL","VARARGPREP","EXTRAARG",
}

local OPCODE_CLASSES = {}
for opcode, name in pairs(OPNAMES) do
  local class = { opcode = opcode, name = name }
  class.__index = class
  OPCODE_CLASSES[opcode] = class
end

local function constant_class(name)
  local class = { name = name }
  class.__index = class
  return class
end

local CONSTANT_CLASSES = {
  Integer = constant_class("IntegerConstant"),
  Float = constant_class("FloatConstant"),
  ShortString = constant_class("ShortStringConstant"),
  LongString = constant_class("LongStringConstant"),
  Nil = constant_class("NilConstant"),
  False = constant_class("FalseConstant"),
  True = constant_class("TrueConstant"),
}

local R = {}

-- primitive reads -----------------------------------------------------------
function R:byte()
  local b = self.p[self.i]; self.i = self.i + 1; return b
end

function R:block(n)
  local s = ffi.string(self.p + self.i, n); self.i = self.i + n; return s
end

-- MSB varint: continuation bit is 0x80 on all but the last byte
function R:varint()
  local x = 0
  while true do
    local b = self:byte()
    x = x * 128 + bit.band(b, 0x7f)
    if bit.band(b, 0x80) == 0 then return x end
  end
end

R.size = R.varint

function R:int() return self:varint() end

function R:align(a)
  local pad = a - (self.i % a)
  if pad < a then self.i = self.i + pad end
end

function R:u32()
  self:align(4)
  local v = ffi.cast("const uint32_t*", self.p + self.i)[0]
  self.i = self.i + 4
  return v
end

-- float constants are NOT alignment-padded in the dump, so read via bytes
function R:number()
  local s = self:block(8)
  return ffi.cast("const double*", s)[0]
end

-- integer constants are zigzag-coded MSB varints (ldump.c dumpInteger):
--   non-negative x -> 2x, negative x -> -2x-1; decode exactly in 64-bit
function R:integer()
  local x = ffi.new("uint64_t[1]")
  while true do
    local b = self:byte()
    x[0] = x[0] * 128 + bit.band(b, 0x7f)
    if bit.band(b, 0x80) == 0 then break end
  end
  local u = x[0]
  local half = u / 2
  if u % 2 == 1 then
    return -ffi.cast("int64_t", half) - 1   -- negative
  end
  return ffi.cast("int64_t", half)
end

-- strings are interned across the chunk: index 0 means "new string"
function R:str(pool)
  local n = self:size()
  if n == 0 then return nil end
  local idx = self:varint()
  if n == 0 then return nil end
  return idx
end

local Rd = ffi.metatype("Rd", { __index = R })

-- string reading needs the pool, so it lives outside the metatype ------------
local function readString(r, pool)
  local sz = r:varint()
  if sz == 0 then
    local idx = r:varint()
    if idx == 0 then return nil end
    return pool[idx]
  end
  local s = r:block(sz - 1)
  r.i = r.i + 1                       -- trailing '\0'
  pool[#pool + 1] = s
  return s
end

-- instruction decoding ------------------------------------------------------
local band, rshift = bit.band, bit.rshift
local function decode(ins)
  local op = band(ins, 0x7f)
  local class = assert(OPCODE_CLASSES[op], "unknown Lua 5.5 opcode " .. tostring(op))
  return setmetatable({
    op   = op,
    name = class.name,
    A    = band(rshift(ins, 7), 0xff),
    k    = band(rshift(ins, 15), 1),
    B    = band(rshift(ins, 16), 0xff),
    C    = band(rshift(ins, 24), 0xff),
    vB   = band(rshift(ins, 16), 0x3f),
    vC   = band(rshift(ins, 22), 0x3ff),
    sB   = band(rshift(ins, 16), 0xff) - 127,
    sC   = band(rshift(ins, 24), 0xff) - 127,
    Bx   = band(rshift(ins, 15), 0x1ffff),
    sBx  = band(rshift(ins, 15), 0x1ffff) - 65535,
    Ax   = band(rshift(ins, 7), 0x1ffffff),
    sJ   = band(rshift(ins, 7), 0x1ffffff) - 16777215,
    raw  = ins,
  }, class)
end

-- prototype -----------------------------------------------------------------
local readProto

readProto = function(r, pool, parentSource)
  local f = {}
  f.linedefined     = r:int()
  f.lastlinedefined = r:int()
  f.numparams       = r:byte()
  f.flag            = r:byte()
  f.maxstacksize    = r:byte()

  -- code
  local ncode = r:int()
  r:align(4)
  f.code = {}
  for i = 1, ncode do
    local ins = ffi.cast("const uint32_t*", r.p + r.i)[0]
    r.i = r.i + 4
    f.code[i] = decode(ins)
  end

  -- constants
  local nk = r:int()
  f.k = {}
  for i = 1, nk do
    local tt = r:byte()
    if tt == 0x03 then                 -- LUA_VNUMINT
      f.k[i] = setmetatable({ t = "int", v = r:integer() }, CONSTANT_CLASSES.Integer)
    elseif tt == 0x13 then             -- LUA_VNUMFLT
      f.k[i] = setmetatable({ t = "flt", v = r:number() }, CONSTANT_CLASSES.Float)
    elseif tt == 0x04 then             -- LUA_VSHRSTR
      f.k[i] = setmetatable({ t = "str", v = readString(r, pool) }, CONSTANT_CLASSES.ShortString)
    elseif tt == 0x14 then             -- LUA_VLNGSTR
      f.k[i] = setmetatable({ t = "str", v = readString(r, pool) }, CONSTANT_CLASSES.LongString)
    elseif tt == 0x00 then
      f.k[i] = setmetatable({ t = "nil" }, CONSTANT_CLASSES.Nil)
    elseif tt == 0x01 then
      f.k[i] = setmetatable({ t = "false" }, CONSTANT_CLASSES.False)
    elseif tt == 0x11 then
      f.k[i] = setmetatable({ t = "true" }, CONSTANT_CLASSES.True)
    else
      error("unsupported Lua 5.5 constant tag " .. tostring(tt))
    end
  end

  -- upvalues
  local nup = r:int()
  f.upvals = {}
  for i = 1, nup do
    f.upvals[i] = { instack = r:byte(), idx = r:byte(), kind = r:byte() }
  end

  -- nested protos
  local np = r:int()
  f.protos = {}
  for i = 1, np do f.protos[i] = readProto(r, pool, parentSource) end

  f.source = readString(r, pool) or parentSource

  -- debug
  local nline = r:int()
  r.i = r.i + nline                                   -- lineinfo: signed bytes
  local nabs = r:int()
  if nabs > 0 then r:align(4); r.i = r.i + nabs * 8 end
  local nloc = r:int()
  f.locals = {}
  for i = 1, nloc do
    f.locals[i] = { name = readString(r, pool), startpc = r:int(), endpc = r:int() }
  end
  local nupn = r:int()
  for i = 1, nupn do
    local nm = readString(r, pool)
    if f.upvals[i] then f.upvals[i].name = nm end
  end
  return f
end

-- entry ---------------------------------------------------------------------
local M = {}

function M.undump(bytes)
  -- NB: do NOT initialize the VLA from the string. LuaJIT's string->array
  -- copy path (lj_cconv_ct_tv) memcpy's str->len+1 bytes when the array is a
  -- VLA (d->size == 0), writing one byte past the allocation whenever
  -- #bytes == n. That corrupts the GC heap. Allocate, then copy exactly.
  -- The decode boundary runs in the interpreter only. When JIT-compiled, the
  -- trace drops the cdata GC reference after its address escapes into r.p, so
  -- a GC step inside readProto can collect the buffer and leave r.p dangling.
  local buf = ffi.new("uint8_t[?]", #bytes)
  local buf = ffi.new("uint8_t[?]", #bytes)
  ffi.copy(buf, bytes, #bytes)
  local r = Rd()
  r.p, r.i, r.len = buf, 0, #bytes

  assert(r:block(4) == "\27Lua", "not a Lua chunk")
  local ver = r:byte()
  assert(ver == 0x55, ("expected 5.5 (0x55), got 0x%02x"):format(ver))
  local fmt = r:byte()
  assert(fmt == 0, "unsupported format")
  assert(r:block(6) == "\25\147\r\n\26\n", "corrupt header")

  local szint = r:byte();  r.i = r.i + szint          -- LUAC_INT check
  local szins = r:byte();  r.i = r.i + szins          -- LUAC_INST check
  local szlint = r:byte(); r.i = r.i + szlint         -- lua_Integer check
  local sznum = r:byte();  r.i = r.i + sznum          -- lua_Number check

  local nupv = r:byte()                                -- upvalues of main
  local pool = {}
  local main = readProto(r, pool, "?")
  main.nupvalues = nupv
  return main, r.i, #bytes
end

M.OPNAMES = OPNAMES
M.OPCODE_CLASSES = OPCODE_CLASSES
M.CONSTANT_CLASSES = CONSTANT_CLASSES
require("jit").off(M.undump, true)
return M
