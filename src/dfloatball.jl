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
        _require_dfloat()
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
        _require_dfloat()
        r = Ref{DFloatBall{$N}}()
        LibFlint.$set_d(r, x)
        return r[]
    end
    @eval function Base.Float64(x::DFloatBall{$N})
        isexact(x) || throw(ArgumentError("an inexact DFloatBall is an enclosure; use Float64(DFloat{$($N)}(x.d)) to take its midpoint explicitly"))
        return LibFlint.$get_d(Ref(x))
    end
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


Base.precision(::Type{DFloatBall{N}}) where {N} = 53 * N
Base.precision(x::DFloatBall) = precision(typeof(x))

# ---- classification, unary operations, parsing ---------------------------------------------------

"`true` if the ball has radius zero."
function isexact end
"`true` if the ball contains zero."
function containszero end

for N in 1:4
    for (name, cf) in ((:(Base.iszero), :is_zero), (:(Base.isfinite), :is_finite), (:isexact, :is_exact))
        c = Symbol("d", N, "b_", cf)
        @eval $name(x::DFloatBall{$N}) = LibFlint.$c(Ref(x)) != 0
    end
    cz = Symbol("d", N, "b_contains_zero")
    @eval containszero(x::DFloatBall{$N}) = LibFlint.$cz(Ref(x)) != 0
    for (op, cf) in ((:-, :neg), (:abs, :abs))
        c = Symbol("d", N, "b_", cf)
        @eval function Base.$op(x::DFloatBall{$N})
            r = Ref{DFloatBall{$N}}()
            LibFlint.$c(r, Ref(x))
            return r[]
        end
    end
    # sqrt: GR_DOMAIN entirely negative; GR_UNABLE contains negatives (output unspecified).
    sq = Symbol("d", N, "b_sqrt")
    @eval function Base.sqrt(x::DFloatBall{$N})
        r = Ref{DFloatBall{$N}}()
        st = LibFlint.$sq(r, Ref(x))
        st == GR_SUCCESS && return r[]
        st & GR_DOMAIN != 0 && throw(DomainError(x, "sqrt of an entirely negative DFloatBall"))
        st & GR_UNABLE != 0 && return _indeterminate(DFloatBall{$N})
        _status_error(st, :sqrt, DFloatBall{$N})
    end
    ss = Symbol("d", N, "b_set_str")
    @eval function Base.parse(::Type{DFloatBall{$N}}, s::AbstractString)
        _require_dfloat()
        r = Ref{DFloatBall{$N}}()
        LibFlint.$ss(r, String(s)) == 0 || throw(ArgumentError("invalid DFloatBall literal: $(repr(s))"))
        return r[]
    end
end

# A ball is never NaN and never a single infinity; the whole real line is `isindeterminate`.
Base.isnan(::DFloatBall) = false
Base.isinf(::DFloatBall) = false
Base.zero(::Type{DFloatBall{N}}) where {N} = DFloatBall{N}(0.0)
Base.one(::Type{DFloatBall{N}}) where {N} = DFloatBall{N}(1.0)
Base.zero(x::DFloatBall) = zero(typeof(x))
Base.one(x::DFloatBall) = one(typeof(x))
DFloatBall{N}(x::Union{Float16,Float32,Bool,Int8,Int16,Int32,UInt8,UInt16,UInt32}) where {N} = DFloatBall{N}(Float64(x))
DFloatBall{N}(x::AbstractString) where {N} = parse(DFloatBall{N}, x)

Base.show(io::IO, x::DFloatBall{N}) where {N} = print(io, "DFloatBall{", N, "}(", x.d, ", ", x.rad, ")")
