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

ArbFloat(x) = ArbFloat{DEFAULT_PRECISION}(x)
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

ArbFloat{P}(x::Real) where {P} = ArbFloat{P}(Float64(x))

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
