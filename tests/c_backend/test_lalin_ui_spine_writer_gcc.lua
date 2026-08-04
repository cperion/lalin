package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")
local ffi = require("ffi")

local available, why = c_gcc.available()
if not available then assert(why.skip); os.exit(0) end

ffi.cdef[[
typedef struct { uint64_t value; } UiIdentity;
typedef struct { uint64_t value; } UiGeneration;
typedef struct { size_t start, count; } UiRange;
typedef struct { int32_t left, top, right, bottom; } UiInsets;
typedef struct { int32_t width, height; } UiExtent;
typedef struct {
  UiIdentity identity, parent, component; UiRange children;
  uint32_t child_count, authored_order, source_start, source_count;
} UiNodeSpine;
typedef struct { UiIdentity node; uint32_t token; } UiStyleTokenFacet;
typedef struct { UiIdentity node; UiInsets margin, padding; UiExtent minimum, maximum; } UiBoxFacet;
typedef struct { UiIdentity node, component; } UiActivationFacet;
typedef struct { size_t node_index; uint32_t direct_child_count; } UiWriterScope;
typedef struct {
  UiGeneration generation; UiNodeSpine *spines; UiStyleTokenFacet *styles; size_t node_count, node_capacity;
  UiBoxFacet *boxes; size_t box_count, box_capacity;
  void *texts; size_t text_count, text_capacity;
  UiActivationFacet *activations; size_t activation_count, activation_capacity;
  uint8_t *text_bytes; size_t text_byte_count, text_byte_capacity;
} UiAuthoredWorld;
typedef struct { UiAuthoredWorld world; UiWriterScope *scopes; size_t scope_count, scope_capacity; } UiDeclarationWriter;
]]

local canonical = assert(io.open("examples/ui/lalin_ui.lln", "rb")):read("*a")
local fixture = canonical .. [=[

fn ui_spine_build(writer [ptr [UiDeclarationWriter]]) [i32]
  entry start()
    emit UiDeclarationWriter.reset(writer, UiGeneration { value = as [u64](7) }; ready = root)
  end

  block root()
    emit UiDeclarationWriter.open_node(writer, UiIdentity { value = as [u64](0) },
      UiIdentity { value = as [u64](100) }, as [u32](11), as [u32](1), as [u32](2);
      opened = root_box, full = capacity, scope_full = capacity, invalid_parent = invalid)
  end

  block root_box(identity [UiIdentity])
    emit UiDeclarationWriter.box(writer, identity,
      UiInsets { left = 1, top = 2, right = 3, bottom = 4 },
      UiInsets { left = 5, top = 6, right = 7, bottom = 8 },
      UiExtent { width = 10, height = 11 }, UiExtent { width = 100, height = 101 };
      written = child, full = capacity, invalid_node = invalid_node)
  end

  block child()
    emit UiDeclarationWriter.open_node(writer, UiIdentity { value = as [u64](1) },
      UiIdentity { value = as [u64](101) }, as [u32](12), as [u32](3), as [u32](4);
      opened = activate, full = capacity, scope_full = capacity, invalid_parent = invalid)
  end

  block activate(identity [UiIdentity])
    emit UiDeclarationWriter.activation(writer, identity, UiIdentity { value = as [u64](101) };
      written = close_child, full = capacity, invalid_node = invalid_node)
  end

  block close_child()
    emit UiDeclarationWriter.close_node(writer; closed = close_root, unbalanced = unbalanced)
  end
  block close_root(identity [UiIdentity])
    emit UiDeclarationWriter.close_node(writer; closed = commit, unbalanced = unbalanced)
  end
  block commit(identity [UiIdentity])
    emit UiDeclarationWriter.commit(writer; committed = done, unbalanced = unbalanced, empty = unbalanced)
  end
  block done(generation [UiGeneration]) return as [i32](0) end
  block capacity(capacity [UiCapacity]) return as [i32](2) end
  block invalid(parent [UiIdentity]) return as [i32](1) end
  block invalid_node(node [UiIdentity]) return as [i32](1) end
  block unbalanced() return as [i32](3) end
end
 ]=]

local decls = assert(lalin.loadstring(fixture, "@lalin_ui_spine_writer.lln"))
local session, source = lalin.compile_c_gcc("lalin_ui_spine_writer", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_lalin_ui_spine_writer_gcc" },
})
assert(source:match("UiAuthFacet") == nil)
assert(source:match("UiAuthoredWorld_resolve_node%(") ~= nil, "facet writers must use the one node resolver")

local build = assert(session:symbol("ui_spine_build", "int32_t (*)(UiDeclarationWriter*)"))
local function new_writer(node_capacity)
  local keep = {
    spines = ffi.new("UiNodeSpine[4]"), styles = ffi.new("UiStyleTokenFacet[4]"),
    boxes = ffi.new("UiBoxFacet[4]"), activations = ffi.new("UiActivationFacet[4]"),
    scopes = ffi.new("UiWriterScope[4]"), bytes = ffi.new("uint8_t[16]"),
  }
  keep.writer = ffi.new("UiDeclarationWriter")
  keep.writer.world.spines = keep.spines; keep.writer.world.styles = keep.styles
  keep.writer.world.node_capacity = node_capacity or 4
  keep.writer.world.boxes = keep.boxes; keep.writer.world.box_capacity = 4
  keep.writer.world.activations = keep.activations; keep.writer.world.activation_capacity = 4
  keep.writer.world.text_bytes = keep.bytes; keep.writer.world.text_byte_capacity = 16
  keep.writer.scopes = keep.scopes; keep.writer.scope_capacity = 4
  return keep
end

local a = new_writer()
assert(build(a.writer) == 0)
assert(a.writer.world.generation.value == 7 and a.writer.world.node_count == 2)
assert(a.spines[0].identity.value == 1 and a.spines[0].parent.value == 0)
assert(a.spines[0].component.value == 100 and a.spines[0].children.start == 1)
assert(a.spines[0].children.count == 1 and a.spines[0].child_count == 1)
assert(a.spines[1].identity.value == 2 and a.spines[1].parent.value == 1)
assert(a.spines[1].children.count == 0 and a.spines[1].child_count == 0)
assert(a.writer.world.box_count == 1 and a.boxes[0].node.value == 1)
assert(a.writer.world.activation_count == 1 and a.activations[0].node.value == 2)
assert(a.writer.scope_count == 0)

local b = new_writer()
assert(build(b.writer) == 0)
assert(ffi.string(a.spines, ffi.sizeof("UiNodeSpine[4]")) == ffi.string(b.spines, ffi.sizeof("UiNodeSpine[4]")), "equal views must produce deterministic spines")

local full = new_writer(1)
assert(build(full.writer) == 2)
assert(full.writer.world.node_count == 1, "capacity rejection must not partially append a node")

session:free()
io.write("Lalin UI NodeSpine + typed authored writer GCC ok\n")
