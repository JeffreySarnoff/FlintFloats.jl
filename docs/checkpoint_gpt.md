# FlintFloats.jl development checkpoint

## Latest continuation: M5 elementary ball functions

Previous step: `d3d0dcb` verifies nfloat square-root truncation (13,314 focused checks across all
supported limbs). This step adds `exp`, `log`, `sin`, `cos`, and `atan` for real/complex balls,
with allocating and qualified destination forms in `src/elementary.jl`. Domain/branch contracts,
source guarantees, and aliasing are recorded in [elementary.md](elementary.md).
Validation: 291 focused ball elementary checks pass using MPFR directed bounds and exact rational
complex series with proved tails; 319-symbol audit, deterministic regeneration, and documentation/
doctests pass. Reused destinations allocate zero warmed Julia bytes in the recorded workloads.
Ten new symbols increase the inventory to 319. Complete-operation allocation/runtime/radius
measurements are in `benchmark/results/elementary_balls.txt`. No whole-suite rerun.
Next: individually audited point-family elementary functions, then compatible CI and portable
artifact/release gates. Matrices and extra mappings remain conditional on measured need.




This handoff covers M0–M3, M4a–M4c, and reusable nfloat scratch. This checkpoint includes conjugating dot (`f5d929a`) and the mapped reduction update in
`src/packed_reduce.jl`, its focused tests, and benchmarks. It does not replace the [public interface contract](float_interfacing.md),
[capability table](capability_table.md), or [development guide](enact_interfacing.md). Check the current
tree before acting. Sum, conjugating dot, and selected `abs2` mapped reductions are implemented; see the latest continuation above.

## Repository and binary state

- **Completed milestones:** M0 (binary contract), M1 (representations), M2 (scalar arithmetic), and M3 (Julia numeric contracts). M4a (inline vector arithmetic), M4b (nfloat vectors), and reusable nfloat scratch are also implemented. M4c packed ball owners/borrowing and §9.4.1–2 documentation/`eachborrow` are also implemented; flat in-place broadcast is implemented; bounded nested broadcast is implemented; borrowed sum is implemented; audited dot products are implemented; selected `sum(abs2, v)` is also implemented.
- **Julia floor:** 1.13; local development uses 1.13.3.
- **Pinned library:** FLINT `3.7.0-dev`, source commit `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25. The nested `FlintFloat.jl/FLINT_jll` package has version `301.690.0+0`; the main project resolves it by path.
- **Artifact constraint:** The bundled x86_64 Linux binary is tuned for the development host (i9-14900K, glibc 2.43). It is unsuitable as a portable CI or release artifact. The BinaryBuilder recipe exists but has not been validated on the target matrix.
- **Commit context:** The sum implementation is `4712769`, following `409f81e` (bounded nested broadcast) and `a140f35` (flat broadcast). Packed dot, bindings, dependencies, tests, benchmarks, and documentation were committed in `f5d929a`. All three requested development steps are complete. Inspect `git status` before resuming; earlier checkpoints are available in Git history.

## Implemented numeric interface

All seven public types carry precision in their type. Real types subtype `FlintReal <: AbstractFloat`; complex types subtype `Number`.

| FLINT family | Point type | Enclosure type | Parameter | Storage |
| --- | --- | --- | --- | --- |
| dfloat | `DFloat{N}` | `DFloatBall{N}` | N doubles, 1–4 | Immutable inline values |
| nfloat | `NFloat{L}` | — | L limbs, 1–66 on the pinned 64-bit build | Immutable inline value; finite only |
| arf/arb | `ArbFloat{P}` | `ArbBall{P}` | P bits | Mutable, owned FLINT storage |
| acf/acb | `AcbFloat{P}` | `AcbBall{P}` | P bits | Mutable, owned FLINT storage |

The implementation includes constructors, copying, classification, parsing/display, `zero`/`one`, `+ - * /`, `sqrt`, `abs`, `abs2`, `real`, `imag`, `conj`, midpoint/radius accessors, and destination operations where the storage permits them. The [capability table](capability_table.md) lists the precise operation and family combinations; an operation in this paragraph should not be read as available for every type. The private destination methods (`FlintFloats.add!`, `mul!`, and related methods) are deliberately not exported.

M3 added cross-precision and mixed-family comparison, explicit ball proof relations, `isequal`/hash, narrow promotion, checked conversion, and selected Base floating-point methods. `NFloatType(bits)` constructs the type from a bit count. `with_precision(f, bits)` calls `f(Val(bits))`; `DEFAULT_PRECISION = 256` is compile-time. There is no scoped runtime `setprecision`.

## Bulk interface and reusable scratch

`FlintFloats.add!(dest, x, y)` and `mul!` support matching-format `DFloat{N}`, `DFloatBall{N}`, and
`NFloat{L}` vectors with matching axes. Destinations must have independent strided slots; gather
inputs have scalar fallbacks. Exact aliasing is permitted via `===`; other possible destination/input
overlap is rejected before mutation. Contiguous aligned ball addition uses `_dNb_vec_add` at length
≥ 4; contiguous aligned nfloat inputs use `_nfloat_vec_add`/`_nfloat_vec_mul`. Dfloat-family multiply
uses scalar loops. These are elementwise operations, not matrix multiplication or dot products.

The exported `NFloatWorkspace(NFloat{L}, capacity=0)` supplies private scratch to four-argument
`FlintFloats.add!(dest, x, y, work)`/`mul!` calls. `sizehint!(work, capacity)` reserves initialized slots;
operations also grow automatically. Only new slots are initialized; smaller operations process and
commit only their active prefix. There is no shrink operation. The format is fixed, context pointers
are acquired per call, and scratch fields are private. An atomic guard rejects concurrent/reentrant
operations and reservation; independent concurrent operations require separate workspaces.

Nfloat kernels OR-combine status bits; overflow under finite-only flags writes zero placeholders and
reports failure. Both allocating and workspace forms commit to the destination only after success.
Underflow intentionally flushes to zero. Numerical or input-read failure preserves the destination,
including exact aliases, and releases the workspace for later reuse. Scratch must not overlap any
operand and is not exposed as a result; its contents after failure are unspecified. The dfloat scalar
fallback does not promise unchanged destinations on arbitrary custom-input exceptions.

`src/arrays.jl` owns shared vector validation and dfloat dispatch. `src/reusable.jl` owns workspace
lifecycle and shared native/scalar nfloat kernels. Three-argument nfloat calls allocate fresh scratch
without allocating a workspace object; four-argument calls reuse it. The tested warmed native and
strided paths allocate no Julia heap memory within capacity, but validation/guard and commit-copy
costs remain. See [recorded measurements](../benchmark/results/reusable.txt); reuse is not universally
faster on tiny vectors or when large-format native multiplication dominates.

## Packed ball ownership and borrowing (M4c)

`PackedBallVector(ArbBall{P}, n)` and the `AcbBall{P}` form own one initialized FLINT allocation;
`PackedBallVector(T, values)` copies in values. Length and allocation are fixed. One idempotent
finalizer clears all initialized elements and frees the allocation; failed population cleans up
immediately. Indexing copies an independent scalar; assignment rounds with containment to destination
precision. Copy/deepcopy never duplicate owning pointer bytes. Ordinary Base array semantics work. The broadcast and reduction follow-ups below add optimized
assignment broadcast and native/borrowed dot products; native matrix methods remain unavailable.

`borrow(v, i)` on packed owners/views returns a nonnumeric `BorrowedBall` retaining its fixed parent.
Read a copy using `r[]`/`copy(r)`, mutate with `r[] = x`, `FlintFloats.set!`, or same-format scalar
`add!`/`sub!`/`mul!`/`div!`. References have no independent finalizer/raw-pointer constructor and reject
already-finalized parents. Mutations affect the parent; ordinary copied reads do not. Concurrent
operations require independent destination slots and no explicit parent finalization during use.

Vector add uses `_arb_vec_add`/`_acb_vec_add` for direct packed vectors; views and multiply use borrowed
scalar calls. Identical formats/axes and independent strided destination slots are required. Exact
aliases are supported; other possible destination/input overlap is rejected. Empty operations skip C.
Validation failures preserve destinations; custom input-read exceptions may partially update valid
balls. Indeterminate enclosures follow FLINT. Arithmetic throughput is comparable to scalar-owner
loops; native layout and construction/cleanup are the principal measured advantages so far.

## Explicit borrowed iteration follow-up

`eachborrow(v)` is exported; its iterator type is private and retains the span. It yields concrete,
immutable `BorrowedBall{T}` references in logical full/strided/reversed/gathered order. Saved references
keep their original parent slot; duplicates in a gather refer to the same slot per occurrence.
Construction and every iteration step check finalized parents, including empty/end states. Ordinary
indexing and iteration still copy; `r[]` also copies. Retaining an iterator/reference retains the whole
parent, while an independent copied scalar can outlive it. Typed warmed iteration avoids per-element
Julia allocation; collecting references intentionally allocates their collection. Numerical kernels
and native declarations are unchanged. Prefer bulk methods for matching whole-vector work.

## Flat in-place broadcast follow-up

`src/packed_broadcast.jl` specializes only the packed destination `copyto!` seam. Identity, binary
addition, and multiplication with same-format packed/owned-scalar/`Ref(value)` leaves reuse initialized
storage. Direct packed set/add reuse native kernels; other recognized spans, scalar/singleton
expansion, and multiplication use borrowed destinations. Shapes and open parents are checked before
writing. Base's `broadcast_unalias` snapshots possibly overlapping views, including expanded singletons,
using existing type-preserving unalias-copy rules. Snapshot native memory can be proportional to the
whole parent; timings report that cost separately. Explicit bulk methods keep overlap rejection.

Unsupported/custom expressions, other Ref kinds, ordinary array inputs, mixed formats/types, and repeated
indices on the destination use an explicit invocation of Base's generic method selected before mutation.
No error retry or global broadcast style is added. Generic callback effects and allocating result types
are retained. Fast-path evaluation errors may partially update a valid destination. Empty recognized
calls skip C and scalar Ref reads after validation. Numerical kernels and C bindings are unchanged.

## Bounded nested broadcast and reductions

Bounded nested assignment broadcast supports identity, unary negation, and binary `+`, `-`, `*`, `/`
with at most eight arithmetic nodes and depth 16. Each node occurrence owns separate scratch, so
live sibling values and repeated subexpressions preserve scalar evaluation order and precision.
All snapshots and scratch are prepared before mutation; unsupported trees select Base's fallback.

`src/packed_reduce.jl` implements plain `sum` using one fresh owned accumulator and borrowed reads.
Empty results are typed zero; singleton results are independent. Keyword and mapped sums remain
generic. `LinearAlgebra.dot` conjugates the first complex operand and returns independent owned
storage, with native/borrowed path details and enclosure evidence recorded below.

## Behavioral decisions that matter when extending the code

- Ball comparisons express proofs. Unproved equality or ordering returns `false`; `!=` is implemented separately from negated equality. Balls do not support numeric `isless`, `min`, `max`, or `sort`; use `sortkey` for presentation order.
- A ball-to-point conversion is never implicit. A point-to-ball conversion must contain the represented point. `ArbBall(Inf)` denotes an exact infinite ball; `DFloatBall(Inf)` denotes the whole real line.
- `NFloat` uses `NFLOAT_ALLOW_UNDERFLOW` only. It rejects Inf/NaN, throws on division by zero, and its division is truncated with error under one ulp. Do not add special-value handling or a correctness claim without a new source audit and tests.
- `ArbFloat` follows FLINT rather than IEEE signed-zero behavior: no negative zero, and division by zero yields NaN. Strict rounding modes are passed explicitly to `ArbFloat` and `AcbFloat` operations.
- `AcbFloat` `abs`/`abs2` use a custom exact-rounding path in `src/acf.jl`; do not replace it with a midpoint approximation. Sampled differential tests support the rounding claims but are not a proof over all values.
- Owned `arf`/`acf`/`arb`/`acb` values have a single object and finalizer. Copying must initialize independent storage; destination operations may reuse storage. Packed borrowed elements retain their fixed-size parent and check that it remains open.
- `DFloatBall` order uses exact endpoints; FLINT's `dNb_cmp` alone cannot prove some touching cases. Keep `GR_UNABLE`/indeterminate enclosure handling explicit.
- Promotion is intentionally narrow. `DFloat` with `NFloat`, `DFloatBall` with the arb family, and mixes with `BigFloat` require explicit conversion. See `src/promotion.jl` before adding a mixed operator.

## Source map and development commands

| Path | Purpose |
| --- | --- |
| `src/FlintFloats.jl`, `src/types.jl` | Module composition, exports, type hierarchy |
| `src/{dfloat,dfloatball,nfloat,arf,acf,arb,acb}.jl` | Family implementation |
| `src/{precision,storage,typegrid,conversions,show,compare,promotion,basefloat}.jl` | Shared numerical and Julia behavior |
| `src/arrays.jl`, `src/reusable.jl` | Bulk validation/dispatch; workspace owner, growth/exclusive-use guard, shared nfloat kernels and commit |
| `src/packed.jl` | Packed owners, parent-retaining references, semantic array copying, native add and borrowed scalar arithmetic |
| `src/packed_broadcast.jl` | Flat/bounded nested assignment broadcast, alias snapshots, per-node scratch, Base fallback |
| `src/packed_reduce.jl` | Fresh borrowed sum, conjugating native/borrowed dot, generic mixed-format fallback |
| `src/libflint/generated/` | Generated C declarations; edit the inventory, not these files |
| `gen/inventory.toml`, `gen/{audit,generate}.jl` | Symbol inventory, audit, deterministic generation |
| `test/abi/` | Matching-header layout probe and recorded evidence |
| `test/*_tests.jl` | Numeric, ownership, conversion, comparison, promotion, Base, arithmetic, vector, and workspace checks |
| `benchmark/results/{m1_scalar,m4a_vectors,m4b_vectors,reusable,m4c_packed}.txt` | Scalar/latency, bulk/context/copy, and reusable-scratch measurements |

From the repository root:

```sh
julia --project=. -t 4 -e 'include("test/packed_reduce_tests.jl"); include("test/packed_dot_tests.jl")'
julia --project=. -t 4 -e 'include("test/packed_broadcast_tests.jl"); include("test/packed_nested_broadcast_tests.jl")'
julia --project=gen gen/audit.jl
julia --project=gen gen/generate.jl
julia --project=benchmark benchmark/m1_scalar.jl
julia --project=benchmark benchmark/m4a_vectors.jl
julia --project=benchmark benchmark/m4b_vectors.jl
julia --project=benchmark benchmark/reusable.jl
julia --project=benchmark benchmark/m4c_packed.jl
julia --project=benchmark benchmark/packed_iteration.jl
julia --project=benchmark benchmark/packed_broadcast.jl
julia --project=benchmark benchmark/packed_nested_broadcast.jl
julia --project=benchmark benchmark/packed_sum.jl
julia --project=benchmark benchmark/packed_dot.jl
```

After a change, rerun only tests covering what changed. Nested broadcast tests reuse flat-test
helpers and must follow that file. No source tests were rerun for this documentation-only refresh;
the verification section records the completed implementation checks.

The ABI probe (`./test/abi/run.sh`) expects an external FLINT build tree under `/tmp/flintfloats-jll-build` and a configured OpenBLAS32 library directory. Inspect the script before relying on it in a clean environment. `docs/make.jl` builds the documentation in its own Julia project.

For a new FLINT operation, update `gen/inventory.toml`, audit the symbol, regenerate bindings, add the Julia method and a numerical test suited to its stated guarantee, then update `docs/capability_table.md`. Keep the inventory, implementation, test, and capability row in one change.

## Verification at this checkpoint

Latest dot follow-up: **346 dot checks** and **205 sum checks** pass with four Julia threads;
documentation/doctests pass. Tests cover exact uncertain endpoint oracles, nonreal singleton
conjugation, signed/gathered spans, precision, cancellation, nonfinites, mixed interfaces, heap-backed
result lifetime after parent cleanup, concurrent readers, and method ambiguities. The previous nested
step passed 781 flat plus 215 nested checks. No whole-suite rerun was performed; 13,709 is the historical
M4c full-suite baseline, not a fresh count for this source.

All **309** inventoried symbols resolve and bindings regenerate twice without drift. New entries are
`arb_dot` and unconjugated `acb_dot`. Public real dot uses native signed strides. Finite complex spans
of length ≥4 use four real-part native dots with two real accumulators and an independent complex
result. Small/gathered/nonfinite/unsupported-part-stride cases use borrowed conjugate/product/sum
storage. Mixed formats delegate to generic LinearAlgebra. `acb_dot` is used only by the private
conjugated-copy benchmark alternative. Standard-library dependency/import and manifests are updated.

`benchmark/results/packed_dot.txt` reports complete generic/public calls and private candidates,
including finite validation, conjugated-copy allocation/cleanup, Julia allocation counts, radius
quality, and severe cancellation. Part-stride native dots were faster on these workloads and avoid
an O(n) copy; enclosure widths are not guaranteed to match generic or conjugated-copy accumulation.
Read-only parents stay alive across C calls; every output is independent and empty calls skip pointers.
No process-global thread settings or relaxed arithmetic modes are changed.

## Next work and open limits

1. **Close scalar evidence gaps (§9.5):** establish independent nfloat square-root differential
   evidence before expanding elementary functions. Additional mapped reductions require measured need.
2. **Measured matrix work only if needed:** native dot support does not establish matrix layout or
   justify a speculative storage type. Other-family bulk/dot expansion requires its own evidence.
3. **M5:** elementary/special functions, portable artifacts, and verified CI/release targets.

Remaining gaps include native matrix methods, further specialized mapped reductions, packed point owners,
complex dfloat/nfloat public types, Rational/Complex{Float64} interop, portable artifacts, and further elementary
functions. NFloat sqrt now has all-limb exact integer-root and MPFR differential evidence. The proposed shared scalar protocol remains
unfactored. The host-tuned artifact is unsuitable for generic CI. Historical drafts remain superseded.
