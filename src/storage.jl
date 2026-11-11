# Pointer conversion for scalar owned values. Packed owners/borrowers use the adapter in packed.jl.
#
# An owner is a mutable struct whose single field `w` is an NTuple of words laid out exactly as the C
# struct (sizes and offsets checked against test/abi/layout.txt). `pointer_from_objref` addresses
# that first field. ccall roots the cconvert result for the duration of the call, so the owner
# stays alive while C uses the pointer.

const FlintOwned = Union{ArbFloat, AcbFloat, ArbBall, AcbBall}

Base.cconvert(::Type{Ptr{Cvoid}}, x::FlintOwned) = x
Base.unsafe_convert(::Type{Ptr{Cvoid}}, x::FlintOwned) = _ptr(x)

# Raw address of the C struct inside an owner. Valid only inside GC.@preserve of `x` (or a ccall).
_ptr(x::FlintOwned) = Ptr{Cvoid}(pointer_from_objref(x))

# Generic deepcopy would duplicate pointer words without native initialization/finalizers. Preserve
# alias graphs with the caller's identity dictionary, but give each copied owner independent storage.
function Base.deepcopy_internal(x::FlintOwned,dict::IdDict)
    haskey(dict,x) && return dict[x]
    y=copy(x)
    dict[x]=y
    y
end
