# ArbBall{P}: FLINT arb at P bits. Mutable owner of a 6-word arb_struct (arf midpoint, mag radius).

"""
    ArbBall{P}

Real ball `mid ± rad` (FLINT `arb`) with working precision `P` bits. The midpoint never exceeds `P`
bits, so [`midpoint`](@ref) is exactly an `ArbFloat{P}`. Mutable owner.
"""
mutable struct ArbBall{P} <: FlintReal
    w::NTuple{6,UInt}                     # arb_struct: mid @0 (arf, 32 B), rad @32 (mag, 16 B)
    function ArbBall{P}() where {P}
        checkprec(P)
        x = new{P}((0, 0, 0, 0, 0, 0))
        LibFlint.arb_init(x)
        finalizer(_clear!, x)
        return x
    end
end

_clear!(x::ArbBall) = (LibFlint.arb_clear(x); nothing)

ArbBall(x) = ArbBall{DEFAULT_PRECISION}(x)
Base.precision(::Type{ArbBall{P}}) where {P} = P
Base.precision(::ArbBall{P}) where {P} = P

function ArbBall{P}(x::Float64) where {P}
    z = ArbBall{P}()
    LibFlint.arb_set_d(z, x)
    LibFlint.arb_set_round(z, z, P)       # precision invariant (a rounded midpoint gains a radius)
    return z
end

function ArbBall{P}(x::Int) where {P}
    z = ArbBall{P}()
    LibFlint.arb_set_si(z, x)
    LibFlint.arb_set_round(z, z, P)
    return z
end

ArbBall{P}(x::Real) where {P} = ArbBall{P}(Float64(x))

function Base.copy(x::ArbBall{P}) where {P}
    z = ArbBall{P}()
    LibFlint.arb_set(z, x)
    return z
end

"Midpoint as an `ArbFloat{P}` (exact)."
function midpoint(x::ArbBall{P}) where {P}
    m = ArbFloat{P}()
    GC.@preserve x LibFlint.arf_set(m, _ptr(x))   # mid is at offset 0
    return m
end

"Radius as an `ArbFloat{P}`, rounded up so it stays an upper bound."
function radius(x::ArbBall{P}) where {P}
    t = ArbBall{P}()
    LibFlint.arb_get_rad_arb(t, x)        # exact ball whose midpoint is the radius
    r = ArbFloat{P}()
    GC.@preserve t LibFlint.arf_set_round(r, _ptr(t), P, ARF_RND_UP)
    return r
end

Base.Float64(x::ArbBall) = Float64(midpoint(x))

for (name, f) in ((:add, :arb_add), (:sub, :arb_sub), (:mul, :arb_mul), (:div, :arb_div))
    bang = Symbol(name, :!)
    @eval function $bang(z::ArbBall{P}, x::ArbBall{P}, y::ArbBall{P}) where {P}
        LibFlint.$f(z, x, y, P)
        return z
    end
end

Base.:+(x::ArbBall{P}, y::ArbBall{P}) where {P} = add!(ArbBall{P}(), x, y)
Base.:-(x::ArbBall{P}, y::ArbBall{P}) where {P} = sub!(ArbBall{P}(), x, y)
Base.:*(x::ArbBall{P}, y::ArbBall{P}) where {P} = mul!(ArbBall{P}(), x, y)
Base.:/(x::ArbBall{P}, y::ArbBall{P}) where {P} = div!(ArbBall{P}(), x, y)

"`true` if the ball `x` contains the ball `y`."
Base.contains(x::ArbBall{P}, y::ArbBall{P}) where {P} = LibFlint.arb_contains(x, y) != 0
"`true` if the balls `x` and `y` share at least one point."
overlaps(x::ArbBall{P}, y::ArbBall{P}) where {P} = LibFlint.arb_overlaps(x, y) != 0
