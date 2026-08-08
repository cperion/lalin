local ffi = require("ffi")
local schema = require("cdefschema")

local S = schema.context {
    name = "concern_tree",
    version = 1,
    prefix = "ConcernTreeV1_",
}

S:cdef [[
typedef struct {
    uint32_t increment_events;
    uint32_t decrement_events;
} ConcernTreeV1_Input;

typedef struct {
    int32_t minimum;
    int32_t maximum;
    int32_t value;
    uint32_t revision;
} ConcernTreeV1_Model;

typedef struct {
    int32_t viewport_width;
    int32_t text_width;
    int32_t text_x;
    uint32_t model_revision;
    uint32_t revision;
} ConcernTreeV1_Layout;

typedef struct {
    uint32_t opcode;
    int32_t x;
    int32_t value;
} ConcernTreeV1_PaintCommand;

typedef struct {
    ConcernTreeV1_PaintCommand commands[2];
    uint32_t command_count;
    uint32_t layout_revision;
    uint32_t revision;
} ConcernTreeV1_Paint;

typedef struct {
    ConcernTreeV1_Input input;
    ConcernTreeV1_Model model;
    ConcernTreeV1_Layout layout;
    ConcernTreeV1_Paint paint;
    uint64_t epoch;
    uint64_t commits;
    uint64_t ignored;
} ConcernTreeV1_App;
 ]]

local Input = S:product("ConcernTreeV1_Input")
local Model = S:product("ConcernTreeV1_Model")
local Layout = S:product("ConcernTreeV1_Layout")
local Paint = S:product("ConcernTreeV1_Paint")
local App = S:product("ConcernTreeV1_App")

local PAINT_CLEAR = 1
local PAINT_VALUE = 2

local function text_width(value)
    if value < -999 then return 40 end
    if value < -99 then return 32 end
    if value < -9 then return 24 end
    if value < 0 then return 16 end
    if value < 10 then return 8 end
    if value < 100 then return 16 end
    if value < 1000 then return 24 end
    return 32
end

function Input:increment(parent, accepted)
    self.increment_events = self.increment_events + 1
    return accepted(parent, 1)
end

function Input:decrement(parent, accepted)
    self.decrement_events = self.decrement_events + 1
    return accepted(parent, -1)
end

function Model:apply(delta, parent, changed, unchanged)
    local candidate = self.value + delta
    if candidate < self.minimum or candidate > self.maximum then
        return unchanged(parent)
    end
    self.value = candidate
    self.revision = self.revision + 1
    return changed(parent)
end

function Layout:synchronize(value, model_revision, parent, completed)
    local width = text_width(value)
    self.text_width = width
    self.text_x = math.floor((self.viewport_width - width) / 2)
    self.model_revision = model_revision
    self.revision = self.revision + 1
    return completed(parent)
end

function Layout:resize(viewport_width, value, model_revision, parent, changed, unchanged)
    if self.viewport_width == viewport_width then
        return unchanged(parent)
    end
    self.viewport_width = viewport_width
    return self:synchronize(value, model_revision, parent, changed)
end

function Paint:commit(value, text_x, viewport_width, layout_revision, parent, completed)
    local clear = self.commands[0]
    clear.opcode = PAINT_CLEAR
    clear.x = 0
    clear.value = viewport_width

    local draw = self.commands[1]
    draw.opcode = PAINT_VALUE
    draw.x = text_x
    draw.value = value

    self.command_count = 2
    self.layout_revision = layout_revision
    self.revision = self.revision + 1
    return completed(parent)
end

local after_input
local model_changed
local model_unchanged
local layout_ready
local resize_changed
local resize_unchanged
local committed
local initialized_layout
local initialized_paint

function App:after_input(delta)
    return self.model:apply(delta, self, model_changed, model_unchanged)
end

function App:model_changed()
    return self.layout:synchronize(
        self.model.value, self.model.revision, self, layout_ready)
end

function App:model_unchanged()
    self.ignored = self.ignored + 1
    return tonumber(self.model.value)
end

function App:layout_ready()
    return self.paint:commit(
        self.model.value, self.layout.text_x, self.layout.viewport_width,
        self.layout.revision, self, committed)
end

function App:resize_changed()
    return self:layout_ready()
end

function App:resize_unchanged()
    self.ignored = self.ignored + 1
    return tonumber(self.model.value)
end

function App:committed()
    self.commits = self.commits + 1
    return tonumber(self.model.value)
end

function App:initialized_layout()
    return self.paint:commit(
        self.model.value, self.layout.text_x, self.layout.viewport_width,
        self.layout.revision, self, initialized_paint)
end

function App:initialized_paint()
    self.epoch = 0
    self.commits = 0
    self.ignored = 0
    return self
end

after_input = App.after_input
model_changed = App.model_changed
model_unchanged = App.model_unchanged
layout_ready = App.layout_ready
resize_changed = App.resize_changed
resize_unchanged = App.resize_unchanged
committed = App.committed
initialized_layout = App.initialized_layout
initialized_paint = App.initialized_paint

function App:initialize(minimum, maximum, value, viewport_width)
    assert(minimum <= value and value <= maximum, "initial value outside model bounds")
    assert(viewport_width > 0, "viewport width must be positive")

    self.input.increment_events = 0
    self.input.decrement_events = 0

    self.model.minimum = minimum
    self.model.maximum = maximum
    self.model.value = value
    self.model.revision = 1

    self.layout.viewport_width = viewport_width
    self.layout.revision = 0

    self.paint.command_count = 0
    self.paint.revision = 0

    return self.layout:synchronize(value, self.model.revision, self, initialized_layout)
end

function App:increment()
    self.epoch = self.epoch + 1
    return self.input:increment(self, after_input)
end

function App:decrement()
    self.epoch = self.epoch + 1
    return self.input:decrement(self, after_input)
end

function App:resize(viewport_width)
    assert(viewport_width > 0, "viewport width must be positive")
    self.epoch = self.epoch + 1
    return self.layout:resize(
        viewport_width, self.model.value, self.model.revision,
        self, resize_changed, resize_unchanged)
end

S:seal()

return {
    App = App,
    Input = Input,
    Model = Model,
    Layout = Layout,
    Paint = Paint,
    PAINT_CLEAR = PAINT_CLEAR,
    PAINT_VALUE = PAINT_VALUE,
}

