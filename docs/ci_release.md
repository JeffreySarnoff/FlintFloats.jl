# CI and release gates

The supplied `FLINT_jll 301.690.0+1` artifact is a BinaryBuilder x86-64 baseline build for glibc
Linux, with a supported runtime floor of glibc 2.17 and Julia 1.13. It replaces the previous
host-tuned development bundle. Other architectures, operating systems, and musl remain unprovided.

## CI and local checks

Hosted push/pull-request jobs use Julia 1.13 x64 on Ubuntu. Source checks first validate GitHub expressions with SHA-pinned actionlint 1.7.12, then verify pinned identities,
archive checksums, target-gate rejection, and deterministic generation. Native jobs install the
bundled portable artifact, run the numerical/ownership/Julia contracts, audit symbols, compare a
fresh artifact-header C ABI probe, and build docs/doctests. No dedicated tuned-host runner is needed.
The [hosted run](https://github.com/JeffreySarnoff/FlintFloats.jl/actions/runs/42962433938) passes
both jobs at ce2831e, including isolated Pkg.test (34,151 checks) and docs/doctests.
[Recorded log evidence](evidence/hosted_ci_acceptance.txt) identifies the exact head and runner.

`scripts/check_host.jl` rejects unprovided OS/architecture and older glibc before importing the
wrapper. For the active portable profile it permits generic x86-64 CPUs. Historical native-build
provenance remains recorded but is not used to advertise the new artifact's CPU requirements.
`scripts/prepare_abi_headers.jl` fetches SHA-verified GMP/MPFR header archives from the pinned URLs
in `Source.toml`. This developer/CI-only step avoids relying on headers omitted by Julia runtime
JLLs. `scripts/check_abi.jl` derives loaded runtime library paths from the wrapper and compares
against the recorded layout without overwriting it. A compiler is needed for this verification,
not for ordinary package loading or bundled installation.

```sh
julia --startup-file=no scripts/check_sources.jl
julia --startup-file=no test/ci_host_tests.jl
julia --startup-file=no scripts/check_host.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(;allow_autoprecomp=false); Pkg.build("FLINT_jll")'
julia --project=gen gen/audit.jl
julia --startup-file=no scripts/prepare_abi_headers.jl /tmp/flint-abi-headers
DEPS_PREFIX=/tmp/flint-abi-headers julia --project=gen scripts/check_abi.jl
julia --project=docs docs/make.jl
```

Instantiate gen/docs in their own projects first. The docs script has an explicit source root and
builds locally by default; source archives work without Git metadata. Deployment requires
`FLINTFLOATS_DOCS_DEPLOY=true` and the intended credentials/repository setup. Verification does
not publish docs.

## Release evidence

| Gate | Current evidence/status |
| --- | --- |
| Selected numerical functions | Five elementary functions for all seven families, with individual guarantees; [audit/evidence](elementary.md). |
| Native declarations/layout | 374 symbols resolve; matching artifact-header C ABI probe; deterministic generation. |
| Portable artifact | BinaryBuilder GCC 14.2.0, baseline x86-64, accepted local build/audit; [logs](evidence/portable_build_logs.tar.gz). |
| Numerical acceptance | 34,151 tests pass against the new binary; docs/doctests pass. The full run was warranted because all native operations changed binary. |
| Clean project installation | New bundled tree unpacked into a separate depot without compiling FLINT; main manifest absent; API/extension smoke passed. Cached dependency sources/artifacts were reused. |
| CI | Both hosted jobs pass at ce2831e; actual package-isolated numerical/ABI/generation/docs gates verified. |
| Distribution | Real source/binary archives and checksums are bundled; public tagged release/remote distribution remains pending final publication. No nonexistent download URLs are advertised. |
| Other targets | Unclaimed until their artifacts, layouts, numerical behavior, and clean installation pass. |

See [release_evidence.md](release_evidence.md) for exact artifact hashes, toolchain downloads,
installation scope, and remaining publication gates. Historical host-tuned benchmark reports remain
historical; [the portable baseline](../benchmark/results/portable_baseline.txt) identifies the new
artifact. A host-native packager cannot overwrite a selected portable bundle without changing the
provenance in an isolated native-build checkout.
