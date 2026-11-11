# Run: julia --project=benchmark benchmark/reusable.jl
using FlintFloats, BenchmarkTools, FLINT_jll
const FF = FlintFloats
function raw_native!(::Val{F}, z, x, y, ctx) where {F}
    GC.@preserve z x y begin
        if F === :add
            FF.LibFlint._nfloat_vec_add(pointer(z), pointer(x), pointer(y), length(z), ctx)
        else
            FF.LibFlint._nfloat_vec_mul(pointer(z), pointer(x), pointer(y), length(z), ctx)
        end
    end
end
println("Reusable nfloat workspace; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=", VERSION, " CPU=", Sys.cpu_info()[1].model, " Julia threads=", Threads.nthreads())
println("kernel=", Sys.KERNEL, " arch=", Sys.ARCH, " libc=", readchomp(`getconf GNU_LIBC_VERSION`))
println("FLINT_jll=", pkgversion(FLINT_jll), " lib=", FLINT_jll.libflint_path)
println("source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25; artifact identity is the loaded library path above")
println("No native threaded kernels; no global thread settings changed")
println("Inputs: finite decimal mantissas, mixed signs; same commit-on-success policy in both checked paths")
println("reuse includes validation, exclusive-use atomic guard, kernel, status check, active-prefix copy; capacity is preallocated")
println("raw excludes scratch/validation/commit; constructor includes initial capacity, grow includes fresh empty workspace plus capacity growth")
println("op L length allocating_ns reuse_ns speedup reuse_allocs reuse_bytes raw_native_ns constructor_ns grow_ns")
for L in (1, 2, 16, 66), n in (1, 4, 64, 1024)
    T = NFloat{L}
    x, y = fill(T("1.234567890123456789"), n), fill(T("-0.9876543210987654321"), n)
    z = similar(x)
    work = NFloatWorkspace(T, n + 8) # Deliberately exercise a larger buffer than the active prefix.
    ctx = FF._ctx(T)
    bc = @benchmark NFloatWorkspace($T, $n) samples=100 seconds=0.05
    bg = @benchmark sizehint!(NFloatWorkspace($T), $n) samples=100 seconds=0.05
    for (op, f!) in ((:add, FF.add!), (:mul, FF.mul!))
        v = Val(op)
        ba = @benchmark $f!($z, $x, $y) samples=100 seconds=0.05
        br = @benchmark $f!($z, $x, $y, $work) samples=100 seconds=0.05
        bn = @benchmark raw_native!($v, $z, $x, $y, $ctx) samples=100 seconds=0.05
        ta, tr = minimum(ba).time, minimum(br).time
        println(op, " ", L, " ", n, " ", round(ta; digits=1), " ", round(tr; digits=1), " ",
                round(ta/tr; digits=2), " ", br.allocs, " ", br.memory, " ",
                round(minimum(bn).time; digits=1), " ", round(minimum(bc).time; digits=1), " ",
                round(minimum(bg).time; digits=1))
    end
end
println("strided input fallback: op L length allocating_ns reuse_ns reuse_allocs reuse_bytes")
for L in (2, 16), n in (4, 64)
    T = NFloat{L}
    x, y = view(fill(T(1.25), 2n), 1:2:2n), view(fill(T(2), 2n), 1:2:2n)
    z, work = Vector{T}(undef, n), NFloatWorkspace(T, n)
    for (op, f!) in ((:add, FF.add!), (:mul, FF.mul!))
        ba = @benchmark $f!($z, $x, $y) samples=100 seconds=0.05
        br = @benchmark $f!($z, $x, $y, $work) samples=100 seconds=0.05
        println(op, " ", L, " ", n, " ", round(minimum(ba).time; digits=1), " ",
                round(minimum(br).time; digits=1), " ", br.allocs, " ", br.memory)
    end
end
