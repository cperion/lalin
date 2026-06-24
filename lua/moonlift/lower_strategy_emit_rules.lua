local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.lower_strategy_emit_rules ~= nil then return T._moonlift_api_cache.lower_strategy_emit_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle

    local LowerEmitCandidate = llb.symbol("LowerEmitCandidate")
    local LowerEmitSelection = llb.symbol("LowerEmitSelection")
    local candidate = llb.symbol("candidate")
    local selection = llb.symbol("selection")
    local lower_emit_selection = llb.symbol("lower_emit_selection")

    local code = llb.symbol("code")
    local closed_form = llb.symbol("closed_form")
    local scalar_kernel = llb.symbol("scalar_kernel")
    local vector_kernel = llb.symbol("vector_kernel")
    local missing_schedule = llb.symbol("missing_schedule")
    local unsupported = llb.symbol("unsupported")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. lower_emit_selection [build_selection],

  relation. select_lower_emit {
    input { candidate [LowerEmitCandidate] },
    output { selection [LowerEmitSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. emit_code {
    llisle.select_lower_emit { candidate = P. candidate },
    when {
      P. candidate.strategy_code :eq (true),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = code,
        },
      },
    },
  },

  rule. emit_closed_form {
    llisle.select_lower_emit { candidate = P. candidate },
    when {
      (P. candidate.strategy_code :eq (false))
        * (P. candidate.strategy_closed_form :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = closed_form,
        },
      },
    },
  },

  rule. emit_vector_kernel {
    llisle.select_lower_emit { candidate = P. candidate },
    when {
      (P. candidate.strategy_code :eq (false))
        * (P. candidate.strategy_closed_form :eq (false))
        * (P. candidate.strategy_kernel :eq (true))
        * (P. candidate.has_schedule :eq (true))
        * (P. candidate.schedule_vector :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = vector_kernel,
        },
      },
    },
  },

  rule. emit_scalar_kernel {
    llisle.select_lower_emit { candidate = P. candidate },
    when {
      (P. candidate.strategy_code :eq (false))
        * (P. candidate.strategy_closed_form :eq (false))
        * (P. candidate.strategy_kernel :eq (true))
        * (P. candidate.has_schedule :eq (true))
        * (P. candidate.schedule_vector :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = scalar_kernel,
        },
      },
    },
  },

  rule. kernel_missing_schedule {
    llisle.select_lower_emit { candidate = P. candidate },
    when {
      (P. candidate.strategy_code :eq (false))
        * (P. candidate.strategy_closed_form :eq (false))
        * (P. candidate.strategy_kernel :eq (true))
        * (P. candidate.has_schedule :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = missing_schedule,
          reason = P. candidate.missing_schedule_reason,
        },
      },
    },
  },

  rule. emit_unsupported {
    llisle.select_lower_emit { candidate = P. candidate },
    when {
      (P. candidate.strategy_code :eq (false))
        * (P. candidate.strategy_closed_form :eq (false))
        * (P. candidate.strategy_kernel :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = unsupported,
          reason = P. candidate.unsupported_reason,
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
        local result, err = engine:run("select_lower_emit", { candidate = candidate })
        if result == nil then return nil, err and err.message or "no lower emission selected" end
        return result.output.selection, nil
    end

    api.kind = {
        code = "code",
        closed_form = "closed_form",
        scalar_kernel = "scalar_kernel",
        vector_kernel = "vector_kernel",
        missing_schedule = "missing_schedule",
        unsupported = "unsupported",
    }
    api.rules = rules
    api.engine = engine

    T._moonlift_api_cache.lower_strategy_emit_rules = api
    return api
end

return bind_context
