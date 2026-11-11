# Run: julia --project=benchmark benchmark/m4c_packed.jl
using FlintFloats, BenchmarkTools, FLINT_jll
const FF=FlintFloats
function owned_loop!(f!, z,x,y)
    for i in eachindex(z,x,y)
        f!(z[i],x[i],y[i])
    end
    z
end
function borrowed_loop!(f!, z,x,y)
    for i in eachindex(z,x,y)
        f!(borrow(z,i),borrow(x,i),borrow(y,i))
    end
    z
end
function owned_construct_clear(T,n)
    values=[T() for _ in 1:n]
    foreach(finalize,values)
    nothing
end
println("M4c packed ball vectors; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," Julia threads=",Threads.nthreads())
println("kernel=",Sys.KERNEL," arch=",Sys.ARCH," libc=",readchomp(`getconf GNU_LIBC_VERSION`))
println("FLINT_jll=",pkgversion(FLINT_jll)," lib=",FLINT_jll.libflint_path)
println("source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25; artifact identity is the loaded library path above")
println("No global thread settings changed; tested kernels are scalar/native loops without threaded dispatch")
println("Inputs: rigorous 1/7 and -2/9 balls, same precision and guarantees in all paths")
println("owned_loop reuses initialized scalar owners; borrowed_loop reuses packed slots; checked_add includes validation and native call")
println("Julia allocation counts exclude FLINT malloc/mantissa growth; warmed reused destinations reported")
println("family P n owned_add_ns borrowed_add_ns checked_add_ns add_allocs add_bytes owned_mul_ns packed_mul_ns mul_allocs mul_bytes copyout_ns packed_construct_ns owned_construct_ns packed_copy_ns")
for family in (ArbBall,AcbBall), P in (128,512), n in (1,16,256)
    T=family{P}
    a,b=T(1)/T(7),T(-2)/T(9)
    x,y,z=PackedBallVector(T,fill(a,n)),PackedBallVector(T,fill(b,n)),PackedBallVector(T,n)
    xs,ys,zs=[copy(a) for _ in 1:n],[copy(b) for _ in 1:n],[T() for _ in 1:n]
    bo=@benchmark owned_loop!(FF.add!,$zs,$xs,$ys) samples=100 seconds=0.05
    bb=@benchmark borrowed_loop!(FF.add!,$z,$x,$y) samples=100 seconds=0.05
    bn=@benchmark FF.add!($z,$x,$y) samples=100 seconds=0.05
    bm=@benchmark owned_loop!(FF.mul!,$zs,$xs,$ys) samples=100 seconds=0.05
    bp=@benchmark FF.mul!($z,$x,$y) samples=100 seconds=0.05
    br=@benchmark getindex($x,1) samples=100 seconds=0.05
    # Force cleanup per sample so repeated construction does not accumulate unfinalized native owners.
    bc=@benchmark finalize(PackedBallVector($T,$n)) samples=100 seconds=0.05 evals=1
    bs=@benchmark owned_construct_clear($T,$n) samples=100 seconds=0.05 evals=1
    bk=@benchmark finalize(copy($x)) samples=100 seconds=0.05 evals=1
    println(family," ",P," ",n," ",round(minimum(bo).time;digits=1)," ",round(minimum(bb).time;digits=1)," ",
            round(minimum(bn).time;digits=1)," ",bn.allocs," ",bn.memory," ",round(minimum(bm).time;digits=1)," ",
            round(minimum(bp).time;digits=1)," ",bp.allocs," ",bp.memory," ",round(minimum(br).time;digits=1)," ",
            round(minimum(bc).time;digits=1)," ",round(minimum(bs).time;digits=1)," ",round(minimum(bk).time;digits=1))
end
println("Construction/copy columns include explicit cleanup; copyout creates an independent finalized-by-GC scalar.")
println("Footprint: packed native structs are 48 B/arb or 96 B/acb per slot plus native dynamic payload;")
println("ordinary vectors add one Julia reference and scalar-owner object headers per element. These are layout counts, not RSS measurements.")
