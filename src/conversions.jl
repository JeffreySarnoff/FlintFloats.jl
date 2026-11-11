# Construction and conversion between numbers and families, and mixed machine-number arithmetic.
#
# Rules (enact §8.2): conversions into a type round to nearest at that type's precision; a point
# converts to a ball containing it; nothing goes through Float64 unless the source is a Float64.

const MachineInteger = Union{Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64}
const MachineFloat = Union{Float16,Float32,Float64}
const MachineScalar = Union{MachineInteger,MachineFloat}

# Arguments accepted by the default-precision constructors `ArbFloat(x)`, `AcbBall(re, im)` and so on.
# Deliberately not `Any`: a catch-all method would be ambiguous with Base's `T(x::T)` and friends.
const Literal = Union{Bool,MachineScalar,Int128,UInt128,BigInt,BigFloat,AbstractString}

# ---- ArbFloat{P} ------------------------------------------------------------------------------

ArbFloat{P}(x::Union{Bool,Int8,Int16,Int32,UInt8,UInt16,UInt32}) where {P} = ArbFloat{P}(Int(x))
ArbFloat{P}(x::Union{Float16,Float32}) where {P} = ArbFloat{P}(Float64(x))

function ArbFloat{P}(x::UInt64) where {P}
    z = ArbFloat{P}()
    LibFlint.arf_set_ui(z, x)
    LibFlint.arf_set_round(z, z, P, ARF_RND_NEAR)
    return z
end

function ArbFloat{P}(x::BigFloat) where {P}
    z = ArbFloat{P}()
    LibFlint.arf_set_mpfr(z, x)
    LibFlint.arf_set_round(z, z, P, ARF_RND_NEAR)
    return z
end

# Exact bit length first, so the intermediate BigFloat holds the integer without rounding.
function ArbFloat{P}(x::Integer) where {P}
    b = big(x)
    return ArbFloat{P}(BigFloat(b; precision = max(2, ndigits(abs(b); base = 2))))
end

"`ArbFloat{P}(x::ArbFloat{Q}, mode)`: re-round `x` to `P` bits (exact when `P >= Q`)."
function ArbFloat{P}(x::ArbFloat, r::RoundingMode = RoundNearest) where {P}
    z = ArbFloat{P}()
    LibFlint.arf_set_round(z, x, P, _rnd(r))
    return z
end

ArbFloat{P}(x::ArbBall) where {P} = throw(ArgumentError(
    "an ArbBall is an enclosure; take midpoint(x) to convert it to a point value explicitly"))

Base.parse(::Type{ArbFloat{P}}, s::AbstractString) where {P} = ArbFloat{P}(parse(BigFloat, s; precision = P))
ArbFloat{P}(s::AbstractString) where {P} = parse(ArbFloat{P}, s)

Base.Float64(x::ArbFloat, r::RoundingMode) = LibFlint.arf_get_d(x, _rnd(r))

"`BigFloat(x::ArbFloat)`: `x` rounded to `precision` bits (default `P`, exact for finite `x` in range)."
function Base.BigFloat(x::ArbFloat{P}, r::RoundingMode = RoundNearest; precision::Integer = P) where {P}
    z = BigFloat(0; precision = precision)
    LibFlint.arf_get_mpfr(z, x, _mpfr_rnd(r))
    return z
end

# ---- ArbBall{P} -------------------------------------------------------------------------------

function ArbBall{P}(x::ArbFloat) where {P}
    z = ArbBall{P}()
    LibFlint.arb_set_arf(z, x)
    LibFlint.arb_set_round(z, z, P)           # a rounded midpoint gains a radius covering the loss
    return z
end

function ArbBall{P}(x::ArbBall) where {P}
    z = ArbBall{P}()
    LibFlint.arb_set_round(z, x, P)
    return z
end

ArbBall{P}(x::Union{Bool,Int8,Int16,Int32,UInt8,UInt16,UInt32}) where {P} = ArbBall{P}(Int(x))
ArbBall{P}(x::Union{Float16,Float32}) where {P} = ArbBall{P}(Float64(x))
ArbBall{P}(x::UInt64) where {P} = ArbBall{P}(ArbFloat{64}(x))
ArbBall{P}(x::BigFloat) where {P} = ArbBall{P}(ArbFloat{max(2, precision(x))}(x))
ArbBall{P}(x::Integer) where {P} = ArbBall{P}(ArbFloat{max(2, ndigits(abs(big(x)); base = 2))}(x))

"Parse a decimal or `[mid +/- rad]` literal into a ball containing it."
function Base.parse(::Type{ArbBall{P}}, s::AbstractString) where {P}
    z = ArbBall{P}()
    LibFlint.arb_set_str(z, String(s), P) == 0 || throw(ArgumentError("invalid ArbBall literal: $(repr(s))"))
    return z
end
ArbBall{P}(s::AbstractString) where {P} = parse(ArbBall{P}, s)

# ---- AcbFloat{P}, AcbBall{P} --------------------------------------------------------------------

AcbFloat{P}(re::ArbFloat, im::ArbFloat) where {P} = AcbFloat{P}(ArbFloat{P}(re), ArbFloat{P}(im))
AcbFloat{P}(re::MachineScalar) where {P} = AcbFloat{P}(ArbFloat{P}(re), ArbFloat{P}())
AcbFloat{P}(re::MachineScalar, im::MachineScalar) where {P} = AcbFloat{P}(ArbFloat{P}(re), ArbFloat{P}(im))
AcbFloat{P}(re::AbstractString, im::AbstractString) where {P} = AcbFloat{P}(ArbFloat{P}(re), ArbFloat{P}(im))
AcbFloat{P}(x::AcbFloat{Q}) where {P,Q} = AcbFloat{P}(real(x), imag(x))
AcbFloat{P}(x::ArbFloat) where {P} = AcbFloat{P}(x, ArbFloat{P}())

AcbBall{P}(re::ArbBall, im::ArbBall) where {P} = AcbBall{P}(ArbBall{P}(re), ArbBall{P}(im))
AcbBall{P}(re::MachineScalar) where {P} = AcbBall{P}(ArbBall{P}(re), ArbBall{P}())
AcbBall{P}(re::MachineScalar, im::MachineScalar) where {P} = AcbBall{P}(ArbBall{P}(re), ArbBall{P}(im))
AcbBall{P}(re::AbstractString, im::AbstractString) where {P} = AcbBall{P}(ArbBall{P}(re), ArbBall{P}(im))
AcbBall{P}(x::AcbBall{Q}) where {P,Q} = AcbBall{P}(real(x), imag(x))
AcbBall{P}(x::ArbBall) where {P} = AcbBall{P}(x, ArbBall{P}())
AcbBall{P}(x::AcbFloat{Q}) where {P,Q} = AcbBall{P}(ArbBall{P}(real(x)), ArbBall{P}(imag(x)))
AcbBall{P}(x::ArbFloat) where {P} = AcbBall{P}(ArbBall{P}(x), ArbBall{P}())

# ---- NFloat{L} ----------------------------------------------------------------------------------

function NFloat{L}(x::ArbFloat) where {L}
    ctx = _ctx(NFloat{L})
    isfinite(x) || throw(DomainError(x, "NFloat has no Inf or NaN"))
    t = ArbFloat{64L}(x)                      # one rounding, to the exact width of the target
    r = Ref{NFloat{L}}()
    st = LibFlint.nfloat_set_arf(r, t, ctx)
    st == GR_SUCCESS || _status_error(st, :set_arf, NFloat{L})
    return r[]
end

NFloat{L}(x::Union{Bool,Int8,Int16,Int32,UInt8,UInt16,UInt32,Float16,Float32}) where {L} = NFloat{L}(Float64(x))
NFloat{L}(x::Union{Int64,UInt64,BigFloat}) where {L} = NFloat{L}(ArbFloat{64L}(x))
NFloat{L}(x::Integer) where {L} = NFloat{L}(ArbFloat{64L}(x))
NFloat{L}(x::NFloat) where {L} = NFloat{L}(ArbFloat{64max(L, length(x.d))}(x))

function ArbFloat{P}(x::NFloat{L}) where {P,L}
    z = ArbFloat{P}()
    st = LibFlint.nfloat_get_arf(z, Ref(x), _ctx(NFloat{L}))
    st == GR_SUCCESS || _status_error(st, :get_arf, NFloat{L})
    LibFlint.arf_set_round(z, z, P, ARF_RND_NEAR)
    return z
end

Base.parse(::Type{NFloat{L}}, s::AbstractString) where {L} = NFloat{L}(parse(ArbFloat{64L}, s))
NFloat{L}(s::AbstractString) where {L} = parse(NFloat{L}, s)

# ---- DFloat{N} ----------------------------------------------------------------------------------

for N in 1:4
    sa = Symbol("d", N, "_set_arf")
    ga = Symbol("d", N, "_get_arf")
    @eval function DFloat{$N}(x::ArbFloat)
        _require_dfloat()
        r = Ref{DFloat{$N}}()
        LibFlint.$sa(r, x)
        return r[]
    end
    @eval function ArbFloat{P}(x::DFloat{$N}) where {P}
        z = ArbFloat{P}()
        LibFlint.$ga(z, Ref(x))
        LibFlint.arf_set_round(z, z, P, ARF_RND_NEAR)
        return z
    end
    sb = Symbol("d", N, "b_set_arf")
    @eval function DFloatBall{$N}(x::ArbFloat)
        _require_dfloat()
        r = Ref{DFloatBall{$N}}()
        LibFlint.$sb(r, x)
        return r[]
    end
end
DFloat{N}(x::Union{Int64,UInt64,BigFloat}) where {N} = DFloat{N}(ArbFloat{53 * N + 64}(x))
DFloat{N}(x::Integer) where {N} = DFloat{N}(ArbFloat{53 * N + 64}(x))
DFloatBall{N}(x::Union{Int64,UInt64,BigFloat}) where {N} = DFloatBall{N}(ArbFloat{53 * N + 64}(x))
DFloatBall{N}(x::Integer) where {N} = DFloatBall{N}(ArbFloat{53 * N + 64}(x))

# ---- mixed arithmetic with machine numbers ------------------------------------------------------
# The result keeps the type (hence precision) of the FLINT operand. Bool is left to Base.

const MixedScalar = Union{Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64,Float16,Float32,Float64}

for op in (:+, :-, :*, :/)
    @eval begin
        Base.$op(x::FlintNumber, y::MixedScalar) = $op(x, typeof(x)(y))
        Base.$op(x::MixedScalar, y::FlintNumber) = $op(typeof(y)(x), y)
    end
end

Base.convert(::Type{T}, x::MixedScalar) where {T<:FlintNumber} = T(x)

# ---- default precision --------------------------------------------------------------------------

ArbFloat(x::Literal) = ArbFloat{DEFAULT_PRECISION}(x)
ArbBall(x::Literal) = ArbBall{DEFAULT_PRECISION}(x)
AcbFloat(re::Literal, im::Literal = 0.0) = AcbFloat{DEFAULT_PRECISION}(re, im)
AcbBall(re::Literal, im::Literal = 0.0) = AcbBall{DEFAULT_PRECISION}(re, im)
