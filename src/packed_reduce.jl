# Packed reductions reuse owned scalar destinations and explicit borrowed reads. Keyword/mapped
# interfaces keep Base's existing behavior unless implemented separately with their own contract.
"""
    sum(v::PackedBallVector)
    sum(view(v, indices))

Return a fresh owned ball at the element working precision enclosing the exact sum. Plain `sum(v)`
accumulates in logical iteration order using one owned accumulator and borrowed inputs; empty sums
are typed zero and singleton results are independent. Its radius/representation need not match Base's
possibly reassociated reduction. No per-term Julia scalar owners are allocated in a warmed typed loop.

Calls with keywords (including `init`/`dims`) and mapped sums retain Base's generic interface and
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
