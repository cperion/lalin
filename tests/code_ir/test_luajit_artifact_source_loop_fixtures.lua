package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local lalin = require('lalin')
local asdl = require("lalin.asdl")

local instruction_budget = 20000000

local fixtures = {
    {
        name = 'parsed_gather_indexed_read_i32',
        expect = 'artifact',
        sink = 'LalinStencil.StencilSinkStore',
        access_layouts = {
            'LalinStencil.StencilAccessWrite:LalinStencil.StencilLayoutContiguous',
            'LalinStencil.StencilAccessRead:LalinStencil.StencilLayoutIndexed',
            'LalinStencil.StencilAccessIndex:LalinStencil.StencilLayoutContiguous',
        },
        source = [=[
local f = fn(dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), bounds(idx)(n), readonly(idx)
  requires disjoint(dst)(src), disjoint(dst)(idx), disjoint(src)(idx)
  loop i in 0 .. n do
    dst[i] = src[idx[i]]
  end
end
return { f }
]=],
    },
    {
        name = 'parsed_scatter_write_i32',
        expect = 'artifact',
        sink = 'LalinStencil.StencilSinkStore',
        access_layouts = {
            'LalinStencil.StencilAccessWrite:LalinStencil.StencilLayoutIndexed',
            'LalinStencil.StencilAccessRead:LalinStencil.StencilLayoutContiguous',
            'LalinStencil.StencilAccessIndex:LalinStencil.StencilLayoutContiguous',
        },
        source = [=[
local f = fn(dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), bounds(src)(n), readonly(src), bounds(idx)(n), readonly(idx)
  requires disjoint(dst)(src), disjoint(dst)(idx), disjoint(src)(idx)
  loop i in 0 .. n do
    dst[idx[i]] = src[i]
  end
end
return { f }
]=],
    },
    {
        name = 'parsed_scatter_reduce_add_i32',
        expect = 'artifact',
        sink = 'LalinStencil.StencilSinkScatterReduce',
        access_layouts = {
            'LalinStencil.StencilAccessReadWrite:LalinStencil.StencilLayoutIndexed',
            'LalinStencil.StencilAccessRead:LalinStencil.StencilLayoutContiguous',
            'LalinStencil.StencilAccessIndex:LalinStencil.StencilLayoutContiguous',
        },
        source = [=[
local f = fn(dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), bounds(src)(n), readonly(src), bounds(idx)(n), readonly(idx)
  requires disjoint(dst)(src), disjoint(dst)(idx), disjoint(src)(idx)
  loop i in 0 .. n do
    dst[idx[i]] = dst[idx[i]] + src[i]
  end
end
return { f }
]=],
    },
    {
        name = 'parsed_dynamic_affine_nd_transpose_i32',
        expect = 'backend_error',
        error_pattern = 'attempt to perform arithmetic on a nil value',
        source = [=[
local f = fn(dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i, j in grid(0 .. h, 0 .. w) do
    dst[j * h + i] = src[i * w + j]
  end
end
return { f }
]=],
    },
    {
        name = 'parsed_predicate_composition_i32_range',
        expect = 'frontend_only',
        source = [=[
local f = fn(dst [ptr [bool]], xs [ptr [i32]], lo [i32], hi [i32], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    dst[i] = xs[i] > lo and xs[i] < hi
  end
end
return { f }
]=],
    },
}

local function with_instruction_budget(fn)
    local function hook()
        error('instruction budget exceeded', 0)
    end
    debug.sethook(hook, '', instruction_budget)
    local ok, result = pcall(fn)
    debug.sethook()
    if ok then return true, result end
    return false, result
end

local function plan_fixture(fixture)
    return with_instruction_budget(function()
        local chunk = assert(lalin.loadstring(fixture.source, '@' .. fixture.name .. '.lln'))
        local parsed = chunk()
        return lalin.plan_luajit_artifact(parsed, {
            name = fixture.name,
            collect_rejects = true,
            reject_on_stencil_rejects = false,
        })
    end)
end

local function artifact_count(plan)
    if type(plan.artifacts) ~= 'table' then return 0 end
    return #plan.artifacts
end

local function reject_count(plan)
    if type(plan.rejects) ~= 'table' then return 0 end
    return #plan.rejects
end

local function class_name(v)
    return tostring(asdl.classof(v)):match('Class%((.-)%)') or tostring(asdl.classof(v))
end

local function assert_artifact_shape(fixture, plan)
    local artifact = assert(plan.artifacts[1], fixture.name .. ' selected no first artifact')
    local descriptor = artifact.instance.descriptor
    assert(class_name(descriptor.producer.shape) == 'LalinStencil.StencilProduceRange1D',
        fixture.name .. ' should preserve the 1D range producer')
    if fixture.sink then
        assert(class_name(descriptor.sink) == fixture.sink,
            fixture.name .. ' expected sink ' .. fixture.sink .. ', got ' .. class_name(descriptor.sink))
    end

    local seen = {}
    for _, access in ipairs(descriptor.accesses or {}) do
        local key = class_name(access.role) .. ':' .. class_name(access.layout)
        seen[key] = (seen[key] or 0) + 1
    end
    for _, key in ipairs(fixture.access_layouts or {}) do
        assert(seen[key] ~= nil and seen[key] > 0, fixture.name .. ' missing descriptor access ' .. key)
        seen[key] = seen[key] - 1
    end
end

for _, fixture in ipairs(fixtures) do
    if fixture.expect == 'frontend_only' then
        local chunk = assert(lalin.loadstring(fixture.source, '@' .. fixture.name .. '.lln'))
        assert(chunk() ~= nil, fixture.name .. ' should parse and convert to LalinTree')
    else
        local ok, result = plan_fixture(fixture)
        if fixture.expect == 'backend_error' then
            assert(not ok, fixture.name .. ' should expose the current backend error gap')
            assert(tostring(result):match(fixture.error_pattern), fixture.name .. ' unexpected error: ' .. tostring(result))
        elseif fixture.expect == 'no_selection' then
            assert(ok, fixture.name .. ' should reach backend planning: ' .. tostring(result))
            assert(artifact_count(result) == 0, fixture.name .. ' unexpectedly selected a stencil artifact')
            assert(reject_count(result) == 0, fixture.name .. ' should currently return the no-selection sentinel, not typed rejects')
        elseif fixture.expect == 'artifact' then
            assert(ok, fixture.name .. ' should select a stencil artifact: ' .. tostring(result))
            assert(artifact_count(result) > 0, fixture.name .. ' selected no stencil artifacts')
            assert(reject_count(result) == 0, fixture.name .. ' should not have stencil rejects')
            assert_artifact_shape(fixture, result)
        elseif fixture.expect == 'typed_reject' then
            assert(ok, fixture.name .. ' should produce typed rejects without backend errors: ' .. tostring(result))
            assert(artifact_count(result) == 0, fixture.name .. ' unexpectedly selected a stencil artifact')
            assert(reject_count(result) > 0, fixture.name .. ' produced no typed reject')
        else
            error('unknown fixture expectation: ' .. tostring(fixture.expect))
        end
    end
end

io.write('test_luajit_artifact_source_loop_fixtures: ok\n')
