# FlintFloats.jl development checkpoint

This records the repository state at commit `a9701ab` (`Add checkpoint of work through M3`) for the next development session. The implementation's latest commit is `c03df7d` (`Implement M3: Julia numeric contracts`); `a9701ab` adds [the companion checkpoint](checkpoint.md). This is a handoff, not a replacement for the [public interface contract](float_interfacing.md), [operation capability table](capability_table.md), or [development guide](enact_interfacing.md). Check `git status` and those documents again before acting; the repository may have advanced since this checkpoint.

## Repository and binary state

- **Completed milestones:** M0 (binary contract), M1 (representations), M2 (scalar arithmetic), and M3 (Julia numeric contracts). The next planned milestone is M4, bulk arithmetic.
- **Julia floor:** 1.13; local development uses 1.13.3.
- **Pinned library:** FLINT `3.7.0-dev`, source commit `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25. The nested `FlintFloat.jl/FLINT_jll` package has version `301.690.0+0`; the main project resolves it by path.
- **Artifact constraint:** The bundled x86_64 Linux binary is tuned for the development host (i9-14900K, glibc 2.43). It is unsuitable as a portable CI or release artifact. The BinaryBuilder recipe exists but has not been validated on the target matrix.
- **Working tree when this file was finalized:** tracked files clean; this `docs/checkpoint_gpt.md` is untracked. The companion `docs/checkpoint.md` is committed and unchanged.

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
| `src/libflint/generated/` | Generated C declarations; edit the inventory, not these files |
| `gen/inventory.toml`, `gen/{audit,generate}.jl` | Symbol inventory, audit, deterministic generation |
| `test/abi/` | Matching-header layout probe and recorded evidence |
| `test/*_tests.jl` | Numeric, ownership, conversion, comparison, promotion, Base, and arithmetic checks |
| `benchmark/results/m1_scalar.txt` | Baseline scalar measurements and first-use latency |

From the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=gen gen/audit.jl
julia --project=gen gen/generate.jl
julia --project=benchmark benchmark/m1_scalar.jl
```

The ABI probe (`./test/abi/run.sh`) expects an external FLINT build tree under `/tmp/flintfloats-jll-build` and a configured OpenBLAS32 library directory. Inspect the script before relying on it in a clean environment. `docs/make.jl` builds the documentation in its own Julia project.

For a new FLINT operation, update `gen/inventory.toml`, audit the symbol, regenerate bindings, add the Julia method and a numerical test suited to its stated guarantee, then update `docs/capability_table.md`. Keep the inventory, implementation, test, and capability row in one change.

## Verification at this checkpoint

I reran `Pkg.test()` on Julia 1.13.3 with the M3 implementation: **6,540 tests passed** in the sandbox with a writable temporary depot (`JULIA_DEPOT_PATH=/tmp/flint-checkpoint-depot:/home/jas/.julia`). The committed test suites cover ABI, construction, conversion, unary and binary arithmetic, comparison, promotion, Base methods, and ownership. Relevant arithmetic claims remain limited to the tested precisions and sampled cases described in the capability table.

## Next work and open limits

1. **M4: bulk arithmetic.** Define concrete arrays for inline values and packed owning vectors for ball values. Decide and test indexing, copying, mutation, element precision, borrowing, empty and strided inputs, exact aliasing, and partial overlap before calling native kernels.
2. Select dfloat, nfloat, arb, and acb vector/dot kernels using the pinned source's guarantees and the binding inventory. Benchmark them against scalar loops with comparable accuracy or containment. Record context and copy costs, not only hot arithmetic throughput.
3. **M5: function expansion and release.** Add selected elementary functions with per-operation domain/rounding evidence and differential tests. Build portable artifacts and establish a CI matrix supported by actual binaries before claiming platform support.

Current gaps include no containers or bulk kernels, no elementary-function surface, no complex dfloat/nfloat public types, no `Rational` or `Complex{Float64}` interop, and no portable artifact. `NFloat` `sqrt` has exact-case tests only. Hashing very large `ArbFloat` exponents can collide with Inf; this is allowed but documented. The shared internal `_result`/`_with`/`_status` protocol proposed in the interface document has not been factored; family-specific implementations currently carry it.

One sequencing choice remains: whether to add a small elementary set (`exp`, `log`, `sin`, `cos`, `atan`) before M4 or follow the documented M4 then M5 order. Until directed otherwise, continue with M4. The older `docs/planinterfacing.md` is a superseded draft; use the current interface contract, capability table, and implementation as the source of truth when they differ from a planning passage.
