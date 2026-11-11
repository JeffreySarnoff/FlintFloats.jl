using FlintFloats, Test, Random

const FF = FlintFloats

@testset "promotion and conversion" begin
    @testset "promoted types" begin
        pt = promote_type
        @test pt(DFloat{2}, DFloat{4}) == DFloat{4} && pt(DFloatBall{1}, DFloatBall{3}) == DFloatBall{3}
        @test pt(DFloat{2}, DFloatBall{3}) == DFloatBall{3} && pt(DFloatBall{3}, DFloat{2}) == DFloatBall{3}
        @test pt(NFloat{1}, NFloat{3}) == NFloat{3}
        @test pt(ArbFloat{64}, ArbFloat{100}) == ArbFloat{100} && pt(ArbBall{64}, ArbBall{10}) == ArbBall{64}
        @test pt(AcbFloat{64}, AcbFloat{100}) == AcbFloat{100} && pt(AcbBall{64}, AcbBall{10}) == AcbBall{64}
        # point with ball gives the ball; real with complex gives the complex
        @test pt(ArbFloat{64}, ArbBall{100}) == ArbBall{100} && pt(ArbFloat{200}, ArbBall{100}) == ArbBall{200}
        @test pt(ArbFloat{64}, AcbFloat{100}) == AcbFloat{100} && pt(ArbBall{64}, AcbBall{100}) == AcbBall{100}
        @test pt(ArbFloat{64}, AcbBall{50}) == AcbBall{64} && pt(ArbBall{64}, AcbFloat{50}) == AcbBall{64}
        @test pt(AcbFloat{64}, AcbBall{50}) == AcbBall{64}
        # DFloat counts as 53N bits, NFloat as 64L, when meeting the arb family
        @test pt(DFloat{2}, ArbFloat{64}) == ArbFloat{106} && pt(DFloat{1}, ArbFloat{64}) == ArbFloat{64}
        @test pt(NFloat{2}, ArbFloat{64}) == ArbFloat{128} && pt(NFloat{1}, ArbBall{200}) == ArbBall{200}
        @test pt(DFloat{2}, AcbBall{64}) == AcbBall{106} && pt(NFloat{2}, AcbFloat{64}) == AcbFloat{128}
        # symmetric
        types = (DFloat{2}, DFloat{4}, DFloatBall{2}, NFloat{1}, NFloat{3}, ArbFloat{64}, ArbBall{100},
                 AcbFloat{80}, AcbBall{70})
        for A in types, B in types
            r1 = Base.promote_rule(A, B); r2 = Base.promote_rule(B, A)
            @test pt(A, B) == pt(B, A) || (r1 === Union{} && r2 === Union{})
        end
        # three-way promotion terminates and is associative on the supported grid
        @test pt(ArbFloat{64}, ArbBall{100}, AcbFloat{80}) == AcbBall{100}
        @test pt(DFloat{2}, DFloat{3}, DFloat{4}) == DFloat{4}
        @test (@inferred promote_type(ArbFloat{64}, AcbBall{70})) == AcbBall{70}
    end

    @testset "cross-family stays explicit" begin
        @test_throws ArgumentError DFloat{2}(1) + NFloat{2}(1)
        @test_throws ArgumentError DFloatBall{2}(1) + ArbBall{64}(1)
        @test_throws ArgumentError DFloatBall{2}(1) + NFloat{2}(1)
        @test_throws ErrorException ArbFloat{64}(1) + big(1.0)               # no silent trip through BigFloat
        @test_throws ErrorException big(1.0) * ArbBall{64}(1)
        @test_throws ErrorException big(1.0) + DFloat{2}(1)
        # explicit conversions are available
        @test DFloat{2}(NFloat{2}(1.5)) == 1.5 && NFloat{2}(DFloat{2}(1.5)) == 1.5
        @test ArbBall{64}(DFloatBall{2}(1.5) |> FF._arbball |> midpoint) == 1.5
    end

    @testset "mixed arithmetic through promotion" begin
        r = ArbFloat{64}(1) + ArbFloat{100}(2)
        @test r isa ArbFloat{100} && r == 3
        @test (DFloat{2}(1) + DFloat{4}(2)) isa DFloat{4} && DFloat{2}(1) + DFloat{4}(2) == 3
        @test (NFloat{1}(1) * NFloat{3}(2)) isa NFloat{3} && NFloat{1}(1) * NFloat{3}(2) == 2
        @test (DFloat{2}(1) + DFloatBall{3}(2)) isa DFloatBall{3}
        b = ArbFloat{64}(2) * ArbBall{50}(3)
        @test b isa ArbBall{64} && isexact(b) && b == 6
        z = ArbFloat{64}(2) * AcbBall{100}(1, 1)
        @test z isa AcbBall{100} && real(z) == 2 && imag(z) == 2
        @test (AcbFloat{64}(1, 1) + AcbBall{50}(1, 1)) isa AcbBall{64}
        @test (DFloat{2}(0.5) + ArbFloat{64}(1)) isa ArbFloat{106} && DFloat{2}(0.5) + ArbFloat{64}(1) == 1.5
        @test (NFloat{2}(0.5) * ArbBall{64}(4)) isa ArbBall{128} && NFloat{2}(0.5) * ArbBall{64}(4) == 2
        # huge exponents survive promotion
        h = FF._pow2(ArbFloat{64}, 10^15)
        @test (h + ArbFloat{100}(1)) isa ArbFloat{100} && (h * ArbBall{64}(1)) isa ArbBall{64}
        @test h * FF._pow2(ArbFloat{64}, -10^15) == 1
        # arrays promote
        v = [ArbFloat{64}(1), ArbFloat{100}(2)]
        @test v isa Vector{ArbFloat{100}} && v[1] == 1
        @test [DFloat{2}(1), DFloat{3}(2)] isa Vector{DFloat{3}}
        @test [ArbFloat{64}(1), ArbBall{64}(2)] isa Vector{ArbBall{64}}
        @test sum([ArbFloat{64}(1), ArbFloat{100}(2), 3]) == 6
    end

    @testset "convert" begin
        # widening and into balls: exact or containing
        @test convert(ArbFloat{200}, ArbFloat{64}(1) / ArbFloat{64}(3)) == ArbFloat{64}(1) / ArbFloat{64}(3)
        @test convert(ArbBall{64}, ArbFloat{64}(2)) isa ArbBall{64} && isexact(convert(ArbBall{64}, ArbFloat{64}(2)))
        @test convert(DFloat{4}, DFloat{2}("0.1")) == DFloat{2}("0.1")
        @test convert(NFloat{3}, NFloat{1}(1.5)) == 1.5
        @test convert(AcbBall{64}, ArbFloat{64}(2)) == 2
        # narrowing a point must be exact
        @test convert(ArbFloat{10}, ArbFloat{64}(0.5)) == 0.5
        @test_throws InexactError convert(ArbFloat{10}, ArbFloat{64}(1) / ArbFloat{64}(3))
        @test_throws InexactError convert(DFloat{1}, DFloat{2}("0.1"))
        @test_throws InexactError convert(NFloat{1}, NFloat{2}(BigFloat(1) / 3))
        @test_throws InexactError convert(AcbFloat{10}, AcbFloat{64}(1 / 3, 0.5))
        # narrowing a ball keeps containment (the radius may grow)
        q = ArbBall{128}(1) / ArbBall{128}(3)
        n = convert(ArbBall{40}, q)
        @test n isa ArbBall{40} && radius(n) >= radius(q) && contains(ArbBall{128}(n), q)
        # ball to point never converts implicitly
        @test_throws ArgumentError convert(ArbFloat{64}, ArbBall{64}(1))
        @test_throws MethodError convert(DFloat{2}, ArbBall{64}(1))
        # machine numbers
        @test convert(ArbBall{64}, 3) isa ArbBall{64} && convert(AcbFloat{64}, 2.5) isa AcbFloat{64}
        @test_throws InexactError convert(ArbFloat{10}, ArbFloat{64}(0.1))
    end

    @testset "precision isolation across tasks" begin
        # precision is part of the type, so concurrent tasks cannot interfere
        third(::Val{P}) where {P} = ArbBall{P}(1) / ArbBall{P}(3)
        tasks = [Threads.@spawn begin
                     out = Tuple[]
                     for k in 1:200
                         P = 64 + 8 * ((i + k) % 8)
                         b = with_precision(third, P)
                         push!(out, (precision(b), contains(b * ArbBall{P}(3), ArbBall{P}(1)), hash(b) == hash(copy(b))))
                     end
                     out
                 end for i in 1:8]
        res = reduce(vcat, fetch.(tasks))
        @test all(r -> r[2] && r[3], res)
        @test Set(first.(res)) == Set(64 .+ 8 .* (0:7))
        # a hash-keyed collection filled from many tasks agrees with a serial fill
        d = Dict{ArbFloat{64},Int}()
        lock = ReentrantLock()
        Threads.@sync for i in 1:8
            Threads.@spawn for k in 1:200
                @lock lock (d[ArbFloat{64}(k % 17)] = k % 17)
            end
        end
        @test length(d) == 17 && all(kv -> kv[1] == kv[2], d)
    end
end
