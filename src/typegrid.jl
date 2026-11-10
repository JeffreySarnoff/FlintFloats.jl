# The grid of types, and traits over it. A missing cell is a MethodError.
#
#                    point            ball
#   dfloat           DFloat{N}        DFloatBall{N}
#   nfloat           NFloat{L}        (none)
#   arb real         ArbFloat{P}      ArbBall{P}
#   arb complex      AcbFloat{P}      AcbBall{P}

"Whether a type's values are exact representations (`Point`) or enclosures (`Enclosure`)."
abstract type Guarantee end
struct Point <: Guarantee end
struct Enclosure <: Guarantee end

"Whether a type's values are immutable and inline (`Inline`) or heap-owning mutable objects (`Owned`)."
abstract type Storage end
struct Inline <: Storage end
struct Owned <: Storage end

guarantee(::Type{<:Union{DFloat,NFloat,ArbFloat,AcbFloat}}) = Point()
guarantee(::Type{<:Union{DFloatBall,ArbBall,AcbBall}}) = Enclosure()
storage(::Type{<:Union{DFloat,DFloatBall,NFloat}}) = Inline()
storage(::Type{<:Union{ArbFloat,AcbFloat,ArbBall,AcbBall}}) = Owned()

pointtype(::Type{DFloat{N}}) where {N} = DFloat{N}
pointtype(::Type{DFloatBall{N}}) where {N} = DFloat{N}
pointtype(::Type{NFloat{L}}) where {L} = NFloat{L}
pointtype(::Type{<:Union{ArbFloat{P},ArbBall{P}}}) where {P} = ArbFloat{P}
pointtype(::Type{<:Union{AcbFloat{P},AcbBall{P}}}) where {P} = AcbFloat{P}

balltype(::Type{<:Union{DFloat{N},DFloatBall{N}}}) where {N} = DFloatBall{N}
balltype(::Type{<:Union{ArbFloat{P},ArbBall{P}}}) where {P} = ArbBall{P}
balltype(::Type{<:Union{AcbFloat{P},AcbBall{P}}}) where {P} = AcbBall{P}

realtype(::Type{T}) where {T<:FlintReal} = T
realtype(::Type{AcbFloat{P}}) where {P} = ArbFloat{P}
realtype(::Type{AcbBall{P}}) where {P} = ArbBall{P}

complextype(::Type{ArbFloat{P}}) where {P} = AcbFloat{P}
complextype(::Type{ArbBall{P}}) where {P} = AcbBall{P}
complextype(::Type{T}) where {T<:Union{AcbFloat,AcbBall}} = T

"Every FlintFloats value type."
const FlintNumber = Union{FlintReal,AcbFloat,AcbBall}

# Instance forms. Restricted to values, so a missing type-level cell is a MethodError, not recursion.
for f in (:guarantee, :storage, :pointtype, :balltype, :realtype, :complextype)
    @eval $f(x::FlintNumber) = $f(typeof(x))
end
