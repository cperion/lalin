package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local out_dir = os.getenv("LALIN_C_AOT_OBJECT_BENCH_DIR") or "target/bench_c_aot_objects"
local cc = os.getenv("CC") or "gcc"
local cflags = os.getenv("LALIN_C_AOT_OBJECT_CFLAGS") or "-std=c99 -O3 -march=native"
local frames = tonumber(os.getenv("LALIN_C_AOT_OBJECT_FRAMES") or "2000000") or 2000000

local source = [=[
struct Vec2
  x [i32]
  y [i32]
end

struct Bounds
  lo [Vec2]
  hi [Vec2]
end

struct Particle
  pos [Vec2]
  vel [Vec2]
  acc [Vec2]
  inv_mass [i32]
  heat [i32]
  life [i32]
end

struct World
  gravity [Vec2]
  wind [Vec2]
  bounds [Bounds]
  damping [i32]
  heat_decay [i32]
end

struct Program
  world [World]
  particle [Particle]
  seed [i32]
  score [i32]
  collisions [i32]
end

fn Vec2.add(self [Vec2], other [Vec2]) [Vec2]
  return Vec2 { x = self.x + other.x, y = self.y + other.y }
end

fn Vec2.sub(self [Vec2], other [Vec2]) [Vec2]
  return Vec2 { x = self.x - other.x, y = self.y - other.y }
end

fn Vec2.scale(self [Vec2], k [i32]) [Vec2]
  return Vec2 { x = self.x * k, y = self.y * k }
end

fn Vec2.dot(self [Vec2], other [Vec2]) [i32]
  return self.x * other.x + self.y * other.y
end

fn Bounds.clamp(self [Bounds], p [Vec2]) [Vec2]
  var x [i32] = p.x
  var y [i32] = p.y
  if x < self.lo.x then
    x = self.lo.x
  end
  if x > self.hi.x then
    x = self.hi.x
  end
  if y < self.lo.y then
    y = self.lo.y
  end
  if y > self.hi.y then
    y = self.hi.y
  end
  return Vec2 { x = x, y = y }
end

fn Particle.kinetic2(self [Particle]) [i32]
  return self.vel:dot(self.vel) * self.inv_mass
end

fn Particle.integrate(self [Particle], world [World], impulse [Vec2], dt [i32]) [Particle]
  var force [Vec2] = world.gravity:add(world.wind):add(impulse)
  var next_acc [Vec2] = force:scale(self.inv_mass)
  var next_vel [Vec2] = self.vel:add(next_acc:scale(dt))
  next_vel = Vec2 { x = next_vel.x - next_vel.x / world.damping, y = next_vel.y - next_vel.y / world.damping }
  var next_pos [Vec2] = self.pos:add(next_vel:scale(dt))
  var bounced [i32] = 0
  if next_pos.x < world.bounds.lo.x then
    next_pos = Vec2 { x = world.bounds.lo.x, y = next_pos.y }
    next_vel = Vec2 { x = 0 - next_vel.x / 2, y = next_vel.y }
    bounced = 1
  end
  if next_pos.x > world.bounds.hi.x then
    next_pos = Vec2 { x = world.bounds.hi.x, y = next_pos.y }
    next_vel = Vec2 { x = 0 - next_vel.x / 2, y = next_vel.y }
    bounced = 1
  end
  if next_pos.y < world.bounds.lo.y then
    next_pos = Vec2 { x = next_pos.x, y = world.bounds.lo.y }
    next_vel = Vec2 { x = next_vel.x, y = 0 - next_vel.y / 2 }
    bounced = 1
  end
  if next_pos.y > world.bounds.hi.y then
    next_pos = Vec2 { x = next_pos.x, y = world.bounds.hi.y }
    next_vel = Vec2 { x = next_vel.x, y = 0 - next_vel.y / 2 }
    bounced = 1
  end
  return Particle {
    pos = next_pos,
    vel = next_vel,
    acc = next_acc,
    inv_mass = self.inv_mass,
    heat = self.heat + bounced * 17 - world.heat_decay,
    life = self.life - 1
  }
end

fn Program.random_step(self [Program], tick [i32]) [Program]
  var seed2 [i32] = self.seed * 1664525 + 1013904223 + tick
  var ix [i32] = seed2 % 9 - 4
  var seed3 [i32] = seed2 * 1103515245 + 12345
  var iy [i32] = seed3 % 7 - 3
  var impulse [Vec2] = Vec2 { x = ix, y = iy }
  var p2 [Particle] = self.particle:integrate(self.world, impulse, 1)
  var e [i32] = p2:kinetic2()
  var hit [i32] = 0
  if p2.pos.x == self.world.bounds.lo.x then
    hit = hit + 1
  end
  if p2.pos.x == self.world.bounds.hi.x then
    hit = hit + 1
  end
  if p2.pos.y == self.world.bounds.lo.y then
    hit = hit + 1
  end
  if p2.pos.y == self.world.bounds.hi.y then
    hit = hit + 1
  end
  return Program {
    world = self.world,
    particle = p2,
    seed = seed3,
    score = self.score + e + p2.heat + p2.pos.x - p2.pos.y,
    collisions = self.collisions + hit
  }
end

fn make_program(argc [i32]) [Program]
  var bounds [Bounds] = Bounds { lo = Vec2 { x = 0 - 10000, y = 0 - 7000 }, hi = Vec2 { x = 10000, y = 7000 } }
  var world [World] = World {
    gravity = Vec2 { x = 0, y = 0 - 3 },
    wind = Vec2 { x = argc % 5 - 2, y = 1 },
    bounds = bounds,
    damping = 16,
    heat_decay = 1
  }
  var particle [Particle] = Particle {
    pos = Vec2 { x = argc * 3 + 10, y = 1200 },
    vel = Vec2 { x = 41, y = 0 - 17 },
    acc = Vec2 { x = 0, y = 0 },
    inv_mass = 2 + argc % 3,
    heat = 40,
    life = __FRAMES__
  }
  return Program { world = world, particle = particle, seed = 12345 + argc, score = 0, collisions = 0 }
end

-- Real-life shape: Lalin owns `main`, constructs the Program object, then
-- transfers to a Program-owned region method.  The region is an open control
-- protocol; `main` wires its `done` continuation to a local block.
region Program.run(self [Program]; done(score [i32], collisions [i32], x [i32], y [i32]))
  entry start()
    jump loop(i = 0, program = self)
  end
  block loop(i [i32], program [Program])
    if i >= __FRAMES__ then
      jump done(score = program.score, collisions = program.collisions, x = program.particle.pos.x, y = program.particle.pos.y)
    end
    jump loop(i = i + 1, program = program:random_step(as [i32] (i)))
  end
end

fn main(argc [i32], argv [ptr [ptr [u8]]]) [i32]
  entry start()
    var program [Program] = make_program(argc)
    emit Program.run(program; done = done)
  end
  block done(score [i32], collisions [i32], x [i32], y [i32])
    return (score + collisions * 17 + x + y) % 251
  end
end
]=]
source = source:gsub("__FRAMES__", tostring(frames))

os.execute("mkdir -p " .. shell_quote(out_dir))
local lln_path = out_dir .. "/program.lln"
local c_path = out_dir .. "/program.c"
local h_path = out_dir .. "/program.h"
local exe_path = out_dir .. "/program"
local asm_path = out_dir .. "/program.s"
write_file(lln_path, source)

local t0 = os.clock()
local parsed = assert(lalin.loadstring(source, "@bench_c_aot_objects.lln"))
local artifact = lalin.emit_c(parsed, { name = "bench_c_aot_objects", c_path = c_path, h_path = h_path })
local t1 = os.clock()

local compile_cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(exe_path) }, " ")
assert(command_ok(compile_cmd), "C AOT object benchmark gcc compile failed")
local asm_cmd = table.concat({ shell_quote(cc), cflags, "-S", shell_quote(c_path), "-o", shell_quote(asm_path) }, " ")
assert(command_ok(asm_cmd), "C AOT object benchmark asm compile failed")

local run_cmd = "start=$(date +%s%N); " .. shell_quote(exe_path) .. " >/dev/null 2>&1; status=$?; finish=$(date +%s%N); echo exit:$status ns:$((finish-start))"
local run_pipe = assert(io.popen(run_cmd, "r"))
local run_report = run_pipe:read("*a") or ""
run_pipe:close()
local exit_status = tonumber(run_report:match("exit:(%d+)")) or -1
local run_ns = tonumber(run_report:match("ns:(%d+)")) or 0

local asm = read_file(asm_path)
local call_count = 0
for _ in asm:gmatch("\n%s*call[%w%._@]*") do call_count = call_count + 1 end
local source_lines = 0
for _ in artifact.source:gmatch("\n") do source_lines = source_lines + 1 end
local asm_lines = 0
for _ in asm:gmatch("\n") do asm_lines = asm_lines + 1 end

print(string.format("C AOT object benchmark emitted %s", c_path))
print(string.format("  frames=%d", frames))
print(string.format("  emit_c_time=%.4fs", t1 - t0))
print(string.format("  executable_exit=%d runtime=%.4fs", exit_status, run_ns / 1e9))
print(string.format("  c_source=%d bytes, %d lines", #artifact.source, source_lines))
print(string.format("  gcc_asm=%d bytes, %d lines, call_instructions=%d", #asm, asm_lines, call_count))
print("  source=" .. lln_path)
print("  executable=" .. exe_path)
