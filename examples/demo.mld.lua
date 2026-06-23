return module "FunctorPlay" {
  const .Welcome [i32] (2026),
  static .Zero [i32] (0),

  struct .Pair {
    head [index],
    tail [index],
  },

  union .Trail {
    found { value [index] },
    none,
  },

  handle .TrailRef {
    invalid = 0,
  },

  expr_frag .inc ({ x [index] }) [index] (x + as [index] (1)),

  region .sum_trail
    { n [index] }
    {
      hit { total [index] },
      miss,
    }
    {
      entry .start {} {
        when (n:ge(as [index] (0))) {
          jump .miss {},
        },
        jump .hit { total = n },
      },
    },

  fn .triangular
    { n [index] }
    [index]
    {
      entry .start {} {
        emit .sum_trail { n } {
          hit = found,
          miss = done,
        },
      },

      block .found { total [index] } {
        ret (total),
      },
      block .done {} {
        ret (as [index] (0)),
      },
    },

  fn .waltz
    { n [index] }
    [index]
    {
      entry .start { acc [index](as [index] (0)), i [index](as [index] (0)) } {
        jump .spin {
          acc = as [index] (Welcome),
          i = i,
        },
      },

      block .spin { acc [index], i [index] } {
        when (i:ge(n)) {
          ret (acc),
        },

        jump .spin {
          acc = acc + i,
          i = i + as [index] (1),
        },
      },
    },
}
