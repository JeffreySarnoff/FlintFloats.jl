# NFloat{L}: FLINT nfloat with L 64-bit limbs. Immutable, inline.
#
# C layout: exponent word, sign word, then L limbs (NFLOAT_HEADER_LIMBS = 2).

const NFLOAT_EXP_ZERO = typemin(Int)  # NFLOAT_EXP_ZERO = WORD_MIN (test/abi/layout.txt)
const NFLOAT_MAX_LIMBS = 66           # FLINT_BITS == 64 (test/abi/layout.txt)
const NFLOAT_FLAGS = Cint(1)          # ALLOW_UNDERFLOW only; see "nfloat specials" in docs

"""
    NFloat{L}

Fixed-precision float of `L` limbs (`64L` bits, `L` in 1:66). Finite values only: no `Inf` or `NaN`
(the pinned FLINT's nfloat special-value arithmetic is incomplete, see `docs/float_interfacing.md`),
division by zero throws `DivideError`, underflow flushes to zero. Create by converting a number,
e.g. `NFloat{2}(1.5)`.
"""
struct NFloat{L} <: FlintReal
    exp::Int
    sign::UInt
    d::NTuple{L,UInt}
    function NFloat{L}(exp::Int, sign::UInt, d::NTuple{L,UInt}) where {L}
        (L isa Int && 1 <= L <= NFLOAT_MAX_LIMBS) ||
            throw(ArgumentError("NFloat{L} requires L in 1:$NFLOAT_MAX_LIMBS, got $(repr(L))"))
        return new{L}(exp, sign, d)
    end
end

"Number of mantissa bits."
Base.precision(::Type{NFloat{L}}) where {L} = 64 * L
Base.precision(x::NFloat) = precision(typeof(x))

"`NFloat` type with at least `bits` bits of precision, in whole limbs."
NFloatType(bits::Integer) = NFloat{cld(Int(bits), 64)}

# One immutable-after-init gr context per limb count. nfloat arithmetic only reads it (no assignments
# to the context in src/nfloat of the pinned revision), so tasks may share these. The contexts hold
# library function pointers, so they are built in __init__, not at precompile time.
const _NFLOAT_CTX = Vector{NTuple{10,UInt}}(undef, NFLOAT_MAX_LIMBS)   # gr_ctx_struct = 80 bytes

function _init_nfloat_contexts!()
    for L in 1:NFLOAT_MAX_LIMBS
        st = LibFlint.nfloat_ctx_init(pointer(_NFLOAT_CTX, L), 64 * L, NFLOAT_FLAGS)
        st == GR_SUCCESS || error("nfloat_ctx_init failed for $L limbs (status $st)")
    end
    return nothing
end

# The limb-count check is a compile-time constant per method instance; it guards the unchecked
# pointer arithmetic below for every path that reaches C (constructors by conversion never run the
# inner constructor).
@inline function _ctx(::Type{NFloat{L}}) where {L}
    (L isa Int && 1 <= L <= NFLOAT_MAX_LIMBS) ||
        throw(ArgumentError("NFloat{L} requires L in 1:$NFLOAT_MAX_LIMBS, got $(repr(L))"))
    return pointer(_NFLOAT_CTX, L)
end

function NFloat{L}(x::Float64) where {L}
    ctx = _ctx(NFloat{L})
    isfinite(x) || throw(DomainError(x, "NFloat has no Inf or NaN"))
    r = Ref{NFloat{L}}()
    st = LibFlint.nfloat_set_d(r, x, ctx)
    st == GR_SUCCESS || _status_error(st, :set_d, NFloat{L})
    return r[]
end
NFloat{L}(x::Real) where {L} = NFloat{L}(Float64(x))

"`true` if `x` is zero (FLINT encodes zero as a special exponent)."
Base.iszero(x::NFloat) = x.exp == NFLOAT_EXP_ZERO

for (op, f) in ((:+, :add), (:-, :sub), (:*, :mul))
    cf = Symbol("nfloat_", f)
    @eval function Base.$op(x::NFloat{L}, y::NFloat{L}) where {L}
        r = Ref{NFloat{L}}()
        st = LibFlint.$cf(r, Ref(x), Ref(y), _ctx(NFloat{L}))
        st == GR_SUCCESS || _status_error(st, $(QuoteNode(f)), NFloat{L})
        return r[]
    end
end

function Base.:/(x::NFloat{L}, y::NFloat{L}) where {L}
    r = Ref{NFloat{L}}()
    st = LibFlint.nfloat_div(r, Ref(x), Ref(y), _ctx(NFloat{L}))
    st == GR_SUCCESS && return r[]
    iszero(y) && throw(DivideError())
    _status_error(st, :div, NFloat{L})
end

function Base.Float64(x::NFloat{L}) where {L}
    t = ArbFloat{64L}()
    st = LibFlint.nfloat_get_arf(t, Ref(x), _ctx(NFloat{L}))
    st == GR_SUCCESS || _status_error(st, :get_arf, NFloat{L})
    return Float64(t)
end
