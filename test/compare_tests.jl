using FlintFloats, Test, Random

const FF = FlintFloats

# One finite value in every type that can hold it exactly.
function exact_family(v::Float64)
    vals = Any[v, BigFloat(v), ArbFloat{53}(v), ArbFloat{200}(v), DFloat{2}(v), DFloat{4}(v),
               ArbBall{64}(v), DFloatBall{2}(v), AcbFloat{64}(v, 0.0), AcbBall{64}(v, 0.0)]
    isfinite(v) && push!(vals, NFloat{1}(v), NFloat{3}(v))
    if v == round(v) && abs(v) < 2^53
        push!(vals, Int(v), big(Int(v)), Float32(v))
        v >= 0 && push!(vals, UInt64(v))
    end
    return vals
end

@testset "equality, ordering, hashing" begin
    @testset "no method ambiguities with Base" begin
        @test isempty(Test.detect_ambiguities(FlintFloats, Base))
    end

    @testset "points: exact value across precisions, families and numbers" begin
        @test ArbFloat{64}(1) == 1 && 1 == ArbFloat{64}(1) && ArbFloat{64}(1.5) == 1.5f0
        @test ArbFloat{10}(0.1) != 0.1 && ArbFloat{10}(0.1) == Float64(ArbFloat{10}(0.1))
        @test ArbFloat{64}(2) == ArbFloat{200}(2) && ArbFloat{64}(2) < ArbFloat{200}(3)
        @test DFloat{2}(1.5) == NFloat{2}(1.5) && DFloat{2}(1.5) == ArbFloat{64}(1.5)
        @test DFloat{2}(0.1) == DFloat{4}(0.1) && DFloat{2}("0.1") != 0.1                # a parsed expansion carries a tail
        @test DFloat{2}("0.1") != DFloat{4}("0.1")                                      # different widths, different values
        @test NFloat{2}(1) == NFloat{4}(1) && NFloat{2}(1) < NFloat{4}(2)
        @test ArbFloat{64}(typemax(UInt64)) == typemax(UInt64) && ArbFloat{64}(typemax(UInt64)) != typemax(Int)
        @test ArbFloat{200}(big(2)^100 + 1) == big(2)^100 + 1 && ArbFloat{200}(big(2)^100 + 1) != big(2)^100
        third = setprecision(BigFloat, 200) do
            BigFloat(1) / 3
        end
        @test ArbFloat{200}(third) == third
        @test ArbFloat{64}(1) < 2 && 2 > ArbFloat{64}(1) && ArbFloat{64}(1) <= 1 && ArbFloat{64}(1) >= 1
        @test ArbFloat{64}(-1) < big(0) && big(2)^70 > ArbFloat{64}(1e20)
        @test AcbFloat{64}(2, 0) == 2 && 2 == AcbFloat{64}(2, 0) && AcbFloat{64}(2, 1) != 2
        @test AcbFloat{64}(2, 1) == AcbFloat{80}(2, 1) && AcbFloat{64}(2, 1) != AcbFloat{80}(2, -1)
    end

    @testset "points: NaN, Inf, zero" begin
        nan, inf = ArbFloat{64}(NaN), ArbFloat{64}(BigFloat(Inf))
        @test nan != nan && !(nan == nan) && !(nan < 1) && !(nan > 1) && !(nan <= nan)
        @test isequal(nan, nan) && isequal(nan, NaN) && isequal(NaN, nan) && !isequal(nan, 1)
        @test inf == Inf && -inf == -Inf && inf > 1e308 && -inf < -1e308 && inf > ArbFloat{64}(10)^20
        @test isequal(inf, Inf) && !isequal(inf, -Inf)
        # a point zero has no sign: it is isequal to +0.0 only
        @test ArbFloat{64}(0) == 0.0 && ArbFloat{64}(0) == -0.0
        @test isequal(ArbFloat{64}(0), 0.0) && !isequal(ArbFloat{64}(0), -0.0)
        @test isequal(DFloat{2}(-0.0), DFloat{2}(0.0)) && isequal(DFloat{2}(-0.0), 0.0) && !isequal(DFloat{2}(0.0), -0.0)
        @test isless(-0.0, ArbFloat{64}(0)) && !isless(ArbFloat{64}(0), -0.0) && !isless(ArbFloat{64}(0), 0.0)
        # total order: NaN last
        v = [ArbFloat{64}(2), nan, ArbFloat{64}(-1), inf, ArbFloat{64}(0)]
        s = sort(v)
        @test isequal.(s, [ArbFloat{64}(-1), ArbFloat{64}(0), ArbFloat{64}(2), inf, nan]) |> all
        @test sort([3.0, ArbFloat{64}(1), 2, DFloat{2}(0.5)]; by = x -> x) isa Vector
        @test maximum([ArbFloat{64}(1), ArbFloat{64}(5), ArbFloat{64}(3)]) == 5
        @test min(ArbFloat{64}(1), ArbFloat{64}(2)) == 1 && isnan(min(nan, ArbFloat{64}(1)))
        @test isless(1, nan) && !isless(nan, 1) && !isless(nan, nan)
    end

    @testset "point laws on a mixed pool" begin
        base = (0.0, 1.0, -1.0, 0.5, -2.5, 3.0, 1e300, 1e-300, 2.0^70, 0.1, 1 / 3, Inf, -Inf, NaN)
        pool = reduce(vcat, [exact_family(v) for v in base])
        # reflexive, symmetric, and isequal implies equal hash, over every pair
        bad = 0
        for a in pool
            isequal(a, a) || (bad += 1)
            hash(a) == hash(a) || (bad += 1)
            for b in pool
                ab = isequal(a, b)
                ab == isequal(b, a) || (bad += 1)
                ab && hash(a) != hash(b) && (bad += 1)
                ab && hash(a, UInt(12345)) != hash(b, UInt(12345)) && (bad += 1)   # every seed
            end
        end
        @test bad == 0
        # transitive on random triples
        rng = MersenneTwister(2)
        trans = 0
        for _ in 1:20_000
            a, b, c = rand(rng, pool), rand(rng, pool), rand(rng, pool)
            isequal(a, b) && isequal(b, c) && !isequal(a, c) && (trans += 1)
        end
        @test trans == 0
        # the same value in different types is isequal; a point zero is +0
        for v in (0.0, 1.0, -2.5, 0.1, 1e300, 2.0^70, Inf, -Inf)
            fam = exact_family(v)
            # an infinite input is an exact infinite ball for arb, but the whole real line for dfloat balls
            isfinite(v) || (fam = filter(a -> !(a isa DFloatBall), fam))
            @test all(a -> isequal(fam[3], a) && isequal(a, fam[3]), fam)
        end
        @test !isindeterminate(ArbBall{64}(Inf)) && isindeterminate(DFloatBall{2}(Inf)) && !isfinite(AcbBall{64}(Inf, 0.0))
        # NaN: every point and number is isequal to NaN; the indeterminate ball is only a ball
        nanfam = exact_family(NaN)
        points = filter(a -> !(a isa Union{ArbBall,DFloatBall,AcbBall}), nanfam)
        @test all(a -> isequal(points[1], a), points)
        @test !any(a -> isequal(ArbBall{64}(NaN), a), points)
        @test isequal(ArbBall{64}(NaN), DFloatBall{2}(Inf)) && !isequal(ArbBall{64}(NaN), ArbBall{64}(Inf))   # one indeterminate value
        @test hash(ArbBall{64}(NaN)) == hash(DFloatBall{2}(Inf)) == hash(ArbBall{64}(1) / ArbBall{64}(0))
        zinf = parse(ArbBall{64}, "[0 +/- inf]")
        @test isindeterminate(zinf) && isequal(zinf, ArbBall{64}(NaN)) && hash(zinf) == hash(ArbBall{64}(NaN))
        @test !isequal(ArbFloat{64}(1), ArbFloat{64}(2)) && !isequal(DFloat{2}("0.1"), 0.1)
        # dictionaries and sets work across types
        d = Dict(ArbFloat{64}(1) => :one, DFloat{2}(0.5) => :half, NFloat{2}(2) => :two)
        @test d[1] == :one && d[1.0] == :one && d[big(1)] == :one && d[0.5] == :half && d[2] == :two
        @test d[ArbFloat{200}(1)] == :one && d[AcbFloat{64}(1, 0)] == :one
        @test length(Set([ArbFloat{64}(1), 1, 1.0, big(1), DFloat{3}(1), NFloat{2}(1), AcbBall{64}(1, 0)])) == 1
    end

    @testset "hash does not expand huge exponents" begin
        huge = FF._pow2(ArbFloat{64}, 10^15)                                   # 2^(10^15)
        t = @elapsed (h = hash(huge))
        @test t < 1.0 && h == hash(huge) && isequal(huge, FF._pow2(ArbFloat{64}, 10^15))
        @test !isequal(huge, ArbFloat{64}(1)) && huge > 1e308 && huge == huge
        beyond = FF._pow2(ArbFloat{64}, 5 * 10^18)                             # outside MPFR's exponent range
        @test hash(beyond) isa UInt && isequal(beyond, beyond) && !isequal(beyond, ArbFloat{64}(1))
        tiny = FF._pow2(ArbFloat{64}, -10^15)
        @test tiny > 0 && tiny < 1e-300 && hash(tiny) isa UInt
    end

    @testset "balls: proofs, not point comparisons" begin
        ball(s) = parse(ArbBall{64}, s)
        pm(m, r) = ArbBall{64}(ArbFloat{64}(m), ArbFloat{64}(r))                   # exact radius, no parse rounding
        a, b = ball("[1 +/- 0.5]"), ball("[1 +/- 0.5]")
        # overlapping uncertain inputs: neither equal nor unequal nor ordered
        @test !(a == b) && !(a != b) && !(a < b) && !(a > b) && !(a <= b) && !(a >= b)
        @test !(a == a)                                                        # a nonsingleton can fail x == x
        @test isequal(a, b) && isequal(a, a) && hash(a) == hash(b)
        # exact balls behave like numbers
        two = ArbBall{64}(2)
        @test two == two && two == 2 && 2 == two && !(two != 2) && two <= 2 && two >= 2 && !(two < 2)
        @test two != 3 && two < 3 && two > 1 && 1 < two && 3 > two
        # disjoint balls
        lo, hi = ball("[1 +/- 0.1]"), ball("[3 +/- 0.1]")
        @test lo != hi && hi != lo && lo < hi && lo <= hi && hi > lo && hi >= lo && !(lo == hi) && !(lo > hi)
        # FLINT rounds a ball radius up to a 30-bit magnitude, so balls built from radii cannot touch
        # exactly (DFloatBall below does); near-touching balls overlap, separated ones do not
        @test !(pm(1.0, 1.0) <= pm(2.9, 1.0)) && !(pm(1.0, 1.0) != pm(2.9, 1.0))
        @test pm(1.0, 1.0) < pm(3.5, 1.0) && pm(1.0, 1.0) != pm(3.5, 1.0)
        # singletons: every relation is decided
        @test ArbBall{64}(2) <= ArbBall{64}(2) && ArbBall{64}(2) >= ArbBall{64}(2) && !(ArbBall{64}(2) < ArbBall{64}(2))
        # point against ball
        @test ball("[1 +/- 0.5]") != 3 && ball("[1 +/- 0.5]") < 2 && !(ball("[1 +/- 0.5]") == 1) && !(ball("[1 +/- 0.5]") != 1)
        @test ArbFloat{64}(5) > lo && lo < ArbFloat{64}(5) && DFloat{2}(5) > lo && 5 > lo
        # indeterminate ball
        w = ArbBall{64}(1) / ArbBall{64}(0)
        @test !(w == w) && !(w != w) && !(w < 1) && isequal(w, w) && hash(w) == hash(w)
        @test isequal(w, ArbBall{64}(NaN)) && !isequal(w, ArbBall{64}(1))
        # precision metadata is not part of equality
        @test ArbBall{64}(3) == ArbBall{200}(3) && isequal(ArbBall{64}(3), ArbBall{200}(3)) && hash(ArbBall{64}(3)) == hash(ArbBall{200}(3))
        # inequality is not the negation of equality, and order is not derived from it
        @test (a != b) == false && (a == b) == false
        # an exact ball is isequal to the number it holds, with the same hash
        @test isequal(two, 2) && isequal(2.0, two) && hash(two) == hash(2) && hash(two) == hash(ArbFloat{64}(2))
        @test !isequal(a, 1) && !isequal(a, ArbFloat{64}(1))
    end

    @testset "dfloat balls" begin
        ball(m, r) = DFloatBall{2}((m, 0.0), r)
        a, b = ball(1.0, 0.5), ball(1.0, 0.5)
        @test !(a == b) && !(a != b) && !(a < b) && !(a > b) && !(a <= b) && !(a >= b)
        @test isequal(a, b) && hash(a) == hash(b) && !isequal(a, ball(1.0, 0.25))
        e = DFloatBall{2}(2.0)
        @test e == e && e == DFloatBall{4}(2.0) && e == 2 && e != 3 && e < 3 && e > 1
        lo, hi = ball(1.0, 0.1), ball(3.0, 0.1)
        @test lo != hi && lo < hi && lo <= hi && hi > lo && hi >= lo && !(lo == hi)
        l, r = ball(1.0, 1.0), ball(3.0, 1.0)                                  # touch at 2
        @test l <= r && r >= l && !(l < r) && !(r > l) && !(l != r)
        # consistency with FLINT's own cmp: whenever it proves an order, so do we
        rng = MersenneTwister(4)
        agree = true
        for _ in 1:500
            x, y = ball(randn(rng), rand(rng) / 2), ball(randn(rng) + 0.5, rand(rng) / 2)
            c = FF._dcmp(x, y)
            c == -1 && !(x < y) && (agree = false)
            c == 1 && !(x > y) && (agree = false)
            c == -1 && (x >= y) && (agree = false)
        end
        @test agree
        # enclosures: comparison with an arb ball agrees with the equivalent ArbBall
        @test ball(1.0, 0.1) < ArbBall{64}(3) && ArbBall{64}(3) > ball(1.0, 0.1) && ball(1.0, 0.1) != ArbBall{64}(3)
        # the whole real line
        wl = FF._indeterminate(DFloatBall{2})
        @test !(wl == wl) && !(wl != wl) && isequal(wl, wl) && hash(wl) == hash(wl)
        @test isequal(wl, DFloatBall{2}((NaN, 0.0), 0.0))                         # any nonfinite input is the whole line
        # different N widen exactly
        @test hash(DFloatBall{2}(2.0)) == hash(DFloatBall{4}(2.0)) == hash(2.0)
        @test isequal(DFloatBall{2}(2.0), DFloatBall{4}(2.0))
    end

    @testset "complex balls" begin
        z = AcbBall{64}(1, 2)
        @test z == z && z == AcbBall{64}(1, 2) && z != AcbBall{64}(1, 3) && z != 1
        @test AcbBall{64}(3, 0) == 3 && 3 == AcbBall{64}(3, 0) && AcbBall{64}(3, 0) == ArbBall{64}(3)
        @test z == AcbFloat{64}(1, 2) && AcbFloat{64}(1, 2) == z && AcbFloat{64}(1, 2) != AcbBall{64}(1, 3)
        u = parse(ArbBall{64}, "[1 +/- 0.5]")
        zz = AcbBall{64}(u, ArbBall{64}(2))
        @test !(zz == zz) && !(zz != zz) && isequal(zz, zz) && hash(zz) == hash(zz)
        @test isequal(AcbBall{64}(3, 0), 3) && hash(AcbBall{64}(3, 0)) == hash(3)
        @test hash(AcbBall{64}(3, 4)) == hash(AcbFloat{64}(3, 4)) && isequal(AcbBall{64}(3, 4), AcbFloat{64}(3, 4))
        @test_throws MethodError AcbBall{64}(1, 2) < AcbBall{64}(1, 3)         # no order on the complex plane
        @test_throws MethodError isless(AcbFloat{64}(1, 2), AcbFloat{64}(3, 4))
    end

    @testset "balls have no numerical order" begin
        bs = [ArbBall{64}(3), ArbBall{64}(1), ArbBall{64}(2)]
        @test_throws ArgumentError sort(bs)
        @test_throws ArgumentError max(bs[1], bs[2])
        @test_throws ArgumentError isless(bs[1], 2.0)
        @test_throws ArgumentError isless(2, bs[1])
        @test_throws ArgumentError isless(DFloatBall{2}(1), DFloatBall{2}(2))
        @test_throws ArgumentError maximum(bs)
        # the enclosure sort key is deterministic and carries no numerical claim
        s = sort(bs; by = FF.sortkey)
        @test Float64.(s) == [1.0, 2.0, 3.0]
        ds = sort([DFloatBall{2}(3.0), DFloatBall{2}(1.0)]; by = FF.sortkey)
        @test Float64.(ds) == [1.0, 3.0]
        zs = sort([AcbBall{64}(2, 1), AcbBall{64}(1, 5)]; by = FF.sortkey)
        @test Float64(real(zs[1])) == 1
    end

    @testset "ball conversion to a point is explicit" begin
        q = ArbBall{64}(1) / ArbBall{64}(3)
        @test_throws ArgumentError Float64(q)
        @test Float64(midpoint(q)) == 1 / 3 && Float64(ArbBall{64}(2.5)) == 2.5
        b = DFloatBall{2}(1.0) / DFloatBall{2}(3.0)
        @test_throws ArgumentError Float64(b)
        @test Float64(DFloatBall{2}(2.5)) == 2.5
    end
end
