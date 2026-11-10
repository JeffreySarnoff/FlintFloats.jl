using FlintFloats, Test

@testset "ownership" begin
    @testset "copy is independent; assignment aliases" begin
        for (mk, T) in ((() -> ArbFloat{64}(2.0), ArbFloat), (() -> ArbBall{64}(2.0), ArbBall))
            x = mk()
            y = copy(x)
            z = x                                   # alias, same owner
            FlintFloats.add!(x, x, x)               # x = 4
            @test Float64(x) == 4.0 && Float64(z) == 4.0
            @test Float64(y) == 2.0                 # copy untouched
        end
        x = AcbFloat{64}(1.0, 1.0); y = copy(x)
        FlintFloats.add!(x, x, x)
        @test Float64(real(x)) == 2.0 && Float64(real(y)) == 1.0
        x = AcbBall{64}(1.0, 1.0); y = copy(x)
        FlintFloats.add!(x, x, x)
        @test Float64(real(x)) == 2.0 && Float64(real(y)) == 1.0
    end

    @testset "destination arithmetic reuses storage, allows aliasing" begin
        acc = ArbBall{128}(0)
        step = ArbBall{128}(1)
        for _ in 1:1000
            FlintFloats.add!(acc, acc, step)       # destination aliases an input
        end
        @test Float64(acc) == 1000.0
        z = ArbFloat{64}(0.0)
        @test FlintFloats.add!(z, ArbFloat{64}(1), ArbFloat{64}(2)) === z    # returns the destination
    end

    @testset "heap-backed mantissas survive GC (no double clear, no use after clear)" begin
        # > 128 bit mantissas allocate on the FLINT heap, so clear bugs would crash or corrupt
        P = 3000
        keep = ArbFloat{P}[]
        for i in 1:2000
            v = ArbFloat{P}(1) / ArbFloat{P}(3 + i)
            i % 10 == 0 && push!(keep, v)
            ArbBall{P}(1) / ArbBall{P}(7)
            AcbBall{P}(1.0, 2.0) / AcbBall{P}(3.0, 4.0)
            AcbFloat{P}(1.0, 2.0) / AcbFloat{P}(3.0, 4.0)
        end
        GC.gc(); GC.gc(true)
        @test all(v -> 0 < Float64(v) < 1, keep)
        c = copy(keep[1]); empty!(keep); GC.gc(true)
        @test 0 < Float64(c) < 1
    end

    @testset "concurrent tasks" begin
        tasks = [Threads.@spawn begin
                     s = ArbBall{128}(0)
                     for _ in 1:2000
                         FlintFloats.add!(s, s, ArbBall{128}(1))
                     end
                     Float64(s) + Float64(NFloat{2}(1.0) + NFloat{2}(i))
                 end for i in 1:8]
        @test fetch.(tasks) == [2000.0 + 1.0 + i for i in 1:8]
    end

    @testset "inference and allocation" begin
        x, y = DFloat{2}(1.5), DFloat{2}(2.5)
        @test (@inferred x + y) isa DFloat{2}
        b1, b2 = DFloatBall{2}(1.0), DFloatBall{2}(2.0)
        @test (@inferred b1 / b2) isa DFloatBall{2}
        n1, n2 = NFloat{4}(1.0), NFloat{4}(2.0)
        @test (@inferred n1 * n2) isa NFloat{4}
        a, c = ArbBall{128}(1), ArbBall{128}(2)
        @test (@inferred a + c) isa ArbBall{128}
        f, g = ArbFloat{128}(1), ArbFloat{128}(2)
        @test (@inferred f * g) isa ArbFloat{128}
        @test (@inferred FlintFloats.add!(f, f, g)) isa ArbFloat{128}
    end
end
