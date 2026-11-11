# Compare a fresh C probe against the recorded ABI using installed artifact headers/libraries.
# Run with --project=gen after installing the intended wrapper; a C compiler is required for this
# developer verification command, never for ordinary package loading.
include("check_host.jl")
check_bundled_host()
using FLINT_jll
root=dirname(@__DIR__)
flint=FLINT_jll.artifact_dir
deps=get(ENV,"DEPS_PREFIX","")
headers=filter(!isempty,[deps,FLINT_jll.GMP_jll.artifact_dir,FLINT_jll.MPFR_jll.artifact_dir])
any(prefix->isfile(joinpath(prefix,"include","gmp.h")),headers) ||
    error("Set DEPS_PREFIX to matching GMP/MPFR development headers; Julia runtime JLLs may omit headers")
any(prefix->isfile(joinpath(prefix,"include","mpfr.h")),headers) ||
    error("Set DEPS_PREFIX to matching GMP/MPFR development headers")
libdirs=[joinpath(flint,"lib"),dirname(FLINT_jll.GMP_jll.libgmp_path),
         dirname(FLINT_jll.MPFR_jll.libmpfr_path),dirname(FLINT_jll.OpenBLAS32_jll.libopenblas_path)]
mktempdir() do directory
    executable=joinpath(directory,"probe")
    includes=["-I"*joinpath(prefix,"include") for prefix in vcat([flint],headers)]
    libraries=vcat(["-L"*directory for directory in libdirs],["-Wl,-rpath-link,"*directory for directory in libdirs])
    run(`cc -O0 -std=c11 $includes $(joinpath(root,"test","abi","probe.c")) $libraries -lflint -lmpfr -lgmp -o $executable`)
    paths=join(libdirs,':')
    inherited=get(ENV,"LD_LIBRARY_PATH","")
    output=read(addenv(`$executable`,"LD_LIBRARY_PATH"=>paths*(isempty(inherited) ? "" : ":"*inherited)),String)
    recorded=read(joinpath(root,"test","abi","layout.txt"),String)
    sort(split(strip(output),'\n'))==sort(split(strip(recorded),'\n')) || error("Native ABI differs from recorded layout; audit before running Julia numerical calls")
    println("Fresh artifact-header ABI probe matches recorded layout")
end
