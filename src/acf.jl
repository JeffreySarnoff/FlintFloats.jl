# AcbFloat{P}: FLINT acf at P bits. Mutable owner of an 8-word acf_struct (two arf).

"""
    AcbFloat{P}

Complex float with `P`-bit parts (FLINT `acf`); each part correctly rounded. Not an enclosure.
Mutable owner; see [`ArbFloat`](@ref) for the shared conventions.
"""
mutable struct AcbFloat{P} <: Number
    w::NTuple{8,UInt}                     # acf_struct (sizeof 64, test/abi/layout.txt)
    function AcbFloat{P}() where {P}
        checkprec(P)
        z = new{P}((0, 0, 0, 0, 0, 0, 0, 0))
        LibFlint.acf_init(z)
        finalizer(_clear!, z)
        return z
    end
end

_clear!(z::AcbFloat) = (LibFlint.acf_clear(z); nothing)

Base.precision(::Type{AcbFloat{P}}) where {P} = P
Base.precision(::AcbFloat{P}) where {P} = P

function AcbFloat{P}(re::Float64, im::Float64) where {P}
    z = AcbFloat{P}()
    GC.@preserve z begin
        for (p, v) in ((LibFlint.acf_real_ptr(z), re), (LibFlint.acf_imag_ptr(z), im))
            LibFlint.arf_set_d(p, v)
            LibFlint.arf_set_round(p, p, P, ARF_RND_NEAR)    # precision invariant
        end
    end
    return z
end

function Base.copy(z::AcbFloat{P}) where {P}
    w = AcbFloat{P}()
    LibFlint.acf_set(w, z)
    return w
end

function _part(z::AcbFloat{P}, ptr) where {P}
    x = ArbFloat{P}()
    GC.@preserve z LibFlint.arf_set(x, ptr(z))
    return x
end
Base.real(z::AcbFloat) = _part(z, LibFlint.acf_real_ptr)
Base.imag(z::AcbFloat) = _part(z, LibFlint.acf_imag_ptr)

for (name, f) in ((:add, :acf_add), (:sub, :acf_sub), (:mul, :acf_mul), (:div, :acf_div))
    bang = Symbol(name, :!)
    inexact = Symbol(name, :_inexact!)
    @eval function $inexact(z::AcbFloat{P}, x::AcbFloat{P}, y::AcbFloat{P},
                            r::RoundingMode = RoundNearest) where {P}
        flag = LibFlint.$f(z, x, y, P, _rnd(r))
        return z, flag != 0
    end
    @eval function $bang(z::AcbFloat{P}, x::AcbFloat{P}, y::AcbFloat{P},
                         r::RoundingMode = RoundNearest) where {P}
        LibFlint.$f(z, x, y, P, _rnd(r))
        return z
    end
end

Base.:+(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = add!(AcbFloat{P}(), x, y)
Base.:-(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = sub!(AcbFloat{P}(), x, y)
Base.:*(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = mul!(AcbFloat{P}(), x, y)
Base.:/(x::AcbFloat{P}, y::AcbFloat{P}) where {P} = div!(AcbFloat{P}(), x, y)

# ---- classification, unary operations -------------------------------------------------------------

Base.iszero(z::AcbFloat) = iszero(real(z)) && iszero(imag(z))
Base.isnan(z::AcbFloat) = isnan(real(z)) || isnan(imag(z))
Base.isinf(z::AcbFloat) = isinf(real(z)) || isinf(imag(z))
Base.isfinite(z::AcbFloat) = isfinite(real(z)) && isfinite(imag(z))

Base.zero(::Type{AcbFloat{P}}) where {P} = AcbFloat{P}()
Base.one(::Type{AcbFloat{P}}) where {P} = AcbFloat{P}(1.0, 0.0)
Base.zero(::Type{AcbFloat}) = zero(AcbFloat{DEFAULT_PRECISION})
Base.one(::Type{AcbFloat}) = one(AcbFloat{DEFAULT_PRECISION})
Base.zero(::AcbFloat{P}) where {P} = AcbFloat{P}()
Base.one(::AcbFloat{P}) where {P} = AcbFloat{P}(1.0, 0.0)

"Complex number from real and imaginary parts of the same precision (exact copy)."
function AcbFloat{P}(re::ArbFloat{P}, im::ArbFloat{P}) where {P}
    z = AcbFloat{P}()
    GC.@preserve z begin
        LibFlint.arf_set(LibFlint.acf_real_ptr(z), re)
        LibFlint.arf_set(LibFlint.acf_imag_ptr(z), im)
    end
    return z
end

function neg!(z::AcbFloat{P}, x::AcbFloat{P}) where {P}
    LibFlint.acf_neg(z, x)
    return z
end
Base.:-(x::AcbFloat{P}) where {P} = neg!(AcbFloat{P}(), x)

"Complex conjugate; exact (the imaginary part's sign flips)."
Base.conj(x::AcbFloat{P}) where {P} = AcbFloat{P}(real(x), -imag(x))

# ---- modulus ------------------------------------------------------------------------------------
#
# FLINT exports no acf_abs, so both are built from arf operations and are still correctly rounded:
#
# abs2: re² and im² are formed exactly (ARF_PREC_EXACT; a product of two P-bit values has at most 2P
#   bits), then added with ONE rounding to P bits.
#
# abs: sqrt(re² + im²) needs the exact sum, which can be arbitrarily wide. Instead bracket it: add the
#   exact squares at W = 2P + 4 bits rounding down (s_lo) and up (s_hi), s_lo <= s <= s_hi, and take
#   the correctly rounded square root of each. Rounding is monotone, so equal results are the answer.
#   If they differ, s_lo and s_hi are adjacent W-bit numbers, so a rounding boundary b (a number of
#   at most P+1 bits, b² of at most 2P+2 < W bits) must equal sqrt of one of them. If sqrt(s_lo) is
#   exactly representable in P+1 bits then b² = s_lo < s and the answer is round(sqrt(s_hi));
#   otherwise b² = s_hi > s and the answer is round(sqrt(s_lo)). No loop, no dependence on the
#   exponent gap.
#
# Scratch values below are ArbFloat{P} owners that hold up to 2P+4 bits. They never escape, so the
# public precision invariant is not affected.

const ARF_PREC_EXACT = typemax(Int)

# Special values of hypot: infinity wins over NaN. Returns true if `z` was set.
function _modulus_special!(z::ArbFloat, ar, ai)
    if LibFlint.arf_is_pos_inf(ar) != 0 || LibFlint.arf_is_neg_inf(ar) != 0 ||
       LibFlint.arf_is_pos_inf(ai) != 0 || LibFlint.arf_is_neg_inf(ai) != 0
        LibFlint.arf_pos_inf(z)
        return true
    elseif LibFlint.arf_is_nan(ar) != 0 || LibFlint.arf_is_nan(ai) != 0
        LibFlint.arf_nan(z)
        return true
    end
    return false
end

# t1 = re², t2 = im², both exact.
function _exact_squares!(t1::ArbFloat, t2::ArbFloat, ar, ai)
    LibFlint.arf_mul_rnd_any(t1, ar, ar, ARF_PREC_EXACT, ARF_RND_NEAR)
    LibFlint.arf_mul_rnd_any(t2, ai, ai, ARF_PREC_EXACT, ARF_RND_NEAR)
    return nothing
end

"""
    abs2(z::AcbFloat{P}, mode = RoundNearest) -> ArbFloat{P}

`re² + im²` correctly rounded to `P` bits in `mode`. See also `abs2_inexact!`.
"""
Base.abs2(x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P} = first(abs2_inexact!(ArbFloat{P}(), x, r))
abs2!(z::ArbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P} = first(abs2_inexact!(z, x, r))

function abs2_inexact!(z::ArbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P}
    mode = _rnd(r)
    GC.@preserve x begin
        ar, ai = LibFlint.acf_real_ptr(x), LibFlint.acf_imag_ptr(x)
        _modulus_special!(z, ar, ai) && return z, false
        t1, t2 = ArbFloat{P}(), ArbFloat{P}()
        _exact_squares!(t1, t2, ar, ai)
        flag = LibFlint.arf_add(z, t1, t2, P, mode)
        return z, flag != 0
    end
end

"""
    abs(z::AcbFloat{P}, mode = RoundNearest) -> ArbFloat{P}

`sqrt(re² + im²)` correctly rounded to `P` bits in `mode` (overflow-free: the exponent is unbounded).
See also `abs_inexact!`.
"""
Base.abs(x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P} = first(abs_inexact!(ArbFloat{P}(), x, r))
abs!(z::ArbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P} = first(abs_inexact!(z, x, r))

function abs_inexact!(z::ArbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P}
    mode = _rnd(r)
    W = 2P + 4
    GC.@preserve x begin
        ar, ai = LibFlint.acf_real_ptr(x), LibFlint.acf_imag_ptr(x)
        _modulus_special!(z, ar, ai) && return z, false
        t1, t2, s_lo = ArbFloat{P}(), ArbFloat{P}(), ArbFloat{P}()
        _exact_squares!(t1, t2, ar, ai)
        if LibFlint.arf_add(s_lo, t1, t2, W, ARF_RND_DOWN) == 0           # sum exact: one rounding
            return z, LibFlint.arf_sqrt(z, s_lo, P, mode) != 0
        end
        s_hi, r_lo, probe = ArbFloat{P}(), ArbFloat{P}(), ArbFloat{P}()
        LibFlint.arf_add(s_hi, t1, t2, W, ARF_RND_UP)
        LibFlint.arf_sqrt(r_lo, s_lo, P, mode)
        LibFlint.arf_sqrt(z, s_hi, P, mode)                              # z = round(sqrt(s_hi))
        if LibFlint.arf_equal(r_lo, z) == 0
            # a rounding boundary b lies at sqrt(s_lo) (answer: the upper result) or sqrt(s_hi)
            if LibFlint.arf_sqrt(probe, s_lo, P + 1, ARF_RND_DOWN) != 0   # sqrt(s_lo) not exact in P+1 bits
                LibFlint.arf_set(z, r_lo)
            end
        end
        return z, true                                                    # s inexact => sqrt(s) is not a P-bit value
    end
end

function sqrt_inexact!(z::AcbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P}
    flag = LibFlint.acf_sqrt(z, x, P, _rnd(r))
    return z, flag != 0
end
sqrt!(z::AcbFloat{P}, x::AcbFloat{P}, r::RoundingMode = RoundNearest) where {P} = first(sqrt_inexact!(z, x, r))
Base.sqrt(x::AcbFloat{P}) where {P} = sqrt!(AcbFloat{P}(), x)

"Set `z` to `x` rounded at destination precision in a strict explicit mode; permits exact aliasing."
function set!(z::AcbFloat{P},x::AcbFloat,r::RoundingMode=RoundNearest) where {P}
    LibFlint.acf_set_round(z,x,P,_rnd(r))
    z
end
