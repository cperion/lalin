package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local JsonEncode = require("moonlift.rpc_json_encode")
local JsonDecode = require("moonlift.rpc_json_decode")
local Loop = require("moonlift.rpc_stdio_loop")

local function frame(msg)
    local body = JsonEncode.encode_lua(msg)
    return "Content-Length: " .. #body .. "\r\n\r\n" .. body
end

local Input = {}; Input.__index = Input
function Input.new(s) return setmetatable({ s = s, i = 1 }, Input) end
function Input:read(arg)
    if self.i > #self.s then return nil end
    if arg == "*l" then
        local j = self.s:find("\n", self.i, true)
        if not j then local out = self.s:sub(self.i); self.i = #self.s + 1; return out end
        local out = self.s:sub(self.i, j - 1); self.i = j + 1; return out
    elseif type(arg) == "number" then
        local out = self.s:sub(self.i, self.i + arg - 1); self.i = self.i + #out; return out
    end
end

local Output = {}; Output.__index = Output
function Output.new() return setmetatable({ parts = {} }, Output) end
function Output:write(...) for i = 1, select("#", ...) do self.parts[#self.parts + 1] = tostring(select(i, ...)) end end
function Output:flush() end
function Output:text() return table.concat(self.parts) end

local uri = "file:///tmp/lsp_redesign.mlua"
local src = table.concat({
    "struct A\n  id: i32\nend\n",
    "struct B\n  id: i32\nend\n",
    "region choose(x: i32; ok(v: i32) | fail(code: i32))\n",
    "entry start()\n",
    "  if x > 0 then jump ok(v = x) end\n",
    "  jump fail(code = 1)\n",
    "end\n",
    "end\n",
    "func use_id(a: ptr(A)): i32\n",
    "  return a.id\n",
    "end\n",
    "func route(x: i32): i32\n",
    "  return region: i32\n",
    "  entry start()\n",
    "    emit choose(x; ok = done, fail = failed)\n",
    "  end\n",
    "  block done(v: i32)\n",
    "    yield v\n",
    "  end\n",
    "  block failed(code: i32)\n",
    "    yield code\n",
    "  end\n",
    "  end\n",
    "end\n",
})

local function pos_of(needle, nth)
    nth = nth or 1
    local start, s = 1, nil
    for _ = 1, nth do s = assert(src:find(needle, start, true), needle); start = s + #needle end
    local prefix = src:sub(1, s - 1)
    local line = select(2, prefix:gsub("\n", ""))
    local last = prefix:match(".*\n()") or 1
    return { line = line, character = s - last }
end

local function eof_pos()
    local line = select(2, src:gsub("\n", ""))
    return { line = line, character = 0 }
end

local input = table.concat({
    frame({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} }),
    frame({ jsonrpc = "2.0", method = "textDocument/didOpen", params = { textDocument = { uri = uri, languageId = "mlua", version = 1, text = src } } }),
    frame({ jsonrpc = "2.0", id = 2, method = "textDocument/completion", params = { textDocument = { uri = uri }, position = eof_pos() } }),
    frame({ jsonrpc = "2.0", id = 3, method = "textDocument/definition", params = { textDocument = { uri = uri }, position = pos_of("fail", 2) } }),
    frame({ jsonrpc = "2.0", id = 4, method = "textDocument/definition", params = { textDocument = { uri = uri }, position = pos_of("id", 3) } }),
    frame({ jsonrpc = "2.0", id = 5, method = "textDocument/completion", params = { textDocument = { uri = uri }, position = pos_of("ok", 2) } }),
    frame({ jsonrpc = "2.0", id = 6, method = "textDocument/completion", params = { textDocument = { uri = uri }, position = pos_of("fail", 3) } }),
    frame({ jsonrpc = "2.0", id = 7, method = "textDocument/signatureHelp", params = { textDocument = { uri = uri }, position = pos_of("ok = done") } }),
    frame({ jsonrpc = "2.0", id = 8, method = "textDocument/inlayHint", params = { textDocument = { uri = uri }, range = { start = { line = 0, character = 0 }, ["end"] = eof_pos() } } }),
    frame({ jsonrpc = "2.0", id = 9, method = "textDocument/foldingRange", params = { textDocument = { uri = uri } } }),
    frame({ jsonrpc = "2.0", id = 10, method = "textDocument/selectionRange", params = { textDocument = { uri = uri }, positions = { pos_of("choose", 2) } } }),
    frame({ jsonrpc = "2.0", id = 11, method = "textDocument/hover", params = { textDocument = { uri = uri }, position = pos_of("choose", 2) } }),
    frame({ jsonrpc = "2.0", id = 12, method = "textDocument/hover", params = { textDocument = { uri = uri }, position = pos_of("v", 2) } }),
    frame({ jsonrpc = "2.0", id = 13, method = "shutdown", params = {} }),
    frame({ jsonrpc = "2.0", method = "exit", params = {} }),
})

local out = Output.new()
Loop.run({ input = Input.new(input), output = out, err = Output.new() })

local function decode_frames(s)
    local msgs, i = {}, 1
    while i <= #s do
        local h = s:find("\r\n\r\n", i, true); if not h then break end
        local len = tonumber(s:sub(i, h - 1):match("Content%-Length:%s*(%d+)")); assert(len)
        local b = s:sub(h + 4, h + 3 + len)
        msgs[#msgs + 1] = JsonDecode.decode_lua(b)
        i = h + 4 + len
    end
    return msgs
end

local by_id = {}
for _, msg in ipairs(decode_frames(out:text())) do if msg.id then by_id[msg.id] = msg end end

local struct_item
for _, item in ipairs(by_id[2].result.items) do
    if item.label == "struct" then struct_item = item end
end
assert(struct_item and struct_item.insertTextFormat == 2, "snippet completions must be marked as snippets")

assert(#by_id[3].result == 1, "jump fail should resolve to its | continuation declaration")
assert(by_id[3].result[1].range.start.line == pos_of("fail", 1).line)

assert(#by_id[4].result == 0, "ambiguous field uses must not jump to the first matching field")

local saw_done, saw_failed = false, false
for _, item in ipairs(by_id[5].result.items) do
    if item.label == "done" then saw_done = true end
    if item.label == "failed" then saw_failed = true end
end
assert(saw_done and saw_failed, "jump completion should list control labels")

local saw_ok, saw_fail = false, false
for _, item in ipairs(by_id[6].result.items) do
    if item.label == "ok" and item.insertTextFormat == 2 then saw_ok = true end
    if item.label == "fail" and item.insertTextFormat == 2 then saw_fail = true end
end
assert(saw_ok and saw_fail, "emit route completion should list region exits as snippets")

assert(by_id[7].result.signatures[1].label:match("ok = <block>"), "emit signature should include continuation routes")
assert(by_id[7].result.activeParameter == 1, "emit signature should move to route parameter after semicolon")

local saw_route_hint = false
for _, hint in ipairs(by_id[8].result) do
    if hint.label == "ok:" then saw_route_hint = true end
end
assert(saw_route_hint, "emit route inlay hints should use route labels")

assert(#by_id[9].result >= 4, "folding should include Moonlift control ranges")
assert(by_id[10].result[1].parent ~= nil, "selection range should include nested parents")
assert(by_id[11].result.contents.value:match("region choose%(x: i32%)"), "region hover should include signature")
assert(by_id[11].result.contents.value:match("ok%(v: i32%)"), "region hover should include exits")
assert(by_id[12].result.contents.value:match("v: i32"), "binding hover should include type")

print("moonlift lsp redesign surface ok")
