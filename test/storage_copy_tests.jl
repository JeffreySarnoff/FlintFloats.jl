using FlintFloats, Test, Serialization
@testset "native scalar semantic deepcopy and persistence" begin
    for P in (64,2048),T in (ArbFloat{P},AcbFloat{P},ArbBall{P},AcbBall{P})
        # Large P forces heap-backed mantissas; copied words would share dangling allocations.
        value=setprecision(BigFloat,P) do;BigFloat(1)/7;end
        x=T<:Union{AcbFloat,AcbBall} ? T(realtype(T)(value),realtype(T)(-value)) : T(value)
        expected=copy(x)
        y=deepcopy(x)
        @test y!==x && isequal(y,x)
        graph=deepcopy((x,[x,x],Ref(x)))
        @test graph[1]===graph[2][1]===graph[2][2]===graph[3][]
        @test graph[1]!==x
        FlintFloats.add!(x,x,T(1))
        @test isequal(y,expected) && isequal(graph[1],expected)
        finalize(x);GC.gc()
        @test isequal(y,expected) && isequal(graph[1],expected)
        @test_throws ArgumentError serialize(IOBuffer(),y)
        @test_throws ArgumentError serialize(IOBuffer(),[y])
        @test_throws ArgumentError Serialization.deserialize(Serialization.Serializer(IOBuffer()),T)
    end
    for T in (ArbBall{128},AcbBall{128})
        v=PackedBallVector(T,[1,2]);r=borrow(v,1)
        for x in (v,r,eachborrow(v),view(v,1:2))
            @test_throws ArgumentError serialize(IOBuffer(),x)
        end
        @test_throws ArgumentError Serialization.deserialize(Serialization.Serializer(IOBuffer()),typeof(v))
        @test_throws ArgumentError Serialization.deserialize(Serialization.Serializer(IOBuffer()),typeof(r))
    end
    # Inline values have no native owners and retain stdlib round-trip behavior.
    for T in (DFloat{2},DFloatBall{2},NFloat{2})
        x=T(1.25);io=IOBuffer();serialize(io,x);seekstart(io)
        @test isequal(deserialize(io),x)
    end
    @test Base.get_extension(FlintFloats,:FlintFloatsSerializationExt)!==nothing
    @test isempty(detect_ambiguities(FlintFloats,Serialization;recursive=true))
end
