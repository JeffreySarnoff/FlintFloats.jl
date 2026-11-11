# Destination-only flat and bounded nested broadcast optimization. Allocating broadcast style/result selection is
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

# Bound arithmetic work and identity-only depth before allocating scratch or evaluating leaves.
const _PACKED_TREE_ARITHMETIC_LIMIT = 8
const _PACKED_TREE_DEPTH_LIMIT = 16
@inline function _packed_tree_cost(::Type{T}, x, depth=0) where {T}
    return _packed_broadcast_leaf(T,x) ? 0 : _PACKED_TREE_ARITHMETIC_LIMIT+1
end
@inline function _packed_tree_cost(::Type{T}, bc::_PackedBroadcast.Broadcasted, depth=0) where {T}
    depth >= _PACKED_TREE_DEPTH_LIMIT && return _PACKED_TREE_ARITHMETIC_LIMIT+1
    f,args=bc.f,bc.args
    if length(args)==1 && (f===identity || f===(-))
        return (f===identity ? 0 : 1)+_packed_tree_cost(T,args[1],depth+1)
    elseif length(args)==2 && (f===(+) || f===(-) || f===(*) || f===(/))
        left=_packed_tree_cost(T,args[1],depth+1)
        left > _PACKED_TREE_ARITHMETIC_LIMIT && return left
        return 1+left+_packed_tree_cost(T,args[2],depth+1)
    end
    return _PACKED_TREE_ARITHMETIC_LIMIT+1
end
@inline function _packed_broadcast_open(bc::_PackedBroadcast.Broadcasted)
    _packed_broadcast_open(bc.args[1])
    length(bc.args)==2 && _packed_broadcast_open(bc.args[2])
    nothing
end

struct _PackedTreeLeaf{A}
    value::A
end
struct _PackedTreeNode{F,A,T}
    f::F
    args::A
    scratch::T
end
@inline _packed_tree_prepare(z,x)=_PackedTreeLeaf(_packed_broadcast_prepare(z,x))
@inline function _packed_tree_prepare(z,bc::_PackedBroadcast.Broadcasted)
    # One scratch per occurrence (including identities), never shared between live sibling results.
    args=map(x -> _packed_tree_prepare(z,x),bc.args)
    return _PackedTreeNode(bc.f,args,eltype(z)())
end
@inline _packed_tree_apply!(::typeof(+),z,x,y)=add!(z,x,y)
@inline _packed_tree_apply!(::typeof(-),z,x,y)=sub!(z,x,y)
@inline _packed_tree_apply!(::typeof(*),z,x,y)=mul!(z,x,y)
@inline _packed_tree_apply!(::typeof(/),z,x,y)=div!(z,x,y)
for (family,prefix) in ((:ArbBall,:arb),(:AcbBall,:acb))
    setround,neg=Symbol(prefix,:_set_round),Symbol(prefix,:_neg)
    @eval begin
        @inline function _packed_tree_apply!(::typeof(identity),z::$family{P},x) where {P}
            LibFlint.$setround(z,x,P)
            z
        end
        @inline function _packed_tree_apply!(::typeof(-),z::$family,x)
            LibFlint.$neg(z,x)
            z
        end
    end
end
@inline _packed_tree_eval(x::_PackedTreeLeaf,i)=_packed_broadcast_value(x.value,i)
@inline function _packed_tree_eval(node::_PackedTreeNode{F,<:Tuple{Any}},i) where {F}
    x=_packed_tree_eval(node.args[1],i)
    return _packed_tree_apply!(node.f,node.scratch,x)
end
@inline function _packed_tree_eval(node::_PackedTreeNode{F,<:Tuple{Any,Any}},i) where {F}
    x=_packed_tree_eval(node.args[1],i)
    y=_packed_tree_eval(node.args[2],i)
    return _packed_tree_apply!(node.f,node.scratch,x,y)
end
@inline function _packed_broadcast_tree!(z,bc)
    tree=_packed_tree_prepare(z,bc) # All snapshots and initialized scratch precede mutation.
    for i in axes(z,1)
        value=_packed_tree_eval(tree,i)
        set!(borrow(z,i),value) # Read every original leaf before overwriting the destination slot.
    end
    z
end

# Invoke the unspecialized Base destination implementation exactly once, bypassing this method.
# This keeps arbitrary callbacks, result types/styles, repeated destination indices, and unsupported
# expressions on their existing path without executing anything speculatively or retrying errors.
@inline function _packed_broadcast_generic!(z, bc::_PackedBroadcast.Broadcasted{Nothing})
    return invoke(Base.copyto!, Tuple{AbstractArray,_PackedBroadcast.Broadcasted{Nothing}}, z, bc)
end

@inline function Base.copyto!(z::PackedBallSpan, bc::_PackedBroadcast.Broadcasted{Nothing})
    _packed_broadcast_destination(z) || return _packed_broadcast_generic!(z,bc)
    flat=_packed_flat_broadcast(eltype(z),bc)
    if !flat && _packed_tree_cost(eltype(z),bc)>_PACKED_TREE_ARITHMETIC_LIMIT
        return _packed_broadcast_generic!(z,bc)
    end
    axes(z) == axes(bc) || throw(DimensionMismatch("packed broadcast axes must match destination"))
    _PackedBroadcast.check_broadcast_axes(axes(z), bc.args...)
    _check_packed_open(_packed_parent(z))
    # Explicit calls avoid heterogeneously typed tuple iteration/boxing for mixed vectors/scalars.
    _packed_broadcast_open(bc)
    isempty(z) && return z # In particular, do not read an unassigned scalar Ref on an empty call.
    flat && return _packed_broadcast_flat!(z,bc.f,bc.args)
    return _packed_broadcast_tree!(z,bc)
end
