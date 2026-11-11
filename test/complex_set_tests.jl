using FlintFloats, Test
function _cs_bounds(x::ArbBall)
    y=ArbBall{max(64,precision(x))}(x)
    m=Rational{BigInt}(BigFloat(midpoint(y)));r=Rational{BigInt}(BigFloat(radius(y)))
    m-r,m+r
end
@testset "complex destination assignment" begin
    for P in (5,64,256,2048),Q in (5,64,256,2048)
        source=AcbFloat{Q}(ArbFloat{Q}(1)/ArbFloat{Q}(7),ArbFloat{Q}(-2)/ArbFloat{Q}(9))
        for mode in (RoundNearest,RoundToZero,RoundFromZero,RoundDown,RoundUp)
            z=AcbFloat{P}();@test (@inferred FlintFloats.set!(z,source,mode))===z
            for part in (real,imag)
                reference=BigFloat(BigFloat(part(source)),mode;precision=P)
                @test BigFloat(part(z))==reference
            end
        end
        source=AcbBall{Q}(ArbBall{Q}(1)/ArbBall{Q}(7),ArbBall{Q}(-2)/ArbBall{Q}(9))
        z=AcbBall{P}();@test (@inferred FlintFloats.set!(z,source))===z
        for part in (real,imag)
            lo,hi=_cs_bounds(part(source));a,b=_cs_bounds(part(z))
            @test a<=lo && hi<=b
        end
    end
    for T in (AcbFloat{64},AcbBall{64})
        z=T(1,2);saved=copy(z)
        @test FlintFloats.set!(z,z)===z && isequal(z,saved)
        source=T(3,4);FlintFloats.set!(z,source);FlintFloats.add!(source,source,T(1))
        @test z==T(3,4)
        function bytes!(z,source)
            FlintFloats.set!(z,source);FlintFloats.set!(z,source)
            @allocated FlintFloats.set!(z,source)
        end
        @test bytes!(z,source)==0
    end
    z=AcbFloat{64}(3,4);source=AcbFloat{64}(1,2)
    @test_throws ArgumentError FlintFloats.set!(z,source,RoundNearestTiesAway)
    @test z==AcbFloat{64}(3,4)
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
