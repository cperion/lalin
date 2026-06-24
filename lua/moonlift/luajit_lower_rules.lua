local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_lower_rules ~= nil then return T._moonlift_api_cache.luajit_lower_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local LuaJITKernelLoweringCandidate = llb.symbol("LuaJITKernelLoweringCandidate")
    local LuaJITKernelLoweringSelection = llb.symbol("LuaJITKernelLoweringSelection")
    local LuaJITSkeletonLoweringCandidate = llb.symbol("LuaJITSkeletonLoweringCandidate")
    local LuaJITSkeletonLoweringSelection = llb.symbol("LuaJITSkeletonLoweringSelection")
    local candidate = llb.symbol("candidate")
    local selection = llb.symbol("selection")
    local kernel_lowering = llb.symbol("kernel_lowering")
    local stencil_reduce = llb.symbol("stencil_reduce")
    local stencil_store = llb.symbol("stencil_store")
    local stencil_skeleton = llb.symbol("stencil_skeleton")
    local no_plan = llb.symbol("no_plan")
    local skeleton_scan = llb.symbol("skeleton_scan")
    local skeleton_find = llb.symbol("skeleton_find")
    local skeleton_partition = llb.symbol("skeleton_partition")
    local skeleton_copy = llb.symbol("skeleton_copy")
    local function build_kernel_lowering(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. kernel_lowering [build_kernel_lowering],

  relation. select_kernel_lowering {
    input { candidate [LuaJITKernelLoweringCandidate] },
    output { selection [LuaJITKernelLoweringSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  relation. select_skeleton_lowering {
    input { candidate [LuaJITSkeletonLoweringCandidate] },
    output { selection [LuaJITSkeletonLoweringSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. stencil_reduce {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      (P. candidate.loop_plan :eq (true))
        * (P. candidate.owns_loop :eq (true))
        * (P. candidate.planned :eq (true))
        * (P. candidate.has_reduce_provider :eq (true))
        * (P. candidate.counted_positive :eq (true))
        * (P. candidate.result_reduction :eq (true))
        * (P. candidate.returns_reduction :eq (true))
        * (P. candidate.stencil_skeleton_ready :eq (false))
        * (P. candidate.stencil_reduce_ready :eq (true)),
    },
    cost (20),
    run {
      ret { selection = kernel_lowering { kind = stencil_reduce } },
    },
  },

  rule. stencil_skeleton {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      (P. candidate.loop_plan :eq (true))
        * (P. candidate.owns_loop :eq (true))
        * (P. candidate.planned :eq (true))
        * (P. candidate.has_skeleton_provider :eq (true))
        * (P. candidate.counted_positive :eq (true))
        * (P. candidate.stencil_skeleton_ready :eq (true)),
    },
    cost (30),
    run {
      ret { selection = kernel_lowering { kind = stencil_skeleton } },
    },
  },

  rule. stencil_store {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      (P. candidate.loop_plan :eq (true))
        * (P. candidate.owns_loop :eq (true))
        * (P. candidate.planned :eq (true))
        * (P. candidate.has_store_provider :eq (true))
        * (P. candidate.counted_positive :eq (true))
        * (P. candidate.returns_void :eq (true))
        * (P. candidate.single_store :eq (true))
        * (P. candidate.store_dst_base :eq (true))
        * (P. candidate.stencil_skeleton_ready :eq (false))
        * (P. candidate.stencil_store_ready :eq (true)),
    },
    cost (10),
    run {
      ret { selection = kernel_lowering { kind = stencil_store } },
    },
  },

  rule. no_kernel_lowering {
    llisle.select_kernel_lowering { candidate = P. candidate },
    when {
      P. candidate.any_ready_lowering :eq (false),
    },
    cost (100),
    run {
      ret {
        selection = kernel_lowering {
          kind = no_plan,
          reason = P. candidate.reject_reason,
        },
      },
    },
  },

  rule. skeleton_scan {
    llisle.select_skeleton_lowering { candidate = P. candidate },
    when {
      P. candidate.scan_ready :eq (true),
    },
    cost (0),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_scan,
          planned = P. candidate.scan_plan,
        },
      },
    },
  },

  rule. skeleton_find {
    llisle.select_skeleton_lowering { candidate = P. candidate },
    when {
      (P. candidate.scan_ready :eq (false))
        * (P. candidate.find_ready :eq (true)),
    },
    cost (10),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_find,
          planned = P. candidate.find_plan,
        },
      },
    },
  },

  rule. skeleton_partition {
    llisle.select_skeleton_lowering { candidate = P. candidate },
    when {
      (P. candidate.scan_ready :eq (false))
        * (P. candidate.find_ready :eq (false))
        * (P. candidate.partition_ready :eq (true)),
    },
    cost (20),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_partition,
          planned = P. candidate.partition_plan,
        },
      },
    },
  },

  rule. skeleton_copy {
    llisle.select_skeleton_lowering { candidate = P. candidate },
    when {
      (P. candidate.scan_ready :eq (false))
        * (P. candidate.find_ready :eq (false))
        * (P. candidate.partition_ready :eq (false))
        * (P. candidate.copy_ready :eq (true)),
    },
    cost (30),
    run {
      ret {
        selection = kernel_lowering {
          kind = skeleton_copy,
          planned = P. candidate.copy_plan,
        },
      },
    },
  },

  rule. skeleton_no_plan {
    llisle.select_skeleton_lowering { candidate = P. candidate },
    when {
      (P. candidate.scan_ready :eq (false))
        * (P. candidate.find_ready :eq (false))
        * (P. candidate.partition_ready :eq (false))
        * (P. candidate.copy_ready :eq (false)),
    },
    cost (100),
    run {
      ret {
        selection = kernel_lowering {
          kind = no_plan,
          reason = P. candidate.reject_reason,
        },
      },
    },
  },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()

    local engine = Llisle.compile(rules)

    local api = {}

    function api.select(candidate)
        local result, err = engine:run("select_kernel_lowering", { candidate = candidate })
        if result == nil then return nil, err and err.message or "no LuaJIT kernel lowering selected" end
        return result.output.selection, nil
    end

    function api.select_skeleton(candidate)
        local result, err = engine:run("select_skeleton_lowering", { candidate = candidate })
        if result == nil then return nil, err and err.message or "no LuaJIT skeleton lowering selected" end
        return result.output.selection, nil
    end

    api.rules = rules
    api.engine = engine
    api.kind = {
        stencil_reduce = "stencil_reduce",
        stencil_store = "stencil_store",
        stencil_skeleton = "stencil_skeleton",
        no_plan = "no_plan",
        skeleton_scan = "skeleton_scan",
        skeleton_find = "skeleton_find",
        skeleton_partition = "skeleton_partition",
        skeleton_copy = "skeleton_copy",
    }

    T._moonlift_api_cache.luajit_lower_rules = api
    return api
end

return bind_context
