module FlintFloatsSerializationExt
using FlintFloats
import Serialization
const NativeStorage = Union{FlintFloats.FlintOwned,FlintFloats.PackedBallVector,FlintFloats.BorrowedBall}
# Raw native pointer words are not a persistent numeric representation. Refuse both writing new
# streams and reconstructing legacy/raw owner objects without native initialization and cleanup.
function Serialization.serialize(::Serialization.AbstractSerializer,::NativeStorage)
    throw(ArgumentError("Serialization of FLINT owners/borrowed references is unsupported; persist explicit numeric text/data instead"))
end
function Serialization.deserialize(::Serialization.AbstractSerializer,::Type{T}) where {T<:NativeStorage}
    throw(ArgumentError("Deserializing raw FLINT owners/borrowed references is unsupported; reconstruct values through their constructors"))
end
end
