package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./lua/?.lua",
    "./lua/?/init.lua",
    package.path,
}, ";")

return function(T)
    local Native = T.LalinNative
    local Support = require("lalin.native_template_support")(T)
    local Sources = require("lalin.native_template_sources")(T)
    local bank_id = Native.NativeBankId(os.getenv("LALIN_NATIVE_BANK_ID") or "lalin.native.complete.host")
    return Sources.bank_request_for_complete_capability(Support.host_complete_bank_capability(), bank_id)
end
