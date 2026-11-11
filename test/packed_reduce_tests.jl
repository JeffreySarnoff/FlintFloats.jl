using FlintFloats, Test

function _reduce_bounds(x::ArbBall)
    m=Rational{BigInt}(BigFloat(midpoint(x))); r=Rational{BigInt}(BigFloat(radius(x)))
    (m-r,m+r)
end
function _sum_allocations(v)
    sum(v); sum(v)
    @allocated sum(v)
end

@testset "packed borrowed sum" begin
    for family in (ArbBall,AcbBall), P in (64,256,2048)
        T=family{P}
        for n in (0,1,17,512)
            v=PackedBallVector(T,T.(1:n))
            s=@inferred sum(v)
            @test s isa T && s==T(n*(n+1)÷2)
            if n>0
                FlintFloats.add!(s,s,T(1))
                @test v[1]==T(1)
            end
        end
        for inds in (1:7,2:2:7,7:-2:1,[7,1,7,3],Int[])
            v=PackedBallVector(T,T.(1:7)); span=view(v,inds)
            @test sum(span)==T(sum(inds))
            @test sum(span;init=T(0))==invoke(Base.sum,Tuple{AbstractArray},span;init=T(0))
            @test isequal(collect(sum(span;dims=1)),collect(invoke(Base.sum,Tuple{AbstractArray},span;dims=1)))
        end
        short=PackedBallVector(T,fill(T(1)/T(7),1)); long=PackedBallVector(T,fill(T(1)/T(7),512))
        @test _sum_allocations(short)==_sum_allocations(long)
        empty=PackedBallVector(T,0)
        @test sum(empty)!==sum(empty)
        @test sum(empty;init=T(0))==T(0)
        v=PackedBallVector(T,[T(1)/T(7)])
        s=sum(v); original=copy(s)
        finalize(v)
        @test isequal(s,original)
        @test_throws ArgumentError sum(v)
        finalize(empty)
        @test_throws ArgumentError sum(empty)
        # Exact sum 1 under large cancellation/exponent gaps; rounded accumulation must enclose it.
        huge=family===ArbBall ? T(big(1)<<4096) : T(ArbBall{P}(big(1)<<4096))
        v=PackedBallVector(T,[huge,T(1),-huge])
        s=sum(v)
        @test family===ArbBall ? contains(s,T(1)) : contains(real(s),ArbBall{P}(1)) && contains(imag(s),ArbBall{P}(0))
        # Generic mapped callbacks receive copied values, not borrowed mutable storage.
        v=PackedBallVector(T,[1,2,3]); calls=Ref(0)
        f=x -> (calls[]+=1; FlintFloats.add!(x,x,T(1)); x)
        @test sum(f,v)==T(9) && calls[]==3
        @test all(i -> v[i]==T(i),eachindex(v))
        @test_throws MethodError sum(v;unknown_keyword=true)
        v[2]=T(0)/T(0)
        @test isindeterminate(sum(v))
    end
    @testset "exact uncertain real/complex endpoint oracle" begin
        for P in (64,256), family in (ArbBall,AcbBall)
            T=family{P}; R=ArbBall{P}
            r(i)=R(ArbFloat{P}(i/8),ArbFloat{P}(1/16))
            vals=family===ArbBall ? [r(i) for i in -8:8] : [T(r(i),r(-2i)) for i in -8:8]
            v=PackedBallVector(T,vals); s=sum(v)
            if family===ArbBall
                endpoints=_reduce_bounds.(vals)
                lo,hi=sum(first,endpoints),sum(last,endpoints)
                a,b=_reduce_bounds(s)
                @test a<=lo && hi<=b
            else
                for part in (real,imag)
                    endpoints=[_reduce_bounds(part(x)) for x in vals]
                    lo,hi=sum(first,endpoints),sum(last,endpoints)
                    a,b=_reduce_bounds(part(s))
                    @test a<=lo && hi<=b
                end
            end
        end
    end
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
