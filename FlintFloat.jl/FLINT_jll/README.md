# Local FLINT_jll from FLINT main

This is a standalone Julia 1.13+ binary-wrapper package built from FLINT
`main` at commit
[`82c40b299084b92299c2d8dac464e39d6743fce4`](https://github.com/flintlib/flint/commit/82c40b299084b92299c2d8dac464e39d6743fce4),
resolved on November 10, 2026. The upstream version is `3.7.0-dev` and the
shared-library ABI is **25**, not the ABI 24 used by the reference wrapper.
The package version `301.690.0+0` identifies this local development build;
it is not a published JuliaBinaryWrappers release.

The package contains:

- The normal `FLINT_jll` loader and `libflint` library product, using JLLWrappers.
- A built native artifact, its headers, FLINT licenses and verified checksums.
- The exact compressed upstream source, with its SHA-256 and provenance.
- A native rebuild script and a separate BinaryBuilder recipe for portable builds.
- Julia wrapper tests and a C arithmetic/ABI smoke test.

The built artifact is **for this x86_64 Linux host**, compiled with GCC
16.2.1 on glibc 2.43, with configure's raptorlake tuning for an i9-14900K.
It is not a portable Linux release and must not be distributed as one.
Other operating systems, architectures, older libc versions and CPUs require
their own builds. `Source.toml` records the build dependencies and source
identity. There are no fabricated remote artifact URLs or entries for binaries
that have not been built.

## Install and test

From this directory:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); include("deps/build.jl")'
julia --project=. -e 'using Pkg; Pkg.test()'
```

`deps/build.jl` verifies the bundled archive's SHA-256 and the extracted
artifact's Git tree hash, and installs it into Julia's artifact store.
`Artifacts.toml` marks the artifact lazy so package resolution does not attempt
a nonexistent public download. Run the installer before the first import;
it is also available through `Pkg.build("FLINT_jll")`. No compiler or FLINT
source build runs during ordinary loading.

```julia
using FLINT_jll

libflint                         # full library path, usable by ccall/@ccall
FLINT_jll.libflint_path
FLINT_jll.libflint_handle
FLINT_jll.artifact_dir            # include/flint, lib, share/licenses/FLINT
FLINT_jll.is_available()          # platform wrapper availability
```

`is_available()` reports whether a platform wrapper exists; it does not certify
CPU compatibility. This local package deliberately keeps the standard JLL
interface. It does not implement Julia numeric types or generate thousands of
C function bindings: the library product makes FLINT's exported functions
available to downstream bindings, while inline C helpers remain in the headers.

To use this copy in another Julia project, develop its path in that project's
environment and build the local artifact:

```julia
using Pkg
Pkg.develop(path="/absolute/path/to/FlintFloat.jl/FLINT_jll")
Pkg.build("FLINT_jll")
using FLINT_jll
```

The UUID matches the reference package, so this replaces that package in the
chosen environment. Keep it isolated from software that requires FLINT ABI 24;
the real/complex number layouts and compatibility of downstream bindings must
be checked before connecting them to the new library.

## Rebuild the native artifact

Requirements: Julia 1.13+, GCC-compatible C compiler, GNU make, Autoconf,
Automake, Libtool, M4, `tar`, `sha256sum`, `patchelf`, `strip`, and development
prefixes containing GMP, MPFR and **32-bit BLAS integer** OpenBLAS headers and
libraries. The prefixes used for the delivered build are identified in
`Source.toml`; build dependency archives must be checked against those hashes.

```sh
bash build/build_native.sh /path/to/gmp /path/to/mpfr /path/to/openblas32 8
```

The script verifies and extracts the bundled source, runs FLINT's Autotools
build, and prints its installation prefix. Package that prefix with:

```sh
julia build/package_native.jl /printed/build/directory/install
```

The packager copies the installation, removes absolute library search paths,
strips debug information, makes `flint.pc` relocatable, checks that the license
files are present, and regenerates `Artifacts.toml` and `bundles/Checksums.toml`.
Update `Source.toml`'s native-build description when changing compiler, CPU,
libc or dependencies. Remove this package's compiled cache or start with a
fresh depot after changing wrapper selection or artifact metadata.

The wrapper initializes GMP_jll, MPFR_jll and OpenBLAS32_jll before loading
FLINT. The delivered library depends on their SONAMEs rather than build-machine
paths. It uses FLINT's default allocator: unlike the reference wrapper's Nemo
integration block, it does not install Julia-specific allocation callbacks or
change process-wide FLINT settings. It also does not invoke global cleanup at
shutdown. Callers must pair owned resources with FLINT's matching clear/free
functions.

## Portable builds

The separate recipe uses BinaryBuilder's toolchains, dependency prefixes and
artifact auditing, pins the same source archive/hash, and declares the
`libflint` product. It follows the upstream Yggdrasil FLINT recipe's Autotools
build, including musl and MinGW configuration. It is supplied for further
platform builds. The initial recipe target is x86_64 glibc Linux; a build attempt has verified and
extracted the bundled pinned source, but a portable artifact has not yet passed complete build/audit
and target tests. The recipe strips the JLL build suffix for BinaryBuilder and reuses the local
source archive when available. See the main package
[release evidence](../../docs/release_evidence.md) for the current verification limits.

```sh
julia --project=build -e 'using Pkg; Pkg.instantiate()'
cd build
julia --project=. build_tarballs.jl --help
julia --project=. build_tarballs.jl x86_64-linux-gnu
```

Use the resulting platform wrappers and real artifact metadata for deployment.
Do not reuse this native bundle's hashes for a different build. Publishing
download URLs, releases or a registry entry is separate work.

## Validation

The delivered build was checked with:

- Julia package loading, exported version and required symbols.
- Julia foreign calls for dfloat addition and arb/acb allocation, arithmetic,
  containment and cleanup.
- A C smoke executable for dfloat, nfloat, arb and acb, including nfloat context
  initialization and cleanup, compiled against the delivered headers.
- FLINT's upstream `make check MOD='dfloat nfloat'` suites.
- Native shared-library SONAME, dependency and relocation inspection.

`test/smoke.c` can be compiled using the artifact include/lib directories plus
the matching GMP and MPFR development include/lib directories. Set the runtime
library search path to include FLINT and its three native dependencies when
running outside Julia. The smoke program reports C struct sizes; downstream
bindings must additionally verify field offsets and alignment.

The full upstream test suite and cross-platform builds have not been run.
For current upstream behavior, consult the pinned source first; the online
documentation may advance after this build.

## References and licensing

- [Reference Julia loader](https://github.com/JuliaBinaryWrappers/FLINT_jll.jl/blob/main/src/FLINT_jll.jl).
- [FLINT documentation](https://flintlib.org/doc/index.html).
- [FLINT source repository](https://github.com/flintlib/flint).
- [Yggdrasil FLINT recipe](https://github.com/JuliaPackaging/Yggdrasil/blob/master/F/FLINT/build_tarballs.jl).

The Julia wrapper follows the reference's MIT license (see `LICENSE`). FLINT
is LGPL-3.0-or-later; its license texts are in the artifact and its complete
corresponding upstream source archive is included under `sources/`. Native
dependency licenses remain with their respective Julia binary packages.
