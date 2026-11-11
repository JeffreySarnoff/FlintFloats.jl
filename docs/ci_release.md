# CI and release gates

The bundled artifact supports the verified development host only: x86_64 Linux, i9-14900K,
glibc 2.43 or later. It is CPU tuned and is not a portable release artifact. The source recipe
and a workflow file alone do not establish support for another platform.

## Development checks

Hosted push/pull-request jobs run source/archive checksums and deterministic binding generation
without importing FLINT. They also exercise the target-gate rejection paths with simulated host
values. No generic hosted x86/32-bit native matrix is advertised.

Native CI is a manually dispatched job (`host_validation=true`) using the label
`flintfloats-i9-14900k-glibc243` in addition to `self-hosted`, `Linux`, and `X64`. Provision a runner
with Julia 1.13, the verified CPU/libc, a C compiler, and matching GMP/MPFR development headers.
Set repository variable `FLINTFLOATS_DEPS_PREFIX` to that header installation prefix. The native
job is not attached to automatic pull-request execution. Runner registration/execution is external
infrastructure work; local script validation does not claim that a remote runner is provisioned.

Before native import, `scripts/check_host.jl` rejects unverified CPU/OS/architecture and older libc.
The native job then installs the bundled artifact, runs numerical/ownership/Julia contracts, audits
symbols, compares a new artifact-header C ABI probe, and builds documentation/doctests.
`scripts/check_abi.jl` derives loaded runtime library paths from the wrapper and uses `DEPS_PREFIX`
for headers omitted by Julia's runtime JLLs; it never overwrites the recorded layout.

From the repository root on the verified host:

```sh
julia --startup-file=no scripts/check_sources.jl
julia --startup-file=no test/ci_host_tests.jl
julia --startup-file=no scripts/check_host.jl
julia --project=gen gen/audit.jl
DEPS_PREFIX=/path/to/matching/headers julia --project=gen scripts/check_abi.jl
julia --project=docs docs/make.jl
```

`docs/make.jl` has an explicit source root and builds locally by default. Deployment is enabled
only when `FLINTFLOATS_DOCS_DEPLOY=true`, with the intended credentials/repository setup. Ordinary
verification does not publish documentation. Instantiate the docs project separately; its sources
resolve the main package and nested wrapper without a developer main-project manifest.

## Release evidence still required

| Gate | Current evidence/status |
| --- | --- |
| Selected numerical functions | Five elementary functions implemented for all seven families with per-family guarantees and focused evidence; see [elementary.md](elementary.md). |
| Foreign declarations | 374 audited symbols, deterministic generation, existing layout evidence. |
| Host-independent CI | Workflow and local checksum/generation/target-gate checks implemented. Remote job execution remains unverified. |
| Controlled native CI | Explicit compatible-runner job and locally verified gate/ABI/docs commands; external runner provisioning/execution remains pending. |
| Portable artifact | BinaryBuilder recipe exists; building/auditing a candidate and its dependencies remains required. |
| Clean supported-target installation | Local bundled installer exists; portable clean-target evidence and actual distribution locations remain required. |
| Additional platforms | Unclaimed until their binaries, layouts, numerical behavior, and clean installation pass. |
| Public release | Pending the preceding gates, real artifact delivery metadata, license/provenance checks, and final review. |

A portable build must retain the source/hash pin, use an appropriate baseline toolchain, and pass
BinaryBuilder audits and target-specific checks. Never relabel a host rebuild as portable or invent
download URLs. The local artifact remains usable until a replacement passes its required checks.
Publishing/releasing artifacts or registering a runner is separate from preparing source commits.
