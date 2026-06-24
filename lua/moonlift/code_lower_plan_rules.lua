local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_lower_plan_rules ~= nil then return T._moonlift_api_cache.code_lower_plan_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle

    local LowerFragmentCandidate = llb.symbol("LowerFragmentCandidate")
    local LowerFragmentSelection = llb.symbol("LowerFragmentSelection")
    local candidate = llb.symbol("candidate")
    local selection = llb.symbol("selection")
    local lower_fragment_selection = llb.symbol("lower_fragment_selection")

    local closed_form = llb.symbol("closed_form")
    local kernel = llb.symbol("kernel")
    local fallback = llb.symbol("fallback")
    local none = llb.symbol("none")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. lower_fragment_selection [build_selection],

  relation. select_lower_fragment {
    input { candidate [LowerFragmentCandidate] },
    output { selection [LowerFragmentSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. planned_closed_form {
    llisle.select_lower_fragment { candidate = P. candidate },
    when {
      (P. candidate.has_kernel :eq (true))
        * (P. candidate.schedule_planned :eq (true))
        * (P. candidate.schedule_closed_form :eq (true))
        * (P. candidate.has_closed_form :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = closed_form,
          closed_form = P. candidate.closed_form,
        },
      },
    },
  },

  rule. closed_form_schedule_without_fact {
    llisle.select_lower_fragment { candidate = P. candidate },
    when {
      (P. candidate.has_kernel :eq (true))
        * (P. candidate.schedule_planned :eq (true))
        * (P. candidate.schedule_closed_form :eq (true))
        * (P. candidate.has_closed_form :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = fallback,
          reason = P. candidate.closed_form_missing_reason,
        },
      },
    },
  },

  rule. planned_kernel {
    llisle.select_lower_fragment { candidate = P. candidate },
    when {
      (P. candidate.has_kernel :eq (true))
        * (P. candidate.schedule_planned :eq (true))
        * (P. candidate.schedule_closed_form :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = kernel,
        },
      },
    },
  },

  rule. planned_kernel_without_schedule {
    llisle.select_lower_fragment { candidate = P. candidate },
    when {
      (P. candidate.has_kernel :eq (true))
        * (P. candidate.schedule_planned :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = fallback,
          reason = P. candidate.no_schedule_reason,
        },
      },
    },
  },

  rule. rejected_kernel {
    llisle.select_lower_fragment { candidate = P. candidate },
    when {
      (P. candidate.has_kernel :eq (false))
        * (P. candidate.has_kernel_no_plan :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = fallback,
          reason = P. candidate.kernel_no_plan_reason,
        },
      },
    },
  },

  rule. no_loop_kernel_decision {
    llisle.select_lower_fragment { candidate = P. candidate },
    when {
      (P. candidate.has_kernel :eq (false))
        * (P. candidate.has_kernel_no_plan :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_fragment_selection {
          kind = none,
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
        local result, err = engine:run("select_lower_fragment", { candidate = candidate })
        if result == nil then return nil, err and err.message or "no lower fragment selected" end
        return result.output.selection, nil
    end

    api.kind = {
        closed_form = "closed_form",
        kernel = "kernel",
        fallback = "fallback",
        none = "none",
    }
    api.rules = rules
    api.engine = engine

    T._moonlift_api_cache.code_lower_plan_rules = api
    return api
end

return bind_context
