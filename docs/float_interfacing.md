# Uniform Julia interface to FLINT floats

Companion to [plan_interfacing.md](plan_interfacing.md) and [enact_interfacing.md](enact_interfacing.md). Those say how to build and verify the binding layer. This document specifies the **one Julia-facing interface** over the seven public types, then reviews that design for clarity, concision and performance.

**Families and names (settled).** Each FLINT family has a point type and, where FLINT provides one, a ball (enclosure) type with the same parameter. Point types end in `Float`, ball types end in `Ball`:

| FLINT family | Point type | Ball type | Parameter |
| --- | --- | --- | --- |
| dfloat (`dN`, `dNb`) | `DFloat{N}` | `DFloatBall{N}` | `N` doubles, 1..4 |
| nfloat | `NFloat{L}` | none | `L` limbs |
| arb, real (`arf`, `arb`) | `ArbFloat{P}` | `ArbBall{P}` | `P` bits |
| arb, complex (`acf`, `acb`) | `AcbFloat{P}` | `AcbBall{P}` | `P` bits |

**Precision is a type parameter for every type** (see §6.3 and §8 for the trade-offs). `ArbFloat`/`AcbFloat` wrap FLINT's `arf`/`acf` (correctly rounded floating point, no error bounds); `ArbBall`/`AcbBall` wrap `arb`/`acb`. `mag` stays private. Complex dfloat (`dNc`, `dNcb`, would be `DFloatComplex`/`DFloatComplexBall`) and complex nfloat are deferred.

Facts marked *(docs)* come from the FLINT 3.7.0-dev dfloat pages (index, `balls`, `d1b_struct`, `d1cb_struct`, `DFLOAT_BALL`, `using`, `d1b_add`, `d1b_is_exact`). Those pages say parts of their text were LLM-generated; confirm against `src/dfloat.h` before binding. Facts marked *(pinned docs)* come from the Markdown documentation shipped in the pinned source tree (`doc/src/arf`, `doc/src/acf`), read locally. Facts marked *(checked)* were read from the local build at `/tmp/flintfloats-jll-build/install` (FLINT 3.7.0-dev, source `82c40b29…`, ABI 25). Availability is recorded in [capability_table.md](capability_table.md); proposed surfaces below are not implementation claims. M0–M3 and M4a–M4c are implemented, including `NFloatWorkspace`, `PackedBallVector`, and explicit `BorrowedBall` references. The copied-read documentation and `eachborrow` follow-up is implemented. Flat in-place broadcast (§9.4.3, first step) is implemented. Bounded nested broadcast is implemented; borrowed sum is next, followed by M4d dot products.

## 1. What "uniform" means

Uniform = a caller writes the same code for any family and gets correct, family-appropriate results, **without** a common storage model. Precisely:

1. Same constructors, same operators, same `precision`, `zero/one`, predicates, conversion and display.
2. Destination-first operations for mutable scalar owners and vector buffers; ordinary arithmetic for immutable scalars.
3. Differences in guarantee (point vs enclosure) are visible through **traits**, not hidden and not forced into one semantics.
4. The proposed shared internal protocol (§4) is a future factoring target; current family implementations carry those responsibilities.

Non-goals: one rounding mode, one storage representation, one precision model, or `AcbBall` pretending to be `Real`.

## 2. Public surface

### 2.1 Types and hierarchy

Naming rule: **point types end in `Float`, ball types end in `Ball`**, and a point type and its ball share one parameter. `FlintReal` covers every real type, point or ball; the two complex types are `<: Number`.

```julia
abstract type FlintReal <: AbstractFloat end      # every real type

struct  DFloat{N}  <: FlintReal  d::NTuple{N,Float64} end          # N = 1..4, ~53N bits
struct  DFloatBall{N}   <: FlintReal  d::NTuple{N,Float64}; rad::Float64 end  # real ball: midpoint + double radius
struct  NFloat{L}  <: FlintReal  exp::Int; sign::Int; d::NTuple{L,UInt} end   # prec = 64L bits
mutable struct ArbFloat{P} <: FlintReal ... end   # arf: correctly rounded float, P bits, owns heap data
mutable struct ArbBall{P}  <: FlintReal ... end   # arb: real ball, P bits
mutable struct AcbFloat{P} <: Number    ... end   # acf: complex float (two arf parts), P bits
mutable struct AcbBall{P}  <: Number    ... end   # acb: complex ball (two arb parts), P bits

const FlintComplex = Union{AcbFloat, AcbBall}
const FlintNumber  = Union{FlintReal, FlintComplex}   # for methods shared by all types
```

- `AbstractFloat <: Real`, so the complex types `AcbFloat` and `AcbBall` are `<: Number` (`AcbFloat` is a complex floating-point number, not an `AbstractFloat`, despite the suffix); `FlintNumber` is the shared dispatch point (Julia has no multiple inheritance).
- **`NFloat{L}` takes the limb count, not bits.** `precision(NFloat{L}) = 64L`. The `exp/sign/d` fields mirror `NFLOAT_HEADER_LIMBS = 2` plus `L` limbs *(checked: header = 2 limbs, 1–66 limbs on this build)*. This replaces the `NFloat{P,L}` prototype in enact §3.1: one parameter, no P/L consistency check, every `NFloat{L}` is concrete, so `Vector{NFloat{2}}` is a packed array. Users think in bits, so provide `NFloatType(bits)` (returns `NFloat{bits÷64}`, errors if not a supported multiple) and aliases `const NFloat128 = NFloat{2}`, etc.
- **`ArbFloat{P}`, `ArbBall{P}`, `AcbFloat{P}`, `AcbBall{P}`: `P` is the working precision in bits** (`P` an `Int`, validated against the C minimum and `slong` range at construction, e.g. `ArbBall{256}`). Precision then reads the same way on every family: `precision(T)` is a constant for `DFloat{N}` (`53N`), `NFloat{L}` (`64L`), and the four arb types (`P`). The unit of the parameter differs by family (doubles, limbs, bits) because `DFloat` and `NFloat` need it for storage size; `precision(T)` and `withprec` (below) hide that.
- `ArbBall` and `AcbBall` without a parameter are abstract `UnionAll` types used for dispatch. The constructors `ArbBall(x)` and `AcbBall(x)` return `ArbBall{DEFAULT_PRECISION}` / `AcbBall{DEFAULT_PRECISION}`, with `DEFAULT_PRECISION` a compile-time constant (256, overridable through a package preference read at precompilation). The same holds for `ArbFloat(x)` and `AcbFloat(x)`. This keeps the constructors type-stable; there is **no scoped runtime default precision** (see §6.3).
- **Dynamic precision** (adaptive algorithms) uses a function barrier: `with_precision(f, bits)` calls `f(Val(bits))`, so a method taking `::Val{P}` is compiled per precision and runs without dynamic dispatch inside. `ArbBall{p}(x)` with a runtime `p` is allowed but type-unstable at that call.
- **Uniform precision adapter:** `withprec(x, bits)` returns a value of the same family holding `x` at (at least) `bits` of precision: `DFloat{cld(bits,53)}`, `DFloatBall{cld(bits,53)}` (same family keeps point vs ball), `NFloat{cld(bits,64)}`, `ArbFloat{bits}`, `ArbBall{bits}`, `AcbFloat{bits}`, `AcbBall{bits}`. `withprec(T, bits)` returns the type.
- **`ArbFloat{P}`** wraps `arf`: arbitrary-precision binary floating point, **correctly rounded** in the strict rounding modes, with an unbounded exponent (no overflow or underflow), no negative zero, and an explicit rounding mode per operation *(pinned docs)*. **`AcbFloat{P}`** wraps `acf`: a pair of `arf` parts without error bounds. Details in §2c.
- **Precision invariant.** Every `ArbFloat{P}` value, each part of an `AcbFloat{P}`, and the midpoint of every `ArbBall{P}`/`AcbBall{P}` has a mantissa of at most `P` bits. FLINT does not enforce this itself (`arf_set`, `arb_set_fmpz` and other exact setters keep every bit), so constructors and conversions round with `arf_set_round`/`arb_set_round`, and arithmetic passes `P`. Consequence: `midpoint(::ArbBall{P})` is exactly an `ArbFloat{P}`.
- **Pairing functions** make the grid navigable in generic code: `pointtype(T)`, `balltype(T)`, `realtype(T)`, `complextype(T)`. Examples: `balltype(DFloat{N}) === DFloatBall{N}`, `balltype(ArbFloat{P}) === ArbBall{P}`, `pointtype(AcbBall{P}) === AcbFloat{P}`, `realtype(AcbBall{P}) === ArbBall{P}`, `complextype(ArbFloat{P}) === AcbFloat{P}`. A missing cell is a `MethodError` (`balltype(NFloat{L})`, `complextype(DFloat{N})` in v1). They define the return types of `midpoint`, `radius`, `abs`, `real`, `imag` by one rule (§2a.5).
- `DFloat{1}` is a plain double. Keep it a distinct type for uniformity, but make its arithmetic *native* (no foreign call).
- **`DFloatBall{N}`** mirrors FLINT's `dNb_struct` (`double d[N]` midpoint, `double rad` radius) *(docs)*: an isbits, finalizer-free enclosure of every `x` with `|x - mid| <= rad`, size `8(N+1)` bytes. It is the only type that is both an **enclosure** and **inline**, so the `Guarantee` and `Storage` traits (§2.3) are genuinely independent. Details in §2b.
- Complex dfloat (`dNc`), complex dfloat balls (`dNcb` = two `dNb`, `re` and `im`), and complex nfloat (`nfloat_complex_*` is exported *(checked)*) are not public in v1; the protocol (§4) and the pairing functions admit them later.

### 2.2 Interface table

Every row works on all seven types unless stated.

| Concern | Interface | Notes |
| --- | --- | --- |
| Construct | `T(x)` for any concrete `T`; `ArbFloat(x)`, `ArbBall(x)`, `AcbFloat(x)`, `AcbBall(x)` = default precision; `parse(T, s)` | Precision comes from `T`. No `precision=` keyword. |
| Precision | `precision(x)`, `precision(T)` | `53N`, `64L`, `P`. Not a certificate of correct digits. Constant per type. |
| Change precision | `withprec(x, bits)`, `withprec(T, bits)`, `with_precision(f, bits)` | Returns another concrete type; `with_precision` is the function barrier for dynamic precision. |
| Arithmetic | `+ - * /`, `inv`, `sqrt`, `abs`, `abs2`, `muladd`, `fma` | `abs` of a complex value returns `realtype(T)`. |
| Rounding mode | trailing `RoundingMode` on `ArbFloat`/`AcbFloat` operations: `add!(z, x, y, RoundUp)`, `sqrt(x, RoundDown)` | Operators use `RoundNearest` (ties to even). Other families: `ArgumentError` for any mode but the default. |
| Pairing | `pointtype(T)`, `balltype(T)`, `realtype(T)`, `complextype(T)` | Navigate the type grid; `MethodError` where no such type exists. |
| Elementary | `exp log sin cos tan atan sinh cosh tanh …` | Per-family inventory table; unsupported → `MethodError`, never a `BigFloat` fallback. |
| Destination | `z = add!(z, x, y)`, `sub!`, `mul!`, `div!`, `addmul!`, `neg!`, `set!` | **Always rebind the result** (§3). |
| Identities | `zero(x)`, `one(x)`, `zero(T)`, `one(T)` | Concrete `T` fixes the precision; `zero(ArbBall)` = `ArbBall{DEFAULT_PRECISION}`. |
| Predicates | `isnan isinf isfinite iszero isone signbit` | |
| Compare | point: `== < <= isless isequal` as for `Float64`. Ball: proven relations (enact §8.1) | See traits below. |
| Enclosure only | `midpoint`, `radius`, `contains(x,y)`, `overlaps(x,y)`, `isexact` | `DFloatBall`, `ArbBall`, `AcbBall` only. Not defined on point types (§6.1). `midpoint(x)` is a `pointtype(T)`; `radius(::DFloatBall)` is a `Float64`, `radius` of an arb ball an `ArbFloat{P}`. |
| Complex only | `real imag conj reim` | `AcbFloat`, `AcbBall` (parts are `realtype(T)`); `real/imag` also give `x`/`zero(x)` on real families. |
| Convert | `convert`, explicit `Float64(x)`, `BigFloat(x)`, `Int(x)` | Nonsingleton ball → point is an error; use `midpoint`. |
| Display | `show`, `string`, `repr` | Balls show uncertainty. |
| Containers | `flintzeros(T,n)`, `flintvec(T, itr)` | Return `Vector{T}` for inline types, `PackedVector{T}` for owned types (§5). `T` is concrete. |

### 2.3 Traits (the only place families differ openly)

```julia
abstract type Guarantee end;  struct Point <: Guarantee end;  struct Enclosure <: Guarantee end
abstract type Storage   end;  struct Inline <: Storage end;   struct Owned <: Storage end

guarantee(::Type{<:Union{DFloat,NFloat,ArbFloat,AcbFloat}}) = Point()
guarantee(::Type{<:Union{DFloatBall,ArbBall,AcbBall}})      = Enclosure()
storage(::Type{<:Union{DFloat,DFloatBall,NFloat}})          = Inline()
storage(::Type{<:Union{ArbFloat,AcbFloat,ArbBall,AcbBall}}) = Owned()
```

Public generic code branches on these (`guarantee(T) isa Enclosure`), not on concrete types. Two traits, no more. The grid:

| | Inline (value return, no finalizer) | Owned (in-place, finalizer) |
| --- | --- | --- |
| **Point** | `DFloat{N}`, `NFloat{L}` | `ArbFloat{P}`, `AcbFloat{P}` |
| **Enclosure** | `DFloatBall{N}` | `ArbBall{P}`, `AcbBall{P}` |

Every cell is occupied. Among point types the numerical contract still differs, and the capability table (§2a.10) records it per operation: `ArbFloat`/`AcbFloat` are correctly rounded, `DFloat` is accurate to a few ulps, `NFloat` depends on operation and context flags.

## 2a. API in detail

Specification of the public interface, as proposed Julia signatures. None of it exists yet. Notation: `T` is any concrete public type (`DFloat{N}`, `DFloatBall{N}`, `NFloat{L}`, `ArbFloat{P}`, `ArbBall{P}`, `AcbFloat{P}`, `AcbBall{P}`); `R` is a real type (`T <: FlintReal`); `B` is a ball (`DFloatBall{N}`, `ArbBall{P}` or `AcbBall{P}`); a *point type* is `DFloat`, `NFloat`, `ArbFloat` or `AcbFloat`. "Inventory" means availability depends on the FLINT function inventory (enact §5.1); anything not in the inventory is a `MethodError`.

### 2a.1 Construction

```julia
DFloat{N}(x::Union{Integer,Float64,Rational,BigFloat,AbstractString})
NFloat{L}(x::Union{Integer,Float64,Rational,BigFloat,AbstractString})
DFloatBall{N}(x)                       # encloses x; accepts Integer, Float64, Rational, BigFloat, String, DFloat{N}, ArbBall
DFloatBall{N}(mid, rad::Real)          # ball(mid, rad); mid::Union{Float64,DFloat{N}}
ArbFloat{P}(x[, r::RoundingMode])   ArbFloat(x) === ArbFloat{DEFAULT_PRECISION}(x)   # arf: rounded to P bits
ArbBall{P}(x)                       ArbBall(x)  === ArbBall{DEFAULT_PRECISION}(x)    # arb: encloses x
AcbFloat{P}(re, im = 0[, r])        AcbFloat(re, im = 0) === AcbFloat{DEFAULT_PRECISION}(re, im)   # acf
AcbBall{P}(re, im = 0)              AcbBall(re, im = 0)  === AcbBall{DEFAULT_PRECISION}(re, im)    # acb
NFloatType(bits::Integer) :: Type{<:NFloat}          # NFloatType(128) === NFloat{2}
withprec(T, bits)  withprec(x, bits)                # uniform: same family at >= bits
```

| Rule | Detail |
| --- | --- |
| Rounding on construction (points) | Nearest for integers/`Float64`/`Rational`/`BigFloat`/strings, via FLINT conversion. Exact request: `T(x; exact=true)` throws `InexactError` if `x` is not representable. |
| Construction of `DFloatBall{N}` | Integers/`Float64` exact (rad 0) when they fit in `N` doubles; else rounded to `N` doubles with the discarded tail added to `rad` *(docs: `dNb_set_*`)*. `DFloat{N}` → `DFloatBall{N}` is exact (rad 0). `Rational`/`BigFloat`/strings go through `arb` at `53N+64` bits and then round into `N` doubles plus radius. Nonfinite input gives the whole real line (below), not an error; invalid decimal text still throws `ArgumentError`. `DFloatBall{N}(mid, rad)`: whole real line if `mid`/`rad` is nonfinite or `rad < 0`. |
| Construction of `ArbFloat{P}`/`AcbFloat{P}` | `x` rounded **once** to `P` bits, to nearest (ties to even) unless a `RoundingMode` is given; correctly rounded for integers, `Float64`, `BigFloat`, `Rational` and decimal strings. `Float64`/integers that fit in `P` bits are exact. `-0.0` becomes `0` (`arf` has no negative zero) *(pinned docs)*. From a ball: only `ArbFloat{P}(midpoint(b))`, never implicitly. |
| Construction of balls | Midpoint rounded to `P` bits with the rounding error added to the radius (precision invariant, §2.1). Result **contains** `x`'s value. Integers and `Float64` give radius 0 when representable at the working precision, otherwise a nonzero radius. `Rational` and strings give an enclosure. |
| Strings | Parsed directly at the destination format/precision, never through `Float64`. Ball strings accept `"1.25"` (enclosing the decimal) and `"[1.25 +/- 0.01]"`. Invalid text throws `ArgumentError`. |
| Special values | `NaN`, `±Inf` accepted for points only if the family's context flags allow them (enact §7.2); balls represent them as indeterminate/unbounded enclosures. Otherwise `DomainError`. |
| Precision | Always the type parameter: `ArbBall{128}(x)`. There is no `precision=` keyword (an unexpected keyword is a `MethodError`). `P` must be an integer ≥ the FLINT minimum and fit the C `slong`, checked once when the type is instantiated (`ArgumentError` otherwise). Bits not a multiple of 64 are allowed; recommend multiples of 64 to limit the number of distinct types. |
| No-arg forms | `ArbFloat{P}()`, `AcbFloat{P}()`, `ArbBall{P}()`, `AcbBall{P}()`, `DFloatBall{N}()` = exact zero. `DFloat{N}()`, `NFloat{L}()` = zero. |
| Complex | `AcbFloat{P}(z::Complex)`, `AcbFloat{P}(x::Real)`, and the same for `AcbBall{P}`; `Complex{Float64}(z::AcbFloat)` rounds each part; `Complex{<:Real}(z::AcbBall)` is an explicit narrowing and requires singleton parts, else `InexactError`. |
| Copy | `copy(x)` independent for owned types, identity for inline types. `deepcopy` supported for owned types through FLINT copy. |

Errors: `ArgumentError` (bad precision parameter, bad string, bad option), `InexactError` (exact conversion impossible), `DomainError` (nonfinite not supported).

### 2a.2 Precision

```julia
precision(x)::Int ;  precision(::Type{T})::Int      # constant for every concrete T
DEFAULT_PRECISION                                    # 256, compile-time preference
withprec(T, bits)::Type ;  withprec(x, bits)::value  # uniform change of precision
with_precision(f, bits)                              # f(Val(bits)); function barrier
```

| Family | `precision(T)` |
| --- | --- |
| `DFloat{N}` | `53N` (nominal; relative accuracy is operation dependent) |
| `DFloatBall{N}` | `53N` (midpoint expansion; the radius tracks actual accuracy) |
| `NFloat{L}` | `64L` |
| `ArbFloat{P}`, `ArbBall{P}`, `AcbFloat{P}`, `AcbBall{P}` | `P` |

Rules for balls (enact §7.1, adapted to a type-level precision): result precision is determined by the argument **types**. Unary ops keep `P`; binary ops of `ArbBall{P}`, `ArbBall{Q}` give `ArbBall{max(P,Q)}`, by promotion (the same rule holds for `ArbFloat`, `AcbFloat` and `AcbBall`); destination ops use the destination's `P`. An operation-level `prec=` override on a `!` operation changes the work for that call, not the destination's type. Mixed arithmetic with integers/`Float64` keeps the ball's `P`.

`DEFAULT_PRECISION` is independent of `BigFloat`. It is a compile-time constant read from a package preference, so changing it requires recompilation; there is no `setprecision`. **Why:** a runtime default would make `ArbBall(x)`'s return type depend on runtime state (type-unstable). If scoped defaults are wanted later, the unparameterised constructor can become explicitly dynamic and documented as such.

Dynamic (adaptive) precision:

```julia
# The body is a method on Val{P}: compiled once per P, no dynamic dispatch inside.
refine(::Val{P}, input) where {P} = begin
    x = ArbBall{P}(input)
    ...                                         # all arithmetic is concretely typed
    radius(x)
end

for bits in (64, 128, 256, 512)
    rad = with_precision(v -> refine(v, input), bits)   # one dynamic dispatch per precision
    rad < tol && break
end
```

Changing a value's precision: `ArbBall{Q}(x)` or `withprec(x, Q)` returns a new ball containing `x`. Increasing precision does not reduce the radius. Every new `P` costs compilation of the methods used; limit the set of precisions in adaptive loops (powers of 2 or multiples of 64).

### 2a.3 Arithmetic and mathematical functions

Operators (all `T`, same-type operands; mixed and promotion in §2a.8):

```julia
+x  -x  x+y  x-y  x*y  x/y  inv(x)  x^n   (n::Integer; also x^y for R, AcbBall inventory)
abs(x)  abs2(x)  sqrt(x)  muladd(x,y,z)  fma(x,y,z)  hypot(x,y)  sign(x)  copysign(x,y)
ldexp(x, n::Integer)               # x * 2^n, exact
```

- `abs(z)` and `abs2(z)` of a complex value return `realtype(T)`: `abs(::AcbBall{P})::ArbBall{P}`, `abs(::AcbFloat{P})::ArbFloat{P}`. `sqrt` of a complex value is the principal branch. `sqrt(x::R)` for negative `x`: `DomainError` for points; for balls, `DomainError` only if the ball is wholly negative, otherwise the FLINT-defined enclosure (documented per function).
- `fma` for points uses the family's fused kernel only if the inventory shows one; otherwise it is `muladd` and documented as not fused. For balls both enclose the exact result.
- **`ArbFloat`/`AcbFloat` rounding** *(pinned docs)*: `+ - *` are correctly rounded; `/`, `sqrt`, `inv` and the elementary functions are correctly rounded in the strict modes (`RoundNearest`, `RoundToZero`, `RoundFromZero`, `RoundUp`, `RoundDown`, mapping to `ARF_RND_NEAR/DOWN/UP/CEIL/FLOOR`); complex results are correctly rounded in each part (`acf_add/sub/mul`, `acf_div`, `acf_sqrt`, `acf_exp`, ...). The wrapper uses the strict modes only, so results are reproducible and comparable bit for bit with MPFR at the same precision and mode. FLINT's relaxed modes (`ARF_RND_FAST`, 1 ulp; `ARF_RND_ACCURATE`, 0.51 ulp) and the `acf_approx_*` functions are faster but not correctly rounded; exposing them is a later opt-in (§8).
- Division by zero: `ArbFloat` returns `NaN` for `x/0` with `x` nonzero (there is no signed zero to choose the sign of an infinity) *(pinned docs)*; this differs from `Float64`. Other points follow the family's special-value policy (`±Inf` or `DomainError` depending on context flags); balls return an indeterminate enclosure, never an exception, when the divisor contains zero but is not exactly zero; exactly zero divisor gives `DomainError`.

Elementary functions (inventory-driven; the planned set):

| Group | Functions | Families |
| --- | --- | --- |
| Exp/log | `exp expm1 log log1p log2 log10` | all real; `AcbBall` for `exp log` |
| Trig | `sin cos tan asin acos atan sincos` ; `atan(y,x)` | all real; `AcbBall` for `sin cos tan` |
| Hyperbolic | `sinh cosh tanh` | all real; `AcbBall` for `sinh cosh tanh` |
| Power/root | `x^y`, `cbrt` | inventory |
| Rounding | `floor ceil round trunc` | points; balls return an enclosure of the integer-valued function, which is a singleton only if the ball does not straddle a boundary (else indeterminate-integer enclosure) |
| Constants | `ArbBall(π)`, `ArbBall(ℯ)`, `ArbBall(MathConstants.γ)`, `ArbBall(MathConstants.catalan)` at the requested precision | balls: rigorous; points: `T(π)` rounds |

Accuracy of function results is stated per function in the capability table (generated, §2a.10): correctly rounded (`ArbFloat`, `AcbFloat`), error bound `k·2^-prec` (from FLINT's `DFLOAT_*_EPS_N`-style constants for `dfloat`), or enclosure. Trig on `dfloat` has absolute (not relative) error near zeros of sin/cos; the table says so.

Unsupported function or family combination: `MethodError`. No `BigFloat` fallback.

### 2a.4 Destination-passing (`!`) API

Scalar destination methods exist for the four mutable owned types and are qualified as
`FlintFloats.add!`, `mul!`, etc.; they are not exported. Immutable scalar `DFloat`, `DFloatBall`,
and `NFloat` use ordinary arithmetic. Vector `add!`/`mul!` are implemented as described in §2a.9.
For a packed ball vector, `FlintFloats.add!(v[i], v[i], step)` changes a copied temporary; use
`v[i] = value`, allocating `v[i] += step`, or qualified arithmetic on `borrow(v, i)` instead.
Ordinary iteration also copies; `eachborrow(v)` is explicit reference iteration.
The following broader list includes proposed fused/utility methods; consult the capability table
before using an operation such as `addmul!`, `inv!`, `zero!`, or `ldexp!`.

```julia
add!(z, x, y)   sub!(z, x, y)   mul!(z, x, y)   div!(z, x, y)
addmul!(z, x, y)   submul!(z, x, y)             # z ← z ± x*y
neg!(z, x)   abs!(z, x)   sqrt!(z, x)   inv!(z, x)   set!(z, x)
zero!(z)   one!(z)   ldexp!(z, x, n)
```

All have the form `z = f!(z, args...)` and return the result. `ArbFloat`/`AcbFloat` methods accept a trailing `RoundingMode` (`add!(z, x, y, RoundUp)`), and an `_inexact` variant returns FLINT's inexact flag as well: `z, inexact = add_inexact!(z, x, y[, r])` (`inexact::Bool`, false exactly when the result is the exact value). Contract:

1. Owned scalar and vector destination methods overwrite and return the supplied destination. Immutable scalar destination methods are not implemented; use `x + y` or `x * y`.
2. The destination type determines the working precision. No public `prec=` override is implemented. Bulk operands must have the same concrete element type and matching axes.
3. Vector operations permit exact destination/input aliasing via `===`; other possible overlap is rejected before mutation (§2a.9). Scalar aliasing follows the documented operation contract.
4. Scalar destination failure behavior is operation-specific. Nfloat vector operations always compute into private scratch and preserve the destination on arithmetic or input-read failure. Dfloat scalar-loop vector fallbacks can partially update the destination on custom input exceptions.
5. `set!(z, x)` converts `x` into `z`'s format with enclosure-preserving conversion for balls.

Proposed fused pattern (`addmul!` and a native `dot` surface remain unimplemented):

```julia
function dot(xs::AbstractVector{T}, ys::AbstractVector{T}) where {T<:FlintNumber}
    acc = zero(first(xs))
    @inbounds for i in eachindex(xs, ys)
        acc = addmul!(acc, xs[i], ys[i])
    end
    acc
end
```

For `ArbBall` and `ArbFloat` this does no allocation in the loop; for `DFloat{2}` it compiles to value arithmetic.

### 2a.5 Predicates, comparison, hashing

```julia
isnan isinf isfinite iszero isone isinteger signbit issubnormal(points only)
x == y   x != y   x < y   x <= y   x > y   x >= y   isequal(x,y)   isless(x,y)   hash(x,h)
contains(x, y)   overlaps(x, y)   isexact(x)               # balls only
```

| Operator | Points (`DFloat`, `NFloat`, `ArbFloat`; `AcbFloat` for `==` only) | Balls (`DFloatBall`, `ArbBall`, `AcbBall`) |
| --- | --- | --- |
| `==` | value equality; `NaN != NaN`; `-0.0 == 0.0` | **proved** equal singletons (`DFloatBall`: `dNb_equal`, true only for exact balls); `x == x` can be `false` for a nonsingleton ball |
| `!=` | `!(x == y)` | proved unequal (disjoint); **not** `!(x == y)` |
| `<`, `<=`, `>`, `>=` | total on finite values; `NaN` false | proved relation over the whole sets; each implemented directly |
| `isequal` | same value, `NaN isequal NaN`, `-0.0` vs `0.0` as for `Float64` | identical enclosures after normalisation (midpoint and radius); reflexive, symmetric, transitive |
| `isless` | Julia total order incl. `NaN` last | `ArgumentError` (no numerical total order on enclosures); use `sortkey(x)` for a deterministic presentation key |
| `hash` | on normalised value; equals `hash` of the equal `Int`/`Rational`/`Float64` where mixed equality holds | on normalised enclosure; precision not included |
| Complex ordering | none: `<` and `isless` are undefined for `AcbFloat` | none for `AcbBall` |

Implication for generic code: sorting or `unique` of balls needs `sortkey`; `==`-based algorithms are not valid on nonsingleton balls. Document this once, in the user guide's "Balls are not scalars" page.

Enclosure-only:

| Function | Meaning |
| --- | --- |
| `contains(x, y)` | enclosure `x` contains every value of `y` (`y` may be point, real, or ball) |
| `overlaps(x, y)` | enclosures intersect |
| `isexact(x)` | radius is exactly zero (`AcbBall`: both parts) |
| `midpoint(x)`, `radius(x)` | copies of the parts. `midpoint(x)::pointtype(T)` exactly (precision invariant): `DFloat{N}`, `ArbFloat{P}`, `AcbFloat{P}`. `radius` is a point value bounding the error: `Float64` for `DFloatBall` (the stored double; `Inf` for the whole real line), `ArbFloat{P}` for `ArbBall{P}` (exact copy of the `mag` radius) and for `AcbBall{P}` (bound covering both parts). |
| `ball(m, r)` | build from midpoint and nonnegative radius; result is `balltype(typeof(m))`: `DFloatBall{N}` from `DFloat{N}`/`Float64`, `ArbBall{P}` from `ArbFloat{P}`, `AcbBall{P}` from `AcbFloat{P}` |
| `uncertainty_bits(x)` | `precision`-independent count of bits certified correct (`-Inf` for unbounded) |

`ArbFloat` comparisons need care in the wrapper: FLINT's `arf_cmp` returns 0 when either argument is NaN and `arf_equal` treats NaN as equal to itself *(pinned docs)*, so `==`, `<` and `isless` test `arf_is_nan` first to give Julia's semantics (`NaN != NaN`, `isequal(NaN, NaN)`, NaN last in `isless`). There is no `-0.0`, so `signbit(zero(T))` is always false.

Where a three-valued answer matters, provide `proved_*` forms: `proved_equal`, `proved_less`, `proved_zero`, returning `Bool` (true only if proved). The operators `==`, `<` are defined to be these.

### 2a.6 Conversion

```julia
Float64(x), Float32(x), Int(x), BigInt(x), BigFloat(x; precision), Rational(x)   # explicit
convert(::Type{T}, x), promote_rule (§2a.8)
Float64(x::ArbBall)  # ArgumentError unless exact (isexact); use Float64(midpoint(x)) for the explicit lossy form
```

| From → to | Rule |
| --- | --- |
| Integer → `P` | nearest (exact if representable); overflow of `DFloat`/`NFloat` range gives `±Inf` if allowed, else `OverflowError`/`DomainError` |
| `P` → `Float64` | nearest-rounded; overflow gives `±Inf` as for `Float64` |
| `P` → `P'` (other precision of same family) | grow exact, shrink rounded to nearest; explicit `T'(x)` or `withprec(x, bits)` only |
| `P` → ball | enclosing conversion; for `DFloat`/`NFloat` midpoint exact, radius 0 |
| Ball → ball (any precision, real → complex) | containment-preserving |
| Ball → point | nonsingleton: `InexactError`; singleton: as `P → T` |
| Ball → `BigFloat` | same rule; `BigFloat(midpoint(x))` is the explicit lossy form |
| `AcbBall` → `Complex{Float64}` | singleton parts only |
| `DFloat{N}`, `NFloat{L}`, `Float64` → `ArbFloat{P}` | exact when `P` covers the source mantissa (`P ≥ 53N`, `P ≥ 64L`, `P ≥ 53`), otherwise correctly rounded |
| `ArbFloat{P}` → `ArbFloat{Q}` | grow exact; shrink correctly rounded (optional `RoundingMode`) |
| `ArbFloat{P}` → `Float64`, `DFloat`, `NFloat`, `BigFloat` | rounded to nearest; `Float64(x, RoundUp)` directed; out-of-range exponents give `±Inf`/`0` as the target format dictates (`ArbFloat` exponents are unbounded) |
| `ArbFloat{P}` → `ArbBall{P}`; `AcbFloat{P}` → `AcbBall{P}` | exact, radius 0 (`balltype`) |
| `ArbBall{P}` → `ArbFloat{P}` | only via `midpoint(x)` (exact) or `lower`/`upper`; `ArbFloat{P}(x::ArbBall)` throws `ArgumentError` (take `midpoint(x)` explicitly) |
| `ArbFloat{P}` → `AcbFloat{P}` | exact, zero imaginary part (`complextype`) |
| `DFloatBall{N}` → `ArbBall{P}` | exact midpoint; radius rounded up (`dNb_get_arb`) *(docs)*; whole real line becomes `[0 ± ∞]`. Needs `P ≥ 53N`, otherwise the midpoint is rounded and the radius grows |
| `ArbBall{P}` → `DFloatBall{N}` | midpoint rounded to `N` doubles, remainder added to the radius, always enclosing *(docs)*; may lose information, so explicit only |
| `DFloatBall{N}` → `DFloatBall{M}` | grow exact; shrink enclosing (remainder to radius) |
| `DFloatBall{N}` → `Float64` | `ArgumentError` unless exact (`isexact`); `Float64(DFloat{N}(x.d))` is the explicit lossy form |
| Endpoints | `lower(x)`, `upper(x)` return `ArbFloat` bounds rounded **outward** with directed rounding: `ArbFloat{P}` for `ArbBall{P}`, `ArbFloat{64N}` for `DFloatBall{N}`; for `AcbBall` apply them to `real`/`imag` |
| `Float64(x, RoundUp/RoundDown)` | directed conversion, for balls (outward) and points |

### 2a.7 Display, parsing, serialization

```julia
show(io, x)   show(io, MIME"text/plain"(), x)   string(x)   repr(x)
parse(T, s)   tryparse(T, s)
```

- Points print the shortest string that round-trips at the type's precision; `repr(x)` is valid Julia source (`DFloat{2}("1.5")`). `parse(T, s)` takes a concrete `T`; `parse(ArbBall, s)` uses `DEFAULT_PRECISION`.
- `ArbFloat`/`AcbFloat` print like points: shortest decimal that round-trips at `P` bits; `repr` gives `ArbFloat{128}("1.5")`, `AcbFloat{128}("1.5", "-2")`.
- Balls print midpoint and radius: `show` as `[1.2345678 ± 3.2e-9]` (readable, digit count adapts to radius); `repr` prints a reconstructing form `ArbBall{256}("[1.2345678 +/- 3.2e-9]")` (midpoint and radius exactly representable as decimal at that precision). `string` equals `show`.
- Round-trip: points exact; balls guarantee **containment** of the original after parse (`contains(parse(ArbBall, repr(x)), x)`), not bit identity.
- `tryparse` returns `nothing` on bad input.
- `IOContext` keys honoured: `:compact`, `:limit`, and `:digits=n` (extension) for balls.
- No `serialize`/`write` of owned values: `Serialization.serialize` of an `ArbFloat`, `AcbFloat`, `ArbBall` or `AcbBall` is defined to throw a clear error rather than write pointer bytes.

### 2a.8 Promotion and mixed operations

Narrow by design (enact §8.2): all promotion goes through `promote_rule` for these cases only. General rule: **point with ball gives a ball; real with complex gives complex; a lower family joins the arb family at the larger precision (`DFloat{N}` counts as `53N` bits, `NFloat{L}` as `64L`; an `NFloat` converts exactly, a `DFloat` expansion that spans more than `53N` bits is rounded to nearest).** `DFloat` and `NFloat` never promote to each other, and `DFloatBall` joins only `DFloat`/`DFloatBall`. Implemented in `src/promotion.jl`; `BigFloat` never promotes silently.

| Operands | Result type |
| --- | --- |
| `T`, `Int`/`Integer`, `Float64`, `Bool` | `T` (balls keep their `P`) |
| `DFloat{N}`, `DFloat{M}` | `DFloat{max(N,M)}` |
| `NFloat{L}`, `NFloat{M}` | `NFloat{max(L,M)}` |
| `DFloatBall{N}`, `DFloatBall{M}` | `DFloatBall{max(N,M)}` |
| `DFloatBall{N}`, `DFloat{M}` | `DFloatBall{max(N,M)}` (the point converts exactly) |
| `DFloatBall{N}`, `Float64`/`Integer` | `DFloatBall{N}` |
| `DFloatBall{N}`, `ArbBall{P}` | `ArbBall{max(P,53N)}` (the `DFloatBall` converts enclosing; midpoint exact) |
| `DFloatBall{N}`, `AcbBall{P}` | `AcbBall{max(P,53N)}` |
| `ArbFloat{P}`, `ArbFloat{Q}` | `ArbFloat{max(P,Q)}` |
| `ArbFloat{P}`, `DFloat{N}` | `ArbFloat{max(P,53N)}` (the lower family converts exactly) |
| `ArbFloat{P}`, `NFloat{L}` | `ArbFloat{max(P,64L)}` |
| `ArbFloat{P}`, `ArbBall{Q}` | `ArbBall{max(P,Q)}` (point becomes an exact ball) |
| `ArbFloat{P}`, `DFloatBall{N}` | `ArbBall{max(P,53N)}` |
| `ArbFloat{P}`, `AcbFloat{Q}` | `AcbFloat{max(P,Q)}` |
| `AcbFloat{P}`, `AcbFloat{Q}` | `AcbFloat{max(P,Q)}` |
| `AcbFloat{P}`, `ArbBall{Q}` or `AcbBall{Q}` | `AcbBall{max(P,Q)}` |
| `AcbFloat{P}`, `Complex{<:Real}` | `AcbFloat{P}` |
| `ArbBall{P}`, `ArbBall{Q}` | `ArbBall{max(P,Q)}` |
| `ArbBall{P}`, `AcbBall{Q}` | `AcbBall{max(P,Q)}` |
| `AcbBall{P}`, `AcbBall{Q}` | `AcbBall{max(P,Q)}` |
| `ArbBall{P}`, point `T` (`DFloat`/`NFloat`) | `ArbBall{max(P, precision(T))}` (enclosing, so the point converts exactly) |
| `AcbBall{P}`, `Complex{<:Real}` | `AcbBall{P}` |
| `NFloat{L}`, `DFloatBall{N}` | **no promotion**; convert explicitly |
| `DFloat{N}`, `NFloat{L}` | **no promotion**; `MethodError`. Convert explicitly: `NFloat{L}(x)` |
| Anything else (e.g. `Float32`, `Rational`) | `MethodError` for arithmetic; convert explicitly. Construction accepts them. |

Mixed with `Rational`/`BigFloat` are explicit constructions only (no blanket `Real` rule). Mixed with `Integer`/`Float64` call direct mixed kernels where FLINT has them (`arb_add_si`, `arb_mul_si`, `arb_add_d` style; inventory) to avoid a temporary ball.

### 2a.9 Collections

**Implemented:** ordinary `Vector{DFloat{N}}`, `Vector{DFloatBall{N}}`, and `Vector{NFloat{L}}`
store concrete inline values. Qualified `FlintFloats.add!(dest, x, y)` and `mul!` perform elementwise
arithmetic, require matching axes and concrete formats, and return the destination. Destinations
must be ordinary vectors or strided views with independent slots; repeated-index/gather destinations
are rejected. Exact aliasing via `dest === x`/`dest === y` is allowed; other possible destination/input
overlap is rejected. Inputs may overlap each other. Empty operations validate and return without a
native arithmetic call. Mixed-format promotion is not provided for bulk operations.

Contiguous aligned `DFloatBall` addition at length ≥ 4 uses `_dNb_vec_add`; dfloat-family
multiplication uses scalar loops. Contiguous aligned nfloat inputs use `_nfloat_vec_add`/`_nfloat_vec_mul`;
strided/reversed/gather inputs have scalar fallbacks. These dispatch paths are explicit vector
methods, not optimized replacements for `sum`, `dot`, or broadcasting. The audited dfloat-ball
vector-add entry returns `void`, not combined statuses; failure semantics require a separate audit
before adding other kernels. Nfloat kernels return OR-combined statuses; numerical/input-read
failure leaves the destination unchanged because scratch is committed only on success.

**Reusable nfloat scratch:** exported `NFloatWorkspace(NFloat{L}, capacity=0)` owns initialized storage
for `FlintFloats.add!(dest, x, y, work)` and `mul!`. `sizehint!(work, capacity)` reserves without
shrinking; operations also grow automatically. Existing slots are reused, only new slots are
initialized, and only the active prefix is processed and copied. The workspace's format is fixed;
it must not overlap any operand. An atomic guard rejects concurrent/reentrant use, including
reservation, and releases on errors. Use independent workspaces concurrently. After an error the
scratch contents are unspecified, the destination is preserved, and the workspace can be reused.
The three-argument calls allocate initialized scratch without a workspace object.

```julia
T = NFloat{2}
x, y, dest = fill(T(1), 100), fill(T(2), 100), Vector{T}(undef, 100)
work = NFloatWorkspace(T, 100)
FlintFloats.add!(dest, x, y, work)
FlintFloats.mul!(dest, dest, y, work)
```

Tested warmed reused native and strided paths allocate no Julia heap memory within capacity;
growth allocates, and successful operations still copy to the destination. The exclusive-use guard
can outweigh allocation savings for tiny vectors. See [measurements](../benchmark/results/reusable.txt).
No result-buffer borrowing or swapping API is provided.

**Packed ball vectors (M4c):** `PackedBallVector(ArbBall{P}, n)` or the complex-ball form owns one
initialized FLINT allocation. `PackedBallVector(T, values)` copies values into initialized slots.
The owner is fixed-size: ordinary indexing and iteration copy independent scalars, while assignment preserves
containment at the destination precision. `copy`/`deepcopy` initialize independent native storage;
`similar`, fill, iteration, and ordinary Base broadcasting are supported. Flat same-format identity/add/multiply
assignment broadcast reuses packed storage; unsupported/custom expressions remain generic. No matrix representation is introduced.

`borrow(v, i)` also accepts packed views and returns an explicit nonnumeric `BorrowedBall` retaining
the fixed-size parent. `r[]`/`copy(r)` copy out; `r[] = value`/`FlintFloats.set!` copy in. Qualified
same-format scalar `add!`/`sub!`/`mul!`/`div!` accept borrowed sources/destinations. Borrowers never
clear slots and cannot be constructed from public raw pointers. Parent finalization is idempotent;
references reject already-finalized storage before a C call. Concurrent writes require independent
slots and no concurrent explicit parent finalization.

Packed-destination vector `FlintFloats.add!`/`mul!` require matching concrete element types and axes;
exact aliases are allowed, other possible destination/input overlap is rejected. Destination views
must have independent strided slots. Direct packed add uses `_arb_vec_add`/`_acb_vec_add`; views and
multiply use borrowed scalar calls. All paths preserve rigorous enclosures and FLINT indeterminates.
Empty calls skip C. Validation errors preserve destinations; custom input-read errors can leave
valid partially updated values. See [measurements](../benchmark/results/m4c_packed.txt) for zero warmed
Julia allocations, arithmetic comparisons, copied reads, and construction/copy/cleanup costs.

**Explicit borrowed iteration:** `eachborrow(v)` accepts the same owners/views as `borrow`, yields
stable nonnumeric `BorrowedBall{eltype(v)}` references in logical order, and retains the parent without
caching raw pointers. Strided/reversed/gathered views retain their index mapping under Base's view
rules. Saved references remain attached to their original parent slots. Construction and every
iteration step reject finalized parents, including empty spans; pointer conversion still checks the
parent before a C call. Ordinary `eltype(v)` and iteration are unchanged.

A reference or iterator keeps the entire parent alive; an independent copied scalar does not need
that owner. Reading `r[]` copies. Views also copy on read and write through on assignment. `v[i] += step`
works through ordinary read/arithmetic/write-back and can allocate. Prefer existing vector destination
methods for matching bulk work, and `eachborrow` for custom mutation loops. Collecting references
allocates their collection intentionally. Validate multi-vector axes before using `zip`; concurrent
writes require independent slots.

**Flat assignment broadcast:** `dest .= src`, `dest .= x .+ y`, and `dest .= x .* y` optimize
same-format packed leaves and owning scalar/`Ref(value)` leaves into initialized destinations.
Whole packed copies/additions use existing native kernels where axes qualify; scalar/singleton
expansion and other recognized spans use borrowed destinations. Base's alias helper snapshots
possibly overlapping views before writing, including singleton expansion and shifted/reversed/gathered
sources. Snapshots preserve source/view types through existing Base rules and can allocate a native
copy of the parent. Explicit vector `FlintFloats.add!`/`mul!` retain stricter overlap rejection.

Other Ref implementations, nested/custom expressions, ordinary array inputs, mixed formats/result
types, and repeated-index destinations take the generic Base path before evaluation, without retry
after exceptions. Allocating broadcast style/result selection is unchanged. Shape/lifetime checks
and snapshots happen before fast-path mutation; evaluation errors may leave a valid partially
updated destination. Nonoverlapping warmed typed paths avoid per-element Julia owners; snapshot/native
memory costs are separate. See [broadcast measurements](../benchmark/results/packed_broadcast.txt).

`PackedVector`, `flintzeros`, `flintones`, `flintvec`, and `flintmatrix` remain unavailable design
names. Native dot products need separate accumulation/error and complex-conjugation contracts (M4d).
Matrix storage/kernels follow only where measured workloads justify them; ordinary Julia matrices
of concrete inline values remain available.

### 2a.10 Introspection and capability queries

```julia
FlintFloats.family(x)            # :dfloat | :dfloatball | :nfloat | :arbfloat | :arbball | :acbfloat | :acbball
precision(T)                     # constant, all seven types
FlintFloats.pointtype(T)  balltype(T)  realtype(T)  complextype(T)    # type grid navigation
FlintFloats.guarantee(T)         # Point() | Enclosure()
FlintFloats.storage(T)           # Inline() | Owned()
FlintFloats.supported(T)::Bool   # DFloat: false if dfloat_is_supported() == 0
FlintFloats.flint_version()::VersionNumber
FlintFloats.capabilities(T)      # Dict: function => guarantee string ("correctly rounded", "enclosure", "≤2^-98 error")
```

`capabilities` is generated from the inventory so the doc table and the code agree.

### 2a.11 Error reference

| Error | Raised for |
| --- | --- |
| `ArgumentError` | invalid precision parameter (`P`, `N`, `L` out of range); bad string; unsupported flag |
| `InexactError` | exact conversion requested/required and impossible; nonsingleton ball → point |
| `DomainError` | point-function input outside domain; ball function on wholly-outside domain; nonfinite disallowed by context |
| `OverflowError` | result outside the exponent range of a point family without infinity support |
| `MethodError` | function or promotion not in the inventory |
| `ErrorException("dfloat unsupported …")` | any `DFloat` or `DFloatBall` use when `dfloat_is_supported()` is 0 |

Ball operations that FLINT reports as "unable" return an indeterminate enclosure, not an error. A global `strict` mode that turns those into errors is a possible later option (`setstrict(f, true)` scoped), not part of v1.

### 2a.12 Worked examples

```julia
# Type-level precision, ball arithmetic with certified result
x = ArbBall{128}("1.2345678901234567890")
y = sqrt(x) + exp(x)                      # ArbBall{128}
@assert contains(y, midpoint(y))          # a ball contains its own midpoint
radius(y)

# Adaptive precision with a function barrier
e512(::Val{P}) where {P} = exp(ArbBall{P}(1))
r = with_precision(e512, 512)

# Same code on every family
function horner(p, x)
    acc = zero(x)
    for c in Iterators.reverse(p)
        acc = muladd(acc, x, c)
    end
    acc
end
horner([1, 2, 3], DFloat{2}(0.5)); horner([1, 2, 3], NFloat{4}(0.5)); horner([1,2,3], ArbBall{256}(0.5))

# In-place loop on balls
function powersum!(acc::ArbBall{P}, x::ArbBall{P}, n) where {P}
    t = one(x)
    for _ in 1:n
        acc = add!(acc, acc, t)
        t   = mul!(t, t, x)
    end
    acc
end

# Fixed-width ball (no heap): a float, then a ball
f = DFloat{2}(0.1)                      # point, ~106 bits
b = DFloatBall{2}("0.1")                     # encloses the decimal 0.1; radius > 0
c = DFloatBall{2}(DFloat{2}(0.1))            # exact: the float's value, radius 0
isexact(b), isexact(c)                  # (false, true)
q = DFloatBall{2}(1) / DFloatBall{2}(0, 3)         # divisor [0 ± 3] contains zero: GR_UNABLE, result W
radius(q)                               # Inf (the whole real line)
DFloatBall{2}(1) / DFloatBall{2}(0)               # exact zero divisor: DomainError

# Correctly rounded floats (arf) and their ball partners
x  = ArbFloat{128}("0.1")                 # nearest 128-bit value to 0.1
lo = ArbFloat{128}("0.1", RoundDown); hi = ArbFloat{128}("0.1", RoundUp)   # lo < hi, adjacent
y  = sqrt(x)                              # correctly rounded, RoundNearest
y2 = sqrt(x, RoundUp)                     # directed
z, inexact = add_inexact!(ArbFloat{128}(), x, y)
b  = ArbBall{128}(x)                      # exact ball around x: radius 0
midpoint(b) == x                          # true; midpoint(::ArbBall{128})::ArbFloat{128}
balltype(typeof(x)) === ArbBall{128}; complextype(typeof(x)) === AcbFloat{128}
w  = AcbFloat{128}(1, 2); abs(w)::ArbFloat{128}
ArbFloat{128}(1) / ArbFloat{128}(0)       # NaN, not Inf: arf has no signed zero

# Complex ball
z = AcbBall{128}(1, 2); abs(z)::ArbBall{128}; real(z)::ArbBall{128}; conj(z); exp(z)

# Mixed types, explicit across point families
y = NFloat{2}(DFloat{2}(1.5))   # explicit
```

### 2a.13 Compatibility promises

- Source-level API in §2a is stable from v0.2 once M3 passes; additions never change meanings.
- Changes to `DEFAULT_PRECISION`, ball comparison semantics, conversion loss, or the meaning of the type parameters (`N`, `L`, `P`) are breaking and need an explicit review (enact §13).
- Anything not listed here is internal (`FlintFloats.LibFlint`, `_*` names, `mag`).

## 2b. DFloatBall{N} in detail

Source: FLINT 3.7.0-dev dfloat docs *(docs)*; confirm against `src/dfloat.h` before binding. `DFloatBall{N}` wraps `dNb`, N = 1..4.

**Representation and invariants.**

- `dNb_struct` = `double d[N]` (midpoint expansion) + `double rad`; `x ∈ ball ⇔ |x − mid| ≤ rad`. Radius is a plain `double`, not `mag`/`arb`.
- A ball returned by FLINT has finite midpoint components and a finite, nonnegative `rad`, **or** is the **whole real line** `W` in normal form `[0 ± ∞]` (`mid = +0`, `rad = +∞`). Inputs with any nonfinite component or radius are *accepted as* `W`; `NaN` never appears as a ball value. So `DFloatBall` has no `NaN`: `isnan(x) == false` always, `isfinite(x)` is false only for `W`, and `isinf` is not defined as "contains infinity" (document).
- `DFloatBall{N}()` = exact zero; `W = DFloatBall{N}(Inf)` or `indeterminate(DFloatBall{N})` (`dNb_indeterminate`).
- `isbits`, 8(N+1) bytes. No `init`/`clear`, no finalizer, arrays contiguous. All operations allow aliasing of inputs and outputs *(docs)*.

**Semantics.** Exact operations on exact balls stay exact (`[3±0]·[3±0] = [9±0]`). The error of each midpoint operation is added to the radius, computed with error-free transformations and a final factor of `1 + 2^-45` on the radius *(docs, bound garbled in extract; check)*. Total functions never fail (add, sub, mul, sqr, neg, abs, `ldexp`, exp, expm1, sin, cos, atan, sinh, cosh, tanh, `atan2`, integer powers with nonnegative exponent, division by a ball excluding zero); on `W` they give `W` or a bounded enclosure (`[0±1]` for `sin`, `cos`, `tanh`; `[0±π/2]` for `atan`). Exact zero times anything is exactly zero; `x^0 = 1` exactly.

**Status mapping** (the point where `DFloatBall` follows FLINT's `gr` statuses; `GR_UNABLE = 2`, others unverified):

| C status | Meaning (docs) | Julia behaviour |
| --- | --- | --- |
| `GR_SUCCESS` | result valid | return it |
| `GR_DOMAIN` | input **disjoint** from the function's domain (e.g. exact zero divisor, wholly negative `sqrt`/`log` argument) | `DomainError` |
| `GR_UNABLE` | input only partly in the domain, or the algorithm cannot decide | return `W` (`indeterminate`). FLINT leaves the output **unspecified**, so the wrapper must write `W` explicitly. Optional strict mode throws instead. |

This matches the rule for `ArbBall` in §2a.3 (indeterminate enclosure, not an exception), so callers see the same behaviour on every ball family. Partial functions: `div`/`inv` (nonzero divisor), `sqrt` (`x ≥ 0`), `rsqrt`/`log` (`x > 0`), `log1p` (`x > −1`), `asin`/`acos` (`|x| ≤ 1`), `tan` (never `GR_DOMAIN`), `pow` (`x > 0`, or `x = 0, y ≥ 0`, or `x < 0` with integer `y`).

**Predicate mapping** *(docs)*:

| Julia | FLINT | Notes |
| --- | --- | --- |
| `isexact(x)` | `dNb_is_exact` | finite and `rad == 0` |
| `iszero(x)` | `dNb_is_zero` | true only for exact zero (certain) |
| `x == y` | `dNb_equal` | true only for exact equal balls |
| `contains(x, y)` | `dNb_contains` | 1 only when certain; `W` contains everything |
| `overlaps(x, y)` | `dNb_overlaps` | 0 only when certain; `x != y` is `!overlaps(x,y)` |
| `contains_zero(x)` | `dNb_contains_zero` | 0 only when certain |
| `x < y`, `x > y` | exact endpoints: `upper(x) < lower(y)` (`mid ± rad` formed exactly in `ArbFloat{2304}` scratch) | proved only; the whole real line proves nothing. Agrees with `dNb_cmp` whenever that succeeds (tested) |
| `x <= y`, `x >= y` | exact endpoints: `upper(x) <= lower(y)` | proves the touching case that `dNb_cmp` reports as `GR_UNABLE` |

**Flags.** `gr_ctx_init_dfloat(ctx, n, flags)` takes `DFLOAT_BALL=1`, `DFLOAT_STRONG=2` (canonical results), `DFLOAT_FAST=4` (cheaper error bound in ball products), `DFLOAT_COMPLEX=8`. Direct `dNb_*` calls have no flags: they track product rounding errors exactly when inputs are exact. v1 uses the direct calls (tight radii); `DFLOAT_FAST` behaviour would be a separate type or a per-call option if wanted. Use `dNb_canonicalise` before hashing and `isequal`; all forms of `W` canonicalise to `[0±∞]` and compare `isequal`.

**Conversions (docs, summary).** `dNb_set_d`, `dNb_set_dd`, `dNb_set_d_rad`; to/from `arf`, `arb` (get is exact with the radius rounded up to `mag`; set rounds the midpoint to `N` doubles and sends the remainder to the radius), `fmpz`, `fmpq`; strings via `arb_set_str` at `53N+64` bits. `dNb_get_d` returns the head of the midpoint (0 for `W`) and is not an enclosure conversion.

**Range and speed guidance from FLINT** *(docs)*: `d2`/`d2b` are intended for roughly 106 bits and below; ball overhead over plain is about 1.2–1.7× for products and 2–4× for division and square roots; above about 212 bits prefer `arb_t` or `nfloat`. `sin`/`cos` kernels cover `|x| ≤ 2^20·π/2 − 1` and `log`/`atan` cover `2^-1022 ≤ x < 2^1022`; outside these FLINT falls back to `arb_t` internally. Ball `exp` underflow gives a ball of radius at most `2^-1074` around 0.

**Implementation.** `ccall` only: native Julia reimplementation of ball arithmetic is not recommended (radius error tracking is intricate and the FLINT code is the oracle). Gate on `dfloat_is_supported()`. Calls return `Cvoid` or `Cint`; `_status` maps the latter. Verify via `dlsym` which `d?b_*` symbols are exported (only `d2_add`, `d2b_add` etc. were confirmed so far *(checked)*); inline helpers need Julia equivalents.

**Relationship to `ArbBall`.** `DFloatBall` is the fast, small, fixed-width ball (≤ ~212 bits, radius as `double`, no allocation). `ArbBall{P}` is the arbitrary-precision ball (owned, `mag` radius). Mixed arithmetic promotes `DFloatBall{N}` to `ArbBall{max(P,53N)}` (§2a.8); conversion back down is explicit because it can lose information.

## 2c. ArbFloat{P} and AcbFloat{P} in detail

Source: the `arf` and `acf` documentation in the pinned source tree *(pinned docs)* and the exported symbols of the local build *(checked)*. `ArbFloat{P}` wraps `arf`, `AcbFloat{P}` wraps `acf`.

**What they are.** `arf` is FLINT's arbitrary-precision binary floating-point type "in the style of MPFR": the midpoint type of an `arb` ball, usable on its own. `acf` is a pair of `arf` parts (real, imaginary) without error bounds. Neither carries a radius: results are **approximations with a rounding guarantee, not enclosures**. Use `ArbBall`/`AcbBall` when a proof is needed.

**Representation.** `arf_struct` is four words (32 B): an `fmpz` exponent, a size-and-sign word, and two words holding either an inline mantissa of at most two limbs or an allocation size and pointer. Values with at most 128 mantissa bits use no heap memory beyond the Julia object. `acf_struct` is two `arf_struct` (64 B). `ArbFloat{P}`/`AcbFloat{P}` are single mutable Julia objects with exactly that layout and a finalizer (`arf_clear`/`acf_clear`), like `ArbBall` (§6.3). `ArbNumerics.jl`'s `ArbFloat{P}` uses the same four-word layout.

**Precision invariant.** FLINT's `arf` has no precision of its own (precision is an argument of each operation, and exact setters keep every bit). The Julia types add the invariant *mantissa ≤ `P` bits*: constructors use `arf_set_round`, arithmetic passes `P`. `ARF_PREC_EXACT` is not exposed through these types.

**Rounding contract** (strict modes only are used):

| Operation | Guarantee |
| --- | --- |
| `+ - *`, `fma`-style `addmul`/`submul`, `ldexp` | correctly rounded (`ldexp` exact) |
| `/`, `inv`, `sqrt`, `rsqrt`, `root` | correctly rounded |
| `exp expm1 log log1p log2 log10 sin cos tan atan atan(y,x) sinh cosh tanh pow` and the `…_pi` variants (exported `arf_*`) | correctly rounded; a hard case near a rounding boundary costs extra evaluations (probability about `2^-20`) |
| `AcbFloat` `+ - *`, `/`, `inv`, `sqrt`, elementary functions (`acf_*`) | each part correctly rounded |
| dot products (`arf_dot`; `arf_approx_dot`, `acf_approx_dot`) | `arf_dot`: one rounding of the exact sum (confirm before use); the `approx` forms give no guarantee and are not used by default |

Rounding modes: `RoundNearest` (ties to even, the default) → `ARF_RND_NEAR`, `RoundToZero` → `ARF_RND_DOWN`, `RoundFromZero` → `ARF_RND_UP`, `RoundDown` → `ARF_RND_FLOOR`, `RoundUp` → `ARF_RND_CEIL`. Other Julia modes (`RoundNearestTiesAway`, `RoundNearestTiesUp`) are an `ArgumentError`. The mode is a trailing argument, never global state. Every rounding function returns FLINT's inexact flag (0 exactly when the result is the exact value; for `acf`, bit 0 real part and bit 1 imaginary part); the `_inexact` variants (§2a.4) expose it.

This makes `ArbFloat` the one family where **bit-for-bit agreement with MPFR (`BigFloat`) at the same precision and mode** is a valid test oracle for every listed operation.

**Special values and differences from `Float64`/`BigFloat`** *(pinned docs)*:

| Topic | `ArbFloat` behaviour |
| --- | --- |
| Zero | one zero; no negative zero. `ArbFloat{P}(-0.0) == 0`, `signbit` false |
| Infinities, NaN | `±Inf` and one NaN (no payload). `Inf - Inf`, `0 * Inf`, `0/0` give NaN |
| `x / 0`, `x ≠ 0` | **NaN**, not `±Inf` |
| Exponent range | unbounded (`fmpz`): no overflow, underflow or subnormals. `floatmax`, `floatmin`, `nextfloat(floatmax)`-style queries throw; `eps(ArbFloat{P}) = 2^(1-P)`, `nextfloat`/`prevfloat` are well defined at `P` bits |
| Huge arguments | `exp` beyond `|x| ≥ 2^max(128, 2P)` and trig beyond FLINT's argument limit return NaN |
| Comparison | wrapper tests NaN first (§2a.5); FLINT's own `arf_cmp`/`arf_equal` do not follow IEEE on NaN |

**`AcbFloat` specifics.** `real`, `imag`, `reim` return `ArbFloat{P}` copies; `abs`, `abs2`, `angle` return `ArbFloat{P}`. Exported as `acf_*` *(checked)*: `add sub mul div inv neg sqrt rsqrt exp expm1 log log1p pow sin cos tan` and the inverse, hyperbolic and `…_pi` variants. No exported `acf_abs`, `acf_arg` or `acf_conj` was found, so `abs`, `abs2`, `angle` and `conj` are built from `arf` operations on the parts (or from inline header functions reimplemented in Julia); settle their rounding guarantee in the inventory, since a composed `abs` is not automatically correctly rounded. No ordering. `Complex{ArbFloat{P}}` is **not** used: it would hold two separately allocated objects, would not match the `acf` layout, and would route through Base's generic complex algorithms without the per-part rounding guarantee; conversion to and from it is provided.

**Choosing among the point types.**

| Need | Use |
| --- | --- |
| Up to about 212 bits, maximum speed, no allocation | `DFloat{N}` (a few ulps, not correctly rounded) |
| Fixed precision of 64–4224 bits, no allocation, packed arrays | `NFloat{L}` (guarantee per operation and flags) |
| Correct rounding, directed rounding, the inexact flag, unbounded exponents, any precision, or agreement with MPFR | `ArbFloat{P}` (heap-owned, finalizer; slowest per operation of the three) |
| Complex versions of the last | `AcbFloat{P}` |
| A proof of the error | the ball types |

## 3. One destination convention

Implemented mutable scalar and vector destination operations return the supplied destination.
Immutable scalars use ordinary arithmetic; an exclamation-mark method cannot replace the caller's
immutable object. A generic scalar loop therefore uses `acc = acc + x*y`; owned-scalar code can
reuse documented destination methods explicitly. Fused methods such as `addmul!` remain proposals.

Vector `FlintFloats.add!`/`mul!` accept ordinary and strided destination buffers under §2a.9's rules.
The optional nfloat workspace is a scratch owner, not a numeric value or a returned result buffer;
both allocating and reusable forms keep status handling and commit-on-success inside the same
kernel implementation in `src/reusable.jl`.

## 4. Proposed internal protocol

Each family implements a small set of private functions; public methods are written once against them.

| Protocol function | Meaning |
| --- | --- |
| `_result(T, args...)` | Allocate/initialise a destination of the right concrete type (precision is in `T`). Inline: uninitialised value. Owned: `init`ed owner. |
| `precision(T)` | Working precision for the op; a compile-time constant for every family, so no `_opprec` protocol function is needed. |
| `_with(f, z, x, y)` | Run `f(pz, px, py, ctx)` with valid pointers/context; returns the written result. Inline: `Ref`s then read back. Owned: `GC.@preserve` and raw pointers. |
| `_status(T, code)` | Interpret the C status (§7). Balls and `dfloat` ball ops return codes; plain ops return `Cvoid`. |

Public methods:

```julia
add!(z::T, x::T, y::T) where {T<:FlintNumber} =
    _with(z, x, y) do pz, px, py, ctx
        _add(T, pz, px, py, ctx)          # one @ccall per family, literal symbol
    end
Base.:+(x::T, y::T) where {T<:FlintNumber} = add!(_result(T, x, y), x, y)
```

Generate only the mechanically identical pieces (`+ - *` and their `!` forms, which all have shape `f(res, x, y, prec-or-ctx)`; `d?b_add`/`sub`/`mul` have no precision argument); write `/`, `sqrt`, comparisons, conversion and anything with status handling by hand. This keeps enact §5.3's rule (do not hide semantic differences behind `@eval`).

Per-family notes *(checked unless marked)*:

- **DFloat.** `d2_add`, `d2_mul`, `d2_div`, `d2_exp`, `d2b_add` are exported. 816 `d1..d4` symbols are exported in this build. Gate everything on `dfloat_is_supported() == 1` in `__init__`. `DFloat{1}`: native `+`. `DFloat{2..4}`: ccall first; native `two_sum`/`two_prod` kernels (explicit `fma`, never `muladd`/`@fastmath`) only where benchmarks win.
- **DFloatBall.** `d2b_add` is exported *(checked)*. Same gate as `DFloat`. Inline struct passed by `Ref`; `Cint` statuses go through `_status` (§2b), which writes the whole real line on `GR_UNABLE`. `DFloatBall{1}` is **not** a native double op: it still needs radius tracking, so use the `d1b_*` calls.
- **NFloat.** `nfloat_add(res, x, y, ctx)` is exported. The context carries `nlimbs, flags, rnd, func_prec` (small). One context per `(L, flags)`; see §6.4.
- **ArbBall/AcbBall.** `arb_add` etc. exported. Precision `P` comes from the type and is passed to C as a constant; `AcbBall{P}` shares the `ArbBall{P}` machinery (two `ArbBall{P}` parts, 96 B).
- **ArbFloat/AcbFloat.** `arf_add`, `arf_mul`, `arf_div`, `arf_sqrt`, `arf_exp`, `arf_set_round`, `acf_add`, `acf_mul`, `acf_div`, `acf_sqrt` and the `acf` elementary functions are exported *(checked)*. Signature shape `int f(res, x, y, slong prec, arf_rnd_t rnd)`: precision is the constant `P`, the mode comes from the trailing `RoundingMode`, the returned inexact flag is discarded except in `_inexact` variants. Many small `arf` helpers are `static inline` in `arf.h`; audit with `dlsym` and reimplement or avoid those.
- **mag.** Private: used for ball radii and bounds only.

## 5. Containers

- Inline families use ordinary concrete Julia vectors, with explicit bulk methods under §2a.9.
- `NFloatWorkspace` supplies reusable scratch while preserving destination identity and failure atomicity.
- `PackedBallVector{ArbBall{P}}`/`PackedBallVector{AcbBall{P}}` own fixed-size initialized native storage;
  `borrow` creates explicit parent-retaining references, while ordinary indexing copies.
- Packed point owners, array factories, nested broadcast optimization, and native dot/matrix methods remain future
  work. The generic `PackedVector{T}` name in earlier designs is not an available API.

## 6. Review

Reviewed the interface above and the two earlier documents for **clarity, concision, performance**. Items already folded into §§2–5 are marked ✔; items that change earlier documents or need a decision are marked ▲.

### 6.1 Clarity

- ✔ **Single statement of the destination rule** (§3). The earlier docs describe `add!` for balls and "ordinary arithmetic" for fixed types in different sections; a reader must reconcile them. The rebinding convention removes the split.
- ✔ **`DFloatBall` confirms the two-trait design.** It is the one inline enclosure, so storage and guarantee must be separate traits; code that assumed "enclosure ⇒ heap-owned" (the destination convention, finalizers, `PackedVector`) now keys on `storage(T)` only.
- ▲ **`radius` has family-specific type** (`Float64` for `DFloatBall`, `ArbFloat{P}` for `ArbBall` and `AcbBall`): always a point value, never a ball. Acceptable (documented, each exact for its family); generic code that needs a number should use `Float64(radius(x))` (rounded up).
- ✔ **Complete, regular grid.** Each FLINT family now has a point type, and a ball type where FLINT has one, sharing a parameter and a suffix rule (`Float`/`Ball`). The Point/Owned cell, previously empty, holds `ArbFloat`/`AcbFloat`. Pairing functions replace the per-function return-type tables.
- ✔ **Precision invariant stated once** (§2.1). Without it `midpoint(::ArbBall{P})::ArbFloat{P}` would be a false type claim, since FLINT allows longer midpoints.
- ▲ **`AcbFloat` is not a float** in Julia's sense (`<: Number`). Kept for symmetry with `AcbBall` and FLINT's `acf`; documented at the type.
- ▲ **Seven public types.** More surface, but every method is defined once against the protocol; the type list is a table, not seven separate designs. `:dfloatball`-style family symbols and the capability table carry the differences.
- ▲ **Three overlapping real point types.** The "choosing" table in §2c is the mitigation; put it on the documentation front page.
- ▲ **`ArbFloat` departs from IEEE in three visible places:** no `-0.0`, `x/0 = NaN`, unbounded exponent. Each is in §2c and must be in the user docs and tests.
- ▲ **Two ball families, one behaviour.** Differences to keep visible: `DFloatBall` has a single `W` and no `NaN`; `ArbBall` can have non-finite parts. Provide `isindeterminate(x)` on all balls.
- ✔ **Two traits instead of case analysis.** `Guarantee` and `Storage` capture every difference users see; everything else is identical.
- ✔ **Precision in the type for every family** (requested): `precision(T)` is uniform and constant, binary-op precision follows ordinary promotion (`max`), and the `precision=` keyword and scoped default disappear. Cost: see §6.3.
- ✔ **`NFloat{L}` instead of `NFloat{P,L}`** removes a type parameter that was always derived, an inner-constructor check, and the "`NFloat{128}` is not concrete" caveat.
- ▲ **Rebinding convention is easy to forget.** `add!(acc, x, y)` without `acc =` works for `ArbBall` and silently does nothing for `DFloat`. Mitigation: document prominently; add a `@flint acc = addmul!(acc, v, w)`-style lint only if misuse shows up. Alternative (not recommended): make inline types unsupported by `!`, breaking uniformity.
- ▲ **`FlintNumber = Union{…}` plus `FlintReal`** is two shared names. Acceptable cost of `AcbBall <: Number`; document why.
- ▲ **Enclosure queries on point types.** Tempting to define `radius(x::DFloat) = 0` for uniformity. Rejected: `DFloat` results carry error ("a few ulps"), so radius 0 would claim exactness it does not have. Keep `midpoint/radius/contains/overlaps/isexact` enclosure-only.
- ▲ **Earlier docs are long and overlap** (enact ≈450 lines restates much of plan ≈200 lines, and `planinterfacing.md`/`plan_interfacing.md` coexist). Recommend: `plan_interfacing.md` = decisions, `enact_interfacing.md` = procedure, this file = interface contract; delete or mark `planinterfacing.md` superseded. Not done here.

### 6.2 Concision of source

- ✔ **Generate only identical shapes** (`+ - *`); everything with status or domain logic is hand-written. Expected size: the generic layer is on the order of a few hundred lines, most of the code in per-family files.
- ✔ **Protocol of four functions** keeps each family's file focused on layout, ccall and quirks.
- ▲ **Resist per-family `Base` method copies.** Where `Float64` semantics already hold (`iszero`, `isone`, `sign`), define once on `FlintReal` through `isnan/iszero` primitives rather than once per type. `ArbFloat` and `ArbBall` share the `arf` layout code and the owner/finalizer machinery; `AcbFloat`/`AcbBall` reuse it twice over.
- ✔ **`arf` and `acf` are public** as `ArbFloat`/`AcbFloat` (they give directed and correct rounding, which no other family offers); `mag` stays private.

### 6.3 Performance

- ✔ **Single heap object per owned value** (`ArbFloat` 32 B, `AcbFloat` 64 B, `ArbBall` 48 B, `AcbBall` 96 B; sizes observed or derived for the 64-bit host, confirm with the probe). Described here for `ArbBall`. Previous docs say "public value containing a private mutable owner and precision", which is two objects per number (wrapper + owner); a runtime precision field would also have been needed. Make `ArbBall` itself the owner: a `mutable struct` whose first fields are exactly the C layout (`arf`: exponent word, size word, two mantissa words; `mag`: exponent word, mantissa word) and **nothing else** (precision is now in the type, so the object is exactly the 48-byte `arb_struct`, or 96 bytes for `AcbBall`). Pass `pointer_from_objref(x)` inside a `GC.@preserve` (valid because the object body starts at the first field and Julia's GC is non-moving for such objects). Saves one allocation and one pointer chase per number. Needs the layout probe from enact §5.2 (field order, `fmpz` tagging) before use. ▲ Verify with a benchmark against the wrapper+owner design before committing.
- ✔ **Native `DFloat{1}`**; likely native `DFloat{2}` add/mul. Direct `+` on doubles needs no `Ref`/call. The foreign call and the temporary `Ref` for output are the dominant cost for tiny operations (≈ a few ns vs <1 ns native); measure per operation, do not assume.
- ✔ **`ArbFloat` cost profile.** One 32-byte Julia object and a finalizer per value, no further heap memory up to 128 mantissa bits *(pinned docs)*. FLINT states one- and two-limb elementary functions run close to `nfloat` speed; the Julia-side allocation and finalizer will dominate for small `P`, so `NFloat`/`DFloat` remain the fast scalar types and `ArbFloat` loops should use `acc = addmul!(acc, …)` and `PackedVector`. Benchmark `ArbFloat{128}` against `NFloat{2}`, `DFloat{2}` and `BigFloat` (which also allocates per value).
- ✔ **Per-element finalizers dominate heap-owned scalars.** Unavoidable for owned scalars (`ArbFloat`, `AcbFloat`, `ArbBall`, `AcbBall`); the answer is in-place `acc = addmul!(acc, …)` loops and `PackedVector`, which has one finalizer for all elements.
- ✔ **Context reuse for `NFloat`.** `nfloat_ctx_init` per call would dwarf the add. Use one context per `(L, flags)`, created once, stored in a per-type `const`/`Ref`, read-only afterwards. ▲ Enact §7.2 requires task-owned contexts until immutability is proven: audit `nfloat_add`/`nfloat_mul` in the pinned source for writes to `ctx` (the struct holds only `nlimbs, flags, rnd, func_prec`, which suggests read-only use). If any write exists, fall back to task-local contexts.
- ▲ **Type specialisation is bounded for `DFloat` and `NFloat` but not for the arb types.** Four families are now parameterised by `P` (`ArbFloat`, `ArbBall`, `AcbFloat`, `AcbBall`), so a new precision can compile four sets of methods. `DFloat{1..4}` and `NFloat{1..66}` give at most 70 types; precompile a handful (`NFloat{1,2,4,16,64}`). `ArbBall{P}`/`AcbBall{P}` admit any `P`, so every new precision recompiles the methods it touches. Mitigations: (a) precompile common `P` (64, 128, 256, 512, 1024) in the package; (b) document multiples of 64; (c) keep the number of distinct `P` in adaptive loops small; (d) keep methods thin (one `@ccall` and a status check) so each specialisation compiles quickly; (e) consider rounding `P` up to the next multiple of 64 inside the type constructor (`ArbBall{100}` normalises to `ArbBall{128}`) as an opt-in, since FLINT balls at 100 bits give no storage saving. **Measure** first-call latency per new `P` and total time for a ten-precision refinement loop before choosing; if latency is unacceptable, fall back to the hybrid in §8.
- ▲ **Adaptive-precision code needs the function barrier.** Without `with_precision(f, bits)`, a loop over precisions dispatches dynamically on every operation. Add a documented example and a test that inside the barrier the loop body infers concretely and allocates nothing beyond the results.
- ✔ **No per-value precision field and no precision lookup per call:** `P` is a compile-time constant, so the C call receives a literal.
- ▲ **Large `NFloat{L}` copy cost.** `NFloat{66}` is ~544 bytes; each value-returning op copies it. Fine for scalars; for sustained large-L work use arrays plus FLINT vector kernels and avoid returning large tuples per element. Set a documented threshold after benchmarking (suspect around L ≥ 16).
- ▲ **Status interpretation off the hot path.** `_status` is a branch on a small integer; keep it `@inline` and make the success case first so it predicts well.
- ▲ **Mixed arithmetic.** `ArbBall + Int` should call the dedicated `arb_add_si` (exported, no temporary `ArbBall`); likewise `Float64`. Include in the inventory so promotion does not allocate.

- ✔ **`DFloatBall` performance profile:** isbits, no finalizer, no allocation, contiguous arrays, vector kernels. Overhead 1.2–1.7× (products) and 2–4× (division, sqrt) over plain `dfloat` per FLINT's own measurements *(docs)*. The foreign call and `Ref` copy still dominate tiny operations; benchmark `DFloatBall{2}` against `DFloat{2}` and `ArbBall{128}` for add, mul, div, sqrt, exp.
- ▲ **Radius growth on long chains.** `rad` is a double accumulating rounding errors; very long accumulations widen it (the same as any ball arithmetic). Offer `canonicalise`-free reductions (`sum` via vector kernels) and document `ArbBall` for deep computations.

### 6.4 Correctness risks surfaced by the review

1. `Ref`-based output for inline types must write into genuinely writable storage and read the result back (enact §6.1). The protocol's `_with` enforces this in one place.
2. Hashing/`isequal` for `DFloat` and `DFloatBall`: equal values can have different component tuples (and `W` has several bit patterns); canonicalise before hashing (FLINT's `dN_equal` compares values).
3. **`NFloat` is finite-only (decided in M1 from evidence).** The pinned `nfloat` special-value handling is incomplete: with `ALLOW_INF|ALLOW_NAN`, `nfloat_add(Inf, 1)` returns NaN, and `nfloat_mul` returns `GR_UNABLE` for any operand that is Inf, NaN or zero-times-zero (`src/nfloat/nfloat.c`, `nfloat_add`/`nfloat_mul`). Context flags are therefore `NFLOAT_ALLOW_UNDERFLOW` only: no `Inf`/`NaN` values (`DomainError` on conversion), `x/0` throws `DivideError`, underflow flushes to zero, and the non-special fast kernels stay enabled. `isinf`/`isnan` are constant `false` (to add with M2). Revisit if upstream completes special values.
4. `GR_UNABLE` leaves ball outputs **unspecified** *(docs)*; every ball wrapper must overwrite the result with `W` on that status, including each element of a vector kernel.
5. `dfloat_is_supported()` governs `DFloatBall` as well as `DFloat`; failing it disables both with a clear error.

6. `ArbFloat` NaN handling: `arf_cmp`/`arf_equal` are not IEEE on NaN; the wrapper must test `arf_is_nan` first in `==`, `<`, `isless`, `isequal`, `hash`, `min`/`max`.
7. Precision invariant must be enforced at **every** entry point (constructors, `set!`, conversions from balls, `ldexp`, parts of complex values, elements written into `PackedVector`); add a debug-mode assertion `arf_bits(x) ≤ P` in tests.
8. `acf` documentation is internally inconsistent in the pinned tree (its introduction calls division and square root approximate, while `acf_div`/`acf_sqrt` are documented as correctly rounded and separate `acf_approx_*` functions exist). **M1 result:** `acf_add/sub/mul/div` pass a differential test (each part correctly rounded against exact results in all five modes, P in {5,24,53}). **M2 result:** `acf_sqrt` passes the same differential test (principal branch, each part, all five modes), so "each part correctly rounded" holds for `AcbFloat` `+ - * / sqrt` on the sampled range. See [capability_table.md](capability_table.md).
9. The pinned documentation is for 3.7.0-dev; `arf`/`acf` elementary functions with a rounding argument may not exist in released FLINT. Record the minimum version in the inventory.

### 6.5 What this design intentionally does not do

No single storage type, no universal rounding mode, no implicit `Real` promotion rules, no `BigFloat` fallbacks, no cross-family arithmetic in v1 (`DFloat + NFloat` is an explicit conversion), no scoped runtime default precision, no global rounding mode (`setrounding` is not supported; the mode is an argument), no FLINT relaxed rounding modes in v1. Each omission avoids a hidden performance or guarantee cliff.

## 7. Status and error mapping (shared across families)

| C result | Julia |
| --- | --- |
| Success | return value |
| Domain error (e.g. `log` of a nonpositive real ball) | `DomainError` for point ops; indeterminate ball enclosure for ball ops where FLINT specifies one |
| Unable (ball contains zero in a divisor, algorithm unavailable) | indeterminate enclosure for balls, descriptive error otherwise |
| Unsupported option or function | `MethodError` or `ArgumentError`, never silent fallback |

The proposed shared mapping would live in `_status`; current family implementations interpret statuses locally. Nfloat vector methods share the checked kernel and commit logic in `src/reusable.jl`.

## 8. Decisions needed before coding

| Decision | Recommendation | Evidence to gather |
| --- | --- | --- |
| `NFloat{L}` (limbs) vs `NFloat{P}` (bits) in the public name | **Resolved (M1):** `NFloat{L}` plus `NFloatType(bits)` | Layout probe confirms header 2 words + `L` limbs; `test/abi_tests.jl` |
| Single-object owned values (`ArbFloat`, `AcbFloat`, `ArbBall`, `AcbBall`) vs wrapper + owner | **Resolved (M1):** single object (1 allocation of 48/64/80/112 B per fresh value, 0 for `add!`) | `benchmark/results/m1_scalar.txt` |
| Native vs FLINT for `DFloat{2..4}` `+ - *` | FLINT first (add: 5.5 ns at N=2, 9 ns at N=4, 0 allocations); native only if a later benchmark justifies | `benchmark/results/m1_scalar.txt` |
| Shared vs task-owned `NFloat` context | **Resolved (M1):** shared, immutable after `__init__` (no context writes in `src/nfloat`; 8-task test) for `+ - * /` | Re-audit per added function |
| `acc = add!(acc, …)` convention | **Adopted (M1):** owned types mutate and return the destination; `add!` is 0-allocation (8.7–20.6 ns at 128 bits) | `benchmark/results/m1_scalar.txt` |
| Precision as type parameter for balls (`ArbBall{P}`, `AcbBall{P}`) | **Adopted (requested).** Matches `DFloat{N}`/`NFloat{L}` and `ArbNumerics.jl`; precision is constant per type; promotion gives `max`. Costs: recompilation per new `P`, no scoped runtime default (`ArbBall(x)` uses compile-time `DEFAULT_PRECISION`), adaptive code must use `with_precision` barriers. Fallback if latency is unacceptable: hybrid `ArbBall{P}` with `P = 0` meaning "precision stored in the value" (second code path, extra promotion rules). | **M1 measurement:** first use of a new `P` costs 6–8 ms (`ArbBall{1001..1003}`, `NFloat{5,6}`), then microseconds; acceptable, hybrid fallback not needed yet. Still to measure: ten-precision refinement loop and precompilation size |
| Complex dfloat and complex nfloat | Deferred: `DFloatComplex{N}`/`DFloatComplexBall{N}` (`dNc`, `dNcb`) and complex `NFloat` | Confirm deferral; M1 symbol audit of `d?c_*`, `d?cb_*`, `nfloat_complex_*` |
| `DFloatBall` product error tracking vs `DFLOAT_FAST` | Tight (exact-input-exact) by default; `FAST` only if benchmarks justify | Radius width and timing on typical workloads |
| `DFloatBall` order via `dNb_cmp` vs endpoint test | **Resolved (M3):** exact endpoint test for all four relations; `dNb_cmp` stays a test cross-check (it returns `GR_UNABLE` for touching balls) | `test/compare_tests.jl` |
| Type names | **Settled:** points `DFloat`, `NFloat`, `ArbFloat`, `AcbFloat`; balls `DFloatBall`, `ArbBall`, `AcbBall`. Pairing functions `pointtype`, `balltype`, `realtype`, `complextype` | none |
| Precision invariant (mantissa ≤ `P` bits for the arb types) | **Adopted** | Test with a bit-length assertion at every entry point |
| Rounding interface for `ArbFloat`/`AcbFloat` | **Adopted:** trailing `RoundingMode`, strict modes only, `_inexact` variants for the flag | **M1 evidence:** `+ - * /` of `ArbFloat` bit-identical to MPFR for P in {5,24,53} in all five modes (9000 cases each family); `AcbFloat` `+ - * /` each part correctly rounded in all five modes (9000 cases) |
| FLINT relaxed modes (`ARF_RND_FAST`/`ACCURATE`) and `approx` kernels | Not in v1; later opt-in such as `FastRounding()` if benchmarks justify | Speed gain at high precision vs loss of reproducibility |
| `ArbFloat` `x/0` | Follow FLINT: NaN | Confirm users accept the departure from IEEE; alternative is a wrapper special case returning `±Inf` by the sign of `x` |

## 9. Next steps

M0–M3 and M4a–M4c are implemented. Copied-read documentation, `eachborrow`, and flat in-place
broadcast complete the first surrounding-interface steps in [enact_interfacing.md §9.4](enact_interfacing.md).
The prior M4c full-suite baseline passed 13,709 tests; this update uses focused broadcast and directly
affected packed-owner checks, plus documentation/doctests. The shared protocol in §4 remains unfactored.

1. **§9.4.4:** borrowed sum with a fresh typed result and bounded scratch, preserving generic keyword/callback behavior.
2. **M4d:** borrowed sum, then selected native dot methods with independent numerical/conjugation
   contracts; mapped reductions and measured matrix work follow their own gates.
3. **M5:** elementary/special functions, portable artifacts, and verified CI/release targets.

Use the development guide for acceptance criteria and [capability_table.md](capability_table.md)
for the implemented operation set. Bounded nested broadcast is implemented with per-node scratch (≤8 arithmetic nodes, depth ≤16). Specialized reductions are not available yet.
