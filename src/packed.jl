const PackedBallScalar = Union{ArbBall,AcbBall}

"""
    PackedBallVector(ArbBall{P}, n)
    PackedBallVector(AcbBall{P}, n)
    PackedBallVector(T, values::AbstractVector)

Fixed-size vector owning one initialized FLINT allocation. New slots are zero. All elements use the
concrete type `T` and its working precision. Indexing copies out an independent scalar; assignment
copies into initialized storage with containing precision conversion. `borrow(v, i)` returns an
explicit parent-retaining reference. Resizing is unsupported, so borrowed addresses remain stable.

`copy` and `deepcopy` create independent storage; ordinary assignment aliases the owner. Mutating
operations require independent writable destinations across tasks. Fields and raw pointers are private.
"""
mutable struct PackedBallVector{T<:PackedBallScalar} <: AbstractVector{T}
    _data::Ptr{Cvoid}
    const _length::Int
    _closed::Bool
    function PackedBallVector{T}(n::Integer) where {T<:PackedBallScalar}
        isconcretetype(T) || throw(ArgumentError("packed element type must be concrete"))
        checkprec(precision(T))
        len = Int(n)
        0 <= len <= typemax(Int) ÷ sizeof(T) || throw(ArgumentError("invalid packed vector length"))
        v = new{T}(C_NULL, len, false)
        # Register cleanup before acquiring native resources; all native slots initialize together.
        finalizer(_clear_packed!, v)
        if len != 0
            v._data = _alloc_packed(T, len)
            v._data != C_NULL || throw(OutOfMemoryError())
        end
        return v
    end
end
PackedBallVector(::Type{T}, n::Integer) where {T<:PackedBallScalar} = PackedBallVector{T}(n)

for (family, prefix) in ((:ArbBall, :arb), (:AcbBall, :acb))
    init, clear, setvec = Symbol(:_, prefix, :_vec_init), Symbol(:_, prefix, :_vec_clear), Symbol(:_, prefix, :_vec_set)
    @eval begin
        _alloc_packed(::Type{<:$family}, n) = LibFlint.$init(n)
        _free_packed(::Type{<:$family}, ptr, n) = LibFlint.$clear(ptr, n)
        function Base.copyto!(z::PackedBallVector{T}, x::PackedBallVector{T}) where {T<:$family}
            _check_packed_open(z); _check_packed_open(x)
            length(z) >= length(x) || throw(BoundsError(z, length(x)))
            isempty(x) && return z
            GC.@preserve z x LibFlint.$setvec(z._data, x._data, length(x))
            return z
        end
    end
end

function _clear_packed!(v::PackedBallVector{T}) where {T}
    v._closed && return nothing
    ptr = v._data
    v._data = C_NULL
    v._closed = true
    ptr == C_NULL || _free_packed(T, ptr, v._length)
    return nothing
end
_check_packed_open(v::PackedBallVector) = v._closed ? throw(ArgumentError("packed vector has been finalized")) : nothing

Base.size(v::PackedBallVector) = (v._length,)
Base.IndexStyle(::Type{<:PackedBallVector}) = IndexLinear()
Base.dataids(v::PackedBallVector) = (objectid(v),)
Base.precision(::PackedBallVector{T}) where {T} = precision(T)

"""
    BorrowedBall

An explicit reference to initialized packed storage, retaining its fixed-size parent. Read an
independent scalar with `r[]` or `copy(r)`, write with `r[] = value` or `FlintFloats.set!`, and use
qualified destination `add!`, `sub!`, `mul!`, `div!` with same-format scalars/references. References
are not numbers and have no independent clear action. No public raw-pointer constructor is provided.
"""
struct BorrowedBall{T<:PackedBallScalar}
    parent::PackedBallVector{T}
    index::Int
    function BorrowedBall(v::PackedBallVector{T}, i::Integer) where {T}
        _check_packed_open(v)
        checkbounds(v, i)
        return new{T}(v, Int(i))
    end
end
"""
    borrow(v::PackedBallVector, i)
    borrow(view(v, indices), i)

Return a parent-retaining [`BorrowedBall`](@ref) to a checked packed slot. Read a copy with `r[]`,
write with `r[] = value`, or use qualified destination arithmetic. The parent cannot resize.
"""
borrow(v::PackedBallVector, i::Integer) = BorrowedBall(v, i)
const PackedBallView = SubArray{T,1,V} where {T,V<:PackedBallVector{T}}
const PackedBallSpan = Union{PackedBallVector,PackedBallView}
function borrow(v::PackedBallView, i::Integer)
    checkbounds(v, i)
    return borrow(parent(v), parentindices(v)[1][i])
end

# ccall retains the conversion object, which retains the parent; the pointer never escapes a call.
Base.cconvert(::Type{Ptr{Cvoid}}, r::BorrowedBall) = r
function Base.unsafe_convert(::Type{Ptr{Cvoid}}, r::BorrowedBall{T}) where {T}
    _check_packed_open(r.parent)
    return r.parent._data + (r.index - 1) * sizeof(T)
end
Base.precision(::BorrowedBall{T}) where {T} = precision(T)
Base.getindex(r::BorrowedBall) = copy(r)
Base.setindex!(r::BorrowedBall, value) = set!(r, value)
Base.getindex(v::PackedBallVector, i::Int) = copy(borrow(v, i))
function Base.setindex!(v::PackedBallVector, value, i::Int)
    set!(borrow(v, i), value)
    return v
end

for (family, prefix) in ((:ArbBall, :arb), (:AcbBall, :acb))
    setround, setexact = Symbol(prefix, :_set_round), Symbol(prefix, :_set)
    @eval begin
        function Base.copy(r::BorrowedBall{T}) where {T<:$family}
            z = T()
            LibFlint.$setexact(z, r)
            return z
        end
        function set!(z::BorrowedBall{$family{P}}, x::$family) where {P}
            LibFlint.$setround(z, x, P)
            return z
        end
        function set!(z::BorrowedBall{$family{P}}, x::BorrowedBall{<:$family}) where {P}
            LibFlint.$setround(z, x, P)
            return z
        end
        function set!(z::$family{P}, x::BorrowedBall{<:$family}) where {P}
            LibFlint.$setround(z, x, P)
            return z
        end
    end
    for (op, f) in ((:add, :add), (:sub, :sub), (:mul, :mul), (:div, :div))
        bang, cf = Symbol(op, :!), Symbol(prefix, :_, f)
        @eval function $bang(z::Union{$family{P},BorrowedBall{$family{P}}},
                             x::Union{$family{P},BorrowedBall{$family{P}}},
                             y::Union{$family{P},BorrowedBall{$family{P}}}) where {P}
            LibFlint.$cf(z, x, y, P)
            return z
        end
    end
end
set!(z::BorrowedBall{T}, value) where {T} = set!(z, T(value))
# Cross-family conversion uses an independent scalar, preserving the existing conversion contract.
set!(z::BorrowedBall{T}, value::BorrowedBall) where {T} = set!(z, T(copy(value)))

function PackedBallVector(::Type{T}, values::AbstractVector) where {T<:PackedBallScalar}
    v = PackedBallVector(T, length(values))
    try
        for (i, value) in enumerate(values)
            v[i] = value
        end
        return v
    catch
        finalize(v) # All slots were initialized; clean immediately after a conversion/input failure.
        rethrow()
    end
end
function Base.copy(v::PackedBallVector{T}) where {T}
    _check_packed_open(v)
    return copyto!(PackedBallVector(T, length(v)), v)
end
function Base.deepcopy_internal(v::PackedBallVector, dict::IdDict)
    haskey(dict, v) && return dict[v]
    z = copy(v)
    dict[v] = z
    return z
end
function Base.similar(::PackedBallVector, ::Type{T}, dims::Dims) where {T}
    if length(dims) == 1 && T <: PackedBallScalar && isconcretetype(T)
        return PackedBallVector(T, dims[1])
    end
    return Array{T}(undef, dims)
end
function Base.fill!(v::PackedBallVector{T}, value) where {T}
    _check_packed_open(v)
    # Snapshot before mutation so a borrowed input is stable for the whole fill.
    x = value isa BorrowedBall ? T(copy(value)) : T(value)
    for i in eachindex(v)
        set!(borrow(v, i), x)
    end
    return v
end

_packed_parent(v::PackedBallVector) = v
_packed_parent(v::PackedBallView) = parent(v)
_packed_input(v::PackedBallSpan, i) = borrow(v, i)
_packed_input(v::AbstractVector, i) = v[i]
function _check_packed_bulk(z::PackedBallSpan, x::AbstractVector, y::AbstractVector)
    T = eltype(z)
    eltype(x) === T && eltype(y) === T || throw(ArgumentError("packed bulk operands must have identical concrete element types"))
    axes(z) == axes(x) == axes(y) || throw(DimensionMismatch("packed bulk axes must match"))
    _check_packed_open(_packed_parent(z))
    if z isa PackedBallView
        inds = parentindices(z)[1]
        (inds isa AbstractRange && step(inds) != 0) || inds isa Base.Slice ||
            throw(ArgumentError("packed destination views require independent strided slots"))
    end
    x isa PackedBallSpan && _check_packed_open(_packed_parent(x))
    y isa PackedBallSpan && _check_packed_open(_packed_parent(y))
    for input in (x, y)
        input === z || !Base.mightalias(z, input) || throw(ArgumentError("packed destination overlaps an input"))
    end
    return nothing
end

# Native vec_add is a forward loop of the corresponding rigorous scalar add, with exact aliasing.
for (family, prefix) in ((:ArbBall, :arb), (:AcbBall, :acb))
    cf = Symbol(:_, prefix, :_vec_add)
    @eval function _packed_add!(z::PackedBallVector{T}, x::PackedBallVector{T}, y::PackedBallVector{T}) where {T<:$family}
        GC.@preserve z x y LibFlint.$cf(z._data, x._data, y._data, length(z), precision(T))
        return z
    end
end
function _packed_scalar!(f!, z, x, y)
    for i in eachindex(z, x, y)
        f!(borrow(z, i), _packed_input(x, i), _packed_input(y, i))
    end
    return z
end
_packed_add!(z, x, y) = _packed_scalar!(add!, z, x, y)

"""
    FlintFloats.add!(dest::PackedBallVector, x, y)
    FlintFloats.mul!(dest::PackedBallVector, x, y)

Elementwise rigorous arithmetic, also accepting strided views of a packed destination. Operands
must have identical concrete element types and matching axes. Exact aliases are supported; other
possible destination/input overlap and gather destinations are rejected before mutation. Direct
packed addition uses native vector kernels; views and multiplication use borrowed scalar calls.
Empty operations skip C. Indeterminate FLINT enclosures are retained. Validation failures preserve
the destination; custom input-read exceptions can leave a valid, partially updated destination.
Concurrent operations must write independent slots and must not finalize their parents explicitly.
"""
function add!(z::PackedBallSpan, x::AbstractVector, y::AbstractVector)
    _check_packed_bulk(z, x, y)
    isempty(z) && return z
    return _packed_add!(z, x, y)
end
"""
    FlintFloats.mul!(dest::PackedBallVector, x, y)

Elementwise ball multiplication through borrowed scalar destinations; also accepts independent
strided packed destination views. Uses the packed vector [`add!`](@ref) shape/type/alias and failure
policy. No native elementwise vector-multiply entry is assumed. This method is not exported.
"""
function mul!(z::PackedBallSpan, x::AbstractVector, y::AbstractVector)
    _check_packed_bulk(z, x, y)
    isempty(z) && return z
    return _packed_scalar!(mul!, z, x, y)
end
