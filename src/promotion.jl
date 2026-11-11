# Narrow promotion (enact §8.2). Implicit promotion exists only where it loses nothing the type
# promises:
#   - within a family, to the larger parameter (DFloat{N}, NFloat{L}, ArbFloat{P}, ArbBall{P}, ...);
#   - DFloat with DFloatBall gives DFloatBall;
#   - in the arb family: a point with a ball gives the ball type, real with complex gives the complex
#     type, parameters give the maximum (DFloat counts as 53N bits, NFloat as 64L);
#   - machine numbers keep the FLINT operand's type.
# DFloat with NFloat, and DFloatBall with the arb family, stay explicit. BigFloat never promotes
# silently to or from a FlintFloats type (Base's blanket AbstractFloat rule would pick BigFloat).

# ---- constructors needed for promotion ------------------------------------------------------------

# Pad an expansion with zero doubles (exact), or round through ArbFloat when narrowing.
function DFloat{N}(x::DFloat{M}) where {N,M}
    N >= M && return DFloat{N}((x.d..., ntuple(_ -> 0.0, N - M)...))
    return DFloat{N}(_arf(x))
end
DFloat{N}(x::NFloat) where {N} = DFloat{N}(_arf(x))
NFloat{L}(x::DFloat) where {L} = NFloat{L}(_arf(x))

for N in 1:4
    sa = Symbol("d", N, "b_set_arb")
    @eval function DFloatBall{$N}(x::ArbBall)
        _require_dfloat()
        r = Ref{DFloatBall{$N}}()
        LibFlint.$sa(r, x)
        return r[]
    end
end
function DFloatBall{N}(x::DFloatBall{M}) where {N,M}
    N >= M && return DFloatBall{N}((x.d..., ntuple(_ -> 0.0, N - M)...), x.rad)
    return DFloatBall{N}(_arbball(x))
end
function DFloatBall{N}(x::DFloat{M}) where {N,M}
    N >= M && return DFloatBall{N}((x.d..., ntuple(_ -> 0.0, N - M)...), 0.0)
    return DFloatBall{N}(_arf(x))
end

ArbBall{P}(x::Union{DFloat,NFloat}) where {P} = ArbBall{P}(_arf(x))
AcbFloat{P}(x::Union{DFloat,NFloat}) where {P} = AcbFloat{P}(ArbFloat{P}(x))
AcbBall{P}(x::Union{DFloat,NFloat}) where {P} = AcbBall{P}(ArbBall{P}(x))

# ---- promote_rule -----------------------------------------------------------------------------------

Base.promote_rule(::Type{DFloat{N}}, ::Type{DFloat{M}}) where {N,M} = DFloat{max(N, M)}
Base.promote_rule(::Type{DFloatBall{N}}, ::Type{DFloatBall{M}}) where {N,M} = DFloatBall{max(N, M)}
Base.promote_rule(::Type{DFloat{N}}, ::Type{DFloatBall{M}}) where {N,M} = DFloatBall{max(N, M)}
Base.promote_rule(::Type{NFloat{L}}, ::Type{NFloat{M}}) where {L,M} = NFloat{max(L, M)}

const ArbKind = Union{ArbFloat,ArbBall,AcbFloat,AcbBall}

_bits(::Type{DFloat{N}}) where {N} = 53N
_bits(::Type{NFloat{L}}) where {L} = 64L
_bits(::Type{<:Union{ArbFloat{P},ArbBall{P},AcbFloat{P},AcbBall{P}}}) where {P} = P
_isball(::Type{T}) where {T} = T <: Union{ArbBall,AcbBall}
_iscomplex(::Type{T}) where {T} = T <: Union{AcbFloat,AcbBall}

function _arbtype(::Type{A}, ::Type{B}) where {A,B}
    P = max(_bits(A), _bits(B))
    ball = _isball(A) || _isball(B)
    cplx = _iscomplex(A) || _iscomplex(B)
    return cplx ? (ball ? AcbBall{P} : AcbFloat{P}) : (ball ? ArbBall{P} : ArbFloat{P})
end

# At least one operand is in the arb family, so DFloat with NFloat is not caught here.
Base.promote_rule(::Type{A}, ::Type{B}) where {A<:ArbKind,B<:Union{DFloat,NFloat,ArbKind}} = _arbtype(A, B)
Base.promote_rule(::Type{A}, ::Type{B}) where {A<:Union{DFloat,NFloat},B<:ArbKind} = _arbtype(A, B)

# Machine numbers keep the FLINT type.
Base.promote_rule(::Type{T}, ::Type{<:Union{Bool,MachineInteger,MachineFloat}}) where {T<:FlintNumber} = T
# No silent trip through BigFloat.
Base.promote_rule(::Type{BigFloat}, ::Type{<:FlintNumber}) = Union{}

# ---- convert ----------------------------------------------------------------------------------------
# Into a ball or a wider point: exact or containing. Narrowing a point must be exact, else InexactError.

function Base.convert(::Type{T}, x::FlintNumber) where {T<:FlintNumber}
    # Reached by `promote` when no rule exists: Base then asks for the common abstract supertype.
    isconcretetype(T) || throw(ArgumentError(
        "no implicit promotion between $(typeof(x)) and this operand; convert one of them explicitly"))
    y = T(x)
    if guarantee(T) isa Point && guarantee(typeof(x)) isa Point && !isequal(y, x)
        throw(InexactError(:convert, T, x))
    end
    return y
end
