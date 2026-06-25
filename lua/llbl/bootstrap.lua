local M = {}

local function shallow_copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function install(llbl)
    if llbl.bootstrap and llbl.bootstrap.stage == "stage1" then return llbl.bootstrap end

    local stage0 = assert(llbl.grammar, "llbl bootstrap requires stage-0 grammar")
    local g, ch = stage0, llbl.channel

    local function text(v)
        if llbl.is(v, "Name") or llbl.is(v, "Symbol") then return v.text end
        if type(v) == "table" and rawget(v, "name") then return tostring(v.name) end
        return tostring(v)
    end

    local function attrs(v)
        return type(v) == "table" and v or {}
    end

    local function with_origin(value, origin)
        if type(value) == "table" and origin ~= nil then value.origin = origin end
        return value
    end

    local function stage0_role(name, spec, origin)
        return with_origin(stage0.role[text(name)](attrs(spec)), origin)
    end

    local function stage0_head(name, body, origin)
        return with_origin(stage0.head[text(name)](attrs(body)), origin)
    end

    local function stage0_slot(name, role, spec, origin)
        return with_origin(stage0.slot[text(name)][stage0[text(role)]](attrs(spec)), origin)
    end

    local function stage0_scalar(name, origin)
        return with_origin(stage0.scalar[text(name)], origin)
    end

    local function stage0_trait(name, origin)
        return with_origin(stage0.trait[text(name)], origin)
    end

    local function stage0_protocol(name, origin)
        return with_origin(stage0.protocol[text(name)], origin)
    end

    local LLBL = llbl.dialect "llbl" {
        g.role. grammar_body { kind = "array", item = "identity" },

        g.head. role {
            g.slot. name [g.name],
            g.slot. spec [g.value] { channel = ch.call_table },
            emit = function(n) return stage0_role(n.name, n.spec, n.origin) end,
        },

        g.head. head {
            g.slot. name [g.name],
            g.slot. body [g.value] { channel = ch.call_table },
            emit = function(n) return stage0_head(n.name, n.body, n.origin) end,
        },

        g.head. slot {
            g.slot. name [g.name],
            g.slot. role [g.identity] { channels = { ch.index_name, ch.index_value, ch.index_type } },
            g.slot. spec [g.value] { channel = ch.call_table, optional = true, default = {} },
            emit = function(n) return stage0_slot(n.name, n.role, n.spec, n.origin) end,
        },

        g.head. scalar {
            g.slot. name [g.name],
            emit = function(n) return stage0_scalar(n.name, n.origin) end,
        },

        g.head. type_ctor {
            g.slot. name [g.name],
            g.slot. spec [g.value] { channel = ch.call_table },
            emit = function(n) return with_origin(stage0.type_ctor[text(n.name)](attrs(n.spec)), n.origin) end,
        },

        g.head. helper {
            g.slot. name [g.name],
            g.slot. spec [g.value] { channel = ch.call_table },
            emit = function(n) return with_origin(stage0.helper[text(n.name)](attrs(n.spec)), n.origin) end,
        },

        g.head. pass {
            g.slot. name [g.name],
            g.slot. spec [g.value] { channel = ch.call_table },
            emit = function(n) return with_origin(stage0.pass[text(n.name)](attrs(n.spec)), n.origin) end,
        },

        g.head. phase {
            g.slot. name [g.name],
            g.slot. spec [g.value] { channel = ch.call_table },
            emit = function(n) return with_origin(stage0.phase[text(n.name)](attrs(n.spec)), n.origin) end,
        },

        g.head. lsp {
            g.slot. name [g.name],
            g.slot. spec [g.value] { channel = ch.call_table },
            emit = function(n) return with_origin(stage0.lsp[text(n.name)](attrs(n.spec)), n.origin) end,
        },

        g.head. trait {
            g.slot. name [g.name],
            emit = function(n) return stage0_trait(n.name, n.origin) end,
        },

        g.head. protocol {
            g.slot. name [g.name],
            emit = function(n) return stage0_protocol(n.name, n.origin) end,
        },

        g.head. type_system {
            g.slot. spec [g.value] { channel = ch.call_table },
            emit = function(n) return with_origin(stage0.type_system(attrs(n.spec)), n.origin) end,
        },
    }

    local function role_ref(name)
        return llbl.shared.symbols.source(name, { origin = llbl.here("llbl-bootstrap-role", { skip = 2 }) })
    end

    local SlotStage = {}
    SlotStage.__index = function(self, role)
        local slot_head = rawget(self, "slot_head")
        return llbl.collect_head_events(slot_head, {
            llbl.event(ch.index_name, llbl.name(text(rawget(self, "name"))), { action = "name", argc = 1 }),
            llbl.event(ch.index_type, role_ref(text(role)), { action = "index", argc = 1 }),
        })
    end

    local SlotFactory = {}
    SlotFactory.__index = function(self, key)
        return setmetatable({
            __llbl_tag = "LlblBootstrapSlotStage",
            name = key,
            slot_head = rawget(self, "slot_head"),
        }, SlotStage)
    end

    local function slot_factory(slot_head)
        return setmetatable({ __llbl_tag = "LlblBootstrapSlotFactory", slot_head = slot_head }, SlotFactory)
    end

    local function grammar_facade(dialect)
        local env = dialect.exports or {}
        local facade = {
            __llbl_tag = "LlblBootstrapGrammar",
            dialect = dialect,
            stage0 = stage0,
            role = env.role,
            head = env.head,
            slot = slot_factory(env.slot),
            scalar = env.scalar,
            type_ctor = env.type_ctor,
            helper = env.helper,
            pass = env.pass,
            phase = env.phase,
            lsp = env.lsp,
            trait = env.trait,
            protocol = env.protocol,
            type_system = env.type_system,
        }
        return setmetatable(facade, {
            __index = function(_, key) return role_ref(key) end,
        })
    end

    local normalize_role_region = llbl.region("llbl.bootstrap.normalize_role")["role_value"] { "ctx", "value" } (function(_, ctx, value)
        return llbl.gps.raw(llbl.gps.once(llbl.normalize_role(ctx, ctx.role, value)))
    end)
    normalize_role_region:materializer("collect", {
        kind = "llbl-bootstrap-normalize-role",
        body = function(ctx, value) return llbl.normalize_role(ctx, ctx.role, value) end,
    })

    local render_doc_region = llbl.region("llbl.bootstrap.render_doc")["role_items"] { "doc", "opts" } (function(_, doc, opts)
        return llbl.render_region(doc, opts or {})
    end)
    render_doc_region:materializer("string", {
        kind = "llbl-bootstrap-render-doc",
        body = function(doc, opts) return llbl.render(doc, opts or {}) end,
    })

    llbl.kernel = llbl.kernel or {}
    llbl.kernel.grammar = llbl.kernel.grammar or stage0
    llbl.kernel.dialect = llbl.kernel.dialect or llbl.dialect
    llbl.kernel.describe = llbl.kernel.describe or {
        stage = "stage0",
        owns = {
            "primitive-values",
            "origins",
            "diagnostics",
            "gps",
            "regions",
            "stage0-grammar-records",
            "dialect-compiler",
        },
    }

    local bootstrap = {
        __llbl_tag = "LlblBootstrap",
        stage = "stage1",
        dialect = LLBL,
        grammar = grammar_facade(LLBL),
        kernel = llbl.kernel,
        machines = {
            normalize_role = normalize_role_region,
            render_doc = render_doc_region,
        },
    }

    function bootstrap.describe()
        return {
            tag = "LlblBootstrap",
            stage = bootstrap.stage,
            dialect = llbl.describe(bootstrap.dialect),
            grammar = {
                tag = bootstrap.grammar.__llbl_tag,
                dialect = bootstrap.grammar.dialect.name,
                stage0 = bootstrap.grammar.stage0 == stage0,
            },
            machines = {
                normalize_role = llbl.describe_region(normalize_role_region),
                render_doc = llbl.describe_region(render_doc_region),
            },
            kernel = shallow_copy(llbl.kernel.describe),
        }
    end

    llbl.bootstrap = bootstrap
    llbl.self = LLBL
    llbl.grammar = bootstrap.grammar
    llbl.dialects.llbl = LLBL
    return bootstrap
end

M.install = install

return M
