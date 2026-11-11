# Run: julia --project=benchmark benchmark/m4b_vectors.jl
using FlintFloats, BenchmarkTools, FLINT_jll
const FF = FlintFloats
context_for(x::AbstractVector{T}) where {T} = FF._ctx(T)

# Same commit-on-success numerical failure policy as the public vector methods.
function scalar_transaction!(op, z, x, y)
    tmp = similar(z)
    FF._scalar_bulk!(op, tmp, x, y)
    copyto!(z, tmp)
    return z
end
function direct_native!(::Val{F}, z, x, y, ctx) where {F}
    GC.@preserve z x y begin
        if F === :add
            FF.LibFlint._nfloat_vec_add(pointer(z), pointer(x), pointer(y), length(z), ctx)
        else
            FF.LibFlint._nfloat_vec_mul(pointer(z), pointer(x), pointer(y), length(z), ctx)
        end
    end
end
println("M4b nfloat add/multiply; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=", VERSION, " CPU=", Sys.cpu_info()[1].model, " Julia threads=", Threads.nthreads())
println("kernel=", Sys.KERNEL, " arch=", Sys.ARCH, " libc=", readchomp(`getconf GNU_LIBC_VERSION`))
println("FLINT_jll=", pkgversion(FLINT_jll), " lib=", FLINT_jll.libflint_path)
println("source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25; artifact identity is the loaded library path above")
println("context=shared immutable ALLOW_UNDERFLOW only; no threaded native kernels or global setting changes")
println("Inputs: full mantissas from decimal parse, finite mixed signs, ordinary exponents; same numerical guarantees")
println("scalar_transaction includes allocation/copy; checked_native includes scratch initialization, context lookup, validation, native call, commit")
println("raw_native excludes validation/scratch allocation/commit; copy and inferred-context columns isolate those costs (context is a compiler-optimized lower bound)")
println("op L length scalar_transaction_ns checked_native_ns speedup checked_allocs checked_bytes raw_native_ns copy_ns context_ns")
for L in (1, 2, 4, 16, 66), len in (1, 4, 64, 1024)
    T = NFloat{L}
    a, b = T("1.2345678901234567890123456789"), T("-0.98765432109876543210987654321")
    x, y, z = fill(a, len), fill(b, len), fill(zero(T), len)
    ctx = FF._ctx(T)
    bc = @benchmark copyto!($z, $x) samples=100 seconds=0.05
    bt = @benchmark context_for($x) samples=100 seconds=0.05
    for (name, f!, op) in ((:add, FF.add!, +), (:mul, FF.mul!, *))
        v = Val(name)
        bs = @benchmark scalar_transaction!($op, $z, $x, $y) samples=100 seconds=0.05
        bn = @benchmark $f!($z, $x, $y) samples=100 seconds=0.05
        br = @benchmark direct_native!($v, $z, $x, $y, $ctx) samples=100 seconds=0.05
        ts, tn = minimum(bs).time, minimum(bn).time
        println(name, " ", L, " ", len, " ", round(ts; digits=1), " ", round(tn; digits=1), " ",
                round(ts/tn; digits=2), " ", bn.allocs, " ", bn.memory, " ",
                round(minimum(br).time; digits=1), " ", round(minimum(bc).time; digits=1), " ",
                round(minimum(bt).time; digits=1))
    end
end
