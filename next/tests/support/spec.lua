local Spec = {
  total = 0,
  failed = 0,
  failures = {},
  finished = false,
}

local function render(value)
  if type(value) == "string" then return string.format("%q", value) end
  return tostring(value)
end

function Spec.reset()
  Spec.total = 0
  Spec.failed = 0
  Spec.failures = {}
  Spec.finished = false
end

function Spec.describe(name, fn)
  print("# " .. name)
  fn()
end

function Spec.it(name, fn)
  Spec.total = Spec.total + 1
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    print("ok " .. Spec.total .. " - " .. name)
    return
  end
  Spec.failed = Spec.failed + 1
  Spec.failures[#Spec.failures + 1] = { name = name, error = err }
  io.stderr:write("not ok " .. Spec.total .. " - " .. name .. "\n")
end

function Spec.pending(name, reason)
  Spec.total = Spec.total + 1
  print("ok " .. Spec.total .. " - " .. name .. " # SKIP " .. (reason or "pending"))
end

function Spec.file_failure(path, err)
  Spec.failed = Spec.failed + 1
  Spec.failures[#Spec.failures + 1] = { name = "file load: " .. path, error = err }
  io.stderr:write("not ok file - " .. path .. "\n")
end

function Spec.assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. render(expected) .. ", got " .. render(actual), 2)
  end
end

function Spec.assert_truthy(value, message)
  if not value then error(message or "expected truthy value", 2) end
end

function Spec.assert_nil(value, message)
  if value ~= nil then error((message or "expected nil") .. ": got " .. render(value), 2) end
end

function Spec.assert_list_equal(actual, expected, message)
  Spec.assert_equal(#actual, #expected, (message or "list length differs"))
  for i = 1, #expected do
    Spec.assert_equal(actual[i], expected[i], (message or "list differs") .. " at index " .. i)
  end
end

function Spec.assert_set_equal(actual, expected, message)
  actual = { unpack(actual) }
  expected = { unpack(expected) }
  table.sort(actual)
  table.sort(expected)
  local i, j = 1, 1
  local missing, extra = {}, {}
  while i <= #actual and j <= #expected do
    if actual[i] == expected[j] then
      i, j = i + 1, j + 1
    elseif actual[i] < expected[j] then
      extra[#extra + 1] = actual[i]
      i = i + 1
    else
      missing[#missing + 1] = expected[j]
      j = j + 1
    end
  end
  while i <= #actual do
    extra[#extra + 1] = actual[i]
    i = i + 1
  end
  while j <= #expected do
    missing[#missing + 1] = expected[j]
    j = j + 1
  end
  if #missing > 0 or #extra > 0 then
    error((message or "sets differ")
      .. ": missing {" .. table.concat(missing, ", ") .. "}"
      .. ", extra {" .. table.concat(extra, ", ") .. "}", 2)
  end
end

function Spec.finish()
  if Spec.finished then return end
  Spec.finished = true
  if Spec.failed > 0 then
    io.stderr:write(string.format("%d/%d specs failed\n", Spec.failed, Spec.total))
    for i, failure in ipairs(Spec.failures) do
      io.stderr:write(string.format("\n%d) %s\n%s\n", i, failure.name, failure.error))
    end
    os.exit(1)
  end
  print(string.format("%d specs passed", Spec.total))
end

return Spec
