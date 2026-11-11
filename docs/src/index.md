```@meta
CurrentModule = FlintFloats
```

# FlintFloats

Documentation for [FlintFloats](https://github.com/JeffreySarnoff/FlintFloats.jl).

## Reuse nfloat vector scratch

Reserve a workspace once and pass it to repeated vector operations. Each successful operation
copies its result into the destination; numerical or input-read failure leaves that destination
unchanged. Capacity grows automatically, or can be reserved with `sizehint!`. Use separate
workspaces for concurrent operations; sharing an active workspace throws an error.

```jldoctest
julia> using FlintFloats

julia> T = NFloat{2}; work = NFloatWorkspace(T, 100);

julia> x = fill(T(1), 100); y = fill(T(2), 100); dest = similar(x);

julia> FlintFloats.add!(dest, x, y, work) === dest
true

julia> all(v -> v == T(3), dest)
true

julia> FlintFloats.mul!(dest, dest, y, work) === dest
true

julia> all(v -> v == T(6), dest)
true
```

## Packed ball vectors and borrowed slots

Packed vectors own fixed-size initialized FLINT storage at their element working precision.
**Ordinary indexing and iteration return independent scalar values.** Assignment copies into a slot
with containing precision conversion. Views retain the parent, but reading a view element also copies;
writing through a view changes its mapped slot.

| Intent | Use |
| --- | --- |
| Read an independent value | `x = v[i]` or `for x in v` |
| Write a value back | `v[i] = x` |
| Convenient read/arithmetic/write update | `v[i] += step` (can allocate temporary owners) |
| Mutate one slot using its storage | `r = borrow(v, i); FlintFloats.add!(r, r, step)` |
| Mutate slots in a custom loop | `for r in eachborrow(v)` with qualified destination arithmetic |
| Reuse storage for whole-vector work | `FlintFloats.add!(dest, x, y)` / `mul!` |

`FlintFloats.add!(v[i], v[i], step)` changes a temporary, not the packed slot. Use explicit write-back
or a borrowed reference when mutation is intended:

```jldoctest
julia> using FlintFloats

julia> T = ArbBall{128}; v = PackedBallVector(T, [1, 2, 3]); step = T(1);

julia> x = v[2]; FlintFloats.add!(x, x, step); v[2] == T(2)
true

julia> FlintFloats.add!(v[2], v[2], step); v[2] == T(2)
true

julia> v[2] = x; v[2] += step; v[2] == T(4)
true

julia> selected = view(v, 3:-2:1); copied = selected[1];

julia> FlintFloats.add!(copied, copied, step); v[3] == T(3)
true

julia> selected[1] = copied; v[3] == T(4)
true

julia> r = borrow(v, 2); snapshot = r[]; FlintFloats.add!(r, r, step);

julia> v[2] == T(5) && snapshot == T(4)
true
```

### Explicit reference iteration

`eachborrow(v)` yields nonnumeric references in logical order, including strided, reversed, and gathered
views. Saved references retain their original slots after iteration; the iterator and each reference
keep the entire fixed-size parent alive. Reading `r[]` or `copy(r)` copies out, and that scalar can
survive independently of the parent. References never clear slots and reject already-finalized parents.

```jldoctest
julia> using FlintFloats

julia> T = ArbBall{128}; v = PackedBallVector(T, [1, 2, 3]); scale = T(2);

julia> for r in eachborrow(view(v, 3:-1:1))
           FlintFloats.mul!(r, r, scale)
       end

julia> all(i -> v[i] == T(2i), eachindex(v))
true

julia> refs = collect(eachborrow(v)); refs[1][] = T(10); v[1] == T(10)
true
```

The typed borrowed loop reuses slot storage; collecting references intentionally allocates a collection.
Use whole-vector destination methods when they fit. Validate matching axes before combining multiple
iterators with `zip`, which otherwise truncates to the shortest. Concurrent writes require independent
slots and no explicit parent finalization during use. Vector operations reject other possible
destination/input overlap. Flat same-format packed assignment broadcast reuses storage as described below. Recognized bounded nested arithmetic also reuses private scratch; custom expressions and specialized reductions remain generic.

## Flat in-place packed broadcast

Preallocate a packed destination and use ordinary dotted assignment. Flat identity, `+`, and `*`
with same-format packed leaves or owned scalar/`Ref(value)` leaves reuse initialized slots. Direct
packed copies/additions use native kernels; other recognized spans use borrowed scalar destinations.
Reading `v[i]` still returns an independent value, and allocating `x .+ y` keeps its existing result
container behavior.

```jldoctest
julia> using FlintFloats

julia> T = ArbBall{128}; x = PackedBallVector(T, [1, 2, 3]); y = PackedBallVector(T, [4, 5, 6]); dest = similar(x);

julia> dest .= x .+ y;

julia> all(i -> dest[i] == T(2i + 3), eachindex(dest))
true

julia> dest .= x .* Ref(T(2));

julia> all(i -> dest[i] == T(2i), eachindex(dest))
true

julia> x .= view(x, 1:1) .+ x;

julia> all(i -> x[i] == T(i + 1), eachindex(x))
true
```

Broadcast follows Base's alias preparation: overlapping views, including singleton expansion, are
snapshotted before writing. These snapshots can allocate, whereas ordinary nonoverlapping typed fast
paths avoid per-element Julia owners. Explicit `FlintFloats.add!`/`mul!` retain their overlap-rejection
policy. Repeated-index destinations, unsupported expressions, callbacks, mixed formats/types, and unsupported
inputs use Base's generic destination method without retry after errors. Evaluation errors can leave
a valid partially updated destination; this is not nfloat's commit-on-success guarantee. Bounded nested arithmetic is supported as described below; borrowed sum/dot reductions follow separately.

## Bounded nested packed broadcast

Same-format pure trees of `identity`, unary negation, and binary `+ - * /` reuse one private scalar
per node occurrence for each operation. The complete scalar tree is evaluated before writing a slot,
so repeated destination leaves retain their original value. Every node uses the scalar working
precision; there is no reassociation or fused multiply-add. Up to eight arithmetic nodes and a depth
of 16 are supported; other expressions retain Base's generic behavior. Scratch allocation depends on
tree size, not vector length; alias snapshots may still allocate full parent copies.

```jldoctest
julia> using FlintFloats

julia> T = ArbBall{128}; v = PackedBallVector(T, [1, 2, 3]);

julia> v .= v .* T(2) .+ v;

julia> all(i -> v[i] == T(3i), eachindex(v))
true
```

## Packed sum

Plain `sum(v)` accumulates through borrowed reads into one fresh owned scalar at element precision.
It encloses the exact sum and returns independent results for empty/singleton inputs too. Accumulation
is in logical view order; radius/representation can differ from Base's reassociated reduction. Julia
allocation is bounded by the result owner, not the number of terms. Calls with keywords or mapped
callbacks retain Base's generic interface; callbacks still receive copied scalar values.

```jldoctest
julia> using FlintFloats

julia> T = ArbBall{128}; v = PackedBallVector(T, [1, 2, 3]); total = sum(v);

julia> total == T(6) && sum(view(v, 3:-1:1)) == T(6)
true

julia> sum(PackedBallVector(T, 0)) == T(0)
true
```

## Squared magnitude sums

`sum(abs2, v)` uses borrowed reads and a constant number of owned temporaries. Both real and complex
inputs return a fresh `ArbBall{P}`, including empty inputs. It follows scalar squared-magnitude
arithmetic and logical accumulation order; enclosure widths may differ from Base's reduction order.
Keywords and other callbacks keep Base's generic behavior and independent copied arguments.

```jldoctest
julia> using FlintFloats

julia> v = PackedBallVector(AcbBall{128}, [AcbBall{128}(1.0, 2.0), AcbBall{128}(3.0, 4.0)]);

julia> sum(abs2, v) == ArbBall{128}(30)
true
```

## Conjugating packed dot products

Use `LinearAlgebra.dot(x, y)` for packed ball vectors and views. Complex dot conjugates its first
operand; empty inputs return a fresh typed zero. Real strided spans use native dot, while finite
complex spans of length at least four use strided real/imaginary native dots with bounded private
scratch. Small, gathered, unsupported-stride, and nonfinite complex inputs use borrowed accumulation.
Mixed formats retain LinearAlgebra's generic interface. Results are independent of input storage.

```jldoctest
julia> using FlintFloats, LinearAlgebra

julia> T = AcbBall{128}; x = PackedBallVector(T, [T(1.0, 2.0)]); y = PackedBallVector(T, [T(3.0, 4.0)]);

julia> dot(x, y) == T(11.0, -2.0)
true
```

Native and scalar accumulation can return different enclosure widths; both must contain the exact
product sum. Complex part accumulation avoids materializing a full conjugated input; benchmark reports
include that alternative and radius quality under cancellation. Dot does not rewrite unconjugated
`sum(x .* y)`, and it does not mutate inputs. Keep parents open and avoid concurrent writes/finalization
while reading; independent concurrent dot results are supported. The selected mapped reduction `sum(abs2, v)` also reuses scratch; other mapped sums continue
to work with copied scalar values.

## Selected elementary functions

`exp`, `log`, `sin`, `cos`, and `atan` return rigorous enclosures for real and complex balls.
Qualified destination forms such as `FlintFloats.exp!(dest, x)` reuse matching-format storage.
Real-domain failures retain indeterminate ball semantics; select complex balls explicitly when needed.
Complex `log` and `atan` retain FLINT's principal branches and branch cuts.

```jldoctest
julia> using FlintFloats

julia> exp(ArbBall{128}(0)) == ArbBall{128}(1)
true

julia> isindeterminate(log(ArbBall{128}(-1)))
true

julia> iszero(real(log(AcbBall{128}(-1, 0))))
true
```

Point functions also support `ArbFloat{P}` and `AcbFloat{P}`, with strict explicit rounding.

```jldoctest
julia> using FlintFloats

julia> x = ArbFloat{128}(1); lo = exp(x, RoundDown); hi = exp(x, RoundUp);

julia> lo < hi
true

julia> iszero(log(ArbFloat{128}(1)))
true
```

```@index
```

```@autodocs
Modules = [FlintFloats]
```
