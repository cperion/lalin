package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema_v2")
require("lalin.impl.cemit_emit")
local C = require("lalin.schema_v2.c")
local Core = require("lalin.schema_v2.core")

local i32 = C.CBackendScalar(Core.ScalarI32)
local cases = {
  { Core.UnaryNeg, "%-a1" },
  { Core.UnaryNot, "!a1" },
  { Core.UnaryBitNot, "~a1" },
}
local lines = { "#include <stdint.h>", "#include <stdbool.h>" }
for i = 1, #cases do
  assert(cases[i][1].c_emit_unary_expression ~= nil)
  local helper = C.CBackendHelperUnary(cases[i][1], i32)
  local source = table.concat(helper:c_emit_helper_lines(), "\n")
  assert(source:match(cases[i][2]), "unary leaf spelling missing")
  lines[#lines + 1] = source
end
lines[#lines + 1] = "int main(void) { return ml_i32_neg(1) == -1 && ml_i32_not(0) == 1 && ml_i32_bitnot(0) == -1 ? 0 : 1; }"
os.execute("mkdir -p target/schema_v2")
local path = "target/schema_v2/cemit_unary.c"
local file = assert(io.open(path, "w")); file:write(table.concat(lines, "\n")); file:close()
local ok = os.execute((os.getenv("CC") or "cc") .. " -std=c99 -Werror -o target/schema_v2/cemit_unary " .. path)
assert(ok == true or ok == 0, "generated unary C must compile")
local ran = os.execute("target/schema_v2/cemit_unary")
assert(ran == true or ran == 0, "generated unary C must run")
io.write("schema_v2 unary leaf C emission ok\n")
