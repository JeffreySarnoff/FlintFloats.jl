# Release preparation evidence

This report records local development evidence, not a portable release certification.
Authority: FLINT 3.7.0-dev, source `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25;
local wrapper 301.690.0+0; Julia 1.13.3 on i9-14900K/glibc 2.43.

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
Toolchain/dependency setup and the native build/audit are still in progress; no portable artifact has
yet been accepted or substituted for the existing host build.

## Outstanding release gates

A portable candidate still needs its complete build, binary/dependency/license audits, target ABI
and numerical tests, and clean-target installation. Distribution must use real artifact locations
and checksums. Controlled CI requires provisioning/executing the documented compatible runner.
External publishing and additional platform claims remain pending those concrete checks.
See [ci_release.md](ci_release.md) for the workflow and target gates.
