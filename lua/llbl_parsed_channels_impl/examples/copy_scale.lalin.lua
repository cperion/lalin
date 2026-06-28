-- Must be loaded through llbl.syntax.loadfile, not plain lua/luajit.
-- This file demonstrates both LLBL import activation and real Lalin statements.

import "lalin.syntax"

local scale = 4

local copy_scale = fn copy_scale(dst: ptr[i32], src: ptr[i32], n: index): void
  requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)

  for i in range(0, n) do
    dst[i] = src[i] * [scale]
  end
end

return {
  copy_scale = copy_scale,
}
