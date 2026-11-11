using FlintFloats, Test
_mapped_bounds(x)=let m=Rational{BigInt}(BigFloat(midpoint(x))),r=Rational{BigInt}(BigFloat(radius(x))); (m-r,m+r) end
_mapped_square(bounds)=let (lo,hi)=bounds; (lo<=0<=hi ? zero(lo) : min(lo^2,hi^2),max(lo^2,hi^2)) end
_mapped_bytes(v)=(sum(abs2,v);sum(abs2,v);@allocated sum(abs2,v))

@testset "packed squared magnitude sum" begin
    for family in (ArbBall,AcbBall),P in (64,256,2048)
        T=family{P};R=ArbBall{P}
        for n in (0,1,17,512)
            vals=family===ArbBall ? T.(-n:-1) : [T(Float64(i),Float64(2i)) for i in 1:n]
            v=PackedBallVector(T,vals)
            s=@inferred sum(abs2,v)
            expected=n*(n+1)*(2n+1)÷6*(family===ArbBall ? 1 : 5)
            @test s isa R && s==R(expected)
            @test s!==sum(abs2,v)
            @test precision(midpoint(s))==P
            if n>0
                saved=copy(v[1]);FlintFloats.add!(s,s,R(1));@test isequal(v[1],saved)
            end
        end
        v=PackedBallVector(T,T.(1:9))
        for inds in (1:9,9:-1:1,2:2:9,[8,1,8,4],Int[])
            span=view(v,inds)
            @test sum(abs2,span)==R(sum(i->i*i,inds;init=0))
            for kw in ((init=R(3),),(dims=1,))
                actual=sum(abs2,span;kw...)
                reference=invoke(Base.sum,Tuple{Any,AbstractArray},abs2,span;kw...)
                @test isequal(actual isa AbstractArray ? collect(actual) : actual, reference isa AbstractArray ? collect(reference) : reference)
            end
        end
        @test_throws MethodError sum(abs2,v;unknown_keyword=true)
        small=PackedBallVector(T,fill(T(1)/T(7),1));large=PackedBallVector(T,fill(T(1)/T(7),512))
        @test _mapped_bytes(small)==_mapped_bytes(large)
        result=sum(abs2,large);saved=copy(result);finalize(large);GC.gc()
        @test isequal(result,saved)
        @test_throws ArgumentError sum(abs2,large)
        empty=PackedBallVector(T,0);finalize(empty)
        @test_throws ArgumentError sum(abs2,empty)
        v[1]=T(0)/T(0);@test isindeterminate(sum(abs2,v))
        # Arbitrary callbacks retain copied arguments and the generic exception/effect behavior.
        v=PackedBallVector(T,[1,2,3]);calls=Ref(0)
        f=x->(calls[]+=1;FlintFloats.add!(x,x,T(9));abs2(x))
        @test sum(f,v)==R(365) && calls[]==3
        @test all(i->v[i]==T(i),1:3)
        @test_throws ErrorException sum(x->error("callback"),v)
        # Rational endpoint oracle includes zero crossing and asymmetric complex rectangles.
        vals=[R(ArbFloat{P}(i/8),ArbFloat{P}(3/16)) for i in -7:7]
        values=family===ArbBall ? vals : [T(vals[i],vals[end-i+1]+R(1)) for i in eachindex(vals)]
        v=PackedBallVector(T,values)
        for inds in (1:15,15:-2:1,[2,7,2,14],Int[])
            lo=big(0)//1;hi=big(0)//1
            for i in inds, part in (family===ArbBall ? (identity,) : (real,imag))
                a,b=_mapped_square(_mapped_bounds(part(values[i])));lo+=a;hi+=b
            end
            a,b=_mapped_bounds(sum(abs2,view(v,inds)))
            @test a<=lo && hi<=b
        end
    end
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
