# Release preparation evidence

This report records local portable artifact acceptance and historical development evidence; public
release publication and remote workflow execution have not occurred.
Authority: FLINT 3.7.0-dev, source `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25;
current local wrapper 301.690.0+1 (historical host build +0); validation uses Julia 1.13.3 on
i9-14900K/glibc 2.43 with the baseline artifact.

## Accepted portable bundle (current)

Wrapper 301.690.0+1 now selects a BinaryBuilder GCC 14.2.0 baseline x86-64 artifact for glibc
Linux (runtime floor 2.17). Artifact tree: `d3d8eabffb56db6d7cfa77fe9fa38dbe6dd4d6c1`;
archive SHA-256: `71384459c4f0da6add70885117c493cab4dff67174d4e2bce926611ded9974a5`.
[Build/audit logs](evidence/portable_build_logs.tar.gz) are retained. ELF notes report x86-64-baseline;
maximum required GLIBC symbol is 2.16, and RUNPATH is `$ORIGIN`. Source and ABI remain pinned.

The isolated candidate passed **34,151 numerical/ownership/Julia contract checks**, 374-symbol
resolution, a fresh matching artifact-header ABI probe, and docs/doctests. Because the binary changes
all underlying operations, this full acceptance run was appropriate; earlier source follow-ups used
focused tests. The promoted bundle has identical bytes/tree and additionally passed 21 wrapper
smoke checks and five target-gate checks. Matching GMP/MPFR headers were downloaded and SHA-verified
using the same script now in hosted CI.

A fresh working-tree copy without its main manifest resolved through its own sources and installed
the new bundle into a separate depot where that artifact was absent. Public API, deep copy, complex
assignment, and Serialization-extension checks passed. FLINT was not compiled. Dependency caches were
reused, so this does not claim a completely empty-machine download test. The new portable benchmark
baseline identifies the new tree and accuracy contracts; older host-tuned reports remain historical.
Actual remote CI execution and public release publication are still pending.

## Empty-depot installation follow-up

A `git archive` of `f1a9c2e` was installed with `JULIA_DEPOT_PATH` pointing only to a new, empty
directory: no dependency source/artifact cache links or fallback depot. Pkg independently obtained
the General registry, JLLWrappers, Preferences, OpenBLAS32_jll and its artifact using its usual
integrity checks. The verified bundled FLINT archive was unpacked into that depot; no FLINT C
compiler was invoked. Arithmetic/elementary smoke checks for all seven families, complex packed
abs2, semantic deepcopy alias graphs, and Serialization rejection passed.

The main manifest was then removed before separately resolving the docs project, which also had
no manifest. This checks that docs resolve their own sources rather than depending on the main
lockfile. The install result is recorded in [empty-depot evidence](evidence/empty_depot_acceptance.txt);
the section audit is in [enact_completion_audit.md](enact_completion_audit.md).

## Fresh project and bundled installation

A `git archive` of commit `8a52604` was extracted to a temporary directory. Its main Manifest.toml
was removed. A separate writable depot reused cached dependency sources/artifacts but deliberately
excluded the bundled FLINT artifact. This tests project/source resolution and a fresh FLINT install;
it is not a test of downloading all dependencies onto an empty machine.

The main project instantiated using its own `[sources]`, with no developer main manifest. Running
`Pkg.build("FLINT_jll")` verified/unpacked the bundled archive into the new depot, producing tree
`b375a8872bc46fbeeae1a15e10297b29900d2451`. No FLINT compiler invocation was required.
Public smoke checks passed for `exp(ArbBall{128}(0))` and complex packed `sum(abs2, v)`.
Both `COPYING` and `COPYING.LESSER` are present in the installed artifact's license directory.

The docs environment then instantiated separately with no docs manifest. This exposed an assumption
that Git metadata would always be available. `docs/make.jl` now disables automatic remote source
links for source archives; the same fresh source tree then built docs and passed doctests without
publishing. Checkout builds retain source links. Registry-download warnings occurred in the network-
restricted environment; cached registry/dependencies resolved successfully.

This complements the independently compiled installed-header ABI probe, which matched the recorded
layout, and the 374-symbol audit. No whole-suite numerical rerun accompanied these infrastructure
changes; the focused function evidence is recorded in [elementary.md](elementary.md).

## Portable build recipe

An actual BinaryBuilder attempt exposed that its source version cannot include a JLL build suffix.
The recipe now strips `+0` from `301.690.0+0` when constructing BinaryBuilder's source version;
BinaryBuilder adds its own JLL build suffix. The package version/source identity are unchanged.

The recipe uses the checked-in, SHA-verified source archive when available and falls back to the
same pinned source URL/hash otherwise. Its initial candidate target is x86_64 glibc Linux; additional
targets are not advertised as supported. No audit bypass or fabricated artifact URL is introduced.
The corrected recipe passes version validation and verifies/extracts the source in an actual build.
The corrected recipe subsequently completed build/audit and its artifact passed the acceptance
checks recorded above; it now replaces the old bundled host artifact.

## Verified replacement build downloads

Direct downloads from the pinned JuliaPackaging/Yggdrasil GitHub release URLs replaced failed
package-server downloads of the root filesystem and GCC 14.2.0 GNU/musl compiler components.
All three archives match the SHA-256 values in BinaryBuilderBase 1.49.0's artifact metadata and
pass a complete gzip decompression/CRC check. The retained files are under
`/tmp/flint-verified-downloads`; [the verification manifest](evidence/portable_downloads.json)
records exact URLs, hashes, tree identities, and byte sizes. These large build archives are not
committed to the source repository.

The eight installed rootfs/LLVM/platform/GCC artifacts were independently checked with
`Pkg.Artifacts.verify_artifact`: rootfs 2026.6.10, LLVM bootstrap 23.1.1, GNU/musl platform support
2025.8.13, and GNU/musl GCC bootstrap 14.2.0 and 4.8.5 all match their expected Git tree hashes.
No checksum/audit bypass or substitution of unverified compiler bytes was used. Obtaining a
verified toolchain does not establish that the FLINT candidate build or target tests have passed.

## Outstanding release gates

Run the configured hosted workflow against the completed source commits and publish the public
release/distribution when approved. The archive and hashes are real and bundled; no nonexistent
remote download URL is advertised. Other platforms remain unprovided. Optional interoperability,
extra special functions/mappings, and matrix storage require individual future scope and evidence.
