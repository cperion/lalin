local Impl = {
  modules = {
  },
}

function Impl.load(_Compiler)
  -- Phase 0 loader hook. Concrete method modules are added only after their
  -- schema specification and fixtures exist.
end

return Impl
