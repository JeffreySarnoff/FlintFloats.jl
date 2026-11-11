# Checkpoint

State after M0–M3, M4 bulk/packed follow-ups, and the five selected M5 elementary functions from
[enact_interfacing.md](enact_interfacing.md). This snapshot accompanies the scalar-copy/persistence correction;
its base commit is `ccd1da0` (clean installation and portable recipe fixes). Inspect `git log` and `git status`
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

## Latest ownership continuation

A release audit of §6.2 found scalar deepcopy was still generic field copying. It now creates
semantic native copies and preserves alias graphs via the caller's IdDict. The optional Serialization
stdlib extension rejects writing/typed reconstruction of native scalar/packed owners and borrowed
references; inline formats retain ordinary stdlib round trips. Tests cover heap-backed mantissas,
independence after source mutation/finalization, repeated references, extension activation, and nested
persistence rejection. **81 new + 17 existing ownership checks pass**; docs/doctests pass.
The extension is a weak dependency, not a mandatory runtime backend. No new C bindings.

## Latest infrastructure continuation

A fresh archived project without its main manifest resolved and installed FLINT into a separate
depot (the FLINT artifact was excluded from cached dependencies). Public API smoke and installed
license-file checks passed without compiling FLINT. The separately resolved docs environment passed
docs/doctests after fixing source-archive builds without Git metadata. Dependency caches were reused;
this is clean-project/install evidence, not empty-machine network-download or portable certification.

An actual BinaryBuilder attempt exposed and corrected the recipe's invalid +0 source-version suffix.
The recipe now prefers the SHA-verified bundled source and limits the initial candidate to x86_64
glibc Linux. It passes version validation and verifies/extracts source; build/audit/target tests are
still pending. No replacement artifact or remote distribution URL is claimed.
See [release_evidence.md](release_evidence.md) and [ci_release.md](ci_release.md).
Five host-gate tests, source/archive checks, fresh C ABI, YAML validation, and local docs passed in
the previous infrastructure step. Remote runner execution remains unverified. Numeric suites were
not rerun for this infrastructure-only change.

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

Continue with compatible CI/documentation setup and portable artifact/release gates (§12).
Hosted jobs no longer load the tuned binary; controlled native jobs require explicit compatible-runner dispatch.
Remote runner provisioning/execution and portable artifact validation remain incomplete.
Selected M5 numerical functions are implemented; additional special functions, mapped reductions,
and native matrices require individual evidence and measured need rather than speculative expansion.

Release remains incomplete until supported targets have audited portable binaries, verified clean
installation and numerical/ABI checks, real artifact delivery metadata, licenses, and passing CI/docs.
Optional Rational/Complex{Float64} interoperability, packed point owners, complex dfloat/nfloat types,
and shared helper factoring remain future work. Ball uncertainty comparisons, explicit conversions,
parent lifetimes, and status policies must remain intact during any future extension.
