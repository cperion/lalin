package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local lalin = require('lalin')

local source = [=[
local Pair = struct Pair
  left [i32]
  right [i32]
end

local int_lit = fn() [i32]
  return 42
end

local float_lit = fn() [f64]
  return 3.5
end

local bool_lit = fn() [bool]
  return true
end

local nil_lit = fn() [ptr [i32]]
  return nil
end

local array_lit = fn() [i32]
  let xs [array [i32] [3]] = { 10, 20, 12 }
  return xs[1] + xs[2]
end

local struct_lit = fn() [i32]
  let p [named("Pair")] = { left = 20, right = 22 }
  return p.left + p.right
end

local string_lit = fn() [i32]
  let s [slice [u8]] = "A\n"
  return as [i32](s[0]) + as [i32](s[1])
end

return {
  Pair,
  int_lit,
  float_lit,
  bool_lit,
  nil_lit,
  array_lit,
  struct_lit,
  string_lit,
}
]=]

local parsed = assert(lalin.loadstring(source, '@test_luajit_artifact_parsed_literals.lln'))()
local loaded = lalin.compile_luajit('ParsedLiterals', parsed, { bytecode = true })

assert(loaded.int_lit() == 42, 'parsed integer literal')
assert(loaded.float_lit() == 3.5, 'parsed float literal')
assert(loaded.bool_lit() == true, 'parsed boolean literal')
assert(loaded.nil_lit() == nil, 'parsed nil pointer literal')
assert(loaded.array_lit() == 32, 'parsed array literal')
assert(loaded.struct_lit() == 42, 'parsed struct literal')
assert(loaded.string_lit() == 75, 'parsed string literal as slice[u8]')

io.write('test_luajit_artifact_parsed_literals: ok\n')
