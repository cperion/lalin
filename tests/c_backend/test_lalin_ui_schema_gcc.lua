package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
  assert(why.skip == true)
  io.write("Lalin UI schema GCC skipped\n")
  os.exit(0)
end

local decls = assert(lalin.loadfile("examples/ui/lalin_ui.lln"))
assert(#decls == 49, "canonical UI spine must expose the complete physical vocabulary")

local session, source = lalin.compile_c_gcc("lalin_ui_schema_gcc", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_lalin_ui_schema_gcc" },
})

for _, name in ipairs({
  "UiNodeSpine", "UiStyledWorld", "UiMeasuredWorld", "UiLaidOutWorld",
  "UiRenderableWorld", "UiInputRecord", "UiEffectRecord",
  "TerminalCapabilities", "TerminalDecodeFrame", "TerminalGraphemeWorld",
  "TerminalCellWorld", "TerminalPatchWorld", "TerminalOutputImage",
  "TerminalWriteResult", "TerminalSessionFrame",
}) do
  assert(source:match("typedef struct module_" .. name), "missing emitted physical type " .. name)
end

assert(source:match("module_TerminalCellSpine%*"), "cell topology must remain a separate aligned spine")
assert(source:match("module_TerminalCellGlyphFacet%*"), "cell glyphs must remain an aligned facet")
assert(source:match("module_TerminalCellStyleFacet%*"), "cell styles must remain an aligned facet")
assert(source:match("module_TerminalCellOwnershipFacet%*"), "cell ownership must remain an aligned facet")
assert(source:match("TerminalEmit") == nil, "schema design must not invent a second terminal semantic command language")

session:free()
io.write("Lalin UI physical schema GCC ok: common worlds + terminal spine/facets/transaction\n")
