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
    local bank_id = os.getenv("LALIN_NATIVE_BANK_ID") or "lalin.native.empty"
    local manifest = Support.template_source_manifest(
        Support.template_manifest_id("empty." .. bank_id),
        Native.NativeTemplateSupportDomainId("native.template.support.empty." .. bank_id),
        {}
    )
    return Native.NativeTemplateBankRequest(
        Native.NativeBankId(bank_id),
        Support.host_target(),
        Support.empty_runtime(),
        manifest,
        {}
    )
end
