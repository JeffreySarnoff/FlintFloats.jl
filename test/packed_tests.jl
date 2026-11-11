using FlintFloats, Test, Random

# Exact endpoints for moderate-exponent balls at P >= 64 (radius has 30 mantissa bits).
function _packed_endpoints(x::ArbBall)
    m, r = Rational{BigInt}(BigFloat(midpoint(x))), Rational{BigInt}(BigFloat(radius(x)))
    return m-r, m+r
end
_interval_add(a,b) = (a[1]+b[1], a[2]+b[2])
_interval_sub(a,b) = (a[1]-b[2], a[2]-b[1])
_interval_mul(a,b) = extrema((a[1]*b[1],a[1]*b[2],a[2]*b[1],a[2]*b[2]))
_interval_covers(a,b) = a[1] <= b[1] && b[2] <= a[2]

@testset "M4c packed ball owners and borrowing" begin
    @test_throws ArgumentError PackedBallVector(ArbBall, 2)
    @test_throws ArgumentError PackedBallVector(ArbBall{1}, 2)
    @test_throws ArgumentError PackedBallVector(ArbBall{64}, -1)
    @test_throws ArgumentError PackedBallVector(AcbBall{64}, typemax(Int))
    for family in (ArbBall, AcbBall), P in (64, 256, 2048)
        T = family{P}
        v = @inferred PackedBallVector(T, 5)
        @test eltype(v) === T && size(v) == (5,) && axes(v) == (Base.OneTo(5),)
        @test precision(v) == P && all(iszero, v)
        @test @inferred(v[1]) isa T
        @test_throws BoundsError v[0]
        @test_throws BoundsError v[6]
        @test_throws BoundsError borrow(v, 0)
        @test_throws BoundsError borrow(v, 6)
        @test_throws MethodError resize!(v, 9)
        @test_throws MethodError push!(v, T(1))
        @test size(v) == (5,)
        @test similar(v) isa PackedBallVector{T}
        @test similar(v, Float64, (2,)) isa Vector{Float64}
        @test similar(v, T, (2,3)) isa Matrix{T}
        @test all(iszero, PackedBallVector(T, 0))
        @test collect(PackedBallVector(T, 0)) == T[]

        source = T(1) / T(7)
        v[1] = source
        original = copy(source)
        FF.add!(source, source, source)
        @test isequal(v[1], original)
        readback = v[1]
        FF.add!(readback, readback, readback)
        @test isequal(v[1], original)
        v[2] = 3
        ref = @inferred borrow(v, 2)
        @test precision(ref) == P && ref[] == T(3)
        @test_throws MethodError ref + ref
        @test_throws MethodError BorrowedBall(Ptr{Cvoid}(0), 2)
        ref[] = T(4)
        @test v[2] == T(4)
        @test FF.add!(ref, ref, T(2)) === ref
        @test v[2] == T(6)
        FF.sub!(ref, ref, T(1)); FF.mul!(ref, ref, T(2)); FF.div!(ref, ref, T(5))
        @test v[2] == T(2)
        owned = T()
        @test FF.set!(owned, ref) === owned && owned == T(2)
        @test FF.add!(owned, ref, T(3)) === owned && owned == T(5)
        v[3] = ref
        ref[] = T(9)
        @test v[3] == T(2)
        @test FF.set!(borrow(v,3), ref) == borrow(v,3) # reference identity includes same parent/index
        @test v[3] == T(9)
        fill!(v, ref)
        ref[] = T(11)
        @test v[1] == T(9) && v[2] == T(11) && v[5] == T(9)

        c, d = copy(v), deepcopy(v)
        v[1] = T(99)
        @test c[1] == T(9) && d[1] == T(9)
        cloned = deepcopy((v,v))
        @test cloned[1] === cloned[2] && cloned[1] !== v
        cloned_refs = deepcopy((v,borrow(v,1)))
        @test cloned_refs[2].parent === cloned_refs[1] && cloned_refs[1] !== v
        @test isequal(cloned_refs[2][],v[1])
        long = PackedBallVector(T, 7)
        @test copyto!(long, c) === long
        @test isequal(collect(long)[1:5], collect(c)) && iszero(long[7])
        @test_throws BoundsError copyto!(PackedBallVector(T,1),c)
        v .= T(2)
        @test all(x -> x == T(2), v)
        v .= c .+ c
        @test all(i -> isequal(v[i], c[i]+c[i]), eachindex(v))

        # Precision-changing assignment rounds the midpoint and encloses the represented input.
        high = family{P+128}(1) / family{P+128}(7)
        v[1] = high
        wide = family{P+128}(v[1])
        if family === ArbBall
            @test contains(wide, high)
            @test BigFloat(BigFloat(midpoint(v[1]); precision=2P+128); precision=P) == BigFloat(midpoint(v[1]); precision=2P+128)
        else
            @test contains(real(wide), real(high)) && contains(imag(wide), imag(high))
            @test BigFloat(BigFloat(midpoint(real(v[1])); precision=2P+128); precision=P) == BigFloat(midpoint(real(v[1])); precision=2P+128)
        end
        highvec = PackedBallVector(family{P+128}, [high])
        @test FF.set!(borrow(v,1), borrow(highvec,1)) === borrow(v,1)
        @test family === ArbBall ? contains(family{P+128}(v[1]), high) : contains(real(family{P+128}(v[1])),real(high))

        # Parent stays alive after the caller drops its owning name, including heap mantissas.
        function retained_reference(T)
            owner = PackedBallVector(T, [T(1)/T(7)])
            return borrow(owner,1), WeakRef(owner)
        end
        kept, weak = retained_reference(T)
        GC.gc(true)
        @test weak.value !== nothing
        @test isequal(kept[], T(1)/T(7))
        FF.add!(kept,kept,kept)
        GC.gc(true)
        @test isequal(kept[], (T(1)/T(7))+(T(1)/T(7)))

        # Explicit finalization is idempotent; surviving borrowers detect it rather than using freed data.
        victim = PackedBallVector(T, [T(1)/T(7)])
        dangling = borrow(victim,1)
        finalize(victim); finalize(victim)
        @test victim._closed && victim._data == C_NULL
        @test_throws ArgumentError dangling[]
        @test_throws ArgumentError victim[1]
        @test_throws ArgumentError FF.set!(dangling,T(2))
        empty = PackedBallVector(T,0)
        finalize(empty); finalize(empty)
        @test_throws ArgumentError FF.add!(empty,empty,empty)
        # Failed population clears the already initialized allocation; stress native heap-backed values.
        for _ in 1:4
            @test_throws MethodError PackedBallVector(T, Any[T(1)/T(7), :invalid])
        end
        GC.gc(true)
    end

    @testset "vector arithmetic and views" begin
        for family in (ArbBall, AcbBall), P in (64,256), n in (0,1,4,17)
            T = family{P}
            x, y = PackedBallVector(T, T.(1:n)), PackedBallVector(T, fill(T(2),n))
            z = PackedBallVector(T,n)
            for (f!, op) in ((FF.add!, +),(FF.mul!, *))
                @test @inferred(f!(z,x,y)) === z
                @test isequal(collect(z), op.(collect(x),collect(y)))
                a,b = copy(x),copy(y)
                f!(a,a,y); f!(b,x,b)
                @test isequal(collect(a),collect(z)) && isequal(collect(b),collect(z))
                a = copy(x); f!(a,a,a)
                @test isequal(collect(a), op.(collect(x),collect(x)))
                f!(z,collect(x),collect(y))
                @test isequal(collect(z),op.(collect(x),collect(y)))
            end
        end
        for family in (ArbBall, AcbBall)
            T=family{128}
            x,y,z = PackedBallVector(T,T.(1:24)),PackedBallVector(T,fill(T(2),24)),PackedBallVector(T,24)
            for inds in (2:17, 2:2:24, 24:-2:2)
                xv,yv,zv = view(x,inds),view(y,inds),view(z,inds)
                @test borrow(xv,1)[] == x[first(inds)]
                for (f!,op) in ((FF.add!,+),(FF.mul!,*))
                    f!(zv,xv,yv)
                    @test isequal(collect(zv),op.(collect(xv),collect(yv)))
                    a=copy(x); av=view(a,inds); f!(av,av,yv)
                    @test isequal(collect(av),collect(zv))
                end
            end
            for (f!,_) in ((FF.add!,+),(FF.mul!,*))
                before=collect(x)
                @test_throws ArgumentError f!(view(x,2:9),view(x,1:8),view(y,1:8))
                @test_throws ArgumentError f!(view(x,1:8),view(x,2:9),view(y,1:8))
                @test_throws ArgumentError f!(view(x,[1,1,2]),T.(1:3),T.(1:3))
                @test isequal(collect(x),before)
                @test_throws DimensionMismatch f!(z,view(x,1:2),y)
                @test_throws ArgumentError f!(z,fill(family{64}(1),24),y)
            end
            # Exceptional results retain FLINT's indeterminate enclosure semantics.
            bad = T(0)/T(0)
            x[4]=bad
            FF.add!(z,x,y); @test isindeterminate(z[4])
            FF.mul!(z,x,y); @test isindeterminate(z[4])
        end
    end

    @testset "independent rational enclosure oracle" begin
        rng=MersenneTwister(409)
        for P in (64,256), family in (ArbBall,AcbBall)
            T=family{P}
            make_real() = ArbBall{P}(ArbFloat{P}(rand(rng,-32:32)),ArbFloat{P}(rand(rng,0:8)/8))
            make_value() = family===ArbBall ? make_real() : T(make_real(),make_real())
            x,y = PackedBallVector(T,[make_value() for _ in 1:33]),PackedBallVector(T,[make_value() for _ in 1:33])
            z=PackedBallVector(T,33)
            for (f!,op) in ((FF.add!,+),(FF.mul!,*))
                f!(z,x,y)
                for i in eachindex(z)
                    if family===ArbBall
                        a,b=_packed_endpoints(x[i]),_packed_endpoints(y[i])
                        exact=op === (+) ? _interval_add(a,b) : _interval_mul(a,b)
                        @test _interval_covers(_packed_endpoints(z[i]),exact)
                    else
                        a,b=_packed_endpoints(real(x[i])),_packed_endpoints(imag(x[i]))
                        c,d=_packed_endpoints(real(y[i])),_packed_endpoints(imag(y[i]))
                        er=op === (+) ? _interval_add(a,c) : _interval_sub(_interval_mul(a,c),_interval_mul(b,d))
                        ei=op === (+) ? _interval_add(b,d) : _interval_add(_interval_mul(a,d),_interval_mul(b,c))
                        @test _interval_covers(_packed_endpoints(real(z[i])),er)
                        @test _interval_covers(_packed_endpoints(imag(z[i])),ei)
                    end
                end
            end
        end
    end

    @testset "independent concurrent owners" begin
        tasks=[Threads.@spawn begin
            T=ArbBall{256}; x=PackedBallVector(T,fill(T(2),33)); y=copy(x); z=similar(x)
            GC.gc(); FF.add!(z,x,y); FF.mul!(z,z,y)
            all(a -> a == T(8),z)
        end for _ in 1:8]
        @test all(fetch,tasks)
        T=AcbBall{256}
        x,y,z=PackedBallVector(T,fill(T(2),8*33)),PackedBallVector(T,fill(T(3),8*33)),PackedBallVector(T,8*33)
        tasks=[Threads.@spawn begin
            inds=(k-1)*33+1:k*33
            FF.mul!(view(z,inds),view(x,inds),view(y,inds))
        end for k in 1:8]
        fetch.(tasks)
        @test all(a -> a == T(6),z)
    end
end
