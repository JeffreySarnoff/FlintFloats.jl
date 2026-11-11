using FlintFloats, BenchmarkTools, FLINT_jll
println("Selected elementary ball functions; minimum warmed time; 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("Loaded artifact identity is shown above. Julia counts exclude FLINT native allocations. All methods return rigorous enclosures.")
println("family P function allocating_ns allocs bytes reused_ns reused_allocs reused_bytes radius")
for T in (ArbBall{64},ArbBall{256},ArbBall{1024},AcbBall{64},AcbBall{256},AcbBall{1024}),f in (exp,log,sin,cos,atan)
    x=T<:ArbBall ? T(0.25) : T(0.25,0.125);z=T()
    bang=getfield(FlintFloats,Symbol(nameof(f),:!))
    a=@benchmark $f($x) samples=100 seconds=0.05
    b=@benchmark $bang($z,$x) samples=100 seconds=0.05
    result=f(x);rad=T<:ArbBall ? Float64(radius(result)) : max(Float64(radius(real(result))),Float64(radius(imag(result))))
    println(T," ",precision(T)," ",f," ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory," ",round(minimum(b).time;digits=1)," ",b.allocs," ",b.memory," ",rad)
end
