local out = "target/copy_patch_cps/u64_runtime"
local command = table.concat({
    "mkdir -p " .. out .. " &&",
    "gcc -O3 -fPIC -shared -fno-stack-protector",
    "experiments/copy_patch_cps/u64_native_learner.c",
    "-o " .. out .. "/native_learner.so",
}, " ")
local ok, why, status = os.execute(command)
assert(ok, ("native learner build failed (%s %s)"):format(tostring(why), tostring(status)))
print("U64 native learner support: ok")
