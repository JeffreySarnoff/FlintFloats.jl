# Operation capability table

Maintained per [enact_interfacing.md §7.3](enact_interfacing.md). Facts are for the pinned source
`82c40b299084b92299c2d8dac464e39d6743fce4` (FLINT 3.7.0-dev). "Evidence" names the test that backs
each claim. Add a row in the same change as each new operation.

| Operation | Family | FLINT entry | Guarantee | Special values and failure | Evidence |
| --- | --- | --- | --- | --- | --- |
| `+ - *` | `DFloat{N}` | `dN_add/sub/mul` | approximate, like `Float64` | `Inf`/`NaN` propagate | `arithmetic_tests` |
| `/` | `DFloat{N}` | `dN_div` | approximate | `x/0` gives `Inf`, `0/0` gives `NaN` | `arithmetic_tests` |
| `sqrt` | `DFloat{N}` | `dN_sqrt` | approximate | negative argument: `DomainError` (checked in Julia) | `unary_tests` |
| `+ - *` | `DFloatBall{N}` | `dNb_add/sub/mul` | rigorous enclosure; exact inputs stay exact | nonfinite input gives the whole real line | `arithmetic_tests` |
| `/` | `DFloatBall{N}` | `dNb_div` | rigorous enclosure | `GR_DOMAIN` (divisor exactly zero): `DomainError`; `GR_UNABLE` (divisor contains zero): whole real line written by the wrapper | `arithmetic_tests` |
| `sqrt` | `DFloatBall{N}` | `dNb_sqrt` | rigorous enclosure | `GR_DOMAIN` (entirely negative): `DomainError`; `GR_UNABLE`: whole real line | `unary_tests` |
| `+ - *` | `NFloat{L}` | `nfloat_add/sub/mul` | flags = underflow only; see note 1 | finite-only; overflow gives an error status | `arithmetic_tests` |
| `/` | `NFloat{L}` | `nfloat_div` | truncated, error under 1 ulp, **not** correctly rounded | divisor zero: `DivideError` | `arithmetic_tests` |
| `sqrt` | `NFloat{L}` | `nfloat_sqrt` | see FLINT docs; not yet differentially tested | negative: `DomainError` (checked in Julia; FLINT reports `GR_UNABLE`) | `unary_tests` (exact cases only) |
| `+ - * /` | `ArbFloat{P}` | `arf_add/sub/mul_rnd_any/div` | correctly rounded in the five strict modes; inexact flag via `_inexact!` | `x/0` is NaN; no negative zero; unbounded exponent | MPFR bit-for-bit, `arithmetic_tests` |
| `sqrt` | `ArbFloat{P}` | `arf_sqrt` | correctly rounded in the five strict modes | negative: `DomainError` (checked in Julia); NaN stays NaN | MPFR bit-for-bit, `unary_tests` |
| `+ - * /` | `AcbFloat{P}` | `acf_add/sub/mul/div` | each part correctly rounded in the five strict modes (sampled, P ≤ 53) | follows `arf` | exact-reference differential, `arithmetic_tests` |
| `sqrt` | `AcbFloat{P}` | `acf_sqrt` | each part correctly rounded (sampled, P ≤ 53) | principal branch | exact-reference differential, `unary_tests` |
| `abs`, `abs2` | `AcbFloat{P}` | built from `arf_mul_rnd_any` (exact squares), `arf_add`, `arf_sqrt` | **correctly rounded** in the five strict modes; `abs2` is one rounding of the exact sum; `abs` brackets the exact sum between two W = 2P+4 bit values and resolves a rounding boundary exactly (comments in `src/acf.jl`); `_inexact!` variants return the flag | `Inf` wins over NaN (as `hypot`); exponent unbounded, so no overflow | exact-reference differential (4000 cases, gaps up to 2^-200), boundary cases, `unary_tests` |
| `conj` | `AcbFloat{P}` | exact negation of the imaginary part | exact | | `unary_tests` |
| `+ - * /`, `sqrt` | `ArbBall{P}` | `arb_*` | rigorous enclosure at working precision `P` | `/` by a ball containing zero, or `sqrt` reaching below zero, gives FLINT's indeterminate ball (NaN midpoint), not an error | `arithmetic_tests`, `unary_tests` |
| `+ - * /`, `sqrt`, `abs` | `AcbBall{P}` | `acb_*` | rigorous enclosure; `abs` is an `ArbBall` | as `ArbBall` | `arithmetic_tests`, `unary_tests` |
| conversion into a type | all | `arf_set_round`, `arb_set_round`, `arf_set_mpfr`, `nfloat_set_arf`, `dN_set_arf` | one rounding to nearest at the target precision; point to ball contains the point | `Inf`/`NaN` into `NFloat`: `DomainError`; ball to point: `ArgumentError` (use `midpoint`) | `conversion_tests` |
| `parse` | all real | `BigFloat` parse then `arf_set_mpfr` (`ArbFloat`, `NFloat`); `arb_set_str` (`ArbBall`); `dN_set_str`, `dNb_set_str` | decimal read directly at the target precision, never through `Float64` | malformed text: `ArgumentError` | `conversion_tests` |
| `show` | all | `BigFloat` formatting (points), `arb_get_str` (balls), exact tuple (`DFloat`, `DFloatBall`) | point types print a constructor that rebuilds the identical value; ball types rebuild a ball containing the original | FLINT string freed with `flint_free` in a `finally` | `conversion_tests` |
| `==`, `<`, `<=`, `isequal`, `isless`, `hash` | `DFloat`, `NFloat`, `ArbFloat`, `AcbFloat` and Julia numbers | `arf_cmp` after an `arf_is_nan` test; exact `ArbFloat` views of every operand | exact value, across precisions and families; NaN: `==` false, `isequal` true, last in `isless`; hash is the `BigFloat` hash of the exact value | no `-0`: a point zero is `isequal` to `0.0` only; huge exponents are hashed without expansion (beyond MPFR's range they hash as `Inf`) | `compare_tests` (every pair of a mixed pool, every seed) |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | `ArbBall`, `AcbBall` (`==`, `!=` only) | `arb_eq/ne/lt/le/gt/ge`, `acb_eq/ne` | proved for every pair of points; `false` when unproved | indeterminate balls prove nothing; `isless`, `min`, `max`, `sort` throw `ArgumentError` | `compare_tests` |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | `DFloatBall` | `dNb_equal`, `dNb_overlaps`, exact endpoints (`dNb_cmp` is a cross-check) | proved; touching balls prove `<=` | the whole real line proves nothing | `compare_tests` |
| `isequal`, `hash` | all balls | `arb_equal`, `acb_equal`, value comparison | identical mid and radius; one indeterminate value; exact ball equals its midpoint | | `compare_tests` |
| promotion, `convert` | all | none (Julia-side) | widening exact or containing; narrowing a point exact else `InexactError` | `DFloat` with `NFloat`, `DFloatBall` with arb, `BigFloat`: explicit only (`ArgumentError`/`ErrorException`) | `promotion_tests` |
| `eps`, `nextfloat`, `prevfloat`, `significand`, `exponent` | `ArbFloat`, `NFloat` | `arf_abs_bound_lt_2exp_si`, `arf_mul_2exp_si`, correctly rounded `arf_add` | match `Float64`/`Float32` at 53/24 bits (tested) | zero, Inf: `DomainError`; unbounded exponent | `basefloat_tests` |

Notes

1. `NFloat` contexts use `NFLOAT_ALLOW_UNDERFLOW` only. With `ALLOW_INF`/`ALLOW_NAN` the pinned
   `nfloat_add(Inf, 1)` returns NaN and `nfloat_mul` returns `GR_UNABLE` for any special operand,
   including zero times zero.
2. "Sampled" means a randomized differential test, not a proof.
3. Unsupported requested rounding modes (for example `RoundNearestTiesAway`) throw `ArgumentError`.
