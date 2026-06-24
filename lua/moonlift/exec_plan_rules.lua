local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.exec_plan_rules ~= nil then return T._moonlift_api_cache.exec_plan_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local RuleApi = require("moonlift.llisle_rule_api")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle

    local ExecFragmentCandidate = llb.symbol("ExecFragmentCandidate")
    local ExecFragmentSelection = llb.symbol("ExecFragmentSelection")
    local candidate = llb.symbol("candidate")
    local selection = llb.symbol("selection")
    local exec_fragment_selection = llb.symbol("exec_fragment_selection")

    local stencil = llb.symbol("stencil")
    local skip = llb.symbol("skip")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. exec_fragment_selection [build_selection],

  relation. select_exec_fragment {
    input { candidate [ExecFragmentCandidate] },
    output { selection [ExecFragmentSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. selected_stencil_artifact {
    llisle.select_exec_fragment { candidate = P. candidate },
    when {
      (P. candidate.stencil_selected :eq (true))
        * (P. candidate.has_artifact :eq (true))
        * (P. candidate.has_func :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = exec_fragment_selection {
          kind = stencil,
          reason = P. candidate.selected_reason,
        },
      },
    },
  },

  rule. skip_unselected_stencil {
    llisle.select_exec_fragment { candidate = P. candidate },
    when {
      P. candidate.stencil_selected :eq (false),
    },
    cost (0),
    run {
      ret {
        selection = exec_fragment_selection {
          kind = skip,
          reason = P. candidate.unselected_reason,
        },
      },
    },
  },

  rule. skip_missing_artifact {
    llisle.select_exec_fragment { candidate = P. candidate },
    when {
      (P. candidate.stencil_selected :eq (true))
        * (P. candidate.has_artifact :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = exec_fragment_selection {
          kind = skip,
          reason = P. candidate.missing_artifact_reason,
        },
      },
    },
  },

  rule. skip_missing_function_owner {
    llisle.select_exec_fragment { candidate = P. candidate },
    when {
      (P. candidate.stencil_selected :eq (true))
        * (P. candidate.has_artifact :eq (true))
        * (P. candidate.has_func :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = exec_fragment_selection {
          kind = skip,
          reason = P. candidate.missing_func_reason,
        },
      },
    },
  },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()
    local engine = Llisle.compile(rules)

    local api = RuleApi.new(rules, engine, {
      kind = {
        stencil = "stencil",
        skip = "skip",
      },
    })

    T._moonlift_api_cache.exec_plan_rules = api
    return api
end

return bind_context
