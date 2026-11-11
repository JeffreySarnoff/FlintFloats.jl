# Based on JuliaPackaging/Yggdrasil F/FLINT/build_tarballs.jl.
# This recipe produces portable artifacts and generated platform wrappers.
using BinaryBuilder, Pkg, TOML

source = TOML.parsefile(joinpath(@__DIR__, "..", "Source.toml"))
name = "FLINT"
wrapper_version = VersionNumber(source["wrapper_version"])
# BinaryBuilder adds the JLL build suffix itself and rejects +0 in its source version.
version = VersionNumber(wrapper_version.major, wrapper_version.minor, wrapper_version.patch)
bundled_source = joinpath(@__DIR__, "..", source["source_archive"])
source_location = isfile(bundled_source) ? abspath(bundled_source) : source["source_url"]
sources = [ArchiveSource(source_location, source["source_sha256"])]

script = raw"""
cd ${WORKSPACE}/srcdir/flint-*
extraflags=""
if [[ ${target} == *musl* ]]; then
    export CFLAGS="${CFLAGS} -D_GNU_SOURCE"
elif [[ ${target} == *mingw* ]]; then
    extraflags="--enable-reentrant"
fi
./bootstrap.sh
./configure --host=${target} --prefix=${prefix} \
    --disable-static --enable-shared \
    --with-gmp=${prefix} --with-mpfr=${prefix} --with-blas=${prefix} ${extraflags}
make -j${nproc}
make install
install_license COPYING COPYING.LESSER
"""

products = [LibraryProduct("libflint", :libflint)]
dependencies = [
    Dependency("GMP_jll", v"6.3.0"),
    Dependency("MPFR_jll", v"4.2.2"),
    Dependency("OpenBLAS32_jll", v"0.3.29"),
]

# First release candidate is 64-bit glibc Linux. Other targets require separate ABI and numerical
# evidence before adding them to this list; a recipe is not a support claim.
platforms = [Platform("x86_64", "linux"; libc="glibc")]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat="1.13", preferred_gcc_version=v"14")
