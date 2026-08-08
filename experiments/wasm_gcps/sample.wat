(module
  (func (export "sum") (param $n i32) (result i32)
    (local $result i32)
    (local $index i32)
    i32.const 0
    local.set $result
    i32.const 1
    local.set $index
    block $exit
      loop $body
        local.get $index
        local.get $n
        i32.gt_s
        br_if $exit
        local.get $result
        local.get $index
        i32.add
        local.set $result
        local.get $index
        i32.const 1
        i32.add
        local.set $index
        br $body
      end
    end
    local.get $result)

  (func (export "mixed") (param $n i32) (result f64)
    (local $result f64)
    (local $index i32)
    f64.const 0
    local.set $result
    i32.const 1
    local.set $index
    block $exit
      loop $body
        local.get $index
        local.get $n
        i32.gt_s
        br_if $exit
        local.get $result
        local.get $index
        f64.convert_i32_s
        f64.const 1.5
        f64.mul
        f64.add
        local.set $result
        local.get $index
        i32.const 1
        i32.add
        local.set $index
        br $body
      end
    end
    local.get $result)
  )

