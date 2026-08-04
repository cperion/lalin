local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[
typedef struct { double value; } AdtBench_Num;
typedef struct { uint32_t left; uint32_t right; uint8_t op; } AdtBench_Binop;
void *malloc(size_t size);
void free(void *ptr);
]]

local C = ffi.C
local band, bor, rshift = bit.band, bit.bor, bit.rshift
local CHUNK_SHIFT = 16
local CHUNK_SIZE = 2 ^ CHUNK_SHIFT
local CHUNK_MASK = CHUNK_SIZE - 1
local MAX_CHUNKS = 256
local INDEX_MASK = 0x00ffffff
local NUM_TAG = 1
local BINOP_TAG = 2
local NUM_BASE = NUM_TAG * 0x01000000
local BINOP_BASE = BINOP_TAG * 0x01000000
local NUM_BYTES = ffi.sizeof("AdtBench_Num") * CHUNK_SIZE
local BINOP_BYTES = ffi.sizeof("AdtBench_Binop") * CHUNK_SIZE

local function checked_malloc(ctype, bytes)
  local raw = C.malloc(bytes)
  if raw == nil or raw == ffi.NULL then
    error("adt arena experiment: malloc failed", 2)
  end
  ffi.fill(raw, bytes, 0)
  return ffi.gc(ffi.cast(ctype, raw), C.free)
end

local function new()
  local num_dir = ffi.new("AdtBench_Num *[?]", MAX_CHUNKS)
  local binop_dir = ffi.new("AdtBench_Binop *[?]", MAX_CHUNKS)
  local num_anchor, binop_anchor = {}, {}
  local num_n, binop_n = 0, 0
  local allocated_bytes = 0

  local function new_num_chunk(ci)
    if ci >= MAX_CHUNKS then error("Num pool exhausted 24-bit index", 2) end
    if num_anchor[ci] ~= nil then return end
    local p = checked_malloc("AdtBench_Num *", NUM_BYTES)
    num_anchor[ci], num_dir[ci] = p, p
    allocated_bytes = allocated_bytes + NUM_BYTES
  end

  local function new_binop_chunk(ci)
    if ci >= MAX_CHUNKS then error("Binop pool exhausted 24-bit index", 2) end
    if binop_anchor[ci] ~= nil then return end
    local p = checked_malloc("AdtBench_Binop *", BINOP_BYTES)
    binop_anchor[ci], binop_dir[ci] = p, p
    allocated_bytes = allocated_bytes + BINOP_BYTES
  end

  local M = {}

  function M.Num(value)
    local i = num_n
    if band(i, CHUNK_MASK) == 0 then new_num_chunk(rshift(i, CHUNK_SHIFT)) end
    num_n = i + 1
    local s = num_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)
    s.value = value
    return NUM_BASE + i
  end

  function M.Binop(left, op, right)
    local i = binop_n
    if band(i, CHUNK_MASK) == 0 then new_binop_chunk(rshift(i, CHUNK_SHIFT)) end
    binop_n = i + 1
    local s = binop_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)
    s.left, s.op, s.right = left, op, right
    return BINOP_BASE + i
  end

  function M.build_chain(total)
    local Num, Binop = M.Num, M.Binop
    local root = Num(1)
    local made = 1
    while made + 2 <= total do
      local leaf = Num(band(made, 15) + 1)
      root = Binop(root, 0, leaf)
      made = made + 2
    end
    return root, made
  end

  function M.build_tree(depth)
    local Num, Binop = M.Num, M.Binop
    local function build(d, seed)
      if d == 0 then return Num(band(seed, 15) + 1) end
      local left = build(d - 1, seed * 2)
      local right = build(d - 1, seed * 2 + 1)
      return Binop(left, 0, right)
    end
    return build(depth, 1), 2 ^ (depth + 1) - 1
  end

  local function eval(h)
    local tag = rshift(h, 24)
    local i = band(h, INDEX_MASK)
    if tag == NUM_TAG then
      return (num_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)).value
    end
    local s = binop_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)
    return eval(s.left) + eval(s.right)
  end
  M.eval = eval

  -- Scalarize both child handles before recursion. No interior cdata pointer is
  -- live across a recursive call; this tests the proposal's strict pointer rule.
  local function eval_scalar(h)
    local tag = rshift(h, 24)
    local i = band(h, INDEX_MASK)
    local ci, si = rshift(i, CHUNK_SHIFT), band(i, CHUNK_MASK)
    if tag == NUM_TAG then return num_dir[ci][si].value end
    local left = binop_dir[ci][si].left
    local right = binop_dir[ci][si].right
    return eval_scalar(left) + eval_scalar(right)
  end
  M.eval_scalar = eval_scalar

  -- Match the proposal's dense tag-indexed method vtable exactly.
  local eval_vtable
  local vtable = {}
  vtable[NUM_TAG] = function(i)
    return num_dir[rshift(i, CHUNK_SHIFT)][band(i, CHUNK_MASK)].value
  end
  vtable[BINOP_TAG] = function(i)
    local ci, si = rshift(i, CHUNK_SHIFT), band(i, CHUNK_MASK)
    local left = binop_dir[ci][si].left
    local right = binop_dir[ci][si].right
    return eval_vtable(left) + eval_vtable(right)
  end
  eval_vtable = function(h)
    return vtable[rshift(h, 24)](band(h, INDEX_MASK))
  end
  M.eval_vtable = eval_vtable

  local function walk_num_sum(h)
    local tag = rshift(h, 24)
    local i = band(h, INDEX_MASK)
    if tag == NUM_TAG then
      return (num_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)).value
    end
    local s = binop_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)
    return walk_num_sum(s.left) + walk_num_sum(s.right)
  end
  M.walk_num_sum = walk_num_sum

  function M.sum_nums()
    local total = 0
    for i = 0, num_n - 1 do
      local s = num_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)
      total = total + s.value
    end
    return total
  end

  function M.mutate_binops()
    local checksum = 0
    for i = 0, binop_n - 1 do
      local s = binop_dir[rshift(i, CHUNK_SHIFT)] + band(i, CHUNK_MASK)
      local op = band(rshift(s.left, 24) + rshift(s.right, 24), 3)
      s.op = op
      checksum = checksum + op
    end
    return checksum
  end

  function M.counts() return num_n, binop_n end
  function M.allocated_bytes() return allocated_bytes end
  function M.tag(h) return rshift(h, 24) end

  function M.reset()
    num_n, binop_n = 0, 0
  end

  function M.release()
    for ci = 0, MAX_CHUNKS - 1 do
      local p = num_anchor[ci]
      if p ~= nil then
        ffi.gc(p, nil)
        C.free(p)
        num_anchor[ci] = nil
        num_dir[ci] = ffi.NULL
      end
      p = binop_anchor[ci]
      if p ~= nil then
        ffi.gc(p, nil)
        C.free(p)
        binop_anchor[ci] = nil
        binop_dir[ci] = ffi.NULL
      end
    end
    num_n, binop_n, allocated_bytes = 0, 0, 0
  end

  return M
end

return {
  new = new,
  name = "arena",
  tags = { Num = NUM_TAG, Binop = BINOP_TAG },
}
