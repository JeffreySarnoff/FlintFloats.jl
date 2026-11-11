# Checkpoint

State of FlintFloats.jl after M0–M3, M4a–M4c bulk arithmetic, and reusable nfloat scratch from
[enact_interfacing.md](enact_interfacing.md). Written to resume the work cold.

- Last committed implementation before this update: `1ff676c` (packed owners and interface plans).
  This update implements the copied-read documentation and `eachborrow` follow-up in §9.4.1–2.
- Prior full-suite baseline: **13,709 pass**. This follow-up uses focused packed ownership/iteration
  tests and concurrency regression checks on Julia 1.13.3 with four threads, plus documentation/doctests;
  it does not rerun the full suite.
- Binding inventory now includes **307** audited symbols (M4c adds eight); regenerate twice without drift.
- Pinned FLINT: 3.7.0-dev, source `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25, wrapper
  `FLINT_jll 301.690.0+0` (host-tuned: x86_64 Linux, i9-14900K).
- Julia floor: 1.13 (developed on 1.13.3).

## 1. What exists

Seven public numeric types, precision in the type everywhere, plus the exported `NFloatWorkspace{L}` scratch owner.

| Family | Point | Ball | Parameter |
| --- | --- | --- | --- |
| dfloat | `DFloat{N}` | `DFloatBall{N}` | N doubles, 1..4 |
| nfloat | `NFloat{L}` | none | L limbs, 1..66 (finite-only) |
| arb real | `ArbFloat{P}` | `ArbBall{P}` | P bits |
| arb complex | `AcbFloat{P}` | `AcbBall{P}` | P bits |

Inline immutable: `DFloat`, `DFloatBall`, `NFloat`. Heap-owning mutable (single object, finalizer):
the four arb types.

Implemented (per [capability_table.md](capability_table.md), which is the authority):

- `+ - * /`, `sqrt`, `-`, `abs`, `abs2`, `conj`, `real`, `imag`, `midpoint`, `radius`, destination forms
  (`FlintFloats.add!`, `sub!`, `mul!`, `div!`, `neg!`, `abs!`, `sqrt!`, `set!`, `_inexact!` variants).
  None of the bang functions is exported (`mul!` would clash with LinearAlgebra).
- Rounding: `ArbFloat`/`AcbFloat` take a trailing `RoundingMode`; strict modes only.
- Classification, `zero`, `one`, constructors from integers/`BigFloat`/strings/other precisions, `parse`,
  `show` (rebuilds the value; balls rebuild a containing ball), mixed arithmetic with machine numbers.
- Type grid (`pointtype`, `balltype`, `realtype`, `complextype`), traits, `with_precision`,
  dfloat support gate.
- Equality, ordering, hashing across precisions, families and Julia numbers; ball relations as proofs;
  narrow promotion; checked `convert`; `AbstractFloat` audit (`eps`, `nextfloat`, ... for `ArbFloat`
  and `NFloat`).

- Vector `FlintFloats.add!`/`mul!` for matching concrete `DFloat`, `DFloatBall`, and `NFloat` formats.
  Contiguous ball addition and nfloat addition/multiplication use audited native kernels; other paths
  use checked scalar loops. Ordinary/strided destinations only; exact aliases allowed, other possible
  destination/input overlap rejected. Nfloat results commit from scratch only after success.
- `NFloatWorkspace(NFloat{L}, capacity)` and four-argument vector operations reuse initialized scratch.
  Capacity grows automatically; `sizehint!` reserves it. Only the active prefix is processed/copied;
  failures preserve the destination and release the workspace. Concurrent/reentrant workspace use
  and workspace/operand overlap are rejected. Use one workspace per concurrent operation.

- `PackedBallVector(T, n/values)` for real/complex balls: fixed-size initialized storage, independent
  copied indexing, containing assignment, semantic copy/deepcopy, ordinary iteration/similar/fill/broadcast.
- Explicit `borrow(v, i)` references retain the parent, never clear slots, and support copied `r[]`
  reads, semantic writes, and qualified same-format scalar destination arithmetic. Packed vector add
  uses native kernels; views/multiply use borrowed scalar calls. Exact aliases are supported; other
  possible overlap and gathered destinations are rejected. Custom-input errors may partially update
  valid ball destinations. Finalization is idempotent; references reject closed parents.

- Exported `eachborrow(v)` retains its span and yields stable parent-retaining references in logical
  owner/view order. Ordinary reads and iteration still copy. Iterator traits are concrete; empty and
  resumed iteration reject finalized parents. Use bulk methods when they fit and explicit iteration
  for custom slot mutation. The concurrency regression test now gives each task independent locals.

Not implemented: native dot/matrix methods (M4d),
elementary functions, a shared internal protocol across families, portable artifacts, verified generic
CI, and `DFloat`/`NFloat` complex types.

## 2. Layout

| Path | Contents |
| --- | --- |
| `src/FlintFloats.jl` | module, include order, exports, `__init__` (dfloat gate, nfloat contexts) |
| `src/libflint/` | `LibFlint.jl` plus `generated/*.jl` (one ccall per bound symbol; do not edit) |
| `src/{dfloat,dfloatball,nfloat,arf,acf,arb,acb}.jl` | one family each |
| `src/{precision,storage,typegrid,conversions,show,compare,promotion,basefloat}.jl` | cross-cutting |
| `src/arrays.jl`, `src/reusable.jl` | vector contracts/dispatch; reusable scratch, shared nfloat kernels and commit-on-success |
| `src/packed.jl` | fixed-size packed ball owners, explicit borrowing, semantic copying, native add and borrowed arithmetic |
| `gen/` | `inventory.toml` (every bound symbol), `inventory.jl`, `audit.jl`, `generate.jl`, own env |
| `test/abi/` | `probe.c`, `run.sh`, `layout.txt` (recorded C layout evidence) |
| `test/*_tests.jl` | abi, construction, conversion, unary, compare, promotion, basefloat, arithmetic, ownership, inline/nfloat vectors, reusable workspaces |
| `benchmark/` | own env; scalar, M4a/M4b and `reusable.jl` drivers; results in `benchmark/results/` |
| `docs/` | `float_interfacing.md` (contract), `plan_interfacing.md`, `enact_interfacing.md` (procedure), `capability_table.md`, this file |

## 3. How to run things

```sh
julia --project=. -e 'using Pkg; Pkg.test()'                  # tests
julia --project=gen gen/audit.jl                              # every inventory symbol resolves in libflint
julia --project=gen gen/generate.jl                           # regenerate bindings; run twice, expect no diff
./test/abi/run.sh                                             # rebuild test/abi/layout.txt from the C probe
julia --project=benchmark benchmark/m1_scalar.jl              # scalar benchmark
julia --project=benchmark benchmark/m4a_vectors.jl            # inline ball vector benchmark
julia --project=benchmark benchmark/m4b_vectors.jl            # nfloat bulk/context/copy benchmark
julia --project=benchmark benchmark/reusable.jl               # allocating vs reused nfloat scratch
julia --project=benchmark benchmark/m4c_packed.jl             # packed lifecycle and arithmetic
julia --project=benchmark benchmark/packed_iteration.jl       # copied/manual/iterator/bulk updates
julia --project=docs docs/make.jl                             # documentation site
cd docs && pandoc enact_interfacing.md -f gfm -o enact_interfacing.docx
```

The probe needs the build tree at `/tmp/flintfloats-jll-build` (not in the repo) and the OpenBLAS32 artifact
directory (`BLAS_LIBDIR`). `Manifest.toml` of `gen/`, `benchmark/` and `docs/` are gitignored; the projects
resolve `FlintFloat.jl/FLINT_jll` through local `[sources]` paths. Instantiate each environment separately.

Adding a function: add its row to `gen/inventory.toml`, run `audit.jl` then `generate.jl`, write the Julia
method, add a differential test, add a row to `capability_table.md`, all in one change.

## 4. Decisions made (and the evidence)

- **Precision is a type parameter** for all seven types; `DEFAULT_PRECISION = 256` is compile-time; no
  `setprecision`; `with_precision(f, bits)` calls `f(Val(bits))`. First use of a new `P` costs 6-8 ms,
  then microseconds, so the hybrid fallback is not needed yet.
- **Single-object owners** for the arb types: one allocation per fresh value (48/64/80/112 B), none for `add!`.
- **Precision invariant:** mantissa at most `P` bits for `ArbFloat`, parts of `AcbFloat`, midpoints of balls.
  Internal scratch values may hold more and never escape.
- **`NFloat` is finite-only** (flags `ALLOW_UNDERFLOW` only). In the pinned source `nfloat_add(Inf,1)` is NaN and
  `nfloat_mul` returns `GR_UNABLE` for every special operand, including `0*0`. `x/0` throws `DivideError`;
  `nfloat_div` truncates (error under 1 ulp), it is not correctly rounded. Contexts are shared and immutable
  (the source never writes to them in `+ - * /`).
- **Rounding evidence:** `ArbFloat` `+ - * / sqrt` match MPFR bit for bit in all five modes (P in 5, 24, 53).
  `AcbFloat` `+ - * / sqrt abs abs2` match an exact reference per part in all five modes. These are sampled
  tests, not proofs. FLINT's own `acf` documentation contradicts itself on division and square root; the
  tests settle it for the sampled range.
- **`AcbFloat` `abs`/`abs2`:** no `acf_abs` exists, so `abs2` rounds the exact sum once and `abs` brackets the
  exact sum between two `2P+4`-bit values and resolves the rounding boundary exactly (comments in `src/acf.jl`).
- **`ArbFloat` follows FLINT, not IEEE:** no negative zero, `x/0` is NaN, unbounded exponent.
- **Points compare by exact value**; hash is the `BigFloat` hash of the exact value. A point zero is `+0`.
- **Balls:** relations are proofs and return `false` when unproved; `isequal` is representation equivalence;
  one indeterminate value (NaN midpoint, infinite radius, dfloat whole real line); no `isless`/`min`/`max`/
  `sort` (use `sortkey`); ball to point is never implicit.
- **`DFloatBall` order** uses exact endpoints because `dNb_cmp` reports "unable" for touching balls.
- **Promotion** only where nothing is lost (see `src/promotion.jl`); `DFloat` with `NFloat`, `DFloatBall` with
  the arb family and anything with `BigFloat` stay explicit.
- **`ArbBall(Inf)`** is an exact infinite ball; **`DFloatBall(Inf)`** is the whole real line.
- FLINT rounds a ball radius up to a 30-bit magnitude, so two `ArbBall`s cannot touch exactly.

## 5. Known gaps and open items

- Elementary functions are not started (scheduled for M5; FLINT exports them for every family).
  Needs per-function: inventory row, pinned guarantee, domain behaviour, differential test, table row.
- `NFloat` `sqrt` is tested on exact cases only; no differential test.
- `hash` of an `ArbFloat` whose exponent is outside MPFR's range collides with `Inf` (allowed, documented).
- `DFloat`/`NFloat` complex types, `Rational` interop, `Complex{Float64}` interop: not done.
- Shared `_result`/`_with`/`_status` protocol from `float_interfacing.md` §4 was not factored; each family has
  its own generated loop.
- CI: the artifact is tuned to the development host and cannot run on a generic runner. The workflow in
  `.github/` is scaffolding, not a verified matrix.
- Version risk: every fact above is for FLINT 3.7.0-dev; a released FLINT may lack `arf` elementary
  functions with rounding arguments or the dfloat families.
- `docs/planinterfacing.md` is the superseded first draft; `plan_interfacing.md` is current.

## 6. Next

**Flat in-place broadcast (§9.4.3)** is next, followed by bounded nested arithmetic and M4d
reductions/dot products. For M4d: independently specify accumulation guarantees, empty sums, and
complex conjugation, then audit selected native kernels and compare equivalent numerical contracts.
Matrix storage follows only where measured workloads justify it. M5 adds elementary functions,
portable artifacts, and verified CI. Keep that sequence.

Packed ball example:

```julia
v = PackedBallVector(ArbBall{128}, [1, 2, 3])
r = borrow(v, 2)
FlintFloats.add!(r, r, ArbBall{128}(1))  # v[2] becomes 3
snapshot = v[2]                         # independent owned copy
```

See [packed measurements](../benchmark/results/m4c_packed.txt); arithmetic throughput is comparable
to reused scalar-owner loops on the recorded workloads, with packed layout and construction benefits.
Zero warmed Julia allocations do not imply zero native allocation. Use independent writable slots
concurrently and never explicitly finalize their parents during use.

For repeated nfloat operations today:

```julia
T = NFloat{2}
x, y, dest = fill(T(1), 100), fill(T(2), 100), Vector{T}(undef, 100)
work = NFloatWorkspace(T, 100)
FlintFloats.add!(dest, x, y, work)
FlintFloats.mul!(dest, dest, y, work)
```

See [reusable benchmark results](../benchmark/results/reusable.txt) for warmed native and strided
reuse, construction/growth costs, and allocating comparisons. The tested warmed reused paths allocate
no Julia heap memory within capacity. Very short vectors may be slower with reuse because of the
exclusive-use guard; large-format arithmetic may dominate. Successful operations still copy to the
destination. Measurements apply to the recorded host, artifact, formats, and input distribution.
