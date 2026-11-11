# M4a: ordinary inline arrays; packed owned ball vectors follow in M4c.
const DFloatInline = Union{DFloat,DFloatBall}

# Validation precedes mutation and pointer creation, including for empty arrays.
function _check_bulk(z::AbstractVector{T}, x::AbstractVector, y::AbstractVector) where {T<:DFloatInline}
    isconcretetype(T) && eltype(x) === T && eltype(y) === T ||
        throw(ArgumentError("bulk arithmetic requires the same concrete element type"))
    (z isa StridedVector && (isempty(z) || stride(z, 1) != 0)) ||
        throw(ArgumentError("bulk destination must be a strided vector with independent element slots"))
    axes(z) == axes(x) == axes(y) || throw(DimensionMismatch("bulk vector axes must match"))
    for input in (x, y)
        input === z || !Base.mightalias(z, input) ||
            throw(ArgumentError("bulk destination may alias an input only when they are the same array object"))
    end
    _require_dfloat()
    return nothing
end

function _scalar_bulk!(op, z, x, y)
    for i in eachindex(z, x, y)
        z[i] = op(x[i], y[i])
    end
    return z
end

# Only native-compatible, contiguous spans enter C. Derived pointers remain scoped to preservation
# of all arrays (SubArray retains its parent). The verified C alignment is 8 bytes for every dNb.
_bulk_add!(z, x, y) = _scalar_bulk!(+, z, x, y)
for N in 1:4
    cf = Symbol("_d", N, "b_vec_add")
    @eval function _bulk_add!(z::StridedVector{DFloatBall{$N}},
                             x::StridedVector{DFloatBall{$N}}, y::StridedVector{DFloatBall{$N}})
        if length(z) < 4 || stride(z, 1) != 1 || stride(x, 1) != 1 || stride(y, 1) != 1
            return _scalar_bulk!(+, z, x, y)
        end
        GC.@preserve z x y begin
            pz, px, py = pointer(z), pointer(x), pointer(y)
            if (UInt(pz) | UInt(px) | UInt(py)) % UInt(8) != 0
                return _scalar_bulk!(+, z, x, y)
            end
            LibFlint.$cf(pz, px, py, length(z))
        end
        return z
    end
end

"""
    FlintFloats.add!(dest::AbstractVector, x::AbstractVector, y::AbstractVector)

Store elementwise `x + y` in `dest` and return it. All vectors must have matching axes and the same
concrete `DFloat{N}` or `DFloatBall{N}` element type. The destination must be an ordinary vector or
strided view with independent element slots (gather/repeated-index destinations are rejected).
Exact aliasing (`dest === x` or `dest === y`) is supported; any other possible destination/input overlap is rejected before mutation. Inputs may
alias each other. Empty vectors are accepted without calling a native kernel.

Contiguous, aligned ball spans of at least four elements use the pinned FLINT vector-add kernel;
other inputs use checked scalar arithmetic. Balls enclose each element's sum; point results have
the scalar approximate guarantee. Validation errors leave `dest` unchanged. An exception from a
custom array's indexing or assignment can leave it partially updated. This method is not exported.
"""
function add!(z::AbstractVector{T}, x::AbstractVector, y::AbstractVector) where {T<:DFloatInline}
    _check_bulk(z, x, y)
    isempty(z) && return z
    return _bulk_add!(z, x, y)
end

"""
    FlintFloats.mul!(dest::AbstractVector, x::AbstractVector, y::AbstractVector)

Store elementwise `x * y` in `dest` with the same type, axes, aliasing, and failure policy as vector
[`add!`](@ref). Uses checked scalar multiplication for all spans. This is elementwise arithmetic;
it is not a matrix product. This method is not exported.
"""
function mul!(z::AbstractVector{T}, x::AbstractVector, y::AbstractVector) where {T<:DFloatInline}
    _check_bulk(z, x, y)
    isempty(z) && return z
    return _scalar_bulk!(*, z, x, y)
end
