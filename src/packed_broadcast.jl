# Destination-only flat broadcast optimization. Allocating broadcast style/result selection is
# unchanged. Version-sensitive Base broadcast interaction is deliberately confined to this file.
const _PackedBroadcast = Base.Broadcast

@inline _packed_broadcast_leaf(::Type{T}, x) where {T} = x isa T || x isa Base.RefValue{T}
@inline _packed_broadcast_leaf(::Type{T}, x::PackedBallSpan) where {T} = eltype(x) === T

@inline function _packed_flat_broadcast(::Type{T}, bc) where {T}
    args = bc.args
    if bc.f === identity && length(args) == 1
        return _packed_broadcast_leaf(T, args[1])
    elseif (bc.f === (+) || bc.f === (*)) && length(args) == 2
        return _packed_broadcast_leaf(T, args[1]) && _packed_broadcast_leaf(T, args[2])
    end
    return false
end

@inline _packed_broadcast_destination(::PackedBallVector) = true
@inline function _packed_broadcast_destination(z::PackedBallView)
    inds = parentindices(z)[1]
    return (inds isa AbstractRange && step(inds) != 0) || inds isa Base.Slice
end

@inline _packed_broadcast_open(x) = nothing
@inline _packed_broadcast_open(x::PackedBallSpan) = _check_packed_open(_packed_parent(x))

# broadcast_unalias preserves each concrete source type, snapshots possibly overlapping views,
# and permits dest === src. For a singleton source expanded over a larger destination, the source
# cannot be === dest; it is therefore snapshotted too when the native parents might overlap.
@inline _packed_broadcast_prepare(z, x::PackedBallSpan) = _PackedBroadcast.broadcast_unalias(z, x)
@inline _packed_broadcast_prepare(z, x::Base.RefValue) = x[]
@inline _packed_broadcast_prepare(z, x::PackedBallScalar) = x

@inline _packed_broadcast_value(x::PackedBallScalar, i) = x
@inline function _packed_broadcast_value(x::PackedBallSpan, i)
    return borrow(x, length(x) == 1 ? firstindex(x) : i)
end

@inline function _packed_broadcast_copy!(z, x)
    for i in axes(z, 1)
        set!(borrow(z, i), _packed_broadcast_value(x, i))
    end
    return z
end
@inline function _packed_broadcast_copy!(z::PackedBallVector{T}, x::PackedBallVector{T}) where {T}
    axes(z) == axes(x) && return copyto!(z, x)
    # Singleton expansion, not prefix copying.
    for i in axes(z, 1)
        set!(borrow(z, i), borrow(x, 1))
    end
    return z
end

@inline function _packed_broadcast_binary!(z, f!, x, y)
    for i in axes(z, 1)
        f!(borrow(z, i), _packed_broadcast_value(x, i), _packed_broadcast_value(y, i))
    end
    return z
end
@inline function _packed_broadcast_add!(z, x, y)
    return _packed_broadcast_binary!(z, add!, x, y)
end
@inline function _packed_broadcast_add!(z::PackedBallVector{T}, x::PackedBallVector{T},
                                      y::PackedBallVector{T}) where {T}
    if axes(z) == axes(x) == axes(y)
        return _packed_add!(z, x, y)
    end
    return _packed_broadcast_binary!(z, add!, x, y)
end

@inline function _packed_broadcast_flat!(z, ::typeof(identity), args::Tuple{Any})
    x = _packed_broadcast_prepare(z, args[1])
    return _packed_broadcast_copy!(z, x)
end
@inline function _packed_broadcast_flat!(z, f::Union{typeof(+),typeof(*)}, args::Tuple{Any,Any})
    # Prepare both leaves before writing so snapshot/allocation failures preserve z.
    x = _packed_broadcast_prepare(z, args[1])
    y = _packed_broadcast_prepare(z, args[2])
    if f === (+)
        return _packed_broadcast_add!(z, x, y)
    end
    return _packed_broadcast_binary!(z, mul!, x, y)
end

# Invoke the unspecialized Base destination implementation exactly once, bypassing this method.
# This keeps arbitrary callbacks, result types/styles, repeated destination indices, and nested
# expressions on their existing path without executing anything speculatively or retrying errors.
@inline function _packed_broadcast_generic!(z, bc::_PackedBroadcast.Broadcasted{Nothing})
    return invoke(Base.copyto!, Tuple{AbstractArray,_PackedBroadcast.Broadcasted{Nothing}}, z, bc)
end

@inline function Base.copyto!(z::PackedBallSpan, bc::_PackedBroadcast.Broadcasted{Nothing})
    if !_packed_broadcast_destination(z) || !_packed_flat_broadcast(eltype(z), bc)
        return _packed_broadcast_generic!(z, bc)
    end
    axes(z) == axes(bc) || throw(DimensionMismatch("packed broadcast axes must match destination"))
    _PackedBroadcast.check_broadcast_axes(axes(z), bc.args...)
    _check_packed_open(_packed_parent(z))
    # Explicit calls avoid heterogeneously typed tuple iteration/boxing for mixed vectors/scalars.
    _packed_broadcast_open(bc.args[1])
    length(bc.args) == 2 && _packed_broadcast_open(bc.args[2])
    isempty(z) && return z # In particular, do not read an unassigned scalar Ref on an empty call.
    return _packed_broadcast_flat!(z, bc.f, bc.args)
end
