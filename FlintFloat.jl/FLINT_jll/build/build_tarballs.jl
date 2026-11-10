# Based on JuliaPackaging/Yggdrasil F/FLINT/build_tarballs.jl.
# This recipe produces portable artifacts and generated platform wrappers.
using BinaryBuilder, Pkg, TOML

source = TOML.parsefile(joinpath(@__DIR__, "..", "Source.toml"))
name = "FLINT"
version = VersionNumber(source["wrapper_version"])
sources = [ArchiveSource(source["source_url"], source["source_sha256"])]

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

build_tarballs(ARGS, name, version, sources, script, supported_platforms(), products, dependencies;
    julia_compat="1.13", preferred_gcc_version=v"14")
