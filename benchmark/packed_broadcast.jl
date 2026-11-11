# Run: julia --project=benchmark benchmark/packed_broadcast.jl
using FlintFloats, BenchmarkTools, FLINT_jll
function generic_flat!(f::F,z,args::Tuple) where {F}
    bc=Base.Broadcast.broadcasted(f,args...)
    bc=Base.Broadcast.instantiate(Base.Broadcast.Broadcasted(bc.style,bc.f,bc.args,axes(z)))
    invoke(Base.copyto!,Tuple{AbstractArray,Base.Broadcast.Broadcasted{Nothing}},z,
           convert(Base.Broadcast.Broadcasted{Nothing},bc))
end
optimized_flat!(f::F,z,args::Tuple) where {F}=broadcast!(f,z,args...)
function broadcast_inputs(T,n,kind)
    a,b=T(1)/T(7),T(2)/T(9)
    if kind===:views
        x=PackedBallVector(T,fill(a,2n)); y=PackedBallVector(T,fill(b,2n)); z=PackedBallVector(T,2n)
        return view(z,2n:-2:1),view(x,1:2:2n),view(y,2n:-2:1)
    end
    x,y,z=PackedBallVector(T,fill(a,n)),PackedBallVector(T,fill(b,n)),PackedBallVector(T,n)
    kind===:scalar && return z,x,Ref(b)
    kind===:singleton && return z,x,PackedBallVector(T,[b])
    z,x,y
end
println("Flat packed broadcast; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," Julia threads=",Threads.nthreads())
println("kernel=",Sys.KERNEL," arch=",Sys.ARCH," libc=",readchomp(`getconf GNU_LIBC_VERSION`))
println("FLINT_jll=",pkgversion(FLINT_jll)," lib=",FLINT_jll.libflint_path)
println("source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25; host-tuned artifact")
println("Inputs: rigorous 1/7 and 2/9; same-format independent parents; reused initialized output")
println("generic invokes Base's unspecialized destination path; optimized includes axes/lifetime/alias preparation")
println("Julia allocation counts exclude FLINT allocation/growth; no global thread settings changed")
println("family P n kind op generic_ns generic_allocs generic_bytes optimized_ns optimized_allocs optimized_bytes")
for family in (ArbBall,AcbBall), P in (128,512), n in (1,32,512), kind in (:full,:scalar,:singleton,:views)
    T=family{P}
    z,x,y=broadcast_inputs(T,n,kind)
    for (name,f) in ((:copy,identity),(:add,+),(:mul,*))
        args=f===identity ? (x,) : (x,y)
        bg=@benchmark generic_flat!($f,$z,$args) samples=100 seconds=0.05
        bo=@benchmark optimized_flat!($f,$z,$args) samples=100 seconds=0.05
        println(family," ",P," ",n," ",kind," ",name," ",round(minimum(bg).time;digits=1)," ",bg.allocs," ",bg.memory," ",
                round(minimum(bo).time;digits=1)," ",bo.allocs," ",bo.memory)
    end
end
println("Alias snapshots: resets excluded, evals=1; both paths snapshot a shifted overlapping view before mutation")
println("family P n generic_ns generic_allocs generic_bytes optimized_ns optimized_allocs optimized_bytes")
for family in (ArbBall,AcbBall), P in (128,512), n in (32,512)
    T=family{P}
    seed=PackedBallVector(T,T.(1:n+1)); parent=copy(seed)
    z,x=view(parent,2:n+1),view(parent,1:n)
    args=(x,T(1))
    bg=@benchmark generic_flat!(+,$z,$args) setup=(copyto!($parent,$seed)) evals=1 samples=100 seconds=0.05
    bo=@benchmark optimized_flat!(+,$z,$args) setup=(copyto!($parent,$seed)) evals=1 samples=100 seconds=0.05
    println(family," ",P," ",n," ",round(minimum(bg).time;digits=1)," ",bg.allocs," ",bg.memory," ",
            round(minimum(bo).time;digits=1)," ",bo.allocs," ",bo.memory)
end
