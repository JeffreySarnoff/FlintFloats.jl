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
AcbFloat{P}(re::Real, im::Real = 0.0) where {P} = AcbFloat{P}(Float64(re), Float64(im))

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
