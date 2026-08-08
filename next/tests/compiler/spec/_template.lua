-- Schema specification template for a compiler boundary.
--
-- Data-only file: do not construct ASDL values here and do not run behavior.
-- Behavior lives in fixture files under next/tests/compiler/fixtures/<key>/.
-- Files whose basename starts with "_" are templates and are skipped by discovery.

return {
  key = "boundary_name",
  plan = "Phase N.N optional plan pointer",
  boundary = "Input.Value -> Output.Value",
  status = "planned", -- planned | in-progress | green

  modules = {
    -- "C",
    -- "Host",
  },

  -- Union leaves owned by this boundary. Every listed leaf must have fixture
  -- coverage before status becomes "green".
  leaves = {
    -- "C.Operation.ConstantOp",
  },
  -- Required method contracts. These make implementation order explicit before
  -- any method code exists.
  methods = {
    -- { owner = "C.Unit", method = "emit_c_unit" },
  },

  implementation_order = {
    -- "C.Type:emit_c_type",
    -- "C.Unit:emit_c_unit",
  },

  -- Deferred leaves must have reasons. Use map form so the reason is attached
  -- to the exact schema leaf.
  excluded = {
    -- ["C.Operation.ClosureOp"] = "closure representation lands in semantic_to_code",
  },

  fixtures = "next/tests/compiler/fixtures/boundary_name/",
  golden = "next/tests/compiler/golden/boundary_name/",

  risks = {
    -- ["known P0 schema risk"] = "intended v1 decision",
  },
}
