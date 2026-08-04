local bit = require("bit")
local band = bit.band

local NUM_TAG = 1
local BINOP_TAG = 2

local function new(options)
  options = options or {}
  local indexed = not not options.indexed
  local nums = indexed and {} or nil
  local binops = indexed and {} or nil
  local num_n, binop_n = 0, 0
  local M = {}

  function M.Num(value)
    local s = { tag = NUM_TAG, value = value }
    num_n = num_n + 1
    if indexed then nums[num_n] = s end
    return s
  end

  function M.Binop(left, op, right)
    local s = { tag = BINOP_TAG, left = left, op = op, right = right }
    binop_n = binop_n + 1
    if indexed then binops[binop_n] = s end
    return s
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

  local function eval(s)
    if s.tag == NUM_TAG then return s.value end
    return eval(s.left) + eval(s.right)
  end
  M.eval = eval
  M.eval_scalar = eval

  local eval_vtable
  local vtable = {}
  vtable[NUM_TAG] = function(s) return s.value end
  vtable[BINOP_TAG] = function(s)
    return eval_vtable(s.left) + eval_vtable(s.right)
  end
  eval_vtable = function(s) return vtable[s.tag](s) end
  M.eval_vtable = eval_vtable
  M.walk_num_sum = eval

  function M.sum_nums()
    if not indexed then error("direct sweep requires table_bucket backend", 2) end
    local total = 0
    for i = 1, num_n do total = total + nums[i].value end
    return total
  end

  function M.mutate_binops()
    if not indexed then error("direct sweep requires table_bucket backend", 2) end
    local checksum = 0
    for i = 1, binop_n do
      local s = binops[i]
      local op = band(s.left.tag + s.right.tag, 3)
      s.op = op
      checksum = checksum + op
    end
    return checksum
  end

  function M.counts() return num_n, binop_n end
  function M.allocated_bytes() return 0 end
  function M.tag(s) return s.tag end

  function M.reset()
    nums = indexed and {} or nil
    binops = indexed and {} or nil
    num_n, binop_n = 0, 0
  end

  function M.release() M.reset() end

  return M
end

return { new = new, name = "table" }
