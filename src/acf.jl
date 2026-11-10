# AcbFloat{P}: FLINT acf at P bits. Mutable owner of an 8-word acf_struct (two arf).

"""
    AcbFloat{P}

Complex float with `P`-bit parts (FLINT `acf`); each part correctly rounded. Not an enclosure.
Mutable owner; see [`ArbFloat`](@ref) for the shared conventions.
"""
mutable struct AcbFloat{P} <: Number
    w::NTuple{8,UInt}                     # acf_struct (sizeof 64, test/abi/layout.txt)
    function AcbFloat{P}() where {P}
        checkprec(P)
        z = new{P}((0, 0, 0, 0, 0, 0, 0, 0))
        LibFlint.acf_init(z)
        finalizer(_clear!, z)
        return z
    end
end

_clear!(z::AcbFloat) = (LibFlint.acf_clear(z); nothing)

AcbFloat(re, im = 0.0) = AcbFloat{DEFAULT_PRECISION}(re, im)
Base.precision(::Type{AcbFloat{P}}) where {P} = P
Base.precision(::AcbFloat{P}) where {P} = P

function AcbFloat{P}(re::Float64, im::Float64) where {P}
    z = AcbFloat{P}()
    GC.@preserve z begin
        for (p, v) in ((LibFlint.acf_real_ptr(z), re), (LibFlint.acf_imag_ptr(z), im))
            LibFlint.arf_set_d(p, v)
            LibFlint.arf_set_round(p, p, P, ARF_RND_NEAR)    # precision invariant
        end
    end
    return z
end

function Base.copy(z::AcbFloat{P}) where {P}
    w = AcbFloat{P}()
    LibFlint.acf_set(w, z)
    return w
end

function _part(z::AcbFloat{P}, ptr) where {P}
    x = ArbFloat{P}()
    GC.@preserve z LibFlint.arf_set(x, ptr(z))
    return x
end
Base.real(z::AcbFloat) = _part(z, LibFlint.acf_real_ptr)
Base.imag(z::AcbFloat) = _part(z, LibFlint.acf_imag_ptr)

for (name, f) in ((:add, :acf_add), (:sub, :acf_sub), (:mul, :acf_mul), (:div, :acf_div))
    bang = Symbol(name, :!)
    inexact = Symbol(name, :_inexact!)
    @eval function $inexact(z::AcbFloat{P}, x::AcbFloat{P}, y::AcbFloat{P},
                            r::RoundingMode = RoundNearest) where {P}
        flag = LibFlint.$f(z, x, y, P, _rnd(r))
        return z, flag != 0
    end
    @eval function $bang(z::AcbFloat{P}, x::AcbFloat{P}, y::AcbFloat{P},
                         r::RoundingMode = RoundNearest) where {P}
        LibFlint.$f(z, x, y, P, _rnd(r))
        return z
    end
end

Base.:+(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = add!(AcbFloat{P}(), x, y)
Base.:-(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = sub!(AcbFloat{P}(), x, y)
Base.:*(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = mul!(AcbFloat{P}(), x, y)
Base.:/(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = div!(AcbFloat{P}(), x, y)

# ---- classification, unary operations -------------------------------------------------------------

Base.iszero(z::AcbFloat) = iszero(real(z)) && iszero(imag(z))
Base.isnan(z::AcbFloat) = isnan(real(z)) || isnan(imag(z))
Base.isinf(z::AcbFloat) = isinf(real(z)) || isinf(imag(z))
Base.isfinite(z::AcbFloat) = isfinite(real(z)) && isfinite(imag(z))

Base.zero(::Type{AcbFloat{P}}) where {P} = AcbFloat{P}()
Base.one(::Type{AcbFloat{P}}) where {P} = AcbFloat{P}(1.0, 0.0)
Base.zero(::Type{AcbFloat}) = zero(AcbFloat{DEFAULT_PRECISION})
Base.one(::Type{AcbFloat}) = one(AcbFloat{DEFAULT_PRECISION})
Base.zero(::AcbFloat{P}) where {P} = AcbFloat{P}()
Base.one(::AcbFloat{P}) where {P} = AcbFloat{P}(1.0, 0.0)

"Complex number from real and imaginary parts of the same precision (exact copy)."
function AcbFloat{P}(re::ArbFloat{P}, im::ArbFloat{P}) where {P}
    z = AcbFloat{P}()
    GC.@preserve z begin
        LibFlint.arf_set(LibFlint.acf_real_ptr(z), re)
        LibFlint.arf_set(LibFlint.acf_imag_ptr(z), im)
    end
    return z
end

function neg!(z::AcbFloat{P}, x::AcbFloat{P}) where {P}
    LibFlint.acf_neg(z, x)
    return z
end
Base.:-(x::AcbFloat{P}) where {P} = neg!(AcbFloat{P}(), x)

"Complex conjugate; exact (the imaginary part's sign flips)."
Base.conj(x::AcbFloat{P}) where {P} = AcbFloat{P}(real(x), -imag(x))

"Squared modulus `re² + im²`: three roundings, not correctly rounded."
Base.abs2(x::AcbFloat) = (r = real(x); i = imag(x); r * r + i * i)

function sqrt_inexact!(z::AcbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P}
    flag = LibFlint.acf_sqrt(z, x, P, _rnd(r))
    return z, flag != 0
end
sqrt!(z::AcbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P} = first(sqrt_inexact!(z, x, r))
Base.sqrt(x::AcbFloat{P}) where {P} = sqrt!(AcbFloat{P}(), x)
