local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonProject {
  product. TaskId { interned, text [str], },
  sum. TaskStatus { TaskTodo, TaskDone, TaskDeferred { variant_unique, reason [str], }, },
  product. Task {
    interned,
    field. id [ty. MoonProject.TaskId],
    title [str],
    status [ty. MoonProject.TaskStatus],
    deps [many [ty. MoonProject.TaskId]],
  },
  product. Project { interned, tasks [many [ty. MoonProject.Task]], },
  sum. TaskFact {
    TaskDeclared { variant_unique, field. id [ty. MoonProject.TaskId], },
    TaskCompleted { variant_unique, field. id [ty. MoonProject.TaskId], },
    TaskDependsOn {
      variant_unique,
      field. id [ty. MoonProject.TaskId],
      dep [ty. MoonProject.TaskId],
    },
    TaskDeferredFact { variant_unique, field. id [ty. MoonProject.TaskId], reason [str], },
    TaskReady { variant_unique, field. id [ty. MoonProject.TaskId], },
    TaskBlocked {
      variant_unique,
      field. id [ty. MoonProject.TaskId],
      missing_or_incomplete [many [ty. MoonProject.TaskId]],
    },
  },
  product. ProjectReport {
    interned,
    facts [many [ty. MoonProject.TaskFact]],
    ready [many [ty. MoonProject.TaskId]],
    blocked [many [ty. MoonProject.TaskId]],
    done [many [ty. MoonProject.TaskId]],
    deferred [many [ty. MoonProject.TaskId]],
  },
}
