# FlintFloats.jl development checkpoint

State after M0–M3, M4 bulk/packed follow-ups, and the five selected M5 elementary functions from
[enact_interfacing.md](enact_interfacing.md). This snapshot accompanies the inline-function update;
its base commit is `cd36c41` (strict arb/acf elementary functions). Inspect `git log` and `git status`
for the current commit and any subsequent changes.

## Implemented

Seven public scalar types carry precision in their type:

| Family | Point | Ball | Parameter/storage |
| --- | --- | --- | --- |
| dfloat | `DFloat{N}` | `DFloatBall{N}` | N=1:4 doubles; immutable inline |
| nfloat | `NFloat{L}` | — | L=1:66 limbs on pinned 64-bit build; immutable inline, finite-only |
| arb real | `ArbFloat{P}` | `ArbBall{P}` | P bits; independently owned native storage |
| arb complex | `AcbFloat{P}` | `AcbBall{P}` | P bits; independently owned native storage |

Scalar construction, semantic copy/deepcopy, parsing/display, arithmetic, sqrt, classification,
comparison/hash, narrow promotion/checked conversions, and selected Base float methods are present.
The [capability table](capability_table.md) is authoritative for each operation/family combination.
Precision is never a mutable runtime default; `with_precision(f,bits)` passes `Val(bits)`.

- Inline vector `FlintFloats.add!`/`mul!` implement checked alias/shape contracts. Nfloat uses private
  initialized scratch and commits only after success; `NFloatWorkspace` reuses capacity with an
  exclusive-use guard. Underflow flushes zero; failures preserve destination storage.
- `PackedBallVector` is a fixed-size native real/complex ball owner. Ordinary indexing/iteration
  returns independent owned values. `borrow` and exported `eachborrow` retain parents and reject
  explicitly finalized storage; references never clear parent slots.
- Packed vector add uses native kernels; multiply/views use borrowed calls. Explicit bulk operations
  accept exact aliases and reject other possible destination overlap or gathered destinations.
- Assignment broadcast supports flat identity/add/multiply and bounded nested identity, unary minus,
  and binary `+ - * /` (eight arithmetic nodes, depth 16). Base snapshots overlapping sources; each
  nested node occurrence owns scratch. Unsupported trees use Base before mutation. Allocating
  broadcast containers and generic callback effects are unchanged.
- Plain `sum(v)` uses one fresh owned accumulator and borrowed reads. `dot` conjugates the first
  complex operand and returns independent storage: native real strided dot; finite complex length
  ≥4 uses four part-strided real dots; small/gathered/nonfinite cases use borrowed accumulation.
  Mixed formats remain generic. Native/loop radii can differ; all must enclose the exact result.
- `sum(abs2,v)` returns fresh `ArbBall{P}` for either packed family, with constant private scratch.
  Keywords and arbitrary callbacks remain generic, with copied argument values.
- `exp`, `log`, `sin`, `cos`, `atan` now support all seven families. Arb/acf points use five strict
  explicit rounding modes; balls enclose rigorously; dfloat/nfloat points are approximate.
  See [elementary.md](elementary.md) for domains, flags, native range limits, and source audits.
  Qualified destination and aggregate `_inexact!` methods reuse arb/acf storage. Inline values return
  by value. Failed status-returning outputs are never read.

## Current verification

Julia 1.13.3, four threads. Latest inline step: **712 inline elementary checks** and **2,227 adjacent
Base-float checks** pass; documentation/doctests, the **374-symbol audit**, and deterministic binding
regeneration pass. This is focused validation, not a whole-suite rerun.

Earlier completed steps: 3,166 strict-point + 291 ball elementary checks; 13,314 nfloat sqrt checks
(all 66 limb counts, exact integer-root oracle, MPFR, extreme exponents, concurrent reads); 259 mapped
+ 205 sum + 346 dot checks; 781 flat + 215 nested broadcast checks. The 13,709 full-suite baseline is
historical M4c evidence, not a current total. Do not add these counts into a claimed full-suite run.

Benchmarks under `benchmark/results/` cover packed lifecycle, iteration, broadcast, sum, dot, mapped
abs2, reusable nfloat workspace, and all selected elementary families. Reports identify the pinned
host/artifact, accuracy, Julia allocations, and relevant radius quality. Julia counters exclude native
allocation; zero Julia allocation is not proof of zero native allocation. Elementary first-use
measurements invoke fresh method specializations at runtime to include compilation.

## Binary and environment

- Julia floor 1.13; FLINT `3.7.0-dev`, revision `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25.
- Local `FLINT_jll 301.690.0+0` resolves through `FlintFloat.jl/FLINT_jll`.
- Bundled binary is tuned for x86_64 Linux, i9-14900K, glibc 2.43. It is not a portable CI/release
  artifact. `Source.toml`, `Artifacts.toml`, and bundled checksums identify source/binary provenance.
- Separate generator, benchmark, docs, and binary-build environments have their own dependencies;
  development manifests for gen/benchmark/docs are ignored. Instantiate each intended environment.

## Source map and focused commands

| Path | Responsibility |
| --- | --- |
| `src/{dfloat,dfloatball,nfloat,arf,acf,arb,acb}.jl` | scalar formats and arithmetic |
| `src/elementary.jl` | selected elementary operations and per-family status/rounding handling |
| `src/{arrays,reusable}.jl` | vector contracts and reusable nfloat scratch |
| `src/{packed,packed_broadcast,packed_reduce}.jl` | packed lifetime, borrowing, broadcast and reductions |
| `gen/inventory.toml`, `gen/{audit,generate}.jl` | foreign declarations, source contracts, deterministic generation |
| `test/elementary*_tests.jl`, `test/elementary_reference.jl` | focused elementary evidence and exact references |
| `test/nfloat_sqrt_tests.jl` | independent all-limb root oracle |
| `docs/elementary.md`, `docs/capability_table.md` | implemented guarantees and source audits |

```sh
julia --project=. -t 4 -e 'include("test/elementary_inline_tests.jl"); include("test/basefloat_tests.jl")'
julia --project=. -t 4 -e 'include("test/elementary_point_tests.jl"); include("test/elementary_ball_tests.jl")'
julia --project=. -t 4 -e 'include("test/nfloat_sqrt_tests.jl")'
julia --project=. -t 4 -e 'include("test/packed_mapped_reduce_tests.jl"); include("test/packed_reduce_tests.jl"); include("test/packed_dot_tests.jl")'
julia --project=. -t 4 -e 'include("test/packed_broadcast_tests.jl"); include("test/packed_nested_broadcast_tests.jl")'
julia --project=gen gen/audit.jl
julia --project=gen gen/generate.jl
julia --project=benchmark benchmark/elementary_inline.jl
```

Run tests covering changed code and directly affected shared contracts. Nested broadcast tests must
follow the flat file because they reuse its helpers. Full-suite/ABI/native diagnostics are separate
validation steps; ABI probes require the matching external build tree and configured BLAS directory.

## Next and open limits

Continue with compatible CI/documentation setup and portable artifact/release gates (§12).
The existing generic hosted x86/x64 workflow is scaffolding and cannot run the tuned binary safely.
Selected M5 numerical functions are implemented; additional special functions, mapped reductions,
and native matrices require individual evidence and measured need rather than speculative expansion.

Release remains incomplete until supported targets have audited portable binaries, verified clean
installation and numerical/ABI checks, real artifact delivery metadata, licenses, and passing CI/docs.
Optional Rational/Complex{Float64} interoperability, packed point owners, complex dfloat/nfloat types,
and shared helper factoring remain future work. Ball uncertainty comparisons, explicit conversions,
parent lifetimes, and status policies must remain intact during any future extension.

## Resuming implementation

Completed continuation commits before this snapshot:

- `25d36c3`: packed squared-magnitude sums with bounded scratch.
- `d3d0dcb`: nfloat square-root truncation evidence across all supported limbs.
- `e7c6aa5`: selected real/complex ball elementary enclosures.
- `cd36c41`: strict real/complex point elementary functions.

The inline continuation adds 45 declarations (40 dfloat plain/ball and five nfloat), increasing
329 audited symbols to 374. Dfloat static bounds were checked against matching `dfloat.h` and
`doc/src/dfloat/index.md`, including normalized-input assumptions and slow fallback ranges.
Nfloat `exp/log/sin_cos/atan/elem` sources use local buffers and read the shared context; default
function precision is initialized to 64L and is never changed by this package. The default accuracy
is approximate: test tolerances are regression checks, not correctly-rounded claims.

Complex strict-point references are exact rational series with proved tail bounds. Before comparing,
both endpoints are independently rounded to the requested MPFR precision/mode and required to agree.
Numerators and denominators must remain exact until the final rounded division; a target-precision
Rational constructor can double-round. Do not replace this oracle with a high-precision complex
approximation. Real interval references use directed MPFR endpoints; uncertain complex tests certify
sampled corners in addition to native source guarantees, not a universal range proof.

For each further implementation step: complete focused validation and applicable symbol/generation,
documentation, and measurement gates; update both checkpoints; commit all. Keep current capabilities
separate from historical evidence. Never mark portable targets supported solely because a recipe
or generic workflow exists, and never substitute a host rebuild for a portable toolchain audit.
