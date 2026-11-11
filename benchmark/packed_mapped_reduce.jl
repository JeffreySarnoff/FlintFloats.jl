using FlintFloats, BenchmarkTools, FLINT_jll
base_abs2_sum(v)=invoke(Base.sum,Tuple{Any,AbstractArray},abs2,v)
println("Packed sum(abs2); minimum warmed time, 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("Loaded artifact; Julia counts exclude native allocations; same scalar mapping, logical-order accumulation.")
println("family P n span generic_ns generic_allocs generic_bytes borrowed_ns borrowed_allocs borrowed_bytes generic_radius borrowed_radius")
for family in (ArbBall,AcbBall),P in (128,512),n in (1,32,512),kind in (:full,:reversed,:gather)
    T=family{P};value=family===ArbBall ? T(1)/T(7) : T(1.0,2.0)/T(7)
    owner=PackedBallVector(T,fill(value,n))
    v=kind===:full ? owner : kind===:reversed ? view(owner,n:-1:1) : view(owner,collect(n:-1:1))
    a=@benchmark base_abs2_sum($v) samples=100 seconds=0.05
    b=@benchmark sum(abs2,$v) samples=100 seconds=0.05
    println(family," ",P," ",n," ",kind," ",round(minimum(a).time;digits=1)," ",a.allocs," ",a.memory," ",round(minimum(b).time;digits=1)," ",b.allocs," ",b.memory," ",Float64(radius(base_abs2_sum(v)))," ",Float64(radius(sum(abs2,v))))
end
