using FlintFloats, Test, Random

const FF = FlintFloats
const MODES = (RoundNearest, RoundToZero, RoundFromZero, RoundDown, RoundUp)

@testset "conversion, parsing, display" begin
    @testset "integers" begin
        for x in (0, 1, -1, 7, typemax(Int), typemin(Int), typemax(UInt64), big(2)^100 + 1, -big(10)^40, typemax(Int128), UInt8(200), Int16(-5), true)
            @test BigFloat(ArbFloat{200}(x)) == BigFloat(x; precision = 200)          # exact when it fits
            @test Float64(ArbBall{200}(x)) == Float64(BigFloat(x; precision = 200))
        end
        # when it does not fit, one rounding to nearest at P bits, like MPFR
        for x in (big(2)^100 + 1, big(3)^70, -big(7)^50), P in (10, 53, 64)
            @test BigFloat(ArbFloat{P}(x)) == BigFloat(x; precision = P)
        end
    end

    @testset "BigFloat" begin
        rng = MersenneTwister(3)
        for P in (2, 24, 64, 200)
            for _ in 1:50
                b = BigFloat(randn(rng) * 2.0^rand(rng, -20:20); precision = P)
                @test BigFloat(ArbFloat{P}(b)) == b                                      # exact round trip
            end
        end
        for v in (BigFloat(NaN), BigFloat(Inf), BigFloat(-Inf), BigFloat(0))
            r = BigFloat(ArbFloat{64}(v))
            @test isnan(v) ? isnan(r) : r == v
        end
        # re-rounding to another precision and mode agrees with MPFR
        for P in (5, 24, 53), mode in MODES
            for _ in 1:100
                b = BigFloat(randn(rng); precision = 200)
                a = ArbFloat{200}(b)
                @test BigFloat(ArbFloat{P}(a, mode)) == BigFloat(b, mode; precision = P)
                @test BigFloat(a, mode; precision = P) == BigFloat(b, mode; precision = P)
            end
        end
    end

    @testset "ball from point contains it" begin
        a = ArbFloat{64}(big(pi))
        r = ArbBall{10}(a)
        err = abs(BigFloat(midpoint(r); precision = 64) - BigFloat(a))
        @test BigFloat(radius(r); precision = 64) >= err > 0
        @test isexact(ArbBall{64}(a)) && !isexact(r)
        @test_throws ArgumentError ArbFloat{64}(ArbBall{64}(1))                          # no implicit information loss
    end

    @testset "nfloat and dfloat" begin
        a = ArbFloat{200}(BigFloat(1) / 3)
        @test BigFloat(ArbFloat{128}(NFloat{2}(a))) == BigFloat(ArbFloat{128}(a))        # one nearest rounding
        @test BigFloat(ArbFloat{64}(NFloat{1}(big(2)^63 + 1))) == BigFloat(2)^63 + 1            # fits 64 bits exactly
        @test Float64(NFloat{3}(big(10)^50)) == 1e50
        @test BigFloat(ArbFloat{64}(NFloat{1}(typemax(UInt64)))) == BigFloat(typemax(UInt64))
        @test_throws DomainError NFloat{2}(ArbFloat{64}(NaN))
        for N in 1:4
            d = DFloat{N}(big(10)^30)
            @test abs(BigFloat(ArbFloat{300}(d)) - BigFloat(10)^30) <= BigFloat(10)^30 * BigFloat(2)^(-52N + 2)
        end
        @test DFloatBall{2}(big(3)).rad == 0.0
        @test DFloatBall{2}(big(10)^60).rad > 0                  # 5^60 needs more than 106 bits
        @test DFloatBall{2}(big(10)^40).rad == 0                 # 5^40 fits
        # NFloat -> ArbFloat is exact once P >= 64L
        n = NFloat{2}(BigFloat(1) / 3)
        @test BigFloat(ArbFloat{128}(n)) == BigFloat(ArbFloat{128}(BigFloat(1) / 3))
    end

    @testset "parse and show round trips" begin
        rng = MersenneTwister(5)
        for P in (2, 10, 53, 64, 130, 500)
            for _ in 1:20
                x = ArbFloat{P}(BigFloat(randn(rng) * 2.0^rand(rng, -30:30); precision = P))
                y = eval(Meta.parse(repr(x)))
                @test y isa ArbFloat{P} && BigFloat(y) == BigFloat(x)
                @test BigFloat(parse(ArbFloat{P}, string(BigFloat(x)))) == BigFloat(x)
            end
        end
        for L in (1, 2, 5)
            x = NFloat{L}(BigFloat(1; precision = 64L) / 7)
            y = eval(Meta.parse(repr(x)))
            @test y isa NFloat{L} && y == x
        end
        for N in 1:4
            x = DFloat{N}("0.1")
            @test eval(Meta.parse(repr(x))) === x
            b = DFloatBall{N}("0.1")
            @test eval(Meta.parse(repr(b))) === b
            @test b.rad > 0
        end
        for P in (53, 128)
            b = ArbBall{P}(1) / ArbBall{P}(3)
            r = eval(Meta.parse(repr(b)))
            @test r isa ArbBall{P} && contains(r, b)                                  # contains the original
            z = AcbBall{P}(1, 2) / AcbBall{P}(3, 4)
            rz = eval(Meta.parse(repr(z)))
            @test rz isa AcbBall{P} && contains(real(rz), real(z)) && contains(imag(rz), imag(z))
            c = AcbFloat{P}(ArbFloat{P}(BigFloat(0.5; precision = P)), ArbFloat{P}(BigFloat(-2.25; precision = P)))
            rc = eval(Meta.parse(repr(c)))
            @test Float64(real(rc)) == 0.5 && Float64(imag(rc)) == -2.25
        end
        @test repr(ArbFloat{64}(NaN)) == "ArbFloat{64}(\"NaN\")"
        @test repr(ArbFloat{64}(BigFloat(Inf))) == "ArbFloat{64}(\"Inf\")"
        @test_throws ArgumentError parse(ArbBall{64}, "not a number")
        @test_throws ArgumentError parse(DFloat{2}, "not a number")
        @test_throws ArgumentError parse(DFloatBall{2}, "not a number")
        @test parse(ArbBall{64}, "[1 +/- 0.5]") isa ArbBall{64}
        @test contains(parse(ArbBall{64}, "[1 +/- 0.5]"), ArbBall{64}(1.25))
    end

    @testset "mixed arithmetic keeps the FLINT operand's type" begin
        x = ArbFloat{100}(2)
        @test (x + 1) isa ArbFloat{100} && Float64(x + 1) == 3 && Float64(1 - x) == -1
        @test Float64(x * 2.5) == 5 && Float64(5 / x) == 2.5
        b = ArbBall{100}(2)
        @test (2.5 * b) isa ArbBall{100} && Float64(b - UInt8(1)) == 1
        z = AcbBall{100}(1, 1)
        @test (z * 2) isa AcbBall{100} && Float64(real(z * 2)) == 2 && Float64(imag(2 * z)) == 2
        @test (AcbFloat{100}(1, 1) + 1.5) isa AcbFloat{100}
        @test (NFloat{2}(1) + 1) isa NFloat{2} && Float64(NFloat{2}(6) / 3) == 2
        @test (DFloat{2}(1) / 2) isa DFloat{2} && Float64(DFloat{3}(3) * 2.0) == 6
        @test (DFloatBall{2}(1) + Int32(2)) isa DFloatBall{2}
        @test convert(ArbBall{64}, 3) isa ArbBall{64}
        @test Float64(ArbFloat{64}(typemax(UInt64)) + 0) == Float64(typemax(UInt64))
    end
end
