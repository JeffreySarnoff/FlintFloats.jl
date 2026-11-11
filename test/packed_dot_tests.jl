using FlintFloats, Test, LinearAlgebra, Random
_base_packed_dot(x,y)=invoke(dot,Tuple{AbstractArray,AbstractArray},x,y)
function _dot_bounds(x::ArbBall)
    m=Rational{BigInt}(BigFloat(midpoint(x))); r=Rational{BigInt}(BigFloat(radius(x)))
    (m-r,m+r)
end
_dot_add(a,b)=(a[1]+b[1],a[2]+b[2])
_dot_sub(a,b)=(a[1]-b[2],a[2]-b[1])
_dot_mul(a,b)=extrema((a[1]*b[1],a[1]*b[2],a[2]*b[1],a[2]*b[2]))
_dot_covers(a,b)=a[1]<=b[1] && b[2]<=a[2]

@testset "packed conjugating dot" begin
    for family in (ArbBall,AcbBall),P in (64,256,2048)
        T=family{P}
        for n in (0,1,4,17)
            a=family===ArbBall ? T(2) : T(1.0,2.0)
            b=family===ArbBall ? T(3) : T(3.0,4.0)
            x,y=PackedBallVector(T,fill(a,n)),PackedBallVector(T,fill(b,n))
            beforex,beforey=collect(x),collect(y)
            z=@inferred dot(x,y)
            expected=family===ArbBall ? T(6n) : T(Float64(11n),Float64(-2n))
            @test z isa T && z==expected
            @test isequal(collect(x),beforex) && isequal(collect(y),beforey)
            @test dot(x,y)==_base_packed_dot(x,y)
            @test dot(x,x)==(family===ArbBall ? T(4n) : T(5n))
            # Both gather and signed-stride paths have the same conjugation and independent output.
            for inds in (n:-1:1,collect(n:-1:1),1:2:n)
                xv,yv=view(x,inds),view(y,inds)
                m=length(inds)
                @test dot(xv,yv)==(family===ArbBall ? T(6m) : T(Float64(11m),Float64(-2m)))
            end
            FlintFloats.add!(z,z,T(1))
            @test n==0 || x[1]==a
        end
        x,y=PackedBallVector(T,3),PackedBallVector(T,4)
        @test_throws DimensionMismatch dot(x,y)
        empty=PackedBallVector(T,0)
        @test dot(empty,empty)!==dot(empty,empty)
        finalize(empty)
        @test_throws ArgumentError dot(empty,empty)
        x=PackedBallVector(T,[T(1)/T(7)])
        z=dot(x,x); old=copy(z); finalize(x)
        @test isequal(z,old)
        # Huge range steps at singleton length must not overflow part-stride conversion.
        x=PackedBallVector(T,[T(2)]); y=copy(x)
        @test dot(view(x,1:typemax(Int):1),y)==T(4)
        # Nonfinite complex components use the compound borrowed reference path.
        x,y=PackedBallVector(T,fill(T(1),4)),PackedBallVector(T,fill(T(2),4))
        x[2]=T(0)/T(0)
        @test isindeterminate(dot(x,y))
        if family===ArbBall
            x[2]=T(Inf)
            @test isequal(dot(x,y),_base_packed_dot(x,y))
        end
    end

    @testset "independent rational product-sum bounds and native candidates" begin
        rng=MersenneTwister(944)
        for P in (64,256),family in (ArbBall,AcbBall),n in (1,4,17)
            T=family{P}; R=ArbBall{P}
            r()=R(ArbFloat{P}(rand(rng,-16:16)/8),ArbFloat{P}(rand(rng,0:4)/16))
            value()=family===ArbBall ? r() : T(r(),r())
            x,y=PackedBallVector(T,[value() for _ in 1:n]),PackedBallVector(T,[value() for _ in 1:n])
            if family===ArbBall
                expected=foldl(_dot_add,[_dot_mul(_dot_bounds(x[i]),_dot_bounds(y[i])) for i in 1:n];init=(big(0)//1,big(0)//1))
                @test _dot_covers(_dot_bounds(dot(x,y)),expected)
            else
                er,ei=(big(0)//1,big(0)//1),(big(0)//1,big(0)//1)
                for i in 1:n
                    a,b=_dot_bounds(real(x[i])),_dot_bounds(imag(x[i]))
                    c,d=_dot_bounds(real(y[i])),_dot_bounds(imag(y[i]))
                    er=_dot_add(er,_dot_add(_dot_mul(a,c),_dot_mul(b,d)))
                    ei=_dot_add(ei,_dot_sub(_dot_mul(a,d),_dot_mul(b,c)))
                end
                sx,sy=FlintFloats._packed_dot_span(x),FlintFloats._packed_dot_span(y)
                candidates=(dot(x,y),FlintFloats._packed_dot_borrowed(x,y,T),
                            FlintFloats._packed_dot_parts(x,y,T,sx,sy),
                            FlintFloats._packed_dot_conjugated_copy(x,y,T,sy))
                for z in candidates
                    @test _dot_covers(_dot_bounds(real(z)),er)
                    @test _dot_covers(_dot_bounds(imag(z)),ei)
                    for part in (real,imag)
                        m=midpoint(part(z)); full=BigFloat(m;precision=2P+64)
                        @test BigFloat(full;precision=P)==full
                    end
                end
            end
        end
    end
    @testset "cross-component cancellation" begin
        for P in (64,256)
            T=AcbBall{P}; R=ArbBall{P}; m=R((big(1)<<P)-1)
            x=PackedBallVector(T,[T(m,m),T(m,-m),T(1),T(0)])
            y=PackedBallVector(T,[T(m,-m),T(m,m),T(1),T(0)])
            sx,sy=FlintFloats._packed_dot_span(x),FlintFloats._packed_dot_span(y)
            for z in (dot(x,y),FlintFloats._packed_dot_borrowed(x,y,T),
                      FlintFloats._packed_dot_conjugated_copy(x,y,T,sy))
                @test contains(real(z),R(1)) && contains(imag(z),R(0))
            end
        end
    end
    @testset "native result lifetime and concurrent readers" begin
        for family in (ArbBall,AcbBall)
            T=family{2048}; R=ArbBall{2048}
            a=family===ArbBall ? T(1)/T(7) : T(R(1)/R(7),R(2)/R(9))
            x,y=PackedBallVector(T,fill(a,17)),PackedBallVector(T,fill(a,17))
            r=dot(x,y); keep=copy(r)
            finalize(x); finalize(y); GC.gc(true)
            @test isequal(r,keep)
        end
        T=AcbBall{512}
        x,y=PackedBallVector(T,fill(T(2.0,3.0),17)),PackedBallVector(T,fill(T(4.0,-5.0),17))
        function threaded_check(x,y)
            result=dot(view(x,17:-1:1),y)
            GC.gc()
            result==T(-119.0,-374.0)
        end
        tasks=[Threads.@spawn threaded_check(x,y) for _ in 1:8]
        @test all(fetch,tasks)
    end
    # Mixed precisions preserve the generic promotion/result interface.
    x=PackedBallVector(ArbBall{64},[1,2]); y=PackedBallVector(ArbBall{128},[3,4])
    @test dot(x,y)==ArbBall{128}(11)
    @test typeof(dot(x,y))===typeof(_base_packed_dot(x,y))
    @test dot(x,collect(y))==_base_packed_dot(x,collect(y))
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
