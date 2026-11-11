using FlintFloats, BenchmarkTools, FLINT_jll, LinearAlgebra
println("Portable binary acceptance baseline; minimum warmed time; 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("BinaryBuilder GCC 14.2.0; x86-64 baseline artifact d3d8eabffb56db6d7cfa77fe9fa38dbe6dd4d6c1")
println("Different families have different precision/accuracy contracts; no cross-family speed ranking. Julia counts exclude native allocations.")
println("type operation time_ns allocations bytes")
for T in (DFloat{2},DFloatBall{2},NFloat{2},ArbFloat{128},AcbFloat{128},ArbBall{128},AcbBall{128})
    x=T(0.25);y=T(0.5)
    for f in (+,*)
        a=@benchmark $f($x,$y) samples=100 seconds=0.05
        println(T," ",f," ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory)
    end
    a=@benchmark exp($x) samples=100 seconds=0.05
    println(T," exp ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory)
end
for T in (ArbBall{128},AcbBall{128},ArbBall{512},AcbBall{512})
    x=PackedBallVector(T,fill(T(1)/T(7),512));y=PackedBallVector(T,fill(T(2)/T(9),512))
    for (label,f) in (("sum",sum),("sum_abs2",v->sum(abs2,v)))
        a=@benchmark $f($x) samples=100 seconds=0.05
        println(T," packed_",label," ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory)
    end
    a=@benchmark dot($x,$y) samples=100 seconds=0.05
    println(T," packed_dot ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory)
end
