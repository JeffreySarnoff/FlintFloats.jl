# AcbBall{P}: FLINT acb at P bits. Mutable owner of a 12-word acb_struct (two arb).

"""
    AcbBall{P}

Complex rectangular ball (FLINT `acb`) with working precision `P` bits; real and imaginary parts are
`ArbBall{P}` enclosures. Mutable owner.
"""
mutable struct AcbBall{P} <: Number
    w::NTuple{12,UInt}                    # acb_struct (sizeof 96, test/abi/layout.txt)
    function AcbBall{P}() where {P}
        checkprec(P)
        z = new{P}((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        LibFlint.acb_init(z)
        finalizer(_clear!, z)
        return z
    end
end

_clear!(z::AcbBall) = (LibFlint.acb_clear(z); nothing)

AcbBall(re, im = 0.0) = AcbBall{DEFAULT_PRECISION}(re, im)
Base.precision(::Type{AcbBall{P}}) where {P} = P
Base.precision(::AcbBall{P}) where {P} = P

function AcbBall{P}(re::Float64, im::Float64) where {P}
    z = AcbBall{P}()
    LibFlint.acb_set_d_d(z, re, im)
    LibFlint.acb_set_round(z, z, P)       # precision invariant
    return z
end
AcbBall{P}(re::Real, im::Real = 0.0) where {P} = AcbBall{P}(Float64(re), Float64(im))

function Base.copy(z::AcbBall{P}) where {P}
    w = AcbBall{P}()
    LibFlint.acb_set(w, z)
    return w
end

function Base.real(z::AcbBall{P}) where {P}
    x = ArbBall{P}()
    LibFlint.acb_get_real(x, z)
    return x
end

function Base.imag(z::AcbBall{P}) where {P}
    x = ArbBall{P}()
    LibFlint.acb_get_imag(x, z)
    return x
end

for (name, f) in ((:add, :acb_add), (:sub, :acb_sub), (:mul, :acb_mul), (:div, :acb_div))
    bang = Symbol(name, :!)
    @eval function $bang(z::AcbBall{P}, x::AcbBall{P}, y::AcbBall{P}) where {P}
        LibFlint.$f(z, x, y, P)
        return z
    end
end

Base.:+(x::AcbBall{P}, y::AcbBall{P}) where {P} = add!(AcbBall{P}(), x, y)
Base.:-(x::AcbBall{P}, y::AcbBall{P}) where {P} = sub!(AcbBall{P}(), x, y)
Base.:*(x::AcbBall{P}, y::AcbBall{P}) where {P} = mul!(AcbBall{P}(), x, y)
Base.:/(x::AcbBall{P}, y::AcbBall{P}) where {P} = div!(AcbBall{P}(), x, y)
