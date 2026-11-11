# Run: julia --project=benchmark benchmark/packed_iteration.jl
using FlintFloats, BenchmarkTools, FLINT_jll
const FF=FlintFloats
function copied_update!(z,x,step)
    axes(z)==axes(x) || throw(DimensionMismatch("axes must match"))
    for i in eachindex(z,x)
        z[i]=x[i]+step
    end
    z
end
function manual_update!(z,x,step)
    axes(z)==axes(x) || throw(DimensionMismatch("axes must match"))
    for i in axes(z,1)
        FF.add!(borrow(z,i),borrow(x,i),step)
    end
    z
end
function iterator_update!(z,x,step)
    axes(z)==axes(x) || throw(DimensionMismatch("axes must match"))
    for (i,r) in enumerate(eachborrow(z))
        FF.add!(r,borrow(x,i),step)
    end
    z
end
function make_span(T,n,mode,value)
    if mode === :full
        return PackedBallVector(T,fill(value,n))
    end
    parent=PackedBallVector(T,fill(value,2n))
    inds = mode === :strided ? (1:2:2n) : mode === :reversed ? (2n:-2:1) : collect(1:2:2n)
    view(parent,inds)
end
println("Packed read/write and eachborrow; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," Julia threads=",Threads.nthreads())
println("kernel=",Sys.KERNEL," arch=",Sys.ARCH," libc=",readchomp(`getconf GNU_LIBC_VERSION`))
println("FLINT_jll=",pkgversion(FLINT_jll)," lib=",FLINT_jll.libflint_path)
println("source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25; host-tuned artifact")
println("No global thread settings changed. Warmed destinations and independent inputs are reused.")
println("Each path writes source 1/7 + scalar 2/9 at matching precision; copied path retains results through semantic slot assignment.")
println("Bulk comparison uses a separately prepared packed vector of the same scalar; its construction is excluded.")
println("Julia allocation counts exclude FLINT allocation and mantissa growth; no native-memory-allocation claim.")
println("family P n span copied_ns copied_allocs copied_bytes manual_ns iterator_ns iterator_allocs iterator_bytes bulk_ns")
for family in (ArbBall,AcbBall), P in (128,512), n in (1,32,512), mode in (:full,:strided,:reversed,:gather)
    T=family{P}
    step=T(2)/T(9)
    x=make_span(T,n,mode,T(1)/T(7))
    z=make_span(T,n,mode,T(0))
    steps=make_span(T,n,mode,step)
    bc=@benchmark copied_update!($z,$x,$step) samples=100 seconds=0.05
    bm=@benchmark manual_update!($z,$x,$step) samples=100 seconds=0.05
    bi=@benchmark iterator_update!($z,$x,$step) samples=100 seconds=0.05
    # Gather views are valid for manual scalar updates/iteration; bulk destinations reject them.
    bulk_ns = if mode === :gather
        "unsupported"
    else
        bb=@benchmark FF.add!($z,$x,$steps) samples=100 seconds=0.05
        string(round(minimum(bb).time;digits=1))
    end
    println(family," ",P," ",n," ",mode," ",round(minimum(bc).time;digits=1)," ",bc.allocs," ",bc.memory," ",
            round(minimum(bm).time;digits=1)," ",round(minimum(bi).time;digits=1)," ",bi.allocs," ",bi.memory," ",bulk_ns)
end
