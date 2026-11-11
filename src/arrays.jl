# M4a/M4b: ordinary inline arrays; packed owned ball vectors follow in M4c.
const DFloatInline = Union{DFloat,DFloatBall}
const FlintInline = Union{DFloatInline,NFloat}

_bulk_context(::Type{T}) where {T<:DFloatInline} = (_require_dfloat(); nothing)
_bulk_context(::Type{T}) where {T<:NFloat} = _ctx(T)

# Validation precedes mutation and pointer creation, including for empty arrays.
function _check_bulk(z::AbstractVector{T}, x::AbstractVector, y::AbstractVector) where {T<:FlintInline}
    isconcretetype(T) && eltype(x) === T && eltype(y) === T ||
        throw(ArgumentError("bulk arithmetic requires the same concrete element type"))
    (z isa StridedVector && (isempty(z) || stride(z, 1) != 0)) ||
        throw(ArgumentError("bulk destination must be a strided vector with independent element slots"))
    axes(z) == axes(x) == axes(y) || throw(DimensionMismatch("bulk vector axes must match"))
    for input in (x, y)
        input === z || !Base.mightalias(z, input) ||
            throw(ArgumentError("bulk destination may alias an input only when they are the same array object"))
    end
    return _bulk_context(T)
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
concrete `DFloat{N}`, `DFloatBall{N}`, or `NFloat{L}` element type. The destination must be an
ordinary vector or
strided view with independent element slots (gather/repeated-index destinations are rejected).
Exact aliasing (`dest === x` or `dest === y`) is supported; any other possible destination/input
overlap is rejected before mutation. Inputs may alias each other. Empty vectors are accepted without calling a native kernel.

Contiguous, aligned ball spans of at least four elements and contiguous, aligned nfloat inputs
use the respective pinned FLINT vector-add kernels; other inputs use checked scalar arithmetic. Balls enclose each element's sum; point results have
the scalar approximate guarantee. Validation errors leave `dest` unchanged. An exception from a
custom array's indexing can leave a dfloat destination partially updated. Nfloat operations use
private scratch: numerical/input errors leave their destination unchanged, including exact aliases.
Nfloat underflow flushes to zero; overflow throws as in scalar arithmetic. This method is not exported.
"""
function add!(z::AbstractVector{T}, x::AbstractVector, y::AbstractVector) where {T<:FlintInline}
    ctx = _check_bulk(z, x, y)
    isempty(z) && return z
    return _bulk_add!(z, x, y, ctx)
end

"""
    FlintFloats.mul!(dest::AbstractVector, x::AbstractVector, y::AbstractVector)

Store elementwise `x * y` in `dest` with the same type, axes, aliasing, and failure policy as vector
[`add!`](@ref). Dfloat families use checked scalar multiplication; contiguous aligned nfloat
spans use the native vector kernel with scratch and commit on success. This is elementwise arithmetic;
it is not a matrix product. This method is not exported.
"""
function mul!(z::AbstractVector{T}, x::AbstractVector, y::AbstractVector) where {T<:FlintInline}
    ctx = _check_bulk(z, x, y)
    isempty(z) && return z
    return _bulk_mul!(z, x, y, ctx)
end

# The context is selected once by _check_bulk, before any loop or native call.
_bulk_add!(z, x, y, ::Nothing) = _bulk_add!(z, x, y)
_bulk_mul!(z, x, y, ::Nothing) = _scalar_bulk!(*, z, x, y)

for (op, scalar, native) in ((:add, :nfloat_add, :_nfloat_vec_add),
                            (:mul, :nfloat_mul, :_nfloat_vec_mul))
    helper = Symbol("_bulk_", op, "!")
    @eval function $helper(z::AbstractVector{NFloat{L}}, x, y, ctx::Ptr) where {L}
        T = NFloat{L}
        # Zero lanes may leave unused mantissa limbs untouched: initialize all bytes before C.
        tmp = fill(T(NFLOAT_EXP_ZERO, UInt(0), ntuple(_ -> UInt(0), Val(L))), length(z))
        if x isa StridedVector{T} && y isa StridedVector{T} &&
                stride(x, 1) == 1 && stride(y, 1) == 1
            GC.@preserve tmp x y begin
                pt, px, py = pointer(tmp), pointer(x), pointer(y)
                if (UInt(pt) | UInt(px) | UInt(py)) % UInt(8) == 0
                    st = LibFlint.$native(pt, px, py, length(tmp), ctx)
                    st == GR_SUCCESS || _status_error(st, $(QuoteNode(op)), T)
                    copyto!(z, tmp)
                    return z
                end
            end
        end
        # Strided/gather inputs use checked scalar calls with the already acquired context.
        r = Ref{T}(tmp[1])
        for (k, i) in enumerate(eachindex(x, y))
            st = LibFlint.$scalar(r, Ref(x[i]), Ref(y[i]), ctx)
            st == GR_SUCCESS || _status_error(st, $(QuoteNode(op)), T)
            tmp[k] = r[]
        end
        copyto!(z, tmp)
        return z
    end
end
