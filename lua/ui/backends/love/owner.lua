
local M = {}
local Owner = {}
Owner.__index = Owner

local vertex_format = {
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "byte", 4 },
}

local function rgba(rgba8, opacity)
    local value = tonumber(rgba8)
    local a = value % 256
    value = math.floor(value / 256)
    local b = value % 256
    value = math.floor(value / 256)
    local g = value % 256
    value = math.floor(value / 256)
    local r = value % 256
    return r / 255, g / 255, b / 255, (a / 255) * (opacity or 1)
end

local function integer(value) return math.floor(tonumber(value) + 0.5) end

local function intersect(a, x, y, width, height)
    if a == nil then return x, y, width, height end
    local x2 = math.min(a[1] + a[3], x + width)
    local y2 = math.min(a[2] + a[4], y + height)
    x = math.max(a[1], x)
    y = math.max(a[2], y)
    return x, y, math.max(0, x2 - x), math.max(0, y2 - y)
end

function M.new(options)
    assert(love and love.graphics, "ui.backends.love.owner requires LÖVE")
    options = options or {}
    local images = options.images or {}
    if images[1] == nil then
        local data = love.image.newImageData(32, 32)
        for y = 0, 31 do
            for x = 0, 31 do
                local checker = (math.floor(x / 8) + math.floor(y / 8)) % 2
                local glow = 0.55 + 0.45 * (x + y) / 62
                data:setPixel(x, y, 0.20 + checker * 0.16, 0.48 * glow, 0.86 * glow, 1)
            end
        end
        images[1] = love.graphics.newImage(data)
        images[1]:setFilter("linear", "linear")
    end

    local contents = {
        [100] = "OPERATIONS / LIVE SYSTEMS",
        [101] = "Overview", [102] = "Explore", [103] = "Automate", [104] = "Deploy",
        [110] = "Command", [111] = "Services", [112] = "Pipelines", [113] = "Signals",
        [114] = "Storage", [115] = "Network", [116] = "Audit",
        [120] = "Gateway", [121] = "Workers", [122] = "Scheduler", [123] = "Database",
        [124] = "Telemetry", [125] = "Cache", [126] = "Ingress", [127] = "Queue",
        [128] = "Build", [129] = "Search", [130] = "Billing", [131] = "Archive",
        [140] = "Live resource activity · retained geometry, images, text, clips, and layers",
    }
    local self = setmetatable({
        contents = contents,
        next_content = 200,
        font_sizes = options.font_sizes or { [1] = 14 },
        fonts = {},
        texts = {},
        images = images,
        shaders = options.shaders or {},
        canvases = options.canvases or {},
        quads = {},
        vertices = {},
        indices = {},
        mesh = nil,
        mesh_capacity = 0,
        clip_stack = {},
        clip_depth = 0,
        layer_stack = {},
        layer_depth = 0,
        clear_rgba8 = options.clear_rgba8 or 0x10141cff,
        uploads = 0,
        draw_calls = 0,
        mesh_rebuilds = 0,
        text_rebuilds = 0,
    }, Owner)

    if options.contents then
        for handle, content in pairs(options.contents) do
            self.contents[handle] = content
            if type(handle) == "number" and handle >= self.next_content then
                self.next_content = handle + 1
            end
        end
    end
    return self
end

function Owner:register_content(content)
    assert(type(content) == "string", "content must be a string")
    local handle = self.next_content
    self.next_content = handle + 1
    self.contents[handle] = content
    return handle
end

function Owner:append_content(handle, suffix)
    local content = self.contents[tonumber(handle)] or ""
    return self:register_content(content .. suffix)
end

function Owner:content(handle)
    return assert(self.contents[tonumber(handle)], "unknown LÖVE content handle")
end

function Owner:font(handle, requested_size)
    handle = tonumber(handle)
    local size = requested_size or self.font_sizes[handle] or 14
    local family = self.fonts[handle]
    if family == nil then
        family = {}
        self.fonts[handle] = family
    end
    local font = family[size]
    if font == nil then
        font = love.graphics.newFont(size)
        font:setFilter("linear", "linear", 1)
        family[size] = font
    end
    return font, size
end

function Owner:measure_text(content_handle, font_handle, font_size, wrap_width)
    local content = self:content(content_handle)
    local font = self:font(font_handle, font_size)
    local width, lines = font:getWrap(content, math.max(1, wrap_width))
    local line_count = math.max(1, #lines)
    local line_height = font:getHeight() * font:getLineHeight()
    return width, line_count * line_height, font:getBaseline(), line_height, line_count
end

function Owner:begin_frame(_host, _projection)
    love.graphics.origin()
    love.graphics.setCanvas()
    love.graphics.setScissor()
    love.graphics.setStencilTest()
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    local r, g, b, a = rgba(self.clear_rgba8)
    love.graphics.clear(r, g, b, a)
    self.clip_depth = 0
    self.layer_depth = 0
end

function Owner:upload_geometry(projection)
    local count = tonumber(projection.vertex_count)
    local index_count = tonumber(projection.index_count)
    if count == 0 then return end

    for index = 0, count - 1 do
        local source = projection.vertices[index]
        local target = self.vertices[index + 1]
        if target == nil then
            target = {}
            self.vertices[index + 1] = target
        end
        local r, g, b, a = rgba(source.rgba8)
        target[1], target[2] = source.x, source.y
        target[3], target[4] = source.u, source.v
        target[5], target[6], target[7], target[8] = r, g, b, a
    end
    for index = count + 1, #self.vertices do self.vertices[index] = nil end

    for index = 0, index_count - 1 do
        self.indices[index + 1] = tonumber(projection.indices[index]) + 1
    end
    for index = index_count + 1, #self.indices do self.indices[index] = nil end

    if self.mesh == nil or self.mesh_capacity < count then
        self.mesh_capacity = count
        self.mesh = love.graphics.newMesh(vertex_format, count, "triangles", "dynamic")
        self.mesh_rebuilds = self.mesh_rebuilds + 1
    end
    self.mesh:setVertices(self.vertices, 1, count)
    self.mesh:setVertexMap(self.indices)
    self.uploads = self.uploads + 1
end

function Owner:draw_geometry(_projection, batch)
    if batch.index_count == 0 then return end
    local mesh = assert(self.mesh, "geometry draw before upload")
    local image = self.images[tonumber(batch.image)]
    mesh:setTexture(image)
    mesh:setDrawRange(tonumber(batch.first_index) + 1,
        tonumber(batch.first_index + batch.index_count))
    local shader = self.shaders[tonumber(batch.shader)]
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
    love.graphics.setShader()
    self.draw_calls = self.draw_calls + 1
end

function Owner:draw_text(draw)
    local content = self:content(draw.content)
    local font, size = self:font(draw.font)
    local content_handle = tonumber(draw.content)
    local font_handle = tonumber(draw.font)
    local wrap_width = integer(draw.wrap_width)
    local alignment = tonumber(draw.alignment)
    local by_content = self.texts[content_handle]
    if by_content == nil then by_content = {}; self.texts[content_handle] = by_content end
    local by_font = by_content[font_handle]
    if by_font == nil then by_font = {}; by_content[font_handle] = by_font end
    local by_width = by_font[wrap_width]
    if by_width == nil then by_width = {}; by_font[wrap_width] = by_width end
    local text = by_width[alignment]
    if text == nil then
        text = love.graphics.newText(font)
        self.text_rebuilds = self.text_rebuilds + 1
        local alignments = { [0] = "left", [1] = "center", [2] = "right", [3] = "justify" }
        text:setf(content, math.max(1, draw.wrap_width), alignments[alignment] or "left")
        by_width[alignment] = text
    end
    love.graphics.setColor(rgba(draw.rgba8, draw.opacity))
    love.graphics.draw(text, draw.x, draw.y)
    love.graphics.setColor(1, 1, 1, 1)
    self.draw_calls = self.draw_calls + 1
end

function Owner:draw_image(draw)
    local image = assert(self.images[tonumber(draw.image)], "unknown LÖVE image handle")
    local source = draw.source
    local destination = draw.destination
    local source_width = source.width > 0 and source.width or image:getWidth()
    local source_height = source.height > 0 and source.height or image:getHeight()
    local image_handle = tonumber(draw.image)
    local by_image = self.quads[image_handle]
    if by_image == nil then by_image = {}; self.quads[image_handle] = by_image end
    local by_x = by_image[source.x]
    if by_x == nil then by_x = {}; by_image[source.x] = by_x end
    local by_y = by_x[source.y]
    if by_y == nil then by_y = {}; by_x[source.y] = by_y end
    local by_width = by_y[source_width]
    if by_width == nil then by_width = {}; by_y[source_width] = by_width end
    local quad = by_width[source_height]
    if quad == nil then
        quad = love.graphics.newQuad(source.x, source.y, source_width, source_height,
            image:getDimensions())
        by_width[source_height] = quad
    end
    love.graphics.setColor(rgba(draw.tint_rgba8, draw.opacity))
    love.graphics.draw(image, quad, destination.x, destination.y, draw.rotation,
        destination.width / source_width, destination.height / source_height)
    love.graphics.setColor(1, 1, 1, 1)
    self.draw_calls = self.draw_calls + 1
end

function Owner:push_clip(clip)
    local depth = self.clip_depth
    local previous = depth > 0 and self.clip_stack[depth] or nil
    local rect = clip.rect
    local x, y, width, height = intersect(previous, rect.x, rect.y, rect.width, rect.height)
    local current = self.clip_stack[depth + 1]
    if current == nil then current = {}; self.clip_stack[depth + 1] = current end
    current[1], current[2], current[3], current[4] = x, y, width, height
    self.clip_depth = depth + 1
    love.graphics.setScissor(integer(x), integer(y), integer(width), integer(height))
end

function Owner:pop_clip()
    local depth = self.clip_depth
    assert(depth > 0, "LÖVE clip stack underflow")
    depth = depth - 1
    self.clip_depth = depth
    local previous = depth > 0 and self.clip_stack[depth] or nil
    if previous then love.graphics.setScissor(unpack(previous))
    else love.graphics.setScissor() end
end

function Owner:push_layer(layer)
    local handle = tonumber(layer.canvas)
    local width = math.max(1, integer(layer.bounds.width))
    local height = math.max(1, integer(layer.bounds.height))
    local canvas = self.canvases[handle]
    if canvas == nil or canvas:getWidth() ~= width or canvas:getHeight() ~= height then
        canvas = love.graphics.newCanvas(width, height)
        self.canvases[handle] = canvas
    end
    local previous = love.graphics.getCanvas()
    local depth = self.layer_depth + 1
    local entry = self.layer_stack[depth]
    if entry == nil then entry = {}; self.layer_stack[depth] = entry end
    entry.previous = previous
    entry.canvas = canvas
    entry.x = layer.bounds.x
    entry.y = layer.bounds.y
    entry.opacity = layer.opacity
    self.layer_depth = depth
    love.graphics.push()
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.translate(-layer.bounds.x, -layer.bounds.y)
end

function Owner:pop_layer()
    local depth = self.layer_depth
    assert(depth > 0, "LÖVE layer stack underflow")
    local entry = self.layer_stack[depth]
    self.layer_depth = depth - 1
    love.graphics.pop()
    love.graphics.setCanvas(entry.previous)
    love.graphics.setColor(1, 1, 1, entry.opacity)
    love.graphics.draw(entry.canvas, entry.x, entry.y)
    love.graphics.setColor(1, 1, 1, 1)
    self.draw_calls = self.draw_calls + 1
end

function Owner:end_frame()
    love.graphics.setShader()
    love.graphics.setStencilTest()
    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
end

M.Owner = Owner
return M

