local ImplStyle = {}

local function find_files(root)
  local out = {}
  local pipe = io.popen("find " .. root .. " -type f -name '*.lua' 2>/dev/null")
  if not pipe then return out end
  for path in pipe:lines() do out[#out + 1] = path end
  pipe:close()
  table.sort(out)
  return out
end

local forbidden = {
  { name = "kind field dispatch", pattern = "%.kind" },
  { name = "kind index dispatch", pattern = "%[\"kind\"%]" },
  { name = "tag field dispatch", pattern = "%.tag" },
  { name = "tag index dispatch", pattern = "%[\"tag\"%]" },
  { name = "class-name dispatch", pattern = "classof%s*%(" },
  { name = "handler table", pattern = "handlers%s*=" },
  { name = "handler table", pattern = "handler%s*=" },
  { name = "visitor table", pattern = "visitors?%s*=" },
  { name = "rule table", pattern = "rules%s*=" },
  { name = "action string dispatch", pattern = "action%s*==" },
  { name = "mode string dispatch", pattern = "mode%s*==" },
  { name = "category string dispatch", pattern = "category%s*==" },
}

function ImplStyle.violations(root)
  local hits = {}
  for _, path in ipairs(find_files(root)) do
    local line_no = 0
    for line in io.lines(path) do
      line_no = line_no + 1
      for _, rule in ipairs(forbidden) do
        if line:find(rule.pattern) then
          hits[#hits + 1] = path .. ":" .. tostring(line_no) .. ": " .. rule.name .. ": " .. line
        end
      end
    end
  end
  table.sort(hits)
  return hits
end

return ImplStyle
