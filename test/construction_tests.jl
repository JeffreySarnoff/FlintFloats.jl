using FlintFloats, Test

@testset "construction and precision" begin
    @testset "invalid type parameters" begin
        @test_throws ArgumentError DFloat{0}(())
        @test_throws ArgumentError DFloat{5}(ntuple(_ -> 0.0, 5))
        @test_throws ArgumentError DFloatBall{5}(ntuple(_ -> 0.0, 5), 0.0)
        @test_throws ArgumentError NFloat{67}(1.0)
        @test_throws ArgumentError NFloat{0}(0, UInt(0), ())
        for T in (ArbFloat, ArbBall)
            @test_throws ArgumentError T{1}()
            @test_throws ArgumentError T{-5}()
            @test_throws ArgumentError T{2.0}()
        end
        for T in (AcbFloat, AcbBall)
            @test_throws ArgumentError T{1}()
            @test_throws ArgumentError T{0}()
        end
    end

    @testset "precision" begin
        @test precision(DFloat{2}(1.0)) == 106 && precision(DFloatBall{4}) == 212
        @test precision(NFloat{3}(1.0)) == 192
        @test FlintFloats.NFloatType(100) == NFloat{2}
        @test FlintFloats.NFloatType(128) == NFloat{2}
        @test FlintFloats.NFloatType(129) == NFloat{3}
        @test precision(ArbFloat{100}(1)) == 100 && precision(ArbBall{100}) == 100
        @test precision(AcbFloat{77}(1.0)) == 77 && precision(AcbBall{77}(1.0)) == 77
        @test ArbFloat(1) isa ArbFloat{FlintFloats.DEFAULT_PRECISION}
        @test ArbBall(1.5) isa ArbBall{256}
        @test AcbBall(1.0, 2.0) isa AcbBall{256}
    end

    @testset "hierarchy" begin
        for T in (DFloat{2}, DFloatBall{2}, NFloat{2}, ArbFloat{64}, ArbBall{64})
            @test T <: AbstractFloat && T <: FlintReal
        end
        for T in (AcbFloat{64}, AcbBall{64})
            @test T <: Number && !(T <: Real)
        end
    end

    @testset "values round trip" begin
        for x in (0.0, 1.0, -2.5, 1e300, 5e-324, 0.1)
            @test Float64(DFloat{1}(x)) == x && Float64(DFloat{3}(x)) == x
            @test Float64(DFloatBall{2}(x)) == x
            @test Float64(NFloat{2}(x)) == x
            @test Float64(ArbFloat{64}(x)) == x
            @test Float64(ArbBall{64}(x)) == x
        end
        @test Float64(ArbFloat{64}(typemax(Int))) == Float64(typemax(Int))
        @test Float64(ArbFloat{64}(-7)) == -7.0
        @test isnan(Float64(ArbFloat{64}(NaN)))
        @test Float64(ArbFloat{64}(Inf)) == Inf
        @test_throws DomainError NFloat{2}(Inf)            # finite-only: see docs/float_interfacing.md
        @test_throws DomainError NFloat{2}(NaN)
    end

    @testset "precision invariant" begin
        # mantissa of Float64(pi) is 53 bits; P = 10 must round it
        function mantbits(x::Float64)
            m = reinterpret(UInt64, x) & (UInt64(1) << 52 - 1) | (UInt64(1) << 52)
            return 53 - trailing_zeros(m)
        end
        for P in (2, 3, 10, 24, 53)
            z = ArbFloat{P}(Float64(pi))
            @test mantbits(Float64(z)) <= P
            m = midpoint(ArbBall{P}(Float64(pi)))
            @test mantbits(Float64(m)) <= P
            @test mantbits(Float64(real(AcbFloat{P}(Float64(pi), 1.0)))) <= P
        end
        @test Float64(ArbFloat{10}(Float64(pi))) == Float64(BigFloat(pi; precision = 10)) == 3.140625
    end
end
