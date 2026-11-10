# Precision parameters, rounding-mode mapping, and status codes.

"Compile-time default precision in bits for the arb types (`ArbFloat(x)` is `ArbFloat{DEFAULT_PRECISION}(x)`)."
const DEFAULT_PRECISION = 256

const MIN_PRECISION = 2
# Far below ARF_PREC_EXACT (= typemax(Int)); keeps `prec + extra` arithmetic inside FLINT safe.
const MAX_PRECISION = typemax(Int) >> 3

"Validate a precision type parameter once, when a type is instantiated."
@inline function checkprec(P)
    (P isa Int && MIN_PRECISION <= P <= MAX_PRECISION) ||
        throw(ArgumentError("precision must be an Int in $MIN_PRECISION:$MAX_PRECISION, got $(repr(P))"))
    return P
end

# arf_rnd_t values (verified by test/abi/layout.txt).
const ARF_RND_DOWN  = Cint(0)
const ARF_RND_UP    = Cint(1)
const ARF_RND_FLOOR = Cint(2)
const ARF_RND_CEIL  = Cint(3)
const ARF_RND_NEAR  = Cint(4)

_rnd(::RoundingMode{:Nearest})  = ARF_RND_NEAR
_rnd(::RoundingMode{:ToZero})   = ARF_RND_DOWN
_rnd(::RoundingMode{:FromZero}) = ARF_RND_UP
_rnd(::RoundingMode{:Down})     = ARF_RND_FLOOR
_rnd(::RoundingMode{:Up})       = ARF_RND_CEIL
_rnd(r::RoundingMode) = throw(ArgumentError("rounding mode $r is not supported"))

# gr status bits (verified by test/abi/layout.txt).
const GR_SUCCESS = Cint(0)
const GR_DOMAIN  = Cint(1)
const GR_UNABLE  = Cint(2)

"Throw for a status the wrapper does not handle."
@noinline _status_error(st, op, T) =
    error("FLINT $op for $T returned unexpected status $st")

# mpfr_rnd_t values (MPFR_RNDN, RNDZ, RNDU, RNDD, RNDA), for conversions to and from BigFloat.
_mpfr_rnd(::RoundingMode{:Nearest})  = Cint(0)
_mpfr_rnd(::RoundingMode{:ToZero})   = Cint(1)
_mpfr_rnd(::RoundingMode{:Up})       = Cint(2)
_mpfr_rnd(::RoundingMode{:Down})     = Cint(3)
_mpfr_rnd(::RoundingMode{:FromZero}) = Cint(4)
_mpfr_rnd(r::RoundingMode) = throw(ArgumentError("rounding mode $r is not supported"))

"""
    with_precision(f, bits)

Call `f(Val(bits))`. The function barrier for adaptive-precision code: write the body as a method on
`Val{P}` and construct `ArbBall{P}` values inside it, so it compiles once per precision.
"""
with_precision(f, bits::Integer) = f(Val(Int(bits)))
