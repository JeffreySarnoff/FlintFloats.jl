# Run: julia --project=benchmark benchmark/m4a_vectors.jl
using FlintFloats, BenchmarkTools, FLINT_jll
const FF = FlintFloats
scalar_add!(z, x, y) = FF._scalar_bulk!(+, z, x, y)
allocating_add(x, y) = FF.add!(similar(x), x, y)
println("M4a DFloatBall vector add; minimum warmed times, 100 samples, 0.1 s budget per case")
println("Julia=", VERSION, " CPU=", Sys.cpu_info()[1].model, " Julia threads=", Threads.nthreads())
println("kernel=", Sys.KERNEL, " arch=", Sys.ARCH, " libc=", readchomp(`getconf GNU_LIBC_VERSION`))
println("FLINT_jll=", pkgversion(FLINT_jll), " lib=", FLINT_jll.libflint_path)
println("source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25; host-tuned artifact")
println("FLINT/BLAS threading: vector add does not invoke threaded kernels; no global settings changed")
println("Inputs: midpoint i/8, radius 2^-30; matching rigorous scalar/native guarantees")
println("N length scalar_ns native_checked_ns speedup native_allocs native_bytes allocating_ns allocating_bytes")
for N in 1:4, len in (1, 4, 16, 256, 4096)
    T = DFloatBall{N}
    x = [T(ntuple(j -> j == 1 ? i/8 : 0.0, N), 2.0^-30) for i in 1:len]
    y, z = copy(x), similar(x)
    bs = @benchmark scalar_add!($z, $x, $y) samples=100 seconds=0.1
    bn = @benchmark FF.add!($z, $x, $y) samples=100 seconds=0.1
    ba = @benchmark allocating_add($x, $y) samples=100 seconds=0.1
    ts, tn, ta = minimum(bs).time, minimum(bn).time, minimum(ba).time
    println(N, " ", len, " ", round(ts; digits=1), " ", round(tn; digits=1), " ",
            round(ts/tn; digits=2), " ", bn.allocs, " ", bn.memory, " ", round(ta; digits=1), " ", ba.memory)
end
