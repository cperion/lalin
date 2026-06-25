local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.lower_strategy_emit_rules ~= nil then return T._lalin_api_cache.lower_strategy_emit_rules end

    local lalin = require("lalin")
    local llbl = require("llbl")
    local Llisle = require("llisle")
    local RuleApi = require("lalin.llisle_rule_api")
    local env = lalin.language.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle

    local LowerEmitInput = llbl.shared.symbols.source("LowerEmitInput")
    local LowerEmitSelection = llbl.shared.symbols.source("LowerEmitSelection")
    local emit = llbl.shared.symbols.source("emit")
    local selection = llbl.shared.symbols.source("selection")
    local lower_emit_selection = llbl.shared.symbols.source("lower_emit_selection")

    local code = llbl.shared.symbols.source("code")
    local closed_form = llbl.shared.symbols.source("closed_form")
    local scalar_kernel = llbl.shared.symbols.source("scalar_kernel")
    local vector_kernel = llbl.shared.symbols.source("vector_kernel")
    local missing_schedule = llbl.shared.symbols.source("missing_schedule")
    local unsupported = llbl.shared.symbols.source("unsupported")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. lower_emit_selection [build_selection],

  relation. select_lower_emit {
    input { emit [LowerEmitInput] },
    output { selection [LowerEmitSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. emit_code {
    llisle.select_lower_emit { emit = P. emit },
    when {
      P. emit.strategy_code :eq (true),
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
    llisle.select_lower_emit { emit = P. emit },
    when {
      (P. emit.strategy_code :eq (false))
        * (P. emit.strategy_closed_form :eq (true)),
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
    llisle.select_lower_emit { emit = P. emit },
    when {
      (P. emit.strategy_code :eq (false))
        * (P. emit.strategy_closed_form :eq (false))
        * (P. emit.strategy_kernel :eq (true))
        * (P. emit.has_schedule :eq (true))
        * (P. emit.schedule_vector :eq (true)),
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
    llisle.select_lower_emit { emit = P. emit },
    when {
      (P. emit.strategy_code :eq (false))
        * (P. emit.strategy_closed_form :eq (false))
        * (P. emit.strategy_kernel :eq (true))
        * (P. emit.has_schedule :eq (true))
        * (P. emit.schedule_vector :eq (false)),
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
    llisle.select_lower_emit { emit = P. emit },
    when {
      (P. emit.strategy_code :eq (false))
        * (P. emit.strategy_closed_form :eq (false))
        * (P. emit.strategy_kernel :eq (true))
        * (P. emit.has_schedule :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = missing_schedule,
          reason = P. emit.missing_schedule_reason,
        },
      },
    },
  },

  rule. emit_unsupported {
    llisle.select_lower_emit { emit = P. emit },
    when {
      (P. emit.strategy_code :eq (false))
        * (P. emit.strategy_closed_form :eq (false))
        * (P. emit.strategy_kernel :eq (false)),
    },
    cost (0),
    run {
      ret {
        selection = lower_emit_selection {
          kind = unsupported,
          reason = P. emit.unsupported_reason,
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
        code = "code",
        closed_form = "closed_form",
        scalar_kernel = "scalar_kernel",
        vector_kernel = "vector_kernel",
        missing_schedule = "missing_schedule",
        unsupported = "unsupported",
      },
    })

    T._lalin_api_cache.lower_strategy_emit_rules = api
    return api
end

return bind_context
