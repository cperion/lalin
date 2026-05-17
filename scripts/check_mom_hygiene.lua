#!/usr/bin/env lua
-- Hygiene checker for native MOM sources.
-- This is intentionally small and grep-like: it catches AI-generated patterns
-- that compile syntactically but violate the MOM implementation contract.

local root = "lua/moonlift/mom"
local allow_raw_cmd = {
  ["lua/moonlift/mom/back/cmd.mlua"] = true,
  ["lua/moonlift/mom/driver/compile_source.mlua"] = true,
}
local allow_cmdtrap = {
  ["lua/moonlift/mom/back/cmd.mlua"] = true,
  ["lua/moonlift/mom/back/validate.mlua"] = true,
}

local forbidden_words = {
  { pat = "TODO", label = "TODO" },
  { pat = "FIXME", label = "FIXME" },
  { pat = "placeholder", label = "placeholder" },
  { pat = "Placeholder", label = "Placeholder" },
  { pat = "simplified", label = "simplified" },
  { pat = "Simplified", label = "Simplified" },
  { pat = "not yet", label = "not yet" },
  { pat = "for now", label = "for now" },
  { pat = "temporary", label = "temporary" },
}

local function list_sources()
  local cmd = "find " .. root .. [[ -type f \( -name '*.lua' -o -name '*.mlua' \) | sort]]
  local p = assert(io.popen(cmd, "r"))
  local files = {}
  for line in p:lines() do files[#files + 1] = line end
  p:close()
  return files
end

local failures = {}

local function fail(path, line_no, label, line)
  failures[#failures + 1] = string.format("%s:%d: %s: %s", path, line_no, label, line)
end

local function check_file(path)
  local f = assert(io.open(path, "r"))
  local prev = ""
  local line_no = 0
  for line in f:lines() do
    line_no = line_no + 1

    if line:find("@malloc", 1, true) then
      fail(path, line_no, "hidden allocation '@malloc'", line)
    end

    -- Fake continuation argument syntax seen in bad generated lowerers.
    if line:find("=%s*%?") or line:find("%(%s*%?%s*%)") then
      fail(path, line_no, "fake continuation/value placeholder '?'", line)
    end

    -- Illegal emitted-region-as-call shape: emit frag(...)(...).  A simple
    -- line-local check catches the generated form; multi-line variants are
    -- caught by parser/tests.
    if line:find("emit%s+[%w_%.]+%b()%s*%(") then
      fail(path, line_no, "illegal emit-call shape", line)
    end

    for _, fw in ipairs(forbidden_words) do
      if line:find(fw.pat, 1, true) then
        fail(path, line_no, "forbidden stale marker " .. fw.label, line)
      end
    end

    -- Raw command packing outside the command API or driver bootstrap.
    if not allow_raw_cmd[path] and line:find("@{T%.Cmd") then
      if line:find("push_cmd%(") then
        fail(path, line_no, "raw command packing outside back/cmd.mlua", line)
      elseif line:find("push_cmd_w%d+%(") then
        fail(path, line_no, "raw wide command packing outside back/cmd.mlua", line)
      end
    end

    -- CmdTrap in lowerers must be explicit and reviewed. The checker reports it
    -- outside the command API/validator; use hosted-source-equivalent issues or
    -- central helpers instead of ad hoc fallback traps.
    if not allow_cmdtrap[path] then
      if line:find("CmdTrap", 1, true) then
        fail(path, line_no, "review CmdTrap use", line)
      end
    end

    prev = line
  end
  f:close()
end

for _, path in ipairs(list_sources()) do
  check_file(path)
end

if #failures > 0 then
  io.stderr:write(string.format("MOM hygiene check failed: %d issue(s)\n", #failures))
  local max = tonumber(os.getenv("MOM_HYGIENE_MAX") or "200")
  for i = 1, math.min(#failures, max) do
    io.stderr:write(failures[i], "\n")
  end
  if #failures > max then
    io.stderr:write(string.format("... %d more issue(s); set MOM_HYGIENE_MAX to show more\n", #failures - max))
  end
  os.exit(1)
end

print("MOM hygiene check ok")
