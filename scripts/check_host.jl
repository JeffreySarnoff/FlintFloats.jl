# Validate the supplied platform before importing FLINT_jll. The portable artifact has baseline
# x86-64 instructions; the Julia/dependency support floor is glibc 2.17.
using TOML
function check_bundled_host(;os=Sys.KERNEL,arch=Sys.ARCH,cpu=Sys.cpu_info()[1].model,
                            libc=nothing)
    os===:Linux && arch===:x86_64 || error("Bundled FLINT requires x86_64 glibc Linux; no artifact is supplied for this target")
    version=libc===nothing ? VersionNumber(unsafe_string(ccall(:gnu_get_libc_version,Cstring,()))) : VersionNumber(libc)
    source=TOML.parsefile(joinpath(@__DIR__,"..","FlintFloat.jl","FLINT_jll","Source.toml"))
    if get(source,"active_build","native")=="portable"
        minimum=VersionNumber(source["portable_build"]["glibc_min"])
    else
        occursin("i9-14900K",cpu) || error("Historical native artifact requires its validated i9-14900K host")
        minimum=VersionNumber(source["native_build"]["libc"][7:end])
    end
    version>=minimum || error("Bundled FLINT requires glibc $minimum or later; found $version")
    println("Supported bundled target: x86_64 Linux, ",cpu,", glibc ",version)
    nothing
end
abspath(PROGRAM_FILE)==(@__FILE__) && check_bundled_host()
