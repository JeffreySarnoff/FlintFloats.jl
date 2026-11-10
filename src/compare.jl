# Equality, ordering, hashing (enact §8.1).
#
# Points (DFloat, NFloat, ArbFloat, AcbFloat) compare by exact represented value, across precisions,
# families and against Julia numbers. Balls compare by proof: `==`, `!=`, `<`, `<=`, `>`, `>=` are true
# only when the relation holds for every pair of points of the operands; `isequal` is a representation
# equivalence; balls have no `isless` (see `sortkey`).

const PointReal = Union{DFloat,NFloat,ArbFloat}
const SmallExact = Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64,Float16,Float32,Float64}
const BigExact = Union{Int128,UInt128,BigInt,BigFloat}
const ExactOther = Union{SmallExact,BigExact}
const RealOperand = Union{PointReal,ExactOther}
const BallReal = Union{DFloatBall,ArbBall}

# Fixed seeds mixed into hashes of values that are not plain real numbers.
const _H_IMAG = 0x32a7a07f3e7cd1f9 % UInt
const _H_BALL = 0x4b9ad0a1f5c3e2d7 % UInt

# ---- exact ArbFloat views --------------------------------------------------------------------------
# `_arf(x)` holds the exact value of `x` (never rounds). Scratch precisions are fixed per source type,
# or a multiple of 64 for Big numbers, to keep the number of compiled precisions small.

_arf(x::ArbFloat) = x
_arf(x::DFloat) = ArbFloat{2304}(x)                  # an expansion of doubles spans at most 2151 bits
_arf(x::NFloat{L}) where {L} = ArbFloat{64L}(x)
_arf(x::Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32}) = ArbFloat{64}(Int(x))
_arf(x::UInt64) = ArbFloat{64}(x)
_arf(x::Union{Float16,Float32,Float64}) = ArbFloat{53}(Float64(x))
_arf(x::Union{Int128,UInt128}) = _arf(big(x))
_arf(x::BigInt) = _arf_wide(x, max(2, ndigits(abs(x); base = 2)))
_arf(x::BigFloat) = _arf_wide(x, max(2, precision(x)))
_arf_wide(x, bits) = _arf_wide(x, Val(64 * cld(bits, 64)))
_arf_wide(x, ::Val{Q}) where {Q} = ArbFloat{Q}(x)

_big(x::ArbFloat{P}) where {P} = BigFloat(x; precision = P)
_big(x::Union{DFloat,NFloat}) = _big(_arf(x))

# ---- point comparison ------------------------------------------------------------------------------
# _cmp: -1, 0, 1, or 2 when unordered (a NaN is involved). arf_cmp returns 0 for NaN, so test first.

function _cmp(x::ArbFloat, y::ArbFloat)
    (LibFlint.arf_is_nan(x) != 0 || LibFlint.arf_is_nan(y) != 0) && return 2
    return Int(sign(LibFlint.arf_cmp(x, y)))
end
_cmp(x::PointReal, y::RealOperand) = _cmp(_arf(x), _arf(y))
_cmp(x::ExactOther, y::PointReal) = (c = _cmp(y, x); c == 2 ? 2 : -c)

# A Float zero may be negative; a FlintFloats point zero never is.
_negzero(y) = y isa AbstractFloat && iszero(y) && signbit(y)

_eq(x, y) = _cmp(x, y) == 0
_lt(x, y) = _cmp(x, y) == -1
_le(x, y) = (c = _cmp(x, y); c == -1 || c == 0)
function _isequal(x, y)
    c = _cmp(x, y)
    c == 2 && return isnan(x) && isnan(y)
    return c == 0 && !(_negzero(x) || _negzero(y))
end
# Total order, NaN last, -0.0 below 0.0 (as Float64).
function _isless(x, y)
    c = _cmp(x, y)
    c == 2 && return !isnan(x) && isnan(y)
    c == 0 && return _negzero(x) && !_negzero(y)
    return c == -1
end

for (A, B) in ((PointReal, PointReal), (PointReal, ExactOther), (ExactOther, PointReal))
    @eval begin
        Base.:(==)(x::$A, y::$B) = _eq(x, y)
        Base.:(<)(x::$A, y::$B) = _lt(x, y)
        Base.:(<=)(x::$A, y::$B) = _le(x, y)
        Base.isequal(x::$A, y::$B) = _isequal(x, y)
        Base.isless(x::$A, y::$B) = _isless(x, y)
    end
end

Base.hash(x::PointReal, h::UInt) = hash(_big(x), h)

# ---- AcbFloat ----------------------------------------------------------------------------------------

Base.:(==)(z::AcbFloat, w::AcbFloat) = real(z) == real(w) && imag(z) == imag(w)
Base.:(==)(z::AcbFloat, r::RealOperand) = iszero(imag(z)) && real(z) == r
Base.:(==)(r::RealOperand, z::AcbFloat) = z == r
Base.isequal(z::AcbFloat, w::AcbFloat) = isequal(real(z), real(w)) && isequal(imag(z), imag(w))
Base.isequal(z::AcbFloat, r::RealOperand) = iszero(imag(z)) && isequal(real(z), r)
Base.isequal(r::RealOperand, z::AcbFloat) = isequal(z, r)

# A complex value with zero imaginary part hashes as its real part, so isequal(z, real) agrees with hash.
function Base.hash(z::AcbFloat, h::UInt)
    i = imag(z)
    return iszero(i) ? hash(real(z), h) : hash(real(z), hash(i, h ⊻ _H_IMAG))
end

# ---- ArbBall -----------------------------------------------------------------------------------------
# Operands that are not an ArbBall become an exact scratch ball first, so a point is never widened.

_ball(x::ArbBall) = x
function _ball(x::ArbFloat{Q}) where {Q}
    z = ArbBall{Q}()                                 # scratch: holds exactly `x`, never escapes
    LibFlint.arb_set_arf(z, x)
    return z
end
_ball(x::Union{DFloat,NFloat,ExactOther}) = _ball(_arf(x))
_ball(x::DFloatBall) = _arbball(x)

for (op, f) in ((:(==), :arb_eq), (:(!=), :arb_ne), (:(<), :arb_lt), (:(<=), :arb_le),
                (:(>), :arb_gt), (:(>=), :arb_ge))
    @eval begin
        Base.$op(x::ArbBall, y::ArbBall) = LibFlint.$f(x, y) != 0
        Base.$op(x::ArbBall, y::RealOperand) = $op(x, _ball(y))
        Base.$op(x::RealOperand, y::ArbBall) = $op(_ball(x), y)
    end
end

# Every indeterminate ball (NaN midpoint or infinite radius) is the one value "no information".
function Base.isequal(x::ArbBall, y::ArbBall)
    (isindeterminate(x) || isindeterminate(y)) && return isindeterminate(x) && isindeterminate(y)
    return LibFlint.arb_equal(x, y) != 0
end
# The indeterminate ball is not a number (not even NaN): it is isequal only to other balls.
Base.isequal(x::ArbBall, y::RealOperand) = !isindeterminate(x) && isexact(x) && isequal(midpoint(x), y)
Base.isequal(x::RealOperand, y::ArbBall) = isequal(y, x)

# An exact ball hashes as its midpoint, so it agrees with the point and the Julia number it equals.
function Base.hash(x::ArbBall, h::UInt)
    isindeterminate(x) && return hash(NaN, h ⊻ _H_BALL)
    isexact(x) && return hash(midpoint(x), h)
    return hash(midpoint(x), hash(radius(x), h ⊻ _H_BALL))
end

# ---- AcbBall -----------------------------------------------------------------------------------------

_acb(z::AcbBall) = z
function _acb(z::AcbFloat{Q}) where {Q}
    w = AcbBall{Q}()
    LibFlint.acb_set_arb_arb(w, _ball(real(z)), _ball(imag(z)))
    return w
end
function _acb(x::Union{ArbBall,DFloatBall,RealOperand})
    b = _ball(x)
    w = AcbBall{precision(b)}()
    LibFlint.acb_set_arb(w, b)
    return w
end

for (op, f) in ((:(==), :acb_eq), (:(!=), :acb_ne))
    @eval begin
        Base.$op(z::AcbBall, w::AcbBall) = LibFlint.$f(z, w) != 0
        Base.$op(z::AcbBall, w::Union{AcbFloat,ArbBall,DFloatBall,RealOperand}) = $op(z, _acb(w))
        Base.$op(w::Union{AcbFloat,ArbBall,DFloatBall,RealOperand}, z::AcbBall) = $op(_acb(w), z)
    end
end
# A point complex value against a ball: promote the point to an exact ball.
for op in (:(==), :(!=))
    @eval begin
        Base.$op(z::AcbFloat, w::Union{ArbBall,DFloatBall}) = $op(_acb(z), w)
        Base.$op(w::Union{ArbBall,DFloatBall}, z::AcbFloat) = $op(w, _acb(z))
    end
end
Base.isequal(z::AcbFloat, w::Union{ArbBall,DFloatBall}) = !isnan(z) && isequal(_acb(z), w)
Base.isequal(w::Union{ArbBall,DFloatBall}, z::AcbFloat) = isequal(z, w)

function Base.isequal(z::AcbBall, w::AcbBall)
    return isequal(real(z), real(w)) && isequal(imag(z), imag(w))
end
# Ball against a point or number: the indeterminate ball never equals one. Ball against ball: as arb.
Base.isequal(z::AcbBall, w::Union{AcbFloat,RealOperand}) = !isindeterminate(z) && isequal(z, _acb(w))
Base.isequal(w::Union{AcbFloat,RealOperand}, z::AcbBall) = isequal(z, w)
Base.isequal(z::AcbBall, w::Union{ArbBall,DFloatBall}) = isequal(z, _acb(w))
Base.isequal(w::Union{ArbBall,DFloatBall}, z::AcbBall) = isequal(z, w)

function Base.hash(z::AcbBall, h::UInt)
    i = imag(z)
    return isexact(i) && iszero(i) ? hash(real(z), h) : hash(real(z), hash(i, h ⊻ _H_IMAG))
end

# ---- DFloatBall --------------------------------------------------------------------------------------
# Against another DFloatBall: dNb_equal and dNb_overlaps for == and !=, exact endpoints for the order
# (after padding to a common N; FLINT's dNb_cmp is used only as a test cross-check). Against anything
# else: the exact ArbBall enclosure of the dfloat ball (its radius is rounded up to a 30-bit magnitude,
# so such comparisons are sound but may miss a proof for balls that touch).

_mid(x::DFloatBall{N}) where {N} = DFloat{N}(x.d)

# Pad an N-double ball to M >= N doubles (exact: trailing zeros extend an expansion).
function _widen(x::DFloatBall{N}, ::Val{M}) where {N,M}
    return DFloatBall{M}((x.d..., ntuple(_ -> 0.0, M - N)...), x.rad)
end
_common(x::DFloatBall{N}, y::DFloatBall{M}) where {N,M} =
    N == M ? (x, y) : N < M ? (_widen(x, Val(M)), y) : (x, _widen(y, Val(N)))

for N in 1:4
    getarb = Symbol("d", N, "b_get_arb")
    cmpf = Symbol("d", N, "b_cmp")
    eqf = Symbol("d", N, "b_equal")
    ovf = Symbol("d", N, "b_overlaps")
    cf = Symbol("d", N, "b_contains")
    @eval begin
        function _arbball(x::DFloatBall{$N})
            z = ArbBall{2304}()                               # scratch enclosure, never escapes
            LibFlint.$getarb(z, Ref(x))
            return z
        end
        # (status success ? sign : 2): the sign when every pair of points compares the same way
        function _dcmp(x::DFloatBall{$N}, y::DFloatBall{$N})
            res = Ref{Cint}(0)
            st = LibFlint.$cmpf(res, Ref(x), Ref(y))
            return st == GR_SUCCESS ? Int(res[]) : 2
        end
        _deq(x::DFloatBall{$N}, y::DFloatBall{$N}) = LibFlint.$eqf(Ref(x), Ref(y)) != 0
        overlaps(x::DFloatBall{$N}, y::DFloatBall{$N}) = LibFlint.$ovf(Ref(x), Ref(y)) != 0
        Base.contains(x::DFloatBall{$N}, y::DFloatBall{$N}) = LibFlint.$cf(Ref(x), Ref(y)) != 0
    end
end

# Exact endpoints mid ± rad as ArbFloat{2304} scratch values (the span of an expansion plus a radius
# fits). Ball order is decided on these, so touching balls are handled exactly: x <= y is proved when
# upper(x) <= lower(y), x < y when upper(x) < lower(y). The whole real line proves nothing.
function _ends(x::DFloatBall)
    m = _arf(_mid(x))
    r = ArbFloat{2304}(x.rad)
    lo, hi = ArbFloat{2304}(), ArbFloat{2304}()
    LibFlint.arf_sub(lo, m, r, ARF_PREC_EXACT, ARF_RND_NEAR)
    LibFlint.arf_add(hi, m, r, ARF_PREC_EXACT, ARF_RND_NEAR)
    return lo, hi
end

function _dorder(x::DFloatBall, y::DFloatBall)     # (strictly below, below or touching)
    (isfinite(x) && isfinite(y)) || return false, false
    a, b = _common(x, y)
    _, xhi = _ends(a)
    ylo, _ = _ends(b)
    c = _cmp(xhi, ylo)
    return c == -1, c == -1 || c == 0
end

Base.:(==)(x::DFloatBall, y::DFloatBall) = _deq(_common(x, y)...)
Base.:(!=)(x::DFloatBall, y::DFloatBall) = !overlaps(_common(x, y)...)         # proved disjoint
Base.:(<)(x::DFloatBall, y::DFloatBall) = first(_dorder(x, y))
Base.:(<=)(x::DFloatBall, y::DFloatBall) = last(_dorder(x, y))
Base.:(>)(x::DFloatBall, y::DFloatBall) = first(_dorder(y, x))
Base.:(>=)(x::DFloatBall, y::DFloatBall) = last(_dorder(y, x))

for op in (:(==), :(!=), :(<), :(<=), :(>), :(>=))
    @eval begin
        Base.$op(x::DFloatBall, y::Union{ArbBall,RealOperand}) = $op(_arbball(x), y)
        Base.$op(x::Union{ArbBall,RealOperand}, y::DFloatBall) = $op(x, _arbball(y))
    end
end

function Base.isequal(x::DFloatBall, y::DFloatBall)
    (!isfinite(x) || !isfinite(y)) && return !isfinite(x) && !isfinite(y)     # the whole real line
    return isequal(_mid(x), _mid(y)) && x.rad == y.rad
end
Base.isequal(x::DFloatBall, y::RealOperand) = isexact(x) && isequal(_mid(x), y)
Base.isequal(x::RealOperand, y::DFloatBall) = isequal(y, x)
# Two balls: the whole real line is the one indeterminate value; otherwise compare the enclosures.
function Base.isequal(x::DFloatBall, y::ArbBall)
    isfinite(x) || return isindeterminate(y)
    isindeterminate(y) && return false
    return isequal(_arbball(x), y)
end
Base.isequal(x::ArbBall, y::DFloatBall) = isequal(y, x)

function Base.hash(x::DFloatBall, h::UInt)
    isfinite(x) || return hash(NaN, h ⊻ _H_BALL)
    isexact(x) && return hash(_mid(x), h)
    return hash(_mid(x), hash(x.rad, h ⊻ _H_BALL))
end

# ---- balls have no numerical order -------------------------------------------------------------------

const _NOORDER = "balls have no numerical order: use <, <=, >, >= for a proof, or sort with `by = FlintFloats.sortkey`"
# Each pair is as narrow as Base's own isless methods so these are never ambiguous with them.
for (A, B) in ((BallReal, BallReal), (BallReal, AbstractFloat), (AbstractFloat, BallReal),
               (BallReal, Real), (Real, BallReal))
    @eval Base.isless(::$A, ::$B) = throw(ArgumentError(_NOORDER))
end

# Base's min/max for a pair of the same AbstractFloat type do not go through isless.
for f in (:min, :max, :minmax)
    @eval Base.$f(::T, ::T) where {T<:BallReal} = throw(ArgumentError(_NOORDER))
end

"""
    sortkey(x)

A deterministic key for presenting balls in a stable order: `(midpoint, radius)`, compared as points
(NaN last). It carries no numerical meaning; use it as `sort(v; by = FlintFloats.sortkey)`.
"""
sortkey(x::DFloatBall) = (_mid(x), x.rad)
sortkey(x::ArbBall) = (midpoint(x), radius(x))
sortkey(z::AcbBall) = (sortkey(real(z)), sortkey(imag(z)))
