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


function Base.copy(x::ArbBall{P}) where {P}
    z = ArbBall{P}()
    LibFlint.arb_set(z, x)
    return z
end

"""
    ArbBall{P}(mid::ArbFloat, rad::ArbFloat)

The ball `mid ± rad`. The midpoint is rounded to `P` bits (the ball grows to cover that), and the
radius is rounded up to FLINT's 30-bit magnitude, so the result contains `mid ± rad`.
"""
function ArbBall{P}(mid::ArbFloat, rad::ArbFloat) where {P}
    (isnan(rad) || signbit(rad)) && throw(ArgumentError("radius must be a nonnegative number"))
    z = ArbBall{P}(mid)
    LibFlint.arb_add_error_arf(z, rad)
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

"Only an exact ball converts implicitly; otherwise take `midpoint(x)` explicitly."
function Base.Float64(x::ArbBall)
    isexact(x) || throw(ArgumentError("an inexact ArbBall is an enclosure; use midpoint(x) to convert it to a point explicitly"))
    return Float64(midpoint(x))
end

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

# ---- classification, unary operations ------------------------------------------------------------

Base.iszero(x::ArbBall) = LibFlint.arb_is_zero(x) != 0
Base.isfinite(x::ArbBall) = LibFlint.arb_is_finite(x) != 0
Base.isinteger(x::ArbBall) = LibFlint.arb_is_int(x) != 0
"`true` if the midpoint is NaN (the indeterminate ball)."
Base.isnan(x::ArbBall{P}) where {P} = isnan(midpoint(x))
"A ball is never infinite as a value; use `isfinite` to test the enclosure's bounds."
Base.isinf(::ArbBall) = false
"`true` if the radius is zero."
isexact(x::ArbBall) = LibFlint.arb_is_exact(x) != 0
"`true` for a ball that tells nothing: NaN midpoint or infinite radius (including `[0 ± ∞]`)."
isindeterminate(x::ArbBall) = isnan(x) || isinf(radius(x))

Base.zero(::Type{ArbBall{P}}) where {P} = ArbBall{P}()
Base.one(::Type{ArbBall{P}}) where {P} = ArbBall{P}(1)
Base.zero(::Type{ArbBall}) = zero(ArbBall{DEFAULT_PRECISION})
Base.one(::Type{ArbBall}) = one(ArbBall{DEFAULT_PRECISION})
Base.zero(::ArbBall{P}) where {P} = ArbBall{P}()
Base.one(::ArbBall{P}) where {P} = ArbBall{P}(1)

"Set `z` to a containing copy of `x` at the precision of `z`, returning `z`."
function set!(z::ArbBall{P}, x::ArbBall) where {P}
    LibFlint.arb_set_round(z, x, P)
    return z
end

for (name, f) in ((:neg, :arb_neg), (:abs, :arb_abs))
    bang = Symbol(name, :!)
    @eval function $bang(z::ArbBall{P}, x::ArbBall{P}) where {P}
        LibFlint.$f(z, x)
        return z
    end
end
function sqrt!(z::ArbBall{P}, x::ArbBall{P}) where {P}
    LibFlint.arb_sqrt(z, x, P)
    return z
end
Base.:-(x::ArbBall{P}) where {P} = neg!(ArbBall{P}(), x)
Base.abs(x::ArbBall{P}) where {P} = abs!(ArbBall{P}(), x)
"Square root of an enclosure; a ball reaching below zero gives FLINT's indeterminate result, not an error."
Base.sqrt(x::ArbBall{P}) where {P} = sqrt!(ArbBall{P}(), x)
