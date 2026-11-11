# Packed reductions reuse owned scalar destinations and explicit borrowed reads. Keyword/mapped
# interfaces keep Base's existing behavior unless implemented separately with their own contract.
"""
    sum(v::PackedBallVector)
    sum(view(v, indices))

Return a fresh owned ball at the element working precision enclosing the exact sum. Plain `sum(v)`
accumulates in logical iteration order using one owned accumulator and borrowed inputs; empty sums
are typed zero and singleton results are independent. Its radius/representation need not match Base's
possibly reassociated reduction. No per-term Julia scalar owners are allocated in a warmed typed loop.

Calls with keywords (including `init`/`dims`) and other mapped sums retain Base's generic interface and
copied scalar reads. Parents must remain open; concurrent writes/finalization during reading are
unsupported. This specialization changes no allocating array container or generic callback semantics.
"""
function Base.sum(v::PackedBallSpan; kwargs...)
    if !isempty(kwargs)
        return invoke(Base.sum,Tuple{AbstractArray},v;kwargs...)
    end
    _check_packed_open(_packed_parent(v))
    result=eltype(v)()
    for r in eachborrow(v)
        add!(result,result,r)
    end
    return result
end

# Only the exact Base.abs2 function is recognized. Arbitrary callbacks keep copied value semantics.
@inline function _packed_abs2!(mapped::ArbBall{P}, scratch, r::BorrowedBall{ArbBall{P}}) where {P}
    mul!(mapped,r,r)
end
@inline function _packed_abs2!(mapped::ArbBall{P}, scratch, r::BorrowedBall{AcbBall{P}}) where {P}
    LibFlint.acb_get_real(mapped,r)
    LibFlint.acb_get_imag(scratch,r)
    mul!(mapped,mapped,mapped)
    mul!(scratch,scratch,scratch)
    add!(mapped,mapped,scratch)
end

"""
    sum(abs2, v::PackedBallVector)
    sum(abs2, view(v, indices))

Enclose the exact sum of squared magnitudes using borrowed reads and constant owned scratch.
The fresh result is `ArbBall{P}` for both real and complex inputs at precision `P`, including empty
inputs. Mapping follows scalar `abs2` arithmetic and accumulation follows logical order; radii may
vary from Base's reduction order. Keywords retain Base's generic interface. Other callbacks always
receive independent copied values. Parents must remain open without concurrent mutation/finalization.
"""
function Base.sum(::typeof(abs2), v::PackedBallSpan; kwargs...)
    !isempty(kwargs) && return invoke(Base.sum,Tuple{Any,AbstractArray},abs2,v;kwargs...)
    _check_packed_open(_packed_parent(v))
    R=realtype(eltype(v))
    result,mapped=R(),R()
    scratch=eltype(v)<:AcbBall ? R() : nothing
    for r in eachborrow(v)
        _packed_abs2!(mapped,scratch,r)
        add!(result,result,mapped)
    end
    result
end

# Start/step descriptors are logical struct offsets, never cached raw pointers. Native dot permits
# signed strides; gather views use borrowed accumulation. Empty calls bypass descriptors entirely.
@inline _packed_dot_span(::PackedBallVector)=(1,1)
@inline function _packed_dot_span(v::PackedBallView)
    inds=parentindices(v)[1]
    if inds isa AbstractRange || inds isa Base.Slice
        firstslot=first(inds)
        stride=inds isa Base.Slice ? 1 : step(inds)
        firstslot isa Int && stride isa Int && return (firstslot,stride)
    end
    nothing
end
# Valid only under GC.@preserve of v; parent bounds/fixed-size layout were checked by view creation.
@inline _packed_dot_pointer(v,firstslot)=_packed_parent(v)._data+(firstslot-1)*sizeof(eltype(v))

function _packed_dot_borrowed(x,y,::Type{T}) where {T<:ArbBall}
    result,product=T(),T()
    for i in axes(x,1)
        mul!(product,borrow(x,i),borrow(y,i))
        add!(result,result,product)
    end
    result
end
function _packed_dot_borrowed(x,y,::Type{T}) where {T<:AcbBall}
    result,product,conjugated=T(),T(),T()
    for i in axes(x,1)
        LibFlint.acb_conj(conjugated,borrow(x,i))
        mul!(product,conjugated,borrow(y,i))
        add!(result,result,product)
    end
    result
end
function _packed_dot_native(x,y,::Type{ArbBall{P}},sx,sy) where {P}
    result=ArbBall{P}()
    isempty(x) && return result
    GC.@preserve x y begin
        px,py=_packed_dot_pointer(x,sx[1]),_packed_dot_pointer(y,sy[1])
        LibFlint.arb_dot(result,C_NULL,0,px,sx[2],py,sy[2],length(x),P)
    end
    result
end
function _packed_dot_parts(x,y,::Type{AcbBall{P}},sx,sy) where {P}
    # conj(x)*y: real=xr*yr+xi*yi; imaginary=xr*yi-xi*yr. Result/initial alias is explicitly
    # permitted by pinned arb_dot documentation. Inputs never alias these independent scalar owners.
    re,im=ArbBall{P}(),ArbBall{P}()
    isempty(x) && return AcbBall{P}(re,im)
    offset=sizeof(ArbBall{P})
    GC.@preserve x y begin
        px,py=_packed_dot_pointer(x,sx[1]),_packed_dot_pointer(y,sy[1])
        xs,ys=2sx[2],2sy[2]
        LibFlint.arb_dot(re,C_NULL,0,px,xs,py,ys,length(x),P)
        LibFlint.arb_dot(re,re,0,px+offset,xs,py+offset,ys,length(x),P)
        LibFlint.arb_dot(im,C_NULL,0,px,xs,py+offset,ys,length(x),P)
        LibFlint.arb_dot(im,im,1,px+offset,xs,py,ys,length(x),P)
    end
    AcbBall{P}(re,im)
end
# Benchmark alternative: one accurate acb_dot after materializing a conjugated native vector.
# The allocating candidate stays private and includes its O(n) copy/native-memory cost.
function _packed_dot_conjugated_copy(x,y,::Type{T},sy) where {T<:AcbBall}
    result=T()
    isempty(x) && return result
    conjugated=PackedBallVector(T,length(x))
    try
        for i in axes(x,1)
            LibFlint.acb_conj(borrow(conjugated,i),borrow(x,i))
        end
        GC.@preserve conjugated y begin
            py=_packed_dot_pointer(y,sy[1])
            LibFlint.acb_dot(result,C_NULL,0,conjugated._data,1,py,sy[2],length(x),precision(T))
        end
        return result
    finally
        finalize(conjugated) # Include cleanup in the candidate's complete-operation cost.
    end
end

@inline function _packed_dot_allfinite(x,y)
    for i in axes(x,1)
        LibFlint.acb_is_finite(borrow(x,i))!=0 || return false
        LibFlint.acb_is_finite(borrow(y,i))!=0 || return false
    end
    true
end

"""
    LinearAlgebra.dot(x::PackedBallVector, y::PackedBallVector)

Rigorous same-format dot product, also accepting packed views. Complex dot conjugates its first
operand. Returns a fresh owned scalar at element precision; empty results are typed zero. Native
real dot and strided real/imaginary complex dots have their own accumulation/error enclosures and
can differ in representation/radius from scalar loops. Gathered spans use borrowed accumulation.
Mixed formats delegate to LinearAlgebra's generic array interface. Inputs may alias each other;
result storage is independent. Parents must stay open, with no concurrent writes/finalization.
"""
function dot(x::PackedBallSpan,y::PackedBallSpan)
    _check_packed_open(_packed_parent(x)); _check_packed_open(_packed_parent(y))
    length(x)==length(y) || throw(DimensionMismatch("packed dot lengths must match"))
    T=eltype(x)
    T===eltype(y) || return invoke(dot,Tuple{AbstractArray,AbstractArray},x,y)
    isempty(x) && return T()
    sx,sy=_packed_dot_span(x),_packed_dot_span(y)
    if sx!==nothing && sy!==nothing
        if T<:ArbBall
            return _packed_dot_native(x,y,T,sx,sy)
        elseif length(x)>=4 && typemin(Int)÷2<=sx[2]<=typemax(Int)÷2 && typemin(Int)÷2<=sy[2]<=typemax(Int)÷2 && _packed_dot_allfinite(x,y)
            return _packed_dot_parts(x,y,T,sx,sy)
        end
    end
    _packed_dot_borrowed(x,y,T)
end
