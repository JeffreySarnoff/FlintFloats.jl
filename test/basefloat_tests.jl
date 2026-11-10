using FlintFloats, Test, Random

const FF = FlintFloats

@testset "inherited AbstractFloat behaviour" begin
    @testset "ArbFloat neighbours match Float64 and Float32" begin
        rng = MersenneTwister(8)
        vals = Float64[1.0, 2.0, 0.5, 1.5, 3.0, 2.0^-20, 2.0^40, 1e300, 1e-300, 10.0, 0.1]
        append!(vals, [randn(rng) * 2.0^rand(rng, -30:30) for _ in 1:200])
        append!(vals, -vals)
        for v in vals
            a = ArbFloat{53}(v)
            @test eps(a) == eps(v) && nextfloat(a) == nextfloat(v) && prevfloat(a) == prevfloat(v)
            @test exponent(a) == exponent(v) && significand(a) == significand(v)
            @test nextfloat(a) isa ArbFloat{53} && significand(a) isa ArbFloat{53}
            f = Float32(v)
            (isfinite(f) && f != 0 && abs(f) > 1e-30 && abs(f) < 1e30) || continue
            b = ArbFloat{24}(Float64(f))
            @test nextfloat(b) == Float64(nextfloat(f)) && prevfloat(b) == Float64(prevfloat(f))
            @test eps(b) == Float64(eps(f))
        end
        @test eps(ArbFloat{53}) == eps(Float64) && eps(ArbFloat{24}) == Float64(eps(Float32))
        @test nextfloat(prevfloat(ArbFloat{53}(1))) == 1 && prevfloat(nextfloat(ArbFloat{53}(1))) == 1
        @test nextfloat(ArbFloat{64}(-1)) > -1 && prevfloat(ArbFloat{64}(-1)) < -1
        # binade boundary: spacing halves going down through a power of two
        @test eps(prevfloat(ArbFloat{53}(1))) == eps(1.0) / 2
        @test nextfloat(ArbFloat{53}(-1)) == nextfloat(-1.0) && nextfloat(ArbFloat{53}(-2)) == nextfloat(-2.0)
    end

    @testset "ArbFloat special cases" begin
        nan, inf = ArbFloat{64}(NaN), ArbFloat{64}(BigFloat(Inf))
        @test isnan(nextfloat(nan)) && isnan(prevfloat(nan)) && isnan(eps(nan))
        @test nextfloat(inf) == Inf && prevfloat(-inf) == -Inf && isnan(eps(inf))
        @test_throws DomainError prevfloat(inf)                           # no largest finite value
        @test_throws DomainError nextfloat(-inf)
        @test_throws DomainError nextfloat(ArbFloat{64}(0))               # no smallest positive value
        @test_throws DomainError prevfloat(ArbFloat{64}(0))
        @test_throws DomainError eps(ArbFloat{64}(0))
        @test_throws DomainError exponent(ArbFloat{64}(0))
        @test_throws DomainError exponent(inf)
        @test_throws DomainError exponent(nan)
        @test iszero(significand(ArbFloat{64}(0))) && isinf(significand(inf)) && isnan(significand(nan))
        # unbounded exponent: neighbours work at huge magnitudes
        h = FF._pow2(ArbFloat{64}, 10^15)
        @test nextfloat(h) > h && prevfloat(h) < h && exponent(h) == 10^15 && significand(h) == 1
        @test eps(h) == FF._pow2(ArbFloat{64}, 10^15 - 63)
    end

    @testset "NFloat through ArbFloat" begin
        for L in (1, 2, 3), v in (1.0, 3.5, -0.1, 1e100)
            x = NFloat{L}(v); a = ArbFloat{64L}(x)
            @test eps(x) == eps(a) && nextfloat(x) == nextfloat(a) && prevfloat(x) == prevfloat(a)
            @test exponent(x) == exponent(a) && significand(x) == significand(a)
            @test nextfloat(x) isa NFloat{L} && eps(x) isa NFloat{L} && significand(x) isa NFloat{L}
            @test eps(NFloat{L}) == eps(ArbFloat{64L}) && eps(NFloat{L}) isa NFloat{L}
        end
        @test_throws DomainError eps(NFloat{2}(0))
        @test_throws DomainError nextfloat(NFloat{2}(0))
    end

    @testset "DFloat: nominal eps only" begin
        @test eps(DFloat{2}) == DFloat{2}(2.0^-105) && eps(DFloat{1}) == eps(Float64)
        for f in (eps, exponent, significand, nextfloat, prevfloat)
            @test_throws ArgumentError f(DFloat{2}(1.5))
        end
        # isapprox works through the nominal eps
        @test isapprox(DFloat{2}(1), DFloat{2}(1) + DFloat{2}(2.0^-120)) && !isapprox(DFloat{2}(1), DFloat{2}(2))
    end

    @testset "exponent range is not advertised" begin
        for T in (DFloat{2}, DFloatBall{2}, NFloat{2}, ArbFloat{64}, ArbBall{64})
            @test_throws ArgumentError floatmin(T)
            @test_throws ArgumentError floatmax(T)
        end
        @test_throws ArgumentError floatmax(ArbFloat{64}(1))
        for T in (DFloat{2}, NFloat{2}, ArbFloat{64}, ArbBall{64})
            @test_throws MethodError typemax(T)
            @test_throws MethodError typemin(T)
        end
    end

    @testset "balls have no neighbours and no isapprox" begin
        for b in (ArbBall{64}(1.5), DFloatBall{2}(1.5))
            for f in (eps, exponent, significand, nextfloat, prevfloat)
                @test_throws ArgumentError f(b)
            end
            @test_throws ArgumentError isapprox(b, b)
            @test_throws ArgumentError isapprox(b, 1.5)
            @test_throws ArgumentError isapprox(1.5, b)
        end
        @test_throws ArgumentError eps(ArbBall{64})
        @test_throws ArgumentError isapprox(AcbBall{64}(1, 1), AcbBall{64}(1, 1))
    end

    @testset "isapprox for points" begin
        x = ArbFloat{200}(1)
        @test isapprox(x, x + eps(x)) && !isapprox(x, ArbFloat{200}(2))
        @test isapprox(x, 1.0) && isapprox(1.0, x) && !isapprox(x, 1.1)
        @test isapprox(NFloat{2}(1), NFloat{2}(1) + eps(NFloat{2}(1)))
        @test isapprox(AcbFloat{128}(1, 1), AcbFloat{128}(1, 1)) && !isapprox(AcbFloat{128}(1, 1), AcbFloat{128}(1, 2))
    end

    @testset "other inherited operations behave" begin
        x = ArbFloat{64}(3)
        @test x^2 == 9 && x^3 == 27 && (x^2) isa ArbFloat{64}               # power by squaring through *
        @test_throws MethodError round(x)
        @test_throws MethodError floor(x)
        @test_throws MethodError exp(x)
        @test zero(x) == 0 && one(x) == 1 && oneunit(x) == 1
        @test float(x) === x                                                # already a float type
        @test hash(x) == hash(3)
        @test isinteger(x) && !isinteger(ArbFloat{64}(2.5))
        @test copysign(Float64(x), -1) == -3
    end
end
