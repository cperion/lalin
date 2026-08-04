package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Region continuation wiring correctness: the typechecker resolves every jump
-- and region-call wire against the enclosing block/cont tables and the callee
-- protocol, so miswires fail with typed issues instead of silent behavior or
-- obscure lowering crashes.

local lalin = require("lalin")

local function compile_ok(src)
  local decls = assert(lalin.loadstring(src, "@wire_neg.lln"))
  local ok, err = pcall(function()
    lalin.compile_c_gcc("wire_neg", decls, { gcc_opts = { opt = 3, out_dir = "target/test_wire_neg" } })
  end)
  return ok, ok and "" or tostring(err)
end

local negatives = {
  {
    name = "wire to nonexistent block",
    src = [[
region Inner(; yes)
  entry start() jump yes end
end
fn main() [i32]
  entry start() call Inner(; yes = ghost(x = 1)) end
  block good(n [i32]) return n end
end]],
  },
  {
    name = "wire with unknown arg name",
    src = [[
region Inner(; yes)
  entry start() jump yes end
end
fn main() [i32]
  entry start() call Inner(; yes = good(x = 1)) end
  block good(n [i32]) return n end
end]],
  },
  {
    name = "wire missing a block param",
    src = [[
region Inner(; yes)
  entry start() jump yes end
end
fn main() [i32]
  entry start() call Inner(; yes = good()) end
  block good(n [i32]) return n end
end]],
  },
  {
    name = "wire to a cont the callee does not expose",
    src = [[
region Inner(; yes)
  entry start() jump yes end
end
fn main() [i32]
  entry start() call Inner(; nope = good(n = 1)) end
  block good(n [i32]) return n end
end]],
  },
  {
    name = "jump to nonexistent block",
    src = [[
fn main() [i32]
  entry start() jump nowhere(n = 1) end
end]],
  },
  {
    name = "jump missing a block param",
    src = [[
fn main() [i32]
  entry start() jump done() end
  block done(v [u64]) return as [i32](v) end
end]],
  },
  {
    name = "cont payload type mismatch with wired block param",
    src = [[
region Inner(; yes(result [i32]))
  entry start() jump yes(result = 41) end
end
fn main() [i32]
  entry start() call Inner(; yes = done) end
  block done(result [u64]) return as [i32](result) end
end]]
  },
}

local count = 0
for _, c in ipairs(negatives) do
  local ok, err = compile_ok(c.src)
  assert(not ok, c.name .. " must be rejected")
  assert(err:match("typecheck rejected"), c.name .. " must fail at typecheck, got: " .. err)
  count = count + 1
end

-- Positive control: a correct wiring (cont payload flows to the wired block,
-- args match params, callee cont exists) compiles and runs.
local ok_src = [[
region Inner(; yes(result [i32]), no)
  entry start()
    jump yes(result = 41)
  end
end

fn main() [i32]
  entry start()
    call Inner(;
      yes = done,
      no = bad
    )
  end
  -- the cont payload `result` feeds block done''s param of the same name
  block done(result [i32])
    return result + 41
  end
  block bad()
    return 0
  end
end]]
local decls = assert(lalin.loadstring(ok_src, "@wire_ok.lln"))
local session = assert(lalin.compile_c_gcc("wire_ok", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_wire_ok" },
}))
local main = assert(session:symbol("main", "int32_t (*)(void)"))
assert(tonumber(main()) == 82, "correct wiring must execute to 82")
session:free()

-- Implicit passthrough: an omitted jump arg whose name resolves to a block
-- param of the current block is forwarded from it. `jump loop(v = v + 1)`
-- forwards `a`; the region machine executes to 41.
local pt_src = [[
region Machine(; done(v [i32]))
  entry start()
    jump step(a = 40, v = 0)
  end
  block step(a [i32], v [i32])
    jump loop(v = v + 1)
  end
  block loop(a [i32], v [i32])
    jump done(v = a + v)
  end
end

fn main() [i32]
  entry start()
    call Machine(;
      done = fin
    )
  end
  block fin(v [i32])
    return v
  end
end]]
local pt_decls = assert(lalin.loadstring(pt_src, "@wire_pt.lln"))
local pt_session = assert(lalin.compile_c_gcc("wire_pt", pt_decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_wire_pt" },
}))
local pt_main = assert(pt_session:symbol("main", "int32_t (*)(void)"))
assert(tonumber(pt_main()) == 41, "passthrough: a=40 forwarded, v=0+1 -> 41 (got " .. tostring(pt_main()) .. ")")
pt_session:free()

-- Function entry params: a fn data param flows into an entry param of the
-- same name (the entry init resolves to a binding ref at typecheck).
local entry_src = [[
fn main(a [i32]) [i32]
  entry start(a [i32])
    jump finish(v = a + 1)
  end
  block finish(v [i32])
    return v
  end
end]]
local entry_decls = assert(lalin.loadstring(entry_src, "@wire_entry.lln"))
local entry_session = assert(lalin.compile_c_gcc("wire_entry", entry_decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_wire_entry" },
}))
local entry_main = assert(entry_session:symbol("main", "int32_t (*)(int32_t)"))
assert(tonumber(entry_main(41)) == 42, "fn entry param flows to block: 41 + 1 = 42")
entry_session:free()

print(("region wiring validation: %d miswires rejected at typecheck, wiring/passthrough/entry run 82/41/42"):format(count))

print(("region wiring validation: %d miswires rejected at typecheck, wiring/passthrough run to 82/41"):format(count))
