package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local MODE = os.getenv('ZYN_SYNTH_TEST_MODE') or 'all'
local script = arg and arg[0] or 'tests/test_zyn_moonlift_synth_impl.lua'
local function run_child(mode)
  local cmd = 'ZYN_SYNTH_TEST_MODE=' .. mode .. ' luajit ' .. script
  local ok = os.execute(cmd)
  assert(ok == true or ok == 0, 'child test phase failed: ' .. mode)
end
if MODE == 'all' then
  -- Keep the full smoke suite from accumulating several independent compiler
  -- worlds in one LuaJIT heap.  Each child still exercises the real compiler;
  -- the parent only orchestrates phases.
  run_child('compile')
  run_child('behavior')
  print('ok zyn synth implementation compile and behavioral smoke coverage')
  return
elseif MODE == 'compile' then
  run_child('compile_abi')
  run_child('compile_wrappers')
  print('ok zyn synth implementation compile coverage')
  return
elseif MODE == 'compile_wrappers' then
  run_child('compile_wrapper_render_voice')
  run_child('compile_wrapper_render_part_voices')
  run_child('compile_wrapper_render_all_parts')
  print('ok zyn synth render wrapper compile coverage')
  return
end

local ffi = require('ffi')
local moon = require('moonlift')

local M = moon.dofile('examples/synth/zyn_moonlift_synth_impl.mlua')
local T, R, F = M.T, M.R, M.F

local function assert_no_headers(group_name, group)
  for name, value in pairs(group) do
    assert(type(value) == 'table', group_name .. '.' .. name .. ' is not a Moonlift value')
    assert(value.kind ~= 'region_header' and value.kind ~= 'func_header',
      group_name .. '.' .. name .. ' is still an unimplemented header')
  end
end

assert_no_headers('R', R)
assert_no_headers('F', F)

local function full_gc()
  collectgarbage('collect')
  collectgarbage('collect')
end

local function compile_value(label, value)
  io.write(label .. ' ... '); io.flush()
  full_gc()
  value._compiled_key = nil
  value:compile()
  value:free()
  value._compiled_key = nil
  full_gc()
  print('ok')
end

if MODE == 'compile_abi' then
-- ABI seals must all bundle/compile; this also pulls their internal region deps.
for _, name in ipairs({
  'synth_required_storage',
  'synth_init',
  'synth_prepare_program',
  'synth_render_block',
  'synth_set_parameter',
  'synth_note_on',
  'synth_note_off',
  'synth_all_notes_off',
  'synth_panic',
}) do
  compile_value('F.' .. name, F[name])
end
print('ok zyn synth ABI compile coverage')
return
end

local B = {
  render_voice = R.render_voice,
  render_part_voices = R.render_part_voices,
  render_all_parts = R.render_all_parts,
  render_block = R.render_block,
}
for k, v in pairs(T) do B[k] = v end

local render_voice_wrapper = moon.func(B)[[
func check_render_voice(program: ptr(@{PreparedProgram}), cache: ptr(@{PadCache}), pool: ptr(@{VoicePool}), controls: ptr(@{ControlBank}), v: @{VoiceRef}, ctx: @{RenderCtx}, scratch: ptr(@{RenderScratch})): i32
return region: i32
entry start()
  emit @{render_voice}(program, cache, pool, controls, v, ctx, scratch; alive = alive, dead = dead, silent = silent, stale_ref = stale, missing_cache = missing, bad_buffer = bad)
end
block alive(v: @{VoiceRef}, peak: f32) yield 1 end
block dead(v: @{VoiceRef}) yield 2 end
block silent(v: @{VoiceRef}) yield 3 end
block stale(v: @{VoiceRef}) yield 4 end
block missing(ref: @{PadTableRef}) yield 5 end
block bad() yield -1 end
end
end
]]

local render_part_wrapper = moon.func(B)[[
func check_render_part_voices(program: ptr(@{PreparedProgram}), cache: ptr(@{PadCache}), pool: ptr(@{VoicePool}), controls: ptr(@{ControlBank}), part: @{PartRef}, ctx: @{RenderCtx}, scratch: ptr(@{RenderScratch})): i32
return region: i32
entry start()
  emit @{render_part_voices}(program, cache, pool, controls, part, ctx, scratch; rendered = rendered, silent = silent, missing_cache = missing, bad_buffer = bad)
end
block rendered(active: index, peak: f32) yield as(i32, active) end
block silent(active: index) yield 0 end
block missing(ref: @{PadTableRef}) yield -2 end
block bad() yield -1 end
end
end
]]

local render_all_wrapper = moon.func(B)[[
func check_render_all_parts(synth: ptr(@{Synth}), ctx: @{RenderCtx}, scratch: ptr(@{RenderScratch}), out: @{StereoBlock}): i32
return region: i32
entry start()
  emit @{render_all_parts}(synth, ctx, scratch, out; rendered = rendered, silent = silent, missing_cache = missing, bad_buffer = bad, bad_state = bad_state)
end
block rendered(active: index, peak: f32) yield as(i32, active) end
block silent(active: index) yield 0 end
block missing(ref: @{PadTableRef}) yield -2 end
block bad() yield -1 end
block bad_state(code: i32) yield code end
end
end
]]

if MODE == 'compile_wrapper_render_voice' then
compile_value('R.render_voice wrapper', render_voice_wrapper)
print('ok zyn synth render_voice wrapper compile coverage')
return
elseif MODE == 'compile_wrapper_render_part_voices' then
compile_value('R.render_part_voices wrapper', render_part_wrapper)
print('ok zyn synth render_part_voices wrapper compile coverage')
return
elseif MODE == 'compile_wrapper_render_all_parts' then
compile_value('R.render_all_parts wrapper', render_all_wrapper)
print('ok zyn synth render_all_parts wrapper compile coverage')
return
end

ffi.cdef[[
typedef struct ZynSmokeByteArena { uint8_t* data; intptr_t cap; intptr_t used; } ZynSmokeByteArena;
typedef struct ZynSmokeByteSlice { uint8_t* data; intptr_t len; } ZynSmokeByteSlice;
typedef struct ZynSmokeSynthConfig { intptr_t max_voices; intptr_t max_parts; intptr_t max_layers; intptr_t max_mod_routes; intptr_t max_additive_partials; intptr_t max_noise_bands; intptr_t max_block_frames; uint16_t program_banks; uint16_t programs_per_bank; intptr_t pad_table_count; intptr_t pad_total_frames; intptr_t effect_bus_count; intptr_t effect_slots_per_bus; intptr_t channel_count; intptr_t macro_count; } ZynSmokeSynthConfig;
typedef struct ZynSmokeDspPolicy { float denormal_floor; float clip_ceiling; bool deterministic_noise; } ZynSmokeDspPolicy;
typedef struct ZynSmokeRenderPolicy { bool clear_outputs_first; bool smooth_block_events; bool retire_dead_voices_after_block; } ZynSmokeRenderPolicy;
typedef struct ZynSmokeEnginePolicy { ZynSmokeDspPolicy dsp; ZynSmokeRenderPolicy render; } ZynSmokeEnginePolicy;
typedef struct ZynSmokeProgramStore { void* slots; uint16_t bank_count; uint16_t programs_per_bank; } ZynSmokeProgramStore;
typedef struct ZynSmokeVoicePool { void* states; uint16_t* generations; void* active; uint32_t* next_free; intptr_t cap; intptr_t active_count; uint32_t free_head; } ZynSmokeVoicePool;
typedef struct ZynSmokeControlBank { void* states; uint8_t* cc_values; float* macro_values; intptr_t channel_count; intptr_t macro_count; } ZynSmokeControlBank;
typedef struct ZynSmokePadCache { float* table_data; intptr_t* table_offsets; intptr_t* table_lengths; uint16_t* table_generations; intptr_t table_count; intptr_t total_frames; intptr_t used_frames; uint16_t generation; } ZynSmokePadCache;
typedef struct ZynSmokeEffectRack { void* states; intptr_t* bus_offsets; intptr_t* bus_slot_counts; intptr_t bus_count; intptr_t cap; uint16_t generation; } ZynSmokeEffectRack;
typedef struct ZynSmokeSynthStorage { ZynSmokeByteArena arena; ZynSmokeProgramStore programs; ZynSmokeVoicePool voices; ZynSmokeControlBank controls; ZynSmokePadCache pad_cache; ZynSmokeEffectRack effects; } ZynSmokeSynthStorage;
typedef struct ZynSmokePatchSource { ZynSmokeByteSlice bytes; uint32_t format_id; uint32_t version; } ZynSmokePatchSource;
typedef struct ZynSmokeProgramRef { uint16_t bank; uint16_t program; uint16_t generation; } ZynSmokeProgramRef;
]]

local function smoke_config()
  local cfg = ffi.new('ZynSmokeSynthConfig')
  cfg.max_voices = 2
  cfg.max_parts = 1
  cfg.max_layers = 1
  cfg.max_mod_routes = 1
  cfg.max_additive_partials = 1
  cfg.max_noise_bands = 1
  cfg.max_block_frames = 4
  cfg.program_banks = 1
  cfg.programs_per_bank = 1
  cfg.channel_count = 1
  return cfg
end

local function smoke_policy()
  local policy = ffi.new('ZynSmokeEnginePolicy')
  policy.dsp.denormal_floor = 0.000001
  policy.dsp.clip_ceiling = 1.0
  policy.dsp.deterministic_noise = true
  policy.render.clear_outputs_first = true
  policy.render.smooth_block_events = false
  policy.render.retire_dead_voices_after_block = true
  return policy
end

local function compile_for_call(label, value)
  io.write(label .. ' behavior ... '); io.flush()
  full_gc()
  value:free()
  value._compiled_key = nil
  local compiled = value:compile()
  full_gc()
  print('ok')
  return compiled
end

local required_storage = compile_for_call('F.synth_required_storage', F.synth_required_storage)
local synth_init = compile_for_call('F.synth_init', F.synth_init)
local prepare_program = compile_for_call('F.synth_prepare_program', F.synth_prepare_program)

local cfg = smoke_config()
local required = tonumber(required_storage(cfg))
assert(required and required > 0, 'valid smoke config should require storage')
local arena = ffi.new('uint8_t[?]', required + 1024)
local storage = ffi.new('ZynSmokeSynthStorage')
storage.arena.data = arena
storage.arena.cap = required + 1024
storage.arena.used = 123
local policy = smoke_policy()
local synth = ffi.new('uint64_t[2048]')
assert(synth_init(synth, storage, cfg, policy, 48000.0) == 0, 'synth_init valid config should return ok')

local bad_cfg = ffi.new('ZynSmokeSynthConfig', cfg)
bad_cfg.max_voices = 0
assert(required_storage(bad_cfg) == 0, 'invalid config should require zero storage')
assert(synth_init(synth, storage, bad_cfg, policy, 48000.0) == 1, 'invalid config init should map to bad_state')
assert(synth_init(synth, storage, cfg, policy, 48000.0) == 0, 'reinit after invalid-config smoke should succeed')

local patch_bytes = ffi.new('uint8_t[16]')
local malformed = ffi.new('ZynSmokePatchSource')
malformed.bytes.data = patch_bytes
malformed.bytes.len = 0
malformed.format_id = 0x5a594e4d
malformed.version = 1
local target = ffi.new('ZynSmokeProgramRef')
assert(prepare_program(synth, target, malformed) == 3, 'short ZYNM v1 patch should map to bad_patch')
assert(synth_init(synth, storage, cfg, policy, 48000.0) == 0, 'reinit after malformed-patch smoke should succeed')

F.synth_required_storage:free()
F.synth_init:free()
F.synth_prepare_program:free()
full_gc()

local SMOKE = {
  classify_host_event = R.classify_host_event,
  classify_midi_event = R.classify_midi_event,
  allocate_voice = R.allocate_voice,
  start_voice = R.start_voice,
  release_matching_voices = R.release_matching_voices,
  retire_voice = R.retire_voice,
  render_block = R.render_block,
}
for k, v in pairs(T) do SMOKE[k] = v end

local behavioral_wrapper = moon.func(SMOKE)[[
func check_events_voice_render(synth: ptr(@{Synth}), work: ptr(u8), out_l: ptr(f32), out_r: ptr(f32)): i32
  let policy: @{EnginePolicy} = synth[0].policy
  return region: i32
  entry events_start()
    let midi_ev: @{MidiEvent} = { kind = as(u8, 144), channel = as(u8, 0), a = as(u8, 60), b = as(u8, 0), frame = as(index, 2) }
    let host_ev: @{HostEvent} = { kind = as(u8, 1), midi = midi_ev, parameter = { address = { scope = as(u8, 1), part = as(u16, 0), layer = as(u16, 0), bus = as(u16, 0), slot = as(u16, 0), param = as(u16, 0) }, value = as(f32, 0.0), frame = as(index, 0) }, program = { bank = as(u16, 0), program = as(u16, 0), generation = as(u16, 0) }, transport = { playing = false, beat_pos = 0.0, bar_pos = 0.0, time_sig_num = as(u8, 4), time_sig_den = as(u8, 4) }, frame = as(index, 2) }
    emit @{classify_host_event}(host_ev; midi = host_midi, parameter = host_bad_param, program_change = host_bad_program, transport = host_bad_transport, all_notes_off = host_bad_notes, panic = host_bad_panic, ignored = host_bad_ignored)
  end
  block host_midi(midi: @{MidiEvent})
    if midi.frame ~= as(index, 2) then yield 50 end
    emit @{classify_midi_event}(midi; note_on = midi_bad_on, note_off = midi_note_off, control_change = midi_bad_cc, pitch_bend = midi_bad_bend, channel_pressure = midi_bad_pressure, poly_pressure = midi_bad_poly, program_change = midi_bad_program, ignored = midi_bad_ignored)
  end
  block midi_note_off(channel: u8, note: u8, frame: index)
    if channel ~= as(u8, 0) or note ~= as(u8, 60) or frame ~= as(index, 2) then yield 51 end
    let bend: @{MidiEvent} = { kind = as(u8, 224), channel = as(u8, 0), a = as(u8, 0), b = as(u8, 64), frame = as(index, 3) }
    emit @{classify_midi_event}(bend; note_on = midi_bad_on, note_off = midi_bad_off, control_change = midi_bad_cc, pitch_bend = midi_bend, channel_pressure = midi_bad_pressure, poly_pressure = midi_bad_poly, program_change = midi_bad_program, ignored = midi_bad_ignored)
  end
  block midi_bend(channel: u8, value: f32, frame: index)
    if channel ~= as(u8, 0) or frame ~= as(index, 3) then yield 52 end
    if value < as(f32, -0.001) or value > as(f32, 0.001) then yield 53 end
    let panic_ev: @{HostEvent} = { kind = as(u8, 6), midi = { kind = as(u8, 0), channel = as(u8, 0), a = as(u8, 0), b = as(u8, 0), frame = as(index, 0) }, parameter = { address = { scope = as(u8, 1), part = as(u16, 0), layer = as(u16, 0), bus = as(u16, 0), slot = as(u16, 0), param = as(u16, 0) }, value = as(f32, 0.0), frame = as(index, 0) }, program = { bank = as(u16, 0), program = as(u16, 0), generation = as(u16, 0) }, transport = { playing = false, beat_pos = 0.0, bar_pos = 0.0, time_sig_num = as(u8, 4), time_sig_den = as(u8, 4) }, frame = as(index, 1) }
    emit @{classify_host_event}(panic_ev; midi = host_bad_midi, parameter = host_bad_param, program_change = host_bad_program, transport = host_bad_transport, all_notes_off = host_bad_notes, panic = host_panic, ignored = host_bad_ignored)
  end
  block host_panic(frame: index)
    jump voice_setup()
  end
  block voice_setup()
    let layerp: ptr(@{LayerPlan}) = as(ptr(@{LayerPlan}), work)
    let partp: ptr(@{PartPlan}) = as(ptr(@{PartPlan}), work + as(index, 4096))
    let programp: ptr(@{PreparedProgram}) = as(ptr(@{PreparedProgram}), work + as(index, 8192))
    partp[0].layers = view(layerp, as(index, 1))
    partp[0].layer_count = as(index, 1)
    partp[0].midi_channel = as(u8, 0)
    partp[0].enabled = true
    partp[0].max_polyphony = as(index, 2)
    partp[0].steal.mode = as(u8, 1)
    partp[0].steal.same_note_bonus = as(f32, 0.0)
    partp[0].steal.release_bonus = as(f32, 0.0)
    partp[0].steal.age_weight = as(f32, 1.0)
    partp[0].steal.level_weight = as(f32, 1.0)
    partp[0].gain = as(f32, 1.0)
    partp[0].pan = as(f32, 0.0)
    programp[0].parts = view(partp, as(index, 1))
    programp[0].part_count = as(index, 1)
    programp[0].generation = as(u16, 1)
    emit @{allocate_voice}(partp, &synth[0].storage.voices, as(u8, 0), as(u8, 60), as(f32, 0.75); allocated = voice_allocated, stolen = voice_stolen, full = voice_full, muted = voice_muted)
  end
  block voice_allocated(v: @{VoiceRef})
    let part_ref: @{PartRef} = { index = as(u16, 0), generation = as(u16, 1) }
    let layer_ref: @{LayerRef} = { part_index = as(u16, 0), layer_index = as(u16, 0), generation = as(u16, 1) }
    let programp: ptr(@{PreparedProgram}) = as(ptr(@{PreparedProgram}), work + as(index, 8192))
    emit @{start_voice}(programp, &synth[0].storage.voices, v, part_ref, layer_ref, as(u8, 0), as(u8, 60), as(f32, 0.75), as(f32, 261.6256); started = voice_started, stale_ref = voice_stale, invalid_layer = voice_invalid_layer)
  end
  block voice_started(v: @{VoiceRef})
    if synth[0].storage.voices.active_count ~= as(index, 1) then yield 70 end
    if synth[0].storage.voices.states[as(index, v.index)].gate ~= true then yield 71 end
    if synth[0].storage.voices.states[as(index, v.index)].stage ~= as(u8, 1) then yield 72 end
    emit @{release_matching_voices}(&synth[0].storage.voices, as(u8, 0), as(u8, 60); released_any = voice_released, none = voice_release_none)
  end
  block voice_released(count: index)
    if count ~= as(index, 1) then yield 73 end
    let v: @{VoiceRef} = synth[0].storage.voices.active[as(index, 0)]
    if synth[0].storage.voices.states[as(index, v.index)].gate ~= false then yield 74 end
    if synth[0].storage.voices.states[as(index, v.index)].stage ~= as(u8, 4) then yield 75 end
    emit @{retire_voice}(&synth[0].storage.voices, v; retired = voice_retired, stale_ref = voice_stale, already_free = voice_already_free)
  end
  block voice_retired()
    if synth[0].storage.voices.active_count ~= as(index, 0) then yield 76 end
    if synth[0].storage.voices.free_head ~= as(u32, 0) then yield 77 end
    jump render_check()
  end
  block render_check()
    out_l[as(index, 0)] = as(f32, 0.25)
    out_r[as(index, 0)] = as(f32, -0.25)
    let ctx: @{RenderCtx} = { shape = { frame_count = as(index, 4), block_index = as(u64, 0) }, dsp = policy.dsp, policy = policy.render, sample_rate_hz = as(f32, 48000.0), inv_sample_rate = as(f32, 0.000020833333), tempo_bpm = as(f32, 120.0), tuning_a4_hz = as(f32, 440.0) }
    let scratch: ptr(@{RenderScratch}) = as(ptr(@{RenderScratch}), work + as(index, 12288))
    let out_block: @{StereoBlock} = { left = view(out_l, as(index, 4)), right = view(out_r, as(index, 4)) }
    emit @{render_block}(synth, view(as(ptr(@{HostEvent}), nil), as(index, 0)), ctx, scratch, out_block; rendered = render_ok, silent = render_silent, clipped = render_ok, requested_program = render_requested, missing_cache = render_missing, bad_buffer = render_bad_buffer, bad_state = render_bad_state)
  end
  block render_silent(active: index)
    if active ~= as(index, 0) then yield 93 end
    if out_l[as(index, 0)] ~= as(f32, 0.0) then yield 91 end
    if out_r[as(index, 0)] ~= as(f32, 0.0) then yield 92 end
    yield 0
  end
  block render_ok(active: index, peak: f32) yield 94 end
  block render_requested(program: @{ProgramRef}) yield 95 end
  block render_missing(ref: @{PadTableRef}) yield 96 end
  block render_bad_buffer() yield 97 end
  block render_bad_state(code: i32) yield 98 end
  block host_bad_midi(midi: @{MidiEvent}) yield 150 end
  block host_bad_param(param: @{ParameterEvent}) yield 151 end
  block host_bad_program(program: @{ProgramRef}, frame: index) yield 152 end
  block host_bad_transport(transport: @{TransportState}, frame: index) yield 153 end
  block host_bad_notes(frame: index) yield 154 end
  block host_bad_panic(frame: index) yield 155 end
  block host_bad_ignored() yield 156 end
  block midi_bad_on(channel: u8, note: u8, velocity: f32, frame: index) yield 160 end
  block midi_bad_off(channel: u8, note: u8, frame: index) yield 161 end
  block midi_bad_cc(channel: u8, cc: u8, value: u8, frame: index) yield 162 end
  block midi_bad_pressure(channel: u8, value: f32, frame: index) yield 163 end
  block midi_bad_poly(channel: u8, note: u8, value: f32, frame: index) yield 164 end
  block midi_bad_program(channel: u8, program: u8, frame: index) yield 165 end
  block midi_bad_bend(channel: u8, value: f32, frame: index) yield 166 end
  block midi_bad_ignored() yield 167 end
  block voice_stolen(v: @{VoiceRef}, previous: @{VoiceRef}) yield 170 end
  block voice_full() yield 171 end
  block voice_muted() yield 172 end
  block voice_stale(v: @{VoiceRef}) yield 173 end
  block voice_invalid_layer(layer: @{LayerRef}) yield 174 end
  block voice_release_none() yield 175 end
  block voice_already_free() yield 176 end
  end
end
]]

local behavioral = compile_for_call('behavioral events/voice/render wrapper', behavioral_wrapper)
local work = ffi.new('uint8_t[?]', 65536)
local out_l = ffi.new('float[4]', 1, 1, 1, 1)
local out_r = ffi.new('float[4]', -1, -1, -1, -1)
local behavior_status = behavioral(synth, work, out_l, out_r)
assert(behavior_status == 0, 'behavioral events/voice/render smoke returned ' .. tostring(behavior_status))
assert(out_l[0] == 0 and out_r[0] == 0, 'silent render smoke should clear output')

behavioral:free()
required_storage:free()
synth_init:free()
prepare_program:free()

print('ok zyn synth behavioral smoke coverage')
