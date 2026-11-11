# Local FLINT_jll from pinned FLINT main

This standalone Julia 1.13+ wrapper packages FLINT `3.7.0-dev`, source revision
`82c40b299084b92299c2d8dac464e39d6743fce4`, shared-library ABI **25**. The local version is
`301.690.0+1`; it is not a published JuliaBinaryWrappers release or the reference ABI-24 wrapper.

The supplied artifact is now a **portable BinaryBuilder x86-64 baseline build for glibc Linux**,
with runtime floor glibc 2.17. It replaces the earlier i9-14900K/glibc-2.43 tuned development build.
Other targets are not supplied. `Source.toml` preserves historical native-build information and
records the active portable compiler, source, artifact tree, archive hash, and validation.

The package includes its normal JLLWrappers loader and `libflint` product, the binary/header/license
archive, exact compressed upstream source and SHA-256, native diagnostic build tools, a separate
BinaryBuilder recipe, and Julia/C smoke tests. [Release evidence](../../docs/release_evidence.md)
records the 374-symbol/ABI checks, 34,151 numerical tests, clean-project installation, and docs.

## Install and test

From this directory on x86_64 glibc Linux:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(;allow_autoprecomp=false); include("deps/build.jl")'
julia --project=. -e 'using Pkg; Pkg.test()'
```

`deps/build.jl` verifies the archive SHA-256 and extracted Git tree hash before installation.
`Artifacts.toml` is lazy: no fabricated remote download URL is supplied. The installer unpacks a
bundled binary; it does not invoke a compiler. It is also available as `Pkg.build("FLINT_jll")`.

```julia
using FLINT_jll
libflint
FLINT_jll.libflint_path
FLINT_jll.libflint_handle
FLINT_jll.artifact_dir
FLINT_jll.is_available()
```

The loader initializes GMP_jll, MPFR_jll, and OpenBLAS32_jll first. It retains the default FLINT
allocator and does not change global thread/cleanup settings. Callers pair native allocations with
their matching FLINT clear/free operations. `is_available()` reports wrapper availability, not a
complete runtime-compatibility certificate. The main repository's `scripts/check_host.jl` checks
the supplied target before native import.

To select this local wrapper in another isolated project:

```julia
using Pkg
Pkg.develop(path="/absolute/path/to/FlintFloat.jl/FLINT_jll")
Pkg.build("FLINT_jll")
```

Its UUID matches the reference package, so this replaces that dependency in the selected environment.
Do not combine ABI-24 bindings with this ABI-25 library without a new layout/numerical audit.

## Rebuild the portable artifact

```sh
julia --project=build -e 'using Pkg; Pkg.instantiate()'
cd build
julia --project=. build_tarballs.jl x86_64-linux-gnu
```

The recipe defaults to this one candidate platform. It verifies the local source archive when
available, otherwise the same pinned URL/hash, and uses BinaryBuilder's toolchain/dependency prefixes.
The source version excludes a JLL build suffix because BinaryBuilder adds that suffix itself.
No deploy/register option is used during local acceptance. Audit binaries/dependencies/licenses,
then run symbol, ABI, numerical, and clean-install checks before changing the supplied artifact.

The accepted archive has tree `d3d8eabffb56db6d7cfa77fe9fa38dbe6dd4d6c1` and SHA-256
`71384459c4f0da6add70885117c493cab4dff67174d4e2bce926611ded9974a5`.
Additional platforms require separate evidence; a recipe option alone is not a support claim.

## Host-native diagnostics

`build/build_native.sh GMP_PREFIX MPFR_PREFIX OPENBLAS32_PREFIX [JOBS]` can rebuild the pinned source
with local Autotools/GCC-compatible tools and matching development prefixes. Such a build can be CPU-
and libc-specific. `build/package_native.jl PREFIX` is a host-only packager and refuses to overwrite
an active portable bundle. Use an isolated native-build checkout with matching Source.toml provenance,
version, and support restrictions. Do not relabel a native rebuild as portable.
