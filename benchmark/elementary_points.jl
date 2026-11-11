using FlintFloats, BenchmarkTools, FLINT_jll
println("Strict point elementary functions; minimum warmed time; 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("Strict RoundNearest, each component correctly rounded. Julia allocation counts exclude native scratch.")
println("family P function allocating_ns allocs bytes reused_ns reused_allocs reused_bytes")
for T in (ArbFloat{64},ArbFloat{256},ArbFloat{1024},AcbFloat{64},AcbFloat{256},AcbFloat{1024}),f in (exp,log,sin,cos,atan)
    x=T<:ArbFloat ? T(0.25) : T(0.25,0.125);z=T();bang=getfield(FlintFloats,Symbol(nameof(f),:!))
    a=@benchmark $f($x) samples=100 seconds=0.05
    b=@benchmark $bang($z,$x) samples=100 seconds=0.05
    println(T," ",precision(T)," ",f," ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory," ",round(minimum(b).time;digits=1)," ",b.allocs," ",b.memory)
end
println("Fresh precision first construction+exp call, includes compilation (seconds):")
first_real(::Val{P}) where {P}=exp(ArbFloat{P}(0.25))
first_complex(::Val{P}) where {P}=exp(AcbFloat{P}(0.25,0.125))
println("ArbFloat997 ",@elapsed Base.invokelatest(first_real,Val(997)))
println("AcbFloat998 ",@elapsed Base.invokelatest(first_complex,Val(998)))
