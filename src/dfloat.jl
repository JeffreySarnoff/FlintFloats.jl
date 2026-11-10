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
        return new{N}(d)
    end
end

for N in 1:4
    set_d = Symbol("d", N, "_set_d")
    get_d = Symbol("d", N, "_get_d")
    @eval function DFloat{$N}(x::Float64)
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

DFloat{N}(x::Real) where {N} = DFloat{N}(Float64(x))
"Nominal expansion precision, `53N` bits; accuracy depends on the operation."
Base.precision(::Type{DFloat{N}}) where {N} = 53 * N
Base.precision(x::DFloat) = precision(typeof(x))
