-- Runtime-parameterized pipeline exotype.
--
-- Stage objects are concrete semantic leaves.  The C emitter calls a leaf method;
-- it never switches on a stage kind.  This is staging dispatch, and no stage object
-- survives in native execution.

local P = require("experiments.exotype_c_emit.protocol")

local Pipeline = {}

local StateLayout = {}
StateLayout.__index = StateLayout
local ModuleQuote = {}
ModuleQuote.__index = ModuleQuote

Pipeline.StateLayout = StateLayout
Pipeline.ModuleQuote = ModuleQuote
Pipeline.Layout = P.property("StateLayout", StateLayout)
Pipeline.Module = P.property("CModule", ModuleQuote)

local AddStage = {}
AddStage.__index = AddStage
local MultiplyStage = {}
MultiplyStage.__index = MultiplyStage
local RejectAboveStage = {}
RejectAboveStage.__index = RejectAboveStage

local function exact_integer(value)
    assert(type(value) == "number" and value == math.floor(value), "stage value must be an integer")
    return value
end

function Pipeline.add(value) return setmetatable({ value = exact_integer(value) }, AddStage) end
function Pipeline.multiply(value) return setmetatable({ value = exact_integer(value) }, MultiplyStage) end
function Pipeline.reject_above(value)
    return setmetatable({ value = exact_integer(value) }, RejectAboveStage)
end

function AddStage:key() return "add:" .. self.value end
function MultiplyStage:key() return "multiply:" .. self.value end
function RejectAboveStage:key() return "reject_above:" .. self.value end

function AddStage:emit(lines, next_name)
    lines[#lines + 1] = "    self->value += " .. self.value .. ";"
    lines[#lines + 1] = "    return " .. next_name .. "(self);"
end

function MultiplyStage:emit(lines, next_name)
    lines[#lines + 1] = "    self->value *= " .. self.value .. ";"
    lines[#lines + 1] = "    return " .. next_name .. "(self);"
end

function RejectAboveStage:emit(lines, next_name, rejected_name)
    lines[#lines + 1] = "    if (self->value > " .. self.value .. ")"
    lines[#lines + 1] = "        return " .. rejected_name .. "(self);"
    lines[#lines + 1] = "    return " .. next_name .. "(self);"
end

function StateLayout:c_declaration()
    return table.concat({
        ("typedef struct %s {"):format(self.ctype_name),
        "    int64_t value;",
        "    uint32_t transitions;",
        "    uint32_t completed;",
        "    uint32_t rejected;",
        "    uint32_t remaining;",
        ("    uint32_t stage_hits[%d];"):format(self.stage_count),
        ("} %s;"):format(self.ctype_name),
    }, "\n")
end

function ModuleQuote:ffi_declaration()
    return ("int32_t %s(%s *self, int64_t input, uint32_t rounds);"):format(
        self.symbol, self.ctype_name)
end

local constructor_cache = {}
local owner_count = 0

local function structural_token(value)
    local hash = 0
    for index = 1, #value do hash = (hash * 131 + value:byte(index)) % 4294967296 end
    return ("%08x"):format(hash)
end

function Pipeline.type(stages)
    assert(type(stages) == "table" and #stages > 0, "pipeline requires at least one stage")
    local keys = {}
    for index = 1, #stages do
        assert(type(stages[index].key) == "function", "pipeline stage must be a concrete stage leaf")
        keys[index] = stages[index]:key()
    end
    local key = table.concat(keys, ",")
    local token = structural_token(key)
    if constructor_cache[key] ~= nil then return constructor_cache[key] end

    owner_count = owner_count + 1
    local owner
    local properties = {}
    properties[Pipeline.Layout] = function()
        return setmetatable({
            ctype_name = "ExotypeCEmitV1_Pipeline_" .. token .. "_State",
            stage_count = #stages,
        }, StateLayout)
    end

    properties[Pipeline.Module] = function(compiler)
        local layout = P.query(compiler, owner, Pipeline.Layout)
        local prefix = "exotype_c_emit_pipeline_" .. token
        local symbol = prefix .. "_run"
        local completed = prefix .. "_completed"
        local rejected = prefix .. "_rejected"
        local loop = prefix .. "_loop"
        local stage_names = {}
        for index = 1, #stages do stage_names[index] = prefix .. "_stage_" .. index end

        local lines = {
            "#include <stdint.h>",
            "",
            layout:c_declaration(),
            "",
        }
        for index = 1, #stage_names do
            lines[#lines + 1] = ("static int32_t %s(%s *self);"):format(
                stage_names[index], layout.ctype_name)
        end
        lines[#lines + 1] = ("static int32_t %s(%s *self);"):format(loop, layout.ctype_name)
        lines[#lines + 1] = ""

        lines[#lines + 1] = ("static int32_t %s(%s *self) {"):format(
            completed, layout.ctype_name)
        lines[#lines + 1] = "    self->completed += 1;"
        lines[#lines + 1] = "    return 1;"
        lines[#lines + 1] = "}"
        lines[#lines + 1] = ("static int32_t %s(%s *self) {"):format(
            rejected, layout.ctype_name)
        lines[#lines + 1] = "    self->rejected += 1;"
        lines[#lines + 1] = "    return 0;"
        lines[#lines + 1] = "}"
        lines[#lines + 1] = ""

        for index = 1, #stages do
            local next_name = index == #stages and loop or stage_names[index + 1]
            lines[#lines + 1] = ("static int32_t %s(%s *self) {"):format(
                stage_names[index], layout.ctype_name)
            lines[#lines + 1] = "    self->transitions += 1;"
            lines[#lines + 1] = ("    self->stage_hits[%d] += 1;"):format(index - 1)
            stages[index]:emit(lines, next_name, rejected)
            lines[#lines + 1] = "}"
            lines[#lines + 1] = ""
        end

        lines[#lines + 1] = ("static int32_t %s(%s *self) {"):format(loop, layout.ctype_name)
        lines[#lines + 1] = "    self->remaining -= 1;"
        lines[#lines + 1] = "    if (self->remaining > 0)"
        lines[#lines + 1] = "        return " .. stage_names[1] .. "(self);"
        lines[#lines + 1] = "    return " .. completed .. "(self);"
        lines[#lines + 1] = "}"
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("int32_t %s(%s *self, int64_t input, uint32_t rounds) {"):format(
            symbol, layout.ctype_name)
        lines[#lines + 1] = "    self->value = input;"
        lines[#lines + 1] = "    self->remaining = rounds;"
        lines[#lines + 1] = "    if (rounds == 0)"
        lines[#lines + 1] = "        return " .. completed .. "(self);"
        lines[#lines + 1] = "    return " .. stage_names[1] .. "(self);"
        lines[#lines + 1] = "}"

        return setmetatable({
            source = table.concat(lines, "\n"),
            symbol = symbol,
            ctype_name = layout.ctype_name,
            stage_count = #stages,
        }, ModuleQuote)
    end

    owner = P.owner("Pipeline" .. owner_count, properties, stages)
    owner.artifact_key = token
    constructor_cache[key] = owner
    return owner
end

return Pipeline
