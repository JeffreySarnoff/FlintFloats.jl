# Audit of inherited AbstractFloat behaviour (enact §8.3).
#
# Supported with a coherent meaning:
#   ArbFloat{P}  eps, nextfloat, prevfloat, significand, exponent (P-bit spacing, unbounded exponent)
#   NFloat{L}    the same, at 64L bits, through ArbFloat
#   DFloat{N}    eps(::Type) only, as the nominal 53N-bit spacing
# Rejected with an explicit error (never the inherited fallback):
#   floatmin, floatmax    unbounded or format-dependent exponent range
#   DFloat per-value neighbours and exponent    expansions have several representations
#   balls: eps, nextfloat, prevfloat, significand, exponent, isapprox    no unique neighbouring scalar
# Not defined (MethodError): typemin, typemax, round, floor, ceil, trunc, elementary functions.

_unsupported(f, T, why) = throw(ArgumentError("$f is not defined for $T: $why"))

# ---- ArbFloat -----------------------------------------------------------------------------------------

function Base.exponent(x::ArbFloat)
    (!isfinite(x) || iszero(x)) && throw(DomainError(x, "Cannot be NaN, Inf or 0"))
    return Int(LibFlint.arf_abs_bound_lt_2exp_si(x)) - 1                  # |x| in [2^e, 2^(e+1))
end

function Base.significand(x::ArbFloat{P}) where {P}
    (!isfinite(x) || iszero(x)) && return copy(x)
    z = ArbFloat{P}()
    LibFlint.arf_mul_2exp_si(z, x, -exponent(x))                          # exact scaling
    return z
end

function _pow2(::Type{ArbFloat{P}}, e::Integer) where {P}
    z = ArbFloat{P}(1)
    LibFlint.arf_mul_2exp_si(z, z, e)
    return z
end

"Spacing of `P`-bit values at 1: `2^(1-P)`."
Base.eps(::Type{ArbFloat{P}}) where {P} = _pow2(ArbFloat{P}, 1 - P)

"Spacing between `x` and the next larger `P`-bit value of the same binade."
function Base.eps(x::ArbFloat{P}) where {P}
    isnan(x) && return x
    isinf(x) && return ArbFloat{P}(NaN)
    iszero(x) && throw(DomainError(x, "ArbFloat has no smallest positive value, so eps(0) is undefined"))
    return _pow2(ArbFloat{P}, exponent(x) - P + 1)
end

# Neighbours by correctly rounded addition of a quantity below half the finest spacing: rounding up
# (down) gives the immediate successor (predecessor) in every binade, including at powers of two.
function _neighbour(x::ArbFloat{P}, sgn::Int) where {P}
    isnan(x) && return x
    iszero(x) && throw(DomainError(x, "ArbFloat has no smallest positive value: nextfloat/prevfloat of 0 is undefined"))
    if isinf(x)
        sgn * (signbit(x) ? -1 : 1) > 0 && return copy(x)                 # nextfloat(Inf), prevfloat(-Inf)
        throw(DomainError(x, "ArbFloat has no largest finite value"))
    end
    tiny = _pow2(ArbFloat{P}, exponent(x) - P - 1)
    sgn < 0 && neg!(tiny, tiny)
    return add!(ArbFloat{P}(), x, tiny, sgn > 0 ? RoundUp : RoundDown)
end
Base.nextfloat(x::ArbFloat) = _neighbour(x, 1)
Base.prevfloat(x::ArbFloat) = _neighbour(x, -1)

# ---- NFloat, through ArbFloat at its own width --------------------------------------------------------

Base.eps(::Type{NFloat{L}}) where {L} = NFloat{L}(eps(ArbFloat{64L}))
Base.eps(x::NFloat{L}) where {L} = NFloat{L}(eps(ArbFloat{64L}(x)))
Base.exponent(x::NFloat{L}) where {L} = exponent(ArbFloat{64L}(x))
Base.significand(x::NFloat{L}) where {L} = NFloat{L}(significand(ArbFloat{64L}(x)))
Base.nextfloat(x::NFloat{L}) where {L} = NFloat{L}(nextfloat(ArbFloat{64L}(x)))
Base.prevfloat(x::NFloat{L}) where {L} = NFloat{L}(prevfloat(ArbFloat{64L}(x)))

# ---- DFloat -------------------------------------------------------------------------------------------

"Nominal spacing of an `N`-double expansion at 1, `2^(1-53N)`; accuracy varies by operation."
Base.eps(::Type{DFloat{N}}) where {N} = DFloat{N}(ldexp(1.0, 1 - 53N))
for f in (:eps, :exponent, :significand, :nextfloat, :prevfloat)
    @eval Base.$f(x::DFloat) = _unsupported($(QuoteNode(f)), typeof(x),
        "an expansion can have several representations of one value")
end

# ---- exponent range -----------------------------------------------------------------------------------

for f in (:floatmin, :floatmax)
    @eval Base.$f(::Type{T}) where {T<:FlintReal} = _unsupported($(QuoteNode(f)), T,
        "the exponent range is unbounded or format-dependent")
end

# ---- balls --------------------------------------------------------------------------------------------

const BallAny = Union{DFloatBall,ArbBall,AcbBall}
for f in (:eps, :exponent, :significand, :nextfloat, :prevfloat)
    @eval Base.$f(x::Union{DFloatBall,ArbBall}) = _unsupported($(QuoteNode(f)), typeof(x),
        "a ball has no unique neighbouring scalar value")
end
Base.eps(::Type{T}) where {T<:Union{DFloatBall,ArbBall}} = _unsupported(:eps, T, "a ball has no unique neighbouring scalar value")

const _NOAPPROX = "use contains or overlaps to relate balls"
Base.isapprox(x::BallAny, y::BallAny; kw...) = _unsupported(:isapprox, typeof(x), _NOAPPROX)
Base.isapprox(x::BallAny, y::Number; kw...) = _unsupported(:isapprox, typeof(x), _NOAPPROX)
Base.isapprox(x::Number, y::BallAny; kw...) = _unsupported(:isapprox, typeof(y), _NOAPPROX)
