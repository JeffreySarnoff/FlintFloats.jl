# M1 scalar benchmark. Run: julia --project=benchmark benchmark/m1_scalar.jl
using FlintFloats, BenchmarkTools
const FF = FlintFloats
f(x,y) = x + y
println("== allocations / time per op (warmed) ==")
for (name, x, y) in (("DFloat{2}", DFloat{2}(1.5), DFloat{2}(2.5)),
                     ("DFloat{4}", DFloat{4}(1.5), DFloat{4}(2.5)),
                     ("DFloatBall{2}", DFloatBall{2}(1.5), DFloatBall{2}(2.5)),
                     ("NFloat{2}", NFloat{2}(1.5), NFloat{2}(2.5)),
                     ("NFloat{16}", NFloat{16}(1.5), NFloat{16}(2.5)))
    b = @benchmark f($x, $y) samples=2000 evals=100
    println(rpad(name, 15), "allocs=", b.allocs, " mem=", b.memory, " B  min=", round(minimum(b).time, digits=1), " ns")
end
for (name, x, y) in (("ArbFloat{128}", ArbFloat{128}(1.5), ArbFloat{128}(2.5)),
                     ("ArbBall{128}", ArbBall{128}(1.5), ArbBall{128}(2.5)),
                     ("AcbFloat{128}", AcbFloat{128}(1.5, 1.0), AcbFloat{128}(2.5, 2.0)),
                     ("AcbBall{128}", AcbBall{128}(1.5, 1.0), AcbBall{128}(2.5, 2.0)))
    z = typeof(x)()
    ba = @benchmark f($x, $y) samples=2000 evals=100
    bm = @benchmark FF.add!($z, $x, $y) samples=2000 evals=100
    println(rpad(name, 15), "allocating: ", ba.allocs, " allocs ", ba.memory, " B ", round(minimum(ba).time, digits=1),
            " ns | add!: ", bm.allocs, " allocs ", round(minimum(bm).time, digits=1), " ns")
end
println("== first-call latency for a fresh P ==")
for P in (1001, 1002, 1003)
    t = @elapsed (ArbBall{P}(1) + ArbBall{P}(2))
    println("ArbBall{$P} first use: ", round(t*1000, digits=1), " ms")
end
t1 = @elapsed (ArbBall{1004}(1) + ArbBall{1004}(2)); t2 = @elapsed (ArbBall{1004}(1) + ArbBall{1004}(2))
println("same P, second use: ", round(t2*1e6, digits=1), " us")
for L in (5, 6)
    tl = @elapsed (NFloat{L}(1.0) + NFloat{L}(2.0))
    println("NFloat{$L} first use: ", round(tl*1000, digits=1), " ms")
end
