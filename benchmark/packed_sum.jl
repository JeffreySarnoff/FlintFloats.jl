using FlintFloats, BenchmarkTools, FLINT_jll
base_sum(v)=invoke(Base.sum,Tuple{AbstractArray},v)
rad(x::ArbBall)=Float64(radius(x))
rad(x::AcbBall)=max(Float64(radius(real(x))),Float64(radius(imag(x))))
println("Packed sum; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("Host-tuned x86_64 Linux artifact; unchanged global thread settings; Julia counts exclude native memory.")
println("Independent 1/7 enclosures; both return fresh results. Accumulation order/radius may differ.")
println("family P n span generic_ns generic_allocs generic_bytes borrowed_ns borrowed_allocs borrowed_bytes generic_radius borrowed_radius")
for family in (ArbBall,AcbBall),P in (128,512),n in (1,32,512),kind in (:full,:reversed,:gather)
    T=family{P}; owner=PackedBallVector(T,fill(T(1)/T(7),n))
    v=kind===:full ? owner : kind===:reversed ? view(owner,n:-1:1) : view(owner,collect(n:-1:1))
    bg=@benchmark base_sum($v) samples=100 seconds=0.05
    bo=@benchmark sum($v) samples=100 seconds=0.05
    println(family," ",P," ",n," ",kind," ",round(minimum(bg).time;digits=1)," ",bg.allocs," ",bg.memory," ",
            round(minimum(bo).time;digits=1)," ",bo.allocs," ",bo.memory," ",rad(base_sum(v))," ",rad(sum(v)))
end
