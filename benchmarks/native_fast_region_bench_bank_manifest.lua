package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

return function(T)
  local Native = T.LalinNative
  local Core = T.LalinCore
  local Support = require('lalin.native_template_support')(T)
  local Sources = require('lalin.native_template_sources')(T)

  local target = Support.host_target()
  local runtime = Support.empty_runtime()
  local bank_id = Native.NativeBankId(os.getenv('LALIN_NATIVE_BANK_ID') or 'lalin.native.fast-region.bench')
  local i32 = Support.scalar_i32()
  local f64 = Support.scalar_f64()
  local ptr = Support.scalar_pointer(target.pointer_bits)
  local abi_i32 = Support.abi_scalar_value(i32)
  local abi_f64 = Support.abi_scalar_value(f64)
  local i32_in0 = Native.NativeExprInput(0, i32)
  local i32_in1 = Native.NativeExprInput(1, i32)
  local f64_in0 = Native.NativeExprInput(0, f64)
  local f64_in1 = Native.NativeExprInput(1, f64)

  local complete = Native.NativeCompleteBankCapability(
    Support.complete_bank_capability_id('fast-region-bench.micro'),
    target,
    { i32, ptr },
    {},
    {},
    {},
    {},
    {},
    Support.complete_runtime_capability({}, {}, {}),
    Support.complete_frame_capability(ptr, {}, {}),
    Support.complete_constant_pool_capability({}),
    Support.complete_atomic_capability(Native.NativeAtomicNoCodegen, {}, {}, {}),
    Support.complete_code_capability({ Native.NativeCodeMicroOpJumpShape }),
    Support.complete_abi_capability({}, Support.default_scalar_public_abi_adapters(target, { i32 })),
    Support.complete_kernel_capability({}),
    Support.complete_stencil_capability({})
  )

  local fast = Native.NativeFastRegionCapability(
    {
      Native.NativeFastAbi0(abi_i32),
      Native.NativeFastAbi2(abi_i32, abi_i32, abi_i32),
      Native.NativeFastAbi2(abi_f64, abi_f64, abi_f64),
    },
    {
      Native.NativeExprReturnAtom(i32, Native.NativeExprImmediate(i32)),
      Native.NativeExprReturnBinary(i32, Core.BinAdd, i32_in0, i32_in1),
      Native.NativeExprReturnBinary(i32, Core.BinMul, i32_in0, i32_in1),
      Native.NativeExprReturnMulAddImm(i32, i32_in0, i32_in1),
      Native.NativeExprReturnBinary(f64, Core.BinAdd, f64_in0, f64_in1),
    },
    {
      Native.NativeCompareBranchAtoms(Core.CmpLt, i32, i32_in0, i32_in1),
    },
    {
      Native.NativeSwitchStepAtoms(i32, i32_in0),
    },
    {},
    {},
    {}
  )

  local sources = {}
  local function append_request(request)
    for _, source in ipairs(request.sources or {}) do sources[#sources + 1] = source end
  end
  append_request(Sources.bank_request_for_complete_capability(complete, Native.NativeBankId(bank_id.text .. '.micro')))
  append_request(Sources.bank_request_for_fast_region_capability(fast, target, runtime, Native.NativeBankId(bank_id.text .. '.fast')))

  local by_generator = {}
  local order = {}
  for _, source in ipairs(sources) do
    local key = source.generator.id.text
    local bucket = by_generator[key]
    if bucket == nil then
      bucket = { generator = source.generator, entries = {} }
      by_generator[key] = bucket
      order[#order + 1] = key
    end
    bucket.entries[#bucket.entries + 1] = Support.template_manifest_entry_for_source(source)
  end

  local groups = {}
  for _, key in ipairs(order) do
    local bucket = by_generator[key]
    groups[#groups + 1] = Support.template_manifest_group(bucket.generator, bucket.entries)
  end

  local manifest = Support.template_source_manifest(
    Support.template_manifest_id(bank_id.text),
    Native.NativeTemplateSupportDomainId(bank_id.text .. '.support'),
    groups
  )
  return Sources.bank_request_from_sources(bank_id, target, runtime, manifest, sources)
end
