# Developer/CI-only matching headers. No compiler or downloads run during ordinary package loading.
using TOML, SHA, Downloads
length(ARGS)==1 || error("Usage: julia scripts/prepare_abi_headers.jl PREFIX")
prefix=abspath(only(ARGS));mkpath(prefix)
source=TOML.parsefile(joinpath(@__DIR__,"..","FlintFloat.jl","FLINT_jll","Source.toml"))
cache=joinpath(prefix,".downloads");mkpath(cache)
for name in ("GMP","MPFR")
    entry=source["build_dependencies"][name]
    archive=joinpath(cache,name*".tar.gz")
    matches()=isfile(archive) && bytes2hex(open(sha256,archive))==entry["sha256"]
    if !matches()
        partial=archive*".partial"
        for attempt in 1:3
            try
                Downloads.download(entry["url"],partial;headers=["Cache-Control"=>"no-cache"],timeout=120)
                bytes2hex(open(sha256,partial))==entry["sha256"] || error("$name header archive checksum mismatch")
                mv(partial,archive;force=true)
                break
            catch err
                attempt==3 && rethrow()
                @warn "$name header fetch/validation failed; retrying" exception=err
            finally
                isfile(partial) && rm(partial)
            end
        end
    end
    run(`tar -xzf $archive -C $prefix include`)
    println(name," matching headers verified/extracted (",entry["sha256"],")")
end
