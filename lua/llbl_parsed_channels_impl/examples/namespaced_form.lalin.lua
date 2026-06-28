-- Namespaced form does not need parse-time import; it only needs lalin.syntax
-- to have been required by the caller before llbl.syntax.loadfile/loadstring.

local add = lalin fn add(a: i32, b: i32): i32
  if a < b then
    return a + b
  else
    return b + a
  end
end

return add
