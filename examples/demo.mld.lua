local region_lookup = {
    sum_trail = "sum_trail",
}

return module "FunctorPlay" {
  const. Welcome [i32] (2026),
  const. One [i32] (1),
  const. Zero [i32] (0),
  const. MaxSafeSteps [i32] (32),

  struct. Pair {
    head [i32],
    tail [i32],
  },

  union. Trail {
    found { value [i32] },
    none,
  },

  union. SignedMagnitude {
    positive { magnitude [i32] },
    negative { magnitude [i32] },
    zero,
  },

  handle. TrailRef {
    invalid = 0,
  },

  expr_frag. inc ({ x [i32] }) [i32] (x + 1),
  expr_frag. abs_i32 ({ x [i32] }) [i32] (select(x:lt(0), 0 - x, x)),
  expr_frag. clamp_nonneg ({ x [i32], lo [i32], hi [i32] }) [i32] (select(x:lt(lo), lo, select(x:gt(hi), hi, x))),

  region. sum_trail { n [i32] }
    { found { total [i32] }, none, }
    {
      entry. start {} {
        when (n:lt(0)) {
          jump. none {},
        },
        jump. walk {
          sum = 0,
          i = 0,
        },
      },
      block. walk { sum [i32], i [i32] } {
        when (i:gt(n)) {
          jump. found { total = sum },
        },
        jump. walk {
          sum = sum + i,
          i = i + 1,
        },
      },
    },

  region. bounded_sum { n [i32], max_steps [i32] }
    {
      done { total [i32], steps [i32] },
    }
    {
      entry. start {} {
        emit. sum_trail { select(max_steps:lt(n), max_steps, n) } {
          found = found,
          none = none,
        },
      },
      block. found { total [i32] } {
        jump. done {
          total = total,
          steps = select(select(max_steps:lt(n), max_steps, n):gt(0), select(max_steps:lt(n), max_steps, n), 0),
        },
      },
      block. none {} {
        jump. done { total = 0, steps = 0 },
      },
    },

  region. classify_sign { x [i32] }
    {
      positive { magnitude [i32] },
      negative { magnitude [i32] },
      zero,
    }
    {
      entry. start {} {
        when (x:gt(0)) {
          jump. positive { magnitude = x },
        },
        when (x:lt(0)) {
          jump. negative { magnitude = 0 - x },
        },
        jump. zero {},
      },
    },

  fn. triangular { n [i32] } [i32] {
      entry. start {} {
        emit. sum_trail { n } {
          found = found,
          none = none,
        },
      },
      block. found { total [i32] } { ret(total) },
      block. none {} { ret(0) },
    },

  fn. safe_triangular { n [i32], cap [i32] } [i32] {
      entry. start {} {
        emit. bounded_sum { n, select(cap:lt(n), cap, n) } {
          done = done,
        },
      },
      block. done { total [i32], steps [i32] } { ret(total) },
    },

  fn. sum_via_lookup { n [i32] } [i32] {
      entry. start {} {
        emit [region_lookup["sum_trail"]] { n } {
          found = done,
          none = none,
        },
      },
      block. done { total [i32] } { ret(total) },
      block. none {} { ret(0) },
    },

  fn. signed_magnitude { x [i32] } [i32] {
      entry. start {} {
        emit. classify_sign { x } {
          positive = pos,
          negative = neg,
          zero = zero,
        },
      },
      block. pos { magnitude [i32] } { ret(magnitude) },
      block. neg { magnitude [i32] } { ret(0 - magnitude) },
      block. zero {} { ret(0) },
    },

  fn. alternating_sum { n [i32] } [i32] {
      entry. start {} {
        jump. loop {
          acc = 0,
          i = 0,
          sign = 1,
        },
      },

      block. loop { acc [i32], i [i32], sign [i32] } {
        when (i:ge(n)) {
          ret(acc),
        },
        jump. loop {
          acc = select(sign:gt(0), acc + i, acc - i),
          i = i + 1,
          sign = 0 - sign,
        },
      },
    },

  fn. trail_powered_pair { n [i32] } [i32] {
      entry. start {} {
        emit. sum_trail { n } {
          found = plus_one,
          none = none,
        },
      },
      block. plus_one { total [i32] } {
        ret (total + 1),
      },
      block. none {} {
        emit. bounded_sum { 0, MaxSafeSteps } {
          done = zero_done,
        },
      },
      block. zero_done { total [i32], steps [i32] } {
        ret(total),
      },
    },
}
