local ffi = require("ffi")
local schema = require("cdefschema")

local S = schema.context {
    name = "love-ui",
    version = 1,
    prefix = "LoveUiV1_",
}

S:cdef [[
enum {
    LoveUiV1_MaxTextMetrics = 1024,
    LoveUiV1_MaxLayoutBoxes = 4096,
    LoveUiV1_MaxVertices = 32768,
    LoveUiV1_MaxIndices = 49152,
    LoveUiV1_MaxGeometryBatches = 4096,
    LoveUiV1_MaxTextDraws = 2048,
    LoveUiV1_MaxImageDraws = 2048,
    LoveUiV1_MaxClips = 1024,
    LoveUiV1_MaxLayers = 128,
    LoveUiV1_MaxSegments = 8192,
    LoveUiV1_MaxClipDepth = 64,
    LoveUiV1_MaxLayerDepth = 16
};

typedef uint64_t LoveUiV1_NodeHandle;
typedef uint64_t LoveUiV1_ContentHandle;
typedef uint64_t LoveUiV1_ResourceHandle;

typedef struct {
    float x;
    float y;
    float width;
    float height;
} LoveUiV1_Rect;

typedef struct {
    double now_seconds;
    double delta_seconds;
    uint64_t frame_index;
    uint64_t event_count;
    uint64_t present_count;
    uint32_t logical_width;
    uint32_t logical_height;
    uint32_t pixel_width;
    uint32_t pixel_height;
    float dpi_scale;
    uint32_t focused;
    uint32_t visible;
    uint32_t quit_requested;
    uint32_t redraw_requested;
} LoveUiV1_Host;

typedef struct {
    double pointer_x;
    double pointer_y;
    double pointer_dx;
    double pointer_dy;
    double wheel_x;
    double wheel_y;
    uint64_t revision;
    uint64_t pointer_revision;
    uint64_t key_revision;
    uint64_t text_revision;
    uint32_t button_mask;
    uint32_t modifiers;
    uint32_t pointer_inside;
    uint32_t text_input_active;
} LoveUiV1_Input;

enum {
    LoveUiV1_DragIdleKind = 0,
    LoveUiV1_DragPendingKind = 1,
    LoveUiV1_DraggingKind = 2
};

typedef struct {
    uint64_t revision;
} LoveUiV1_DragIdle;

typedef struct {
    LoveUiV1_NodeHandle source;
    double press_x;
    double press_y;
    double threshold_squared;
    uint64_t revision;
} LoveUiV1_DragPending;

typedef struct {
    LoveUiV1_NodeHandle source;
    LoveUiV1_NodeHandle target;
    double origin_x;
    double origin_y;
    double current_x;
    double current_y;
    uint64_t revision;
} LoveUiV1_Dragging;

typedef union {
    LoveUiV1_DragIdle idle;
    LoveUiV1_DragPending pending;
    LoveUiV1_Dragging dragging;
} LoveUiV1_DragPayload;

typedef struct {
    uint32_t kind;
    uint32_t reserved;
    LoveUiV1_DragPayload payload;
} LoveUiV1_DragState;

typedef struct {
    LoveUiV1_NodeHandle hover;
    LoveUiV1_NodeHandle focus;
    LoveUiV1_NodeHandle pressed;
    LoveUiV1_NodeHandle captured;
    LoveUiV1_NodeHandle drop_target;
    LoveUiV1_DragState drag;
    uint64_t revision;
    uint64_t visual_revision;
    uint64_t layout_revision;
} LoveUiV1_Interaction;

typedef struct {
    uint32_t active_tool;
    uint32_t hovered_tool;
    uint64_t revision;
} LoveUiV1_ToolbarModel;

typedef struct {
    double pan_x;
    double pan_y;
    double zoom;
    LoveUiV1_NodeHandle selection;
    uint64_t revision;
} LoveUiV1_WorkspaceModel;

typedef struct {
    LoveUiV1_ContentHandle content;
    uint64_t revision;
} LoveUiV1_StatusModel;

typedef struct {
    LoveUiV1_ToolbarModel toolbar;
    LoveUiV1_WorkspaceModel workspace;
    LoveUiV1_StatusModel status;
    uint64_t revision;
} LoveUiV1_Model;

typedef struct {
    LoveUiV1_NodeHandle node;
    LoveUiV1_ContentHandle content;
    LoveUiV1_ResourceHandle font;
    float font_size;
    float wrap_width;
    float measured_width;
    float measured_height;
    float baseline;
    float line_height;
    uint32_t line_count;
    uint32_t reserved;
    uint64_t input_revision;
    uint64_t output_revision;
} LoveUiV1_TextMetric;

typedef struct {
    LoveUiV1_TextMetric items[LoveUiV1_MaxTextMetrics];
    uint32_t count;
    uint32_t overflow_count;
    uint64_t model_revision;
    uint64_t revision;
    uint64_t measure_count;
} LoveUiV1_TextMeasure;

typedef struct {
    LoveUiV1_NodeHandle node;
    uint32_t parent_index;
    int32_t z_index;
    LoveUiV1_Rect border_rect;
    LoveUiV1_Rect content_rect;
    uint32_t clip_index;
    uint32_t flags;
} LoveUiV1_LayoutBox;

typedef struct {
    LoveUiV1_LayoutBox boxes[LoveUiV1_MaxLayoutBoxes];
    uint32_t box_count;
    uint32_t overflow_count;
    uint64_t model_revision;
    uint64_t interaction_revision;
    uint64_t text_revision;
    uint64_t revision;
    uint64_t solve_count;
} LoveUiV1_Layout;

typedef struct {
    float x;
    float y;
    float u;
    float v;
    uint32_t rgba8;
    uint32_t reserved;
} LoveUiV1_Vertex;

typedef struct {
    uint32_t first_vertex;
    uint32_t vertex_count;
    uint32_t first_index;
    uint32_t index_count;
    LoveUiV1_ResourceHandle image;
    LoveUiV1_ResourceHandle shader;
    uint32_t topology;
    uint32_t blend_mode;
} LoveUiV1_GeometryBatch;

typedef struct {
    LoveUiV1_NodeHandle node;
    LoveUiV1_ContentHandle content;
    LoveUiV1_ResourceHandle font;
    LoveUiV1_ResourceHandle text_resource;
    float x;
    float y;
    float wrap_width;
    float opacity;
    uint32_t rgba8;
    uint32_t alignment;
} LoveUiV1_TextDraw;

typedef struct {
    LoveUiV1_NodeHandle node;
    LoveUiV1_ResourceHandle image;
    LoveUiV1_Rect source;
    LoveUiV1_Rect destination;
    float rotation;
    float opacity;
    uint32_t tint_rgba8;
    uint32_t reserved;
} LoveUiV1_ImageDraw;

typedef struct {
    LoveUiV1_Rect rect;
    float radius;
    uint32_t kind;
    uint64_t revision;
} LoveUiV1_Clip;

typedef struct {
    LoveUiV1_ResourceHandle canvas;
    LoveUiV1_Rect bounds;
    float opacity;
    uint32_t blend_mode;
    uint64_t revision;
} LoveUiV1_Layer;

enum {
    LoveUiV1_GeometrySegmentKind = 1,
    LoveUiV1_TextSegmentKind = 2,
    LoveUiV1_ImageSegmentKind = 3,
    LoveUiV1_ClipPushSegmentKind = 4,
    LoveUiV1_ClipPopSegmentKind = 5,
    LoveUiV1_LayerPushSegmentKind = 6,
    LoveUiV1_LayerPopSegmentKind = 7
};

typedef struct {
    uint32_t kind;
    uint32_t item_index;
} LoveUiV1_Segment;

typedef struct {
    LoveUiV1_Vertex vertices[LoveUiV1_MaxVertices];
    uint32_t indices[LoveUiV1_MaxIndices];
    LoveUiV1_GeometryBatch geometry_batches[LoveUiV1_MaxGeometryBatches];
    LoveUiV1_TextDraw text_draws[LoveUiV1_MaxTextDraws];
    LoveUiV1_ImageDraw image_draws[LoveUiV1_MaxImageDraws];
    LoveUiV1_Clip clips[LoveUiV1_MaxClips];
    LoveUiV1_Layer layers[LoveUiV1_MaxLayers];
    LoveUiV1_Segment segments[LoveUiV1_MaxSegments];
    uint32_t vertex_count;
    uint32_t index_count;
    uint32_t geometry_batch_count;
    uint32_t text_draw_count;
    uint32_t image_draw_count;
    uint32_t clip_count;
    uint32_t layer_count;
    uint32_t segment_count;
    uint32_t overflow_count;
    uint32_t reserved;
    uint64_t layout_revision;
    uint64_t revision;
} LoveUiV1_FrameProjection;

typedef struct {
    LoveUiV1_FrameProjection frame;
    uint64_t commit_count;
} LoveUiV1_Paint;

typedef struct {
    LoveUiV1_ResourceHandle mesh;
    LoveUiV1_ResourceHandle shader;
    uint64_t uploaded_revision;
    uint64_t draw_count;
    uint64_t uploaded_vertices;
    uint64_t uploaded_indices;
} LoveUiV1_GeometryRenderer;

typedef struct {
    uint64_t drawn_revision;
    uint64_t draw_count;
    uint64_t rebuilt_count;
} LoveUiV1_TextRenderer;

typedef struct {
    LoveUiV1_ResourceHandle sprite_batch;
    uint64_t drawn_revision;
    uint64_t draw_count;
    uint64_t rebuilt_count;
} LoveUiV1_ImageRenderer;

typedef struct {
    LoveUiV1_Rect stack[LoveUiV1_MaxClipDepth];
    uint32_t depth;
    uint32_t maximum_depth;
    uint64_t change_count;
} LoveUiV1_ClipRenderer;

typedef struct {
    LoveUiV1_ResourceHandle stack[LoveUiV1_MaxLayerDepth];
    uint32_t depth;
    uint32_t maximum_depth;
    uint64_t change_count;
} LoveUiV1_LayerRenderer;

typedef struct {
    LoveUiV1_GeometryRenderer geometry;
    LoveUiV1_TextRenderer text;
    LoveUiV1_ImageRenderer image;
    LoveUiV1_ClipRenderer clip;
    LoveUiV1_LayerRenderer layer;
    uint32_t segment_cursor;
    uint32_t rejected_segment;
    uint64_t projection_revision;
    uint64_t rendered_revision;
    uint64_t frame_count;
    uint64_t rejection_count;
} LoveUiV1_Renderer;

typedef struct {
    LoveUiV1_Host host;
    LoveUiV1_Input input;
    LoveUiV1_Interaction interaction;
    LoveUiV1_Model model;
    LoveUiV1_TextMeasure text_measure;
    LoveUiV1_Layout layout;
    LoveUiV1_Paint paint;
    LoveUiV1_Renderer renderer;
    uint64_t epoch;
    uint64_t ignored_count;
    uint64_t local_visual_change_count;
    uint64_t model_change_count;
    uint64_t text_change_count;
    uint64_t layout_change_count;
    uint64_t suspension_count;
} LoveUiV1_Application;

typedef struct {
    uint32_t enabled;
    uint32_t reserved;
    uint64_t measured_turns;
    uint64_t report_count;
    double turn_started_seconds;
    double heap_started_kb;
    uint64_t uploads_started;
    uint64_t draws_started;
    uint64_t mesh_rebuilds_started;
    uint64_t text_rebuilds_started;
    double last_drain_seconds;
    double total_drain_seconds;
    double max_drain_seconds;
    double last_window_seconds;
    double total_window_seconds;
    double max_window_seconds;
    double last_tick_seconds;
    double total_tick_seconds;
    double max_tick_seconds;
    double last_render_seconds;
    double total_render_seconds;
    double max_render_seconds;
    double last_present_seconds;
    double total_present_seconds;
    double max_present_seconds;
    double last_turn_seconds;
    double total_turn_seconds;
    double max_turn_seconds;
    double last_heap_delta_kb;
    double max_heap_growth_kb;
    uint64_t last_uploads;
    uint64_t last_draws;
    uint64_t last_mesh_rebuilds;
    uint64_t last_text_rebuilds;
    uint64_t upload_count;
    uint64_t draw_count;
    uint64_t mesh_rebuild_count;
    uint64_t text_rebuild_count;
    double next_report_seconds;
} LoveUiV1_DriverMetrics;

typedef struct {
    LoveUiV1_Application application;
    LoveUiV1_DriverMetrics metrics;
    uint64_t turn_count;
    uint64_t drained_event_count;
    uint64_t ignored_event_count;
    uint64_t render_turn_count;
    uint64_t idle_turn_count;
    uint64_t quit_turn_count;
    uint32_t running;
    int32_t exit_code;
    uint32_t bootstrap_remaining;
    uint32_t reserved;
} LoveUiV1_Driver;
 ]]

local Rect = S:product("LoveUiV1_Rect")
local Host = S:product("LoveUiV1_Host")
local Input = S:product("LoveUiV1_Input")
local Drag = S:sum("Drag")
local DragIdle = Drag:leaf("LoveUiV1_DragIdle")
local DragPending = Drag:leaf("LoveUiV1_DragPending")
local Dragging = Drag:leaf("LoveUiV1_Dragging")
local DragPayload = S:union("LoveUiV1_DragPayload")
local DragState = S:product("LoveUiV1_DragState")
local Interaction = S:product("LoveUiV1_Interaction")
local ToolbarModel = S:product("LoveUiV1_ToolbarModel")
local WorkspaceModel = S:product("LoveUiV1_WorkspaceModel")
local StatusModel = S:product("LoveUiV1_StatusModel")
local Model = S:product("LoveUiV1_Model")
local TextMetric = S:product("LoveUiV1_TextMetric")
local TextMeasure = S:product("LoveUiV1_TextMeasure")
local LayoutBox = S:product("LoveUiV1_LayoutBox")
local Layout = S:product("LoveUiV1_Layout")
local Vertex = S:product("LoveUiV1_Vertex")
local GeometryBatch = S:product("LoveUiV1_GeometryBatch")
local TextDraw = S:product("LoveUiV1_TextDraw")
local ImageDraw = S:product("LoveUiV1_ImageDraw")
local Clip = S:product("LoveUiV1_Clip")
local Layer = S:product("LoveUiV1_Layer")
local Segment = S:product("LoveUiV1_Segment")
local FrameProjection = S:product("LoveUiV1_FrameProjection")
local Paint = S:product("LoveUiV1_Paint")
local GeometryRenderer = S:product("LoveUiV1_GeometryRenderer")
local TextRenderer = S:product("LoveUiV1_TextRenderer")
local ImageRenderer = S:product("LoveUiV1_ImageRenderer")
local ClipRenderer = S:product("LoveUiV1_ClipRenderer")
local LayerRenderer = S:product("LoveUiV1_LayerRenderer")
local Renderer = S:product("LoveUiV1_Renderer")
local Application = S:product("LoveUiV1_Application")
local DriverMetrics = S:product("LoveUiV1_DriverMetrics")
local Driver = S:product("LoveUiV1_Driver")

-- This module deliberately does not declare methods and does not seal S.
-- The physical schema must be reviewed before the behavior module installs
-- concrete methods and seals the FFI metatypes once.
return {
    Context = S,
    Rect = Rect,
    Host = Host,
    Input = Input,
    Drag = Drag,
    DragIdle = DragIdle,
    DragPending = DragPending,
    Dragging = Dragging,
    DragPayload = DragPayload,
    DragState = DragState,
    Interaction = Interaction,
    ToolbarModel = ToolbarModel,
    WorkspaceModel = WorkspaceModel,
    StatusModel = StatusModel,
    Model = Model,
    TextMetric = TextMetric,
    TextMeasure = TextMeasure,
    LayoutBox = LayoutBox,
    Layout = Layout,
    Vertex = Vertex,
    GeometryBatch = GeometryBatch,
    TextDraw = TextDraw,
    ImageDraw = ImageDraw,
    Clip = Clip,
    Layer = Layer,
    Segment = Segment,
    FrameProjection = FrameProjection,
    Paint = Paint,
    GeometryRenderer = GeometryRenderer,
    TextRenderer = TextRenderer,
    ImageRenderer = ImageRenderer,
    ClipRenderer = ClipRenderer,
    LayerRenderer = LayerRenderer,
    Renderer = Renderer,
    Application = Application,
    DriverMetrics = DriverMetrics,
    Driver = Driver,
    capacities = {
        text_metrics = 1024,
        layout_boxes = 4096,
        vertices = 32768,
        indices = 49152,
        geometry_batches = 4096,
        text_draws = 2048,
        image_draws = 2048,
        clips = 1024,
        layers = 128,
        segments = 8192,
        clip_depth = 64,
        layer_depth = 16,
    },
}

