# FlintFloats.jl development checkpoint

This handoff covers M0–M3, M4a/M4b, and the reusable-scratch source update. The last implementation
commit before this update is `d7b2b58` (M4b); this checkpoint is committed with `src/reusable.jl`, its
integration, tests, benchmarks, and documentation. It does not replace the [public interface contract](float_interfacing.md),
[capability table](capability_table.md), or [development guide](enact_interfacing.md). Check the current
tree before acting. The next implementation part is **M4c: packed ball owners and borrowing**.

## Repository and binary state

- **Completed milestones:** M0 (binary contract), M1 (representations), M2 (scalar arithmetic), and M3 (Julia numeric contracts). M4a (inline vector arithmetic), M4b (nfloat vectors), and reusable nfloat scratch are also implemented. M4c is next.
- **Julia floor:** 1.13; local development uses 1.13.3.
- **Pinned library:** FLINT `3.7.0-dev`, source commit `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25. The nested `FlintFloat.jl/FLINT_jll` package has version `301.690.0+0`; the main project resolves it by path.
- **Artifact constraint:** The bundled x86_64 Linux binary is tuned for the development host (i9-14900K, glibc 2.43). It is unsuitable as a portable CI or release artifact. The BinaryBuilder recipe exists but has not been validated on the target matrix.
- **Commit context:** source and documentation changes described here are committed together. Earlier M3-only checkpoints are available in Git history.

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

## Behavioral decisions that matter when extending the code

- Ball comparisons express proofs. Unproved equality or ordering returns `false`; `!=` is implemented separately from negated equality. Balls do not support numeric `isless`, `min`, `max`, or `sort`; use `sortkey` for presentation order.
- A ball-to-point conversion is never implicit. A point-to-ball conversion must contain the represented point. `ArbBall(Inf)` denotes an exact infinite ball; `DFloatBall(Inf)` denotes the whole real line.
- `NFloat` uses `NFLOAT_ALLOW_UNDERFLOW` only. It rejects Inf/NaN, throws on division by zero, and its division is truncated with error under one ulp. Do not add special-value handling or a correctness claim without a new source audit and tests.
- `ArbFloat` follows FLINT rather than IEEE signed-zero behavior: no negative zero, and division by zero yields NaN. Strict rounding modes are passed explicitly to `ArbFloat` and `AcbFloat` operations.
- `AcbFloat` `abs`/`abs2` use a custom exact-rounding path in `src/acf.jl`; do not replace it with a midpoint approximation. Sampled differential tests support the rounding claims but are not a proof over all values.
- Owned `arf`/`acf`/`arb`/`acb` values have a single object and finalizer. Copying must initialize independent storage; destination operations may reuse storage. Borrowed array elements require a parent lifetime rule before they are introduced.
- `DFloatBall` order uses exact endpoints; FLINT's `dNb_cmp` alone cannot prove some touching cases. Keep `GR_UNABLE`/indeterminate enclosure handling explicit.
- Promotion is intentionally narrow. `DFloat` with `NFloat`, `DFloatBall` with the arb family, and mixes with `BigFloat` require explicit conversion. See `src/promotion.jl` before adding a mixed operator.

## Source map and development commands

| Path | Purpose |
| --- | --- |
| `src/FlintFloats.jl`, `src/types.jl` | Module composition, exports, type hierarchy |
| `src/{dfloat,dfloatball,nfloat,arf,acf,arb,acb}.jl` | Family implementation |
| `src/{precision,storage,typegrid,conversions,show,compare,promotion,basefloat}.jl` | Shared numerical and Julia behavior |
| `src/arrays.jl`, `src/reusable.jl` | Bulk validation/dispatch; workspace owner, growth/exclusive-use guard, shared nfloat kernels and commit |
| `src/libflint/generated/` | Generated C declarations; edit the inventory, not these files |
| `gen/inventory.toml`, `gen/{audit,generate}.jl` | Symbol inventory, audit, deterministic generation |
| `test/abi/` | Matching-header layout probe and recorded evidence |
| `test/*_tests.jl` | Numeric, ownership, conversion, comparison, promotion, Base, arithmetic, vector, and workspace checks |
| `benchmark/results/{m1_scalar,m4a_vectors,m4b_vectors,reusable}.txt` | Scalar/latency, bulk/context/copy, and reusable-scratch measurements |

From the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=gen gen/audit.jl
julia --project=gen gen/generate.jl
julia --project=benchmark benchmark/m1_scalar.jl
julia --project=benchmark benchmark/m4a_vectors.jl
julia --project=benchmark benchmark/m4b_vectors.jl
julia --project=benchmark benchmark/reusable.jl
```

The ABI probe (`./test/abi/run.sh`) expects an external FLINT build tree under `/tmp/flintfloats-jll-build` and a configured OpenBLAS32 library directory. Inspect the script before relying on it in a clean environment. `docs/make.jl` builds the documentation in its own Julia project.

For a new FLINT operation, update `gen/inventory.toml`, audit the symbol, regenerate bindings, add the Julia method and a numerical test suited to its stated guarantee, then update `docs/capability_table.md`. Keep the inventory, implementation, test, and capability row in one change.

## Verification at this checkpoint

The source update passed **12,759 tests** on Julia 1.13.3 with **four Julia threads**, using
`JULIA_DEPOT_PATH=/tmp/flint-checkpoint-depot:/home/jas/.julia`. Documentation and doctests pass.
Workspace tests cover growth, active prefixes, alias/type rejection, zero warmed native allocations,
overflow and input exceptions followed by reuse, and deterministic concurrent/reentrant-use rejection.
The M4b binding audit resolved all **299** inventoried symbols and regenerated twice without drift;
this workspace update adds no C bindings. Matching-header ABI evidence now includes nfloat exponent
limits. Numerical error tests use independent exact dyadics and retain their sampled scope.

## Next work and open limits

1. **M4c:** implement fixed-size packed `ArbBall{P}`/`AcbBall{P}` owners, semantic element copies,
   assignment, and explicit parent-retaining borrowing. Verify cleanup, lifetime, bounds, precision,
   containment, and aliasing before adding native arithmetic.
2. **M4d:** selected native dot products, with exact/certified references, empty sums, complex
   conjugation conventions, and independent accumulation guarantees. Evaluate matrix storage only
   after measured workloads justify it.
3. **M5:** elementary/special functions with per-operation source/rounding/domain evidence, portable
   artifacts, and CI on supported binaries. Keep elementary functions after M4.

Remaining gaps include packed ball owners/borrowing, native dot/matrix methods, elementary functions,
complex dfloat/nfloat public types, `Rational`/`Complex{Float64}` interop, and portable artifacts.
`NFloat` `sqrt` still has exact-case tests only. Huge `ArbFloat` exponents can hash like Inf (allowed).
The proposed shared `_result`/`_with`/`_status` protocol remains unfactored. The host artifact cannot
run on generic CI. `docs/planinterfacing.md` is a historical superseded draft.
