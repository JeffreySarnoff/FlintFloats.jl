# Checkpoint

State of FlintFloats.jl after milestones M0–M3 of [enact_interfacing.md](enact_interfacing.md), plus a
correctly rounded `AcbFloat` modulus. Written to resume the work cold.

- Last commit: `c03df7d` "Implement M3: Julia numeric contracts". Working tree clean at that point.
- Tests: 6540 pass (`julia --project=. -e 'using Pkg; Pkg.test()'`, about 15 s).
- Pinned FLINT: 3.7.0-dev, source `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25, wrapper
  `FLINT_jll 301.690.0+0` (host-tuned: x86_64 Linux, i9-14900K).
- Julia floor: 1.13 (developed on 1.13.3).

## 1. What exists

Seven public types, precision in the type everywhere.

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

Not implemented: elementary functions, containers and bulk kernels, a shared internal protocol across
families, portable artifacts, CI for the host-tuned artifact, `DFloat`/`NFloat` complex types.

## 2. Layout

| Path | Contents |
| --- | --- |
| `src/FlintFloats.jl` | module, include order, exports, `__init__` (dfloat gate, nfloat contexts) |
| `src/libflint/` | `LibFlint.jl` plus `generated/*.jl` (one ccall per bound symbol; do not edit) |
| `src/{dfloat,dfloatball,nfloat,arf,acf,arb,acb}.jl` | one family each |
| `src/{precision,storage,typegrid,conversions,show,compare,promotion,basefloat}.jl` | cross-cutting |
| `gen/` | `inventory.toml` (every bound symbol), `inventory.jl`, `audit.jl`, `generate.jl`, own env |
| `test/abi/` | `probe.c`, `run.sh`, `layout.txt` (recorded C layout evidence) |
| `test/*_tests.jl` | abi, construction, conversion, unary, compare, promotion, basefloat, arithmetic, ownership |
| `benchmark/` | own env; `m1_scalar.jl`, results in `benchmark/results/` |
| `docs/` | `float_interfacing.md` (contract), `plan_interfacing.md`, `enact_interfacing.md` (procedure), `capability_table.md`, this file |

## 3. How to run things

```sh
julia --project=. -e 'using Pkg; Pkg.test()'                  # tests
julia --project=gen gen/audit.jl                              # every inventory symbol resolves in libflint
julia --project=gen gen/generate.jl                           # regenerate bindings; run twice, expect no diff
./test/abi/run.sh                                             # rebuild test/abi/layout.txt from the C probe
julia --project=benchmark benchmark/m1_scalar.jl              # scalar benchmark
julia --project=docs docs/make.jl                             # documentation site
cd docs && pandoc enact_interfacing.md -f gfm -o enact_interfacing.docx
```

The probe needs the build tree at `/tmp/flintfloats-jll-build` (not in the repo) and the OpenBLAS32 artifact
directory (`BLAS_LIBDIR`). `Manifest.toml` of `gen/`, `benchmark/` and `docs/` are gitignored; each environment
develops `FlintFloat.jl/FLINT_jll` by path.

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

Per the process: **M4, bulk arithmetic**: concrete fixed-format arrays, packed ball vectors, explicit
borrowing, selected native kernels (`dNb_vec_*`, `_nfloat_vec_*`), with aliasing, lifetime, empty and strided
input tests and benchmark evidence. Then **M5**: elementary functions, portable artifacts, CI.

Open question for the owner: pull a small set of elementary functions (`exp`, `log`, `sin`, `cos`, `atan`)
forward ahead of M4, or keep the M4 then M5 order.
