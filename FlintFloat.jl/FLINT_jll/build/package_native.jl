# Run with Julia's standard environment: julia build/package_native.jl PREFIX
# This packager is intentionally limited to the native Linux wrapper supplied here.
using Pkg.Artifacts
using TOML
using Base.BinaryPlatforms

length(ARGS) == 1 || error("Usage: julia build/package_native.jl PREFIX")
Sys.islinux() && Sys.ARCH == :x86_64 || error("Only the x86_64 Linux wrapper is supplied")
platform = HostPlatform()
libc(platform) == "glibc" || error("The supplied wrapper requires glibc")
root = dirname(@__DIR__)
provenance = TOML.parsefile(joinpath(root,"Source.toml"))
get(provenance,"active_build","native")=="native" ||
    error("Host-native packaging cannot replace the selected portable bundle; use an isolated native-build checkout with matching Source.toml provenance")
prefix = abspath(only(ARGS))
isfile(joinpath(prefix, "lib", "libflint.so")) || error("Missing lib/libflint.so in $prefix")
hash = create_artifact() do directory
    for name in readdir(prefix)
        cp(joinpath(prefix, name), joinpath(directory, name); follow_symlinks=false)
    end
    # Remove the build machine's absolute dependency paths. JLLWrappers loads
    # GMP, MPFR and OpenBLAS before FLINT at runtime.
    library = realpath(joinpath(directory, "lib", "libflint.so"))
    run(`patchelf --set-rpath \$ORIGIN $library`)
    run(`strip --strip-debug $library`)
    pcfile = joinpath(directory, "lib", "pkgconfig", "flint.pc")
    if isfile(pcfile)
        content = replace(read(pcfile, String), r"(?m)^prefix=.*$" => s"prefix=${pcfiledir}/../..")
        write(pcfile, content)
    end
    isfile(joinpath(directory, "share", "licenses", "FLINT", "COPYING.LESSER")) ||
        error("The installation prefix must contain FLINT's license files")
end
mkpath(joinpath(root, "bundles"))
filename = "FLINT.x86_64-linux-gnu.tar.gz"
archive = joinpath(root, "bundles", filename)
checksum = archive_artifact(hash, archive)
bind_artifact!(joinpath(root, "Artifacts.toml"), "FLINT", hash;
    platform=Platform("x86_64", "linux"; libc="glibc"), lazy=true, force=true)
open(joinpath(root, "bundles", "Checksums.toml"), "w") do io
    TOML.print(io, Dict(bytes2hex(hash.bytes) => Dict("file" => filename, "sha256" => checksum)))
end
println("Packaged artifact ", hash, " (archive SHA-256 ", checksum, ")")
