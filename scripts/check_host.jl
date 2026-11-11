# Run before importing FLINT_jll. The bundled artifact's platform tag omits CPU/libc restrictions.
using TOML
function check_bundled_host(;os=Sys.KERNEL,arch=Sys.ARCH,cpu=Sys.cpu_info()[1].model,
                            libc=nothing)
    os===:Linux && arch===:x86_64 || error("Bundled FLINT requires x86_64 Linux; build and validate another artifact for this target")
    occursin("i9-14900K",cpu) || error("Bundled FLINT is tuned for i9-14900K; this CPU has no validated artifact")
    version=libc===nothing ? VersionNumber(unsafe_string(ccall(:gnu_get_libc_version,Cstring,()))) : VersionNumber(libc)
    minimum=VersionNumber(TOML.parsefile(joinpath(@__DIR__,"..","FlintFloat.jl","FLINT_jll","Source.toml"))["native_build"]["libc"][7:end])
    version>=minimum || error("Bundled FLINT requires glibc $minimum or later; found $version")
    println("Validated development target: ",cpu,", glibc ",version)
    nothing
end
abspath(PROGRAM_FILE)==(@__FILE__) && check_bundled_host()
