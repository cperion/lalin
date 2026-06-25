local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_schedule_plan_rules ~= nil then return T._lalin_api_cache.code_schedule_plan_rules end

    local lalin = require("lalin")
    local llbl = require("llbl")
    local Llisle = require("llisle")
    local RuleApi = require("lalin.llisle_rule_api")
    local env = lalin.language.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle
    local KernelScheduleInput = llbl.shared.symbols.source("KernelScheduleInput")
    local KernelScheduleSelection = llbl.shared.symbols.source("KernelScheduleSelection")
    local schedule = llbl.shared.symbols.source("schedule")
    local selection = llbl.shared.symbols.source("selection")
    local kernel_schedule = llbl.shared.symbols.source("kernel_schedule")
    local planned = llbl.shared.symbols.source("planned")
    local no_plan = llbl.shared.symbols.source("no_plan")
    local function build_kernel_schedule(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. kernel_schedule [build_kernel_schedule],

  relation. select_kernel_schedule {
    input { schedule [KernelScheduleInput] },
    output { selection [KernelScheduleSelection] },
    strategy {
      select. best_cost,
      ambiguity. error,
      coverage. complete,
    },
  },

  rule. vector_executable {
    llisle.select_kernel_schedule { schedule = P. schedule },
    when {
      (P. schedule.has_vector_schedule :eq (true))
        * (P. schedule.vector_executable :eq (true)),
    },
    cost (0),
    run {
      ret {
        selection = kernel_schedule {
          kind = planned,
          schedule_kind = P. schedule.vector_kind,
          capability = P. schedule.vector_capability,
          rejected_alternatives = {},
        },
      },
    },
  },

  rule. scalar_after_vector_reject {
    llisle.select_kernel_schedule { schedule = P. schedule },
    when {
      (P. schedule.has_vector_schedule :eq (true))
        * (P. schedule.vector_executable :eq (false))
        * (P. schedule.scalar_executable :eq (true)),
    },
    cost (10),
    run {
      ret {
        selection = kernel_schedule {
          kind = planned,
          schedule_kind = P. schedule.scalar_kind,
          capability = P. schedule.scalar_capability,
          rejected_alternatives = P. schedule.vector_rejects,
        },
      },
    },
  },

  rule. scalar_without_vector {
    llisle.select_kernel_schedule { schedule = P. schedule },
    when {
      (P. schedule.has_vector_schedule :eq (false))
        * (P. schedule.scalar_executable :eq (true)),
    },
    cost (20),
    run {
      ret {
        selection = kernel_schedule {
          kind = planned,
          schedule_kind = P. schedule.scalar_kind,
          capability = P. schedule.scalar_capability,
          rejected_alternatives = {},
        },
      },
    },
  },

  rule. no_executable_schedule_after_vector_reject {
    llisle.select_kernel_schedule { schedule = P. schedule },
    when {
      (P. schedule.has_vector_schedule :eq (true))
        * (P. schedule.vector_executable :eq (false))
        * (P. schedule.scalar_executable :eq (false)),
    },
    cost (30),
    run {
      ret {
        selection = kernel_schedule {
          kind = no_plan,
          rejects = P. schedule.scalar_rejects,
        },
      },
    },
  },

  rule. no_executable_schedule_without_vector {
    llisle.select_kernel_schedule { schedule = P. schedule },
    when {
      (P. schedule.has_vector_schedule :eq (false))
        * (P. schedule.scalar_executable :eq (false)),
    },
    cost (40),
    run {
      ret {
        selection = kernel_schedule {
          kind = no_plan,
          rejects = P. schedule.scalar_rejects,
        },
      },
    },
  },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()

    local engine = Llisle.compile(rules)

    local api = RuleApi.new(rules, engine)

    T._lalin_api_cache.code_schedule_plan_rules = api
    return api
end

return bind_context
