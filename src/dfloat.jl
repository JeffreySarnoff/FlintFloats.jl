# DFloat{N}: FLINT dN, an unevaluated sum of N doubles. Immutable, inline, approximate arithmetic.

"""
    DFloat{N}

Expansion of `N` doubles (`N` in 1:4, nominal precision `53N` bits). Plain approximate arithmetic in
the style of `Float64`: results are rounded, overflow gives `Inf`, `Inf`/`NaN` propagate.
"""
struct DFloat{N} <: FlintReal
    d::NTuple{N,Float64}
    function DFloat{N}(d::NTuple{N,Float64}) where {N}
        (N isa Int && 1 <= N <= 4) || throw(ArgumentError("DFloat{N} requires N in 1:4, got $(repr(N))"))
        _require_dfloat()
        return new{N}(d)
    end
end

for N in 1:4
    set_d = Symbol("d", N, "_set_d")
    get_d = Symbol("d", N, "_get_d")
    @eval function DFloat{$N}(x::Float64)
        _require_dfloat()
        r = Ref{DFloat{$N}}()
        LibFlint.$set_d(r, x)
        return r[]
    end
    @eval Base.Float64(x::DFloat{$N}) = LibFlint.$get_d(Ref(x))
    for (op, f) in ((:+, :add), (:-, :sub), (:*, :mul), (:/, :div))
        cf = Symbol("d", N, "_", f)
        @eval function Base.$op(x::DFloat{$N}, y::DFloat{$N})
            r = Ref{DFloat{$N}}()
            LibFlint.$cf(r, Ref(x), Ref(y))
            return r[]
        end
    end
end

DFloat{N}(x::Union{Float16,Float32,Bool,Int8,Int16,Int32,UInt8,UInt16,UInt32}) where {N} = DFloat{N}(Float64(x))
"Nominal expansion precision, `53N` bits; accuracy depends on the operation."
Base.precision(::Type{DFloat{N}}) where {N} = 53 * N
Base.precision(x::DFloat) = precision(typeof(x))

# ---- classification, unary operations, conversion, parsing --------------------------------------

_require_dfloat() = dfloat_supported() ||
    error("FLINT dfloat is not supported on this machine (dfloat_is_supported() is false)")

for N in 1:4
    for (name, cf) in ((:iszero, :is_zero), (:isfinite, :is_finite), (:isnan, :is_nan))
        c = Symbol("d", N, "_", cf)
        @eval Base.$name(x::DFloat{$N}) = LibFlint.$c(Ref(x)) != 0
    end
    sgn = Symbol("d", N, "_sgn")
    @eval Base.signbit(x::DFloat{$N}) = LibFlint.$sgn(Ref(x)) < 0
    for (op, cf) in ((:-, :neg), (:abs, :abs))
        c = Symbol("d", N, "_", cf)
        @eval function Base.$op(x::DFloat{$N})
            r = Ref{DFloat{$N}}()
            LibFlint.$c(r, Ref(x))
            return r[]
        end
    end
    sq = Symbol("d", N, "_sqrt")
    @eval function Base.sqrt(x::DFloat{$N})
        signbit(x) && !iszero(x) && throw(DomainError(x, "sqrt of a negative DFloat"))
        r = Ref{DFloat{$N}}()
        LibFlint.$sq(r, Ref(x))
        return r[]
    end
    ss = Symbol("d", N, "_set_str")
    @eval function Base.parse(::Type{DFloat{$N}}, s::AbstractString)
        _require_dfloat()
        r = Ref{DFloat{$N}}()
        LibFlint.$ss(r, String(s)) == 0 || throw(ArgumentError("invalid DFloat literal: $(repr(s))"))
        return r[]
    end
end

Base.isinf(x::DFloat) = !isfinite(x) && !isnan(x)
Base.zero(::Type{DFloat{N}}) where {N} = DFloat{N}(0.0)
Base.one(::Type{DFloat{N}}) where {N} = DFloat{N}(1.0)
Base.zero(x::DFloat) = zero(typeof(x))
Base.one(x::DFloat) = one(typeof(x))

DFloat{N}(x::AbstractString) where {N} = parse(DFloat{N}, x)

# Exact decimal-free form: reconstructs the same expansion.
Base.show(io::IO, x::DFloat{N}) where {N} = print(io, "DFloat{", N, "}(", x.d, ")")
