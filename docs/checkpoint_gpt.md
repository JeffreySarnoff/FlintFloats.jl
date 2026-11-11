# FlintFloats.jl development checkpoint

State after M0–M3, scoped M4 bulk/packed work, selected M5 elementary functions, ownership
corrections, and portable x86_64 Linux artifact acceptance. This snapshot accompanies the portable
bundle promotion; the preceding commit is `4dfb12d` (verified replacement build downloads).
Inspect `git log` and `git status` for subsequent changes.

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

## Portable artifact acceptance

`FLINT_jll 301.690.0+1` now selects the accepted BinaryBuilder GCC 14.2.0 artifact. Baseline
x86-64 instructions and maximum GLIBC symbol 2.16 were inspected; the supported wrapper/runtime
floor is glibc 2.17 and Julia 1.13. Only x86_64 glibc Linux is supplied.

- Tree: `d3d8eabffb56db6d7cfa77fe9fa38dbe6dd4d6c1`.
- Archive SHA-256: `71384459c4f0da6add70885117c493cab4dff67174d4e2bce926611ded9974a5`.
- **34,151 tests pass** against that binary; all 374 symbols and the fresh artifact-header ABI
  probe pass; docs/doctests pass. A full run was appropriate because the binary changed beneath
  all operations. Source changes before promotion used focused tests.
- A fresh project with no main manifest installed the new archive into a separate depot, with
  public API/deepcopy/assignment/Serialization-extension smoke checks passing. No compiler was
  invoked for FLINT installation. Cached dependency sources/artifacts were reused.
- Five portable-target gate tests, 21 wrapper smoke checks, source/archive checksum checks,
  and matching downloaded GMP/MPFR headers pass. Hosted CI is configured for this portable artifact;
  actual remote workflow execution and public release publication remain pending.

Build logs and exact download identities are in [release_evidence.md](release_evidence.md),
[evidence/portable_build_logs.tar.gz](evidence/portable_build_logs.tar.gz), and
[evidence/portable_downloads.json](evidence/portable_downloads.json). The three previously corrupted
rootfs/GCC archives were obtained directly, verified by SHA-256 and full gzip checks, and retained
under `/tmp/flint-verified-downloads`; all eight installed toolchain trees independently match.

Scalar deepcopy now copies native values semantically and preserves alias graphs. The optional
Serialization extension rejects raw native owners/references. Complex owning `set!` supports strict
point rounding and containing ball copies across precision; all have focused evidence and are
included in the accepted full run. Matrix and further mapping work remain conditional on need.

## Current verification

Julia 1.13.3, four threads: **34,151 tests pass** on the new portable binary, plus wrapper,
ABI/symbol, target-gate, checksum, deterministic-generation, and documentation checks as above.
The following earlier focused counts are historical step evidence, not extra tests to add to that total.

Earlier completed steps: 3,166 strict-point + 291 ball elementary checks; 13,314 nfloat sqrt checks
(all 66 limb counts, exact integer-root oracle, MPFR, extreme exponents, concurrent reads); 259 mapped
+ 205 sum + 346 dot checks; 781 flat + 215 nested broadcast checks. The 13,709 M4c full-suite baseline is historical and superseded by portable acceptance.

The current portable acceptance baseline is `benchmark/results/portable_baseline.txt`. Older
recorded host-tuned reports retain their original identities; driver labels now defer to the actual
loaded library identity. Benchmarks under `benchmark/results/` cover packed lifecycle, iteration, broadcast, sum, dot, mapped
abs2, reusable nfloat workspace, and all selected elementary families. Reports identify the pinned
host/artifact, accuracy, Julia allocations, and relevant radius quality. Julia counters exclude native
allocation; zero Julia allocation is not proof of zero native allocation. Elementary first-use
measurements invoke fresh method specializations at runtime to include compilation.

## Binary and environment

- Julia floor 1.13; FLINT `3.7.0-dev`, revision `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25.
- Local `FLINT_jll 301.690.0+1` resolves through `FlintFloat.jl/FLINT_jll`.
- Bundled binary is portable x86-64 baseline glibc Linux (minimum glibc 2.17).
  `Source.toml`, `Artifacts.toml`, and bundled checksums identify current and historical provenance.
- Separate generator, benchmark, docs, and binary-build environments have their own dependencies;
  development manifests for gen/benchmark/docs are ignored. Instantiate each intended environment.

## Source map and focused commands

| Path | Responsibility |
| --- | --- |
| `src/{dfloat,dfloatball,nfloat,arf,acf,arb,acb}.jl` | scalar formats and arithmetic |
| `src/elementary.jl` | selected elementary operations and per-family status/rounding handling |
| `src/storage.jl`, `ext/FlintFloatsSerializationExt.jl` | semantic scalar deepcopy and optional persistence rejection |
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

Local numerical, ownership, portable artifact, and clean-project installation gates are implemented
and verified. Next run the configured hosted workflow against these commits and complete public
release/distribution publication. Those external actions have not occurred. No nonexistent remote
artifact URL or additional platform claim is supplied. The actual archive remains bundled and can
be installed without compiling FLINT. Additional special functions, mappings, and native matrices
need individually justified scope/evidence; they do not block the selected numerical milestones.


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
