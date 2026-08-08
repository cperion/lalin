local Generation = {}

function Generation.assert_equal(spec, left, right, message)
  spec.assert_truthy(left, "missing left generation")
  spec.assert_truthy(right, "missing right generation")
  spec.assert_truthy(left.key, "left value is not a Provenance.Generation")
  spec.assert_truthy(right.key, "right value is not a Provenance.Generation")
  spec.assert_equal(left.key, right.key, message or "generation mismatch")
end

function Generation.field(value, field)
  field = field or "generation"
  return value and value[field]
end

return Generation
