using FlintFloats, BenchmarkTools, FLINT_jll
println("Inline elementary functions; minimum warmed time; 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("Dfloat/nfloat approximate, dfloat balls rigorous; Julia counts exclude native scratch.")
println("type function time_ns allocations bytes")
for T in (DFloat{1},DFloat{2},DFloat{4},DFloatBall{1},DFloatBall{2},DFloatBall{4},NFloat{1},NFloat{2},NFloat{4},NFloat{16},NFloat{66}),f in (exp,log,sin,cos,atan)
    x=T(0.25)
    a=@benchmark $f($x) samples=100 seconds=0.05
    println(T," ",f," ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory)
end
first_inline(::Val{L}) where {L}=exp(NFloat{L}(0.25))
println("Fresh NFloat65 construction+exp, includes runtime compilation (seconds): ",@elapsed Base.invokelatest(first_inline,Val(65)))
