# ArbFloat{P}: FLINT arf at P bits. Mutable owner of a 4-word arf_struct. Correctly rounded in strict modes.

"""
    ArbFloat{P}

Arbitrary-precision float with `P`-bit mantissa (FLINT `arf`): unbounded exponent, no negative zero,
correctly rounded `+ - * /`. Not an enclosure. Invariant: the mantissa never exceeds `P` bits.
Mutable; `copy` makes an independent value and `add!`, `sub!`, `mul!`, `div!` reuse storage
(destination first, returned).
"""
mutable struct ArbFloat{P} <: FlintReal
    w::NTuple{4,UInt}                     # arf_struct (sizeof 32, test/abi/layout.txt)
    function ArbFloat{P}() where {P}
        checkprec(P)
        x = new{P}((0, 0, 0, 0))
        LibFlint.arf_init(x)
        finalizer(_clear!, x)             # registered immediately after successful init
        return x
    end
end

_clear!(x::ArbFloat) = (LibFlint.arf_clear(x); nothing)

Base.precision(::Type{ArbFloat{P}}) where {P} = P
Base.precision(::ArbFloat{P}) where {P} = P

function ArbFloat{P}(x::Float64) where {P}
    z = ArbFloat{P}()
    LibFlint.arf_set_d(z, x)
    LibFlint.arf_set_round(z, z, P, ARF_RND_NEAR)    # precision invariant
    return z
end

function ArbFloat{P}(x::Int) where {P}
    z = ArbFloat{P}()
    LibFlint.arf_set_si(z, x)
    LibFlint.arf_set_round(z, z, P, ARF_RND_NEAR)
    return z
end


function Base.copy(x::ArbFloat{P}) where {P}
    z = ArbFloat{P}()
    LibFlint.arf_set(z, x)
    return z
end

Base.Float64(x::ArbFloat) = LibFlint.arf_get_d(x, ARF_RND_NEAR)

# Destination-first arithmetic: z = add!(z, x, y [, rounding]). `_inexact` also returns FLINT's flag.
for (name, f) in ((:add, :arf_add), (:sub, :arf_sub), (:mul, :arf_mul_rnd_any), (:div, :arf_div))
    bang = Symbol(name, :!)
    inexact = Symbol(name, :_inexact!)
    @eval function $inexact(z::ArbFloat{P}, x::ArbFloat{P}, y::ArbFloat{P},
                            r::RoundingMode = RoundNearest) where {P}
        flag = LibFlint.$f(z, x, y, P, _rnd(r))
        return z, flag != 0
    end
    @eval function $bang(z::ArbFloat{P}, x::ArbFloat{P}, y::ArbFloat{P},
                         r::RoundingMode = RoundNearest) where {P}
        LibFlint.$f(z, x, y, P, _rnd(r))
        return z
    end
end

Base.:+(x::ArbFloat{P}, y::ArbFloat{P}) where {P} = add!(ArbFloat{P}(), x, y)
Base.:-(x::ArbFloat{P}, y::ArbFloat{P}) where {P} = sub!(ArbFloat{P}(), x, y)
Base.:*(x::ArbFloat{P}, y::ArbFloat{P}) where {P} = mul!(ArbFloat{P}(), x, y)
Base.:/(x::ArbFloat{P}, y::ArbFloat{P}) where {P} = div!(ArbFloat{P}(), x, y)

# ---- classification, unary operations ------------------------------------------------------------

Base.iszero(x::ArbFloat) = LibFlint.arf_is_zero(x) != 0
Base.isnan(x::ArbFloat) = LibFlint.arf_is_nan(x) != 0
Base.isfinite(x::ArbFloat) = LibFlint.arf_is_finite(x) != 0
Base.isinf(x::ArbFloat) = LibFlint.arf_is_pos_inf(x) != 0 || LibFlint.arf_is_neg_inf(x) != 0
Base.isinteger(x::ArbFloat) = LibFlint.arf_is_int(x) != 0
"Negative values only: FLINT's `arf` has no negative zero, and NaN has no sign."
Base.signbit(x::ArbFloat) = LibFlint.arf_sgn(x) < 0
Base.sign(x::ArbFloat{P}) where {P} = isnan(x) ? x : ArbFloat{P}(Int(LibFlint.arf_sgn(x)))

Base.zero(::Type{ArbFloat{P}}) where {P} = ArbFloat{P}()
Base.one(::Type{ArbFloat{P}}) where {P} = ArbFloat{P}(1)
Base.zero(::Type{ArbFloat}) = zero(ArbFloat{DEFAULT_PRECISION})
Base.one(::Type{ArbFloat}) = one(ArbFloat{DEFAULT_PRECISION})
Base.zero(::ArbFloat{P}) where {P} = ArbFloat{P}()
Base.one(::ArbFloat{P}) where {P} = ArbFloat{P}(1)

"Set `z` to the nearest-rounded copy of `x` (precision `P` of `z`), returning `z`."
function set!(z::ArbFloat{P}, x::ArbFloat, r::RoundingMode = RoundNearest) where {P}
    LibFlint.arf_set_round(z, x, P, _rnd(r))
    return z
end

for (name, f) in ((:neg, :arf_neg), (:abs, :arf_abs))
    bang = Symbol(name, :!)
    # Exact for same precision, so no rounding argument; z may alias x.
    @eval function $bang(z::ArbFloat{P}, x::ArbFloat{P}) where {P}
        LibFlint.$f(z, x)
        return z
    end
end
Base.:-(x::ArbFloat{P}) where {P} = neg!(ArbFloat{P}(), x)
Base.abs(x::ArbFloat{P}) where {P} = abs!(ArbFloat{P}(), x)

function sqrt_inexact!(z::ArbFloat{P}, x::ArbFloat{P}, r::RoundingMode = RoundNearest) where {P}
    signbit(x) && throw(DomainError(x, "sqrt of a negative ArbFloat; use AcbFloat for a complex result"))
    flag = LibFlint.arf_sqrt(z, x, P, _rnd(r))
    return z, flag != 0
end
sqrt!(z::ArbFloat{P}, x::ArbFloat{P}, r::RoundingMode = RoundNearest) where {P} = first(sqrt_inexact!(z, x, r))
Base.sqrt(x::ArbFloat{P}) where {P} = sqrt!(ArbFloat{P}(), x)
