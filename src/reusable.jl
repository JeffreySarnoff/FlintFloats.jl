"""
    NFloatWorkspace(NFloat{L}, capacity=0)

Reusable private scratch for vector `FlintFloats.add!(dest, x, y, workspace)` and `mul!`.
The format is fixed by `L`. Storage grows automatically to accommodate the destination, or can be
reserved with `sizehint!(workspace, capacity)`. Only new slots are initialized; warmed calls within
capacity reuse storage and commit results only after successful arithmetic.

Each workspace permits one operation at a time. Concurrent or reentrant use (including `sizehint!`)
throws `ArgumentError`; use a separate workspace per concurrent operation. Workspace storage must
not overlap any input or destination. Fields are private implementation details; scratch contents
after failure are unspecified and are never returned as numerical results.

# Example
```julia
T = NFloat{2}
x, y, dest = fill(T(1), 100), fill(T(2), 100), Vector{T}(undef, 100)
work = NFloatWorkspace(T, 100)
FlintFloats.add!(dest, x, y, work)
FlintFloats.mul!(dest, dest, y, work)
```
"""
mutable struct NFloatWorkspace{L}
    const _buffer::Vector{NFloat{L}}
    const _busy::Threads.Atomic{Bool}
    function NFloatWorkspace{L}(capacity::Integer=0) where {L}
        _ctx(NFloat{L}) # Validate the format; never retain a runtime context pointer in a workspace.
        n = Int(capacity)
        n >= 0 || throw(ArgumentError("workspace capacity must be nonnegative"))
        return new{L}(_nfloat_scratch(NFloat{L}, n), Threads.Atomic{Bool}(false))
    end
end
NFloatWorkspace(::Type{NFloat{L}}, capacity::Integer=0) where {L} = NFloatWorkspace{L}(capacity)

function _nfloat_scratch(::Type{NFloat{L}}, n::Int) where {L}
    canonical_zero = NFloat{L}(NFLOAT_EXP_ZERO, UInt(0), ntuple(_ -> UInt(0), Val(L)))
    return fill(canonical_zero, n)
end

function _acquire_workspace!(work::NFloatWorkspace)
    Threads.atomic_cas!(work._busy, false, true) == false ||
        throw(ArgumentError("NFloatWorkspace is already in use; use independent workspaces concurrently"))
    return nothing
end
_release_workspace!(work::NFloatWorkspace) = (work._busy[] = false; nothing)

# Caller holds the exclusive-use guard and has checked overlap before any possible reallocation.
function _grow_workspace!(work::NFloatWorkspace{L}, n::Int) where {L}
    buffer = work._buffer
    old = length(buffer)
    if n > old
        canonical_zero = NFloat{L}(NFLOAT_EXP_ZERO, UInt(0), ntuple(_ -> UInt(0), Val(L)))
        resize!(buffer, n)
        for i in old+1:n
            buffer[i] = canonical_zero
        end
    end
    return work
end

"""
    sizehint!(workspace::NFloatWorkspace, capacity)

Reserve at least `capacity` initialized scratch slots without shrinking existing storage.
Throws if the workspace is already in use. Preallocate before a hot loop to avoid growth there.
"""
function Base.sizehint!(work::NFloatWorkspace, capacity::Integer)
    n = Int(capacity)
    n >= 0 || throw(ArgumentError("workspace capacity must be nonnegative"))
    _acquire_workspace!(work)
    try
        return _grow_workspace!(work, n)
    finally
        _release_workspace!(work)
    end
end

# Scalar and native paths share initialized scratch and the same commit-on-success policy.
for (op, scalar, native) in ((:add, :nfloat_add, :_nfloat_vec_add),
                            (:mul, :nfloat_mul, :_nfloat_vec_mul))
    kernel = Symbol("_workspace_", op, "!")
    helper = Symbol("_bulk_", op, "!")
    public = Symbol(op, "!")
    @eval begin
        function $kernel(z::AbstractVector{NFloat{L}}, x, y, ctx::Ptr,
                         tmp::Vector{NFloat{L}}) where {L}
            T = NFloat{L}
            n = length(z)
            n == 0 && return z
            if x isa StridedVector{T} && y isa StridedVector{T} &&
                    stride(x, 1) == 1 && stride(y, 1) == 1
                GC.@preserve tmp x y begin
                    pt, px, py = pointer(tmp), pointer(x), pointer(y)
                    if (UInt(pt) | UInt(px) | UInt(py)) % UInt(8) == 0
                        st = LibFlint.$native(pt, px, py, n, ctx)
                        st == GR_SUCCESS || _status_error(st, $(QuoteNode(op)), T)
                        copyto!(z, 1, tmp, 1, n)
                        return z
                    end
                end
            end
            r = Ref{T}(tmp[1])
            for (k, i) in enumerate(eachindex(x, y))
                st = LibFlint.$scalar(r, Ref(x[i]), Ref(y[i]), ctx)
                st == GR_SUCCESS || _status_error(st, $(QuoteNode(op)), T)
                tmp[k] = r[]
            end
            copyto!(z, 1, tmp, 1, n)
            return z
        end

        # Fresh private scratch cannot alias callers or be used concurrently; no workspace object needed.
        function $helper(z::AbstractVector{NFloat{L}}, x, y, ctx::Ptr) where {L}
            return $kernel(z, x, y, ctx, _nfloat_scratch(NFloat{L}, length(z)))
        end

        function $public(z::AbstractVector{T}, x::AbstractVector, y::AbstractVector,
                         work::NFloatWorkspace{L}) where {T<:NFloat,L}
            _acquire_workspace!(work)
            try
                T === NFloat{L} || throw(ArgumentError("workspace format must match the vector element type"))
                ctx = _check_bulk(z, x, y)
                # Separate calls preserve concrete types when mixing vectors and views.
                buffer = work._buffer
                (Base.mightalias(buffer, z) || Base.mightalias(buffer, x) || Base.mightalias(buffer, y)) &&
                    throw(ArgumentError("workspace storage must not overlap inputs or destination"))
                _grow_workspace!(work, length(z))
                return $kernel(z, x, y, ctx, work._buffer)
            finally
                _release_workspace!(work)
            end
        end
    end
end

"""
    FlintFloats.add!(dest, x, y, workspace::NFloatWorkspace)

Elementwise nfloat vector addition using reusable scratch. Uses the vector [`add!`](@ref) type,
axes, destination, and alias rules. Automatically grows scratch if needed. Arithmetic or input-read
failure preserves `dest`; the workspace can be reused after failure. Concurrent/reentrant workspace
use and workspace overlap with any operand are rejected. Within reserved capacity, the native path
avoids scratch allocation and initialization; successful results are still copied into `dest`.
"""
add!(::AbstractVector{<:NFloat}, ::AbstractVector, ::AbstractVector, ::NFloatWorkspace)

"""
    FlintFloats.mul!(dest, x, y, workspace::NFloatWorkspace)

Elementwise nfloat vector multiplication using the same reusable-scratch and failure policy as
workspace [`add!`](@ref). This method is not exported.
"""
mul!(::AbstractVector{<:NFloat}, ::AbstractVector, ::AbstractVector, ::NFloatWorkspace)
