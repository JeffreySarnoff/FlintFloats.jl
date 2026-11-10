# DFloatBall{N}: FLINT dNb, a dN midpoint plus a Float64 radius. Immutable, inline enclosure.

"""
    DFloatBall{N}

Real ball `mid ± rad`: `N`-double midpoint and a `Float64` radius. Every operation encloses the exact
result. The indeterminate value is the whole real line `[0 ± ∞]`; a valid ball is never NaN.
"""
struct DFloatBall{N} <: FlintReal
    d::NTuple{N,Float64}
    rad::Float64
    function DFloatBall{N}(d::NTuple{N,Float64}, rad::Float64) where {N}
        (N isa Int && 1 <= N <= 4) || throw(ArgumentError("DFloatBall{N} requires N in 1:4, got $(repr(N))"))
        return new{N}(d, rad)
    end
end

"`true` if `x` is the whole real line (the indeterminate ball)."
isindeterminate(x::DFloatBall) = x.rad == Inf

for N in 1:4
    set_d = Symbol("d", N, "b_set_d")
    get_d = Symbol("d", N, "b_get_d")
    indet = Symbol("d", N, "b_indeterminate")
    @eval function DFloatBall{$N}(x::Float64)
        r = Ref{DFloatBall{$N}}()
        LibFlint.$set_d(r, x)
        return r[]
    end
    @eval Base.Float64(x::DFloatBall{$N}) = LibFlint.$get_d(Ref(x))
    @eval function _indeterminate(::Type{DFloatBall{$N}})
        r = Ref{DFloatBall{$N}}()
        LibFlint.$indet(r)
        return r[]
    end
    for (op, f) in ((:+, :add), (:-, :sub), (:*, :mul))
        cf = Symbol("d", N, "b_", f)
        @eval function Base.$op(x::DFloatBall{$N}, y::DFloatBall{$N})
            r = Ref{DFloatBall{$N}}()
            LibFlint.$cf(r, Ref(x), Ref(y))
            return r[]
        end
    end
    # Division returns a status. GR_DOMAIN: divisor is exactly zero. GR_UNABLE: divisor contains zero;
    # FLINT leaves the output unspecified, so write the whole real line explicitly.
    cf = Symbol("d", N, "b_div")
    @eval function Base.:/(x::DFloatBall{$N}, y::DFloatBall{$N})
        r = Ref{DFloatBall{$N}}()
        st = LibFlint.$cf(r, Ref(x), Ref(y))
        st == GR_SUCCESS && return r[]
        st & GR_DOMAIN != 0 && throw(DomainError(y, "division by an exactly zero ball"))
        st & GR_UNABLE != 0 && return _indeterminate(DFloatBall{$N})
        _status_error(st, :div, DFloatBall{$N})
    end
end

DFloatBall{N}(x::Real) where {N} = DFloatBall{N}(Float64(x))

Base.precision(::Type{DFloatBall{N}}) where {N} = 53 * N
Base.precision(x::DFloatBall) = precision(typeof(x))
