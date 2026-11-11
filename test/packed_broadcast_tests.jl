using FlintFloats, Test, Random

# Independent invocation of Julia's generic destination method for compatibility comparisons.
function _generic_packed_broadcast!(z, f, args...)
    bc = Base.Broadcast.broadcasted(f, args...)
    prepared = Base.Broadcast.instantiate(Base.Broadcast.Broadcasted(bc.style,bc.f,bc.args,axes(z)))
    bare = convert(Base.Broadcast.Broadcasted{Nothing},prepared)
    invoke(Base.copyto!,Tuple{AbstractArray,Base.Broadcast.Broadcasted{Nothing}},z,bare)
end
function _packed_broadcast_allocations(z,x,y)
    z .= x .+ y
    z .= x .+ y
    @allocated z .= x .+ y
end

struct PackedBroadcastCustomVector{T} <: AbstractVector{T}
    values::Vector{T}
end
Base.size(v::PackedBroadcastCustomVector)=size(v.values)
Base.getindex(v::PackedBroadcastCustomVector,i::Int)=v.values[i]
struct PackedBroadcastCustomStyle <: Base.Broadcast.AbstractArrayStyle{1} end
Base.BroadcastStyle(::Type{<:PackedBroadcastCustomVector})=PackedBroadcastCustomStyle()

function _broadcast_endpoints(x::ArbBall)
    m=Rational{BigInt}(BigFloat(midpoint(x)))
    r=Rational{BigInt}(BigFloat(radius(x)))
    (m-r,m+r)
end
_broadcast_add(a,b)=(a[1]+b[1],a[2]+b[2])
_broadcast_sub(a,b)=(a[1]-b[2],a[2]-b[1])
_broadcast_mul(a,b)=extrema((a[1]*b[1],a[1]*b[2],a[2]*b[1],a[2]*b[2]))
_broadcast_contains(a,b)=a[1]<=b[1] && b[2]<=a[2]

@testset "flat packed in-place broadcast" begin
    for family in (ArbBall,AcbBall), P in (64,256), n in (0,1,4,17)
        T=family{P}
        x=PackedBallVector(T,[T(i)/T(7) for i in 1:n])
        y=PackedBallVector(T,[T(-i)/T(9) for i in 1:n])
        z,expected=similar(x),similar(x)
        for f in (identity,+,*)
            operands = f===identity ? ((x,),) : ((x,y),(x,T(2)),(T(2),x),(x,Ref(T(2))),(Ref(T(2)),x))
            for args in operands
                @test broadcast!(f,z,args...) === z
                _generic_packed_broadcast!(expected,f,args...)
                @test isequal(collect(z),collect(expected))
            end
        end
        @test axes(x .+ y)==axes(x)
        @test (x .== x) isa AbstractVector{Bool}
        @test eltype(real.(x)) === ArbBall{P}
        # No per-element copied scalar owners for nonaliasing direct packed arithmetic.
        @test _packed_broadcast_allocations(z,x,y)==0
        if n>0
            a,b=copy(x),copy(x)
            a .= a .+ a
            _generic_packed_broadcast!(b,+,b,b)
            @test isequal(collect(a),collect(b))
            a .= a .* a
            _generic_packed_broadcast!(b,*,b,b)
            @test isequal(collect(a),collect(b))
            # Singleton and scalar expansion with varying identity/add/multiply paths.
            singleton=PackedBallVector(T,[T(2)/T(7)])
            for f in (identity,+,*)
                args=f===identity ? (singleton,) : (singleton,y)
                broadcast!(f,z,args...)
                _generic_packed_broadcast!(expected,f,args...)
                @test isequal(collect(z),collect(expected))
            end
        else
            # Binary empty broadcast must not evaluate an unassigned scalar Ref.
            z .= x .+ Ref{T}()
            @test isempty(z)
        end
    end

    @testset "views and alias snapshots" begin
        for family in (ArbBall,AcbBall)
            T=family{128}
            for inds in (2:9,2:2:16,16:-2:2)
                x,y,z,expected=(PackedBallVector(T,T.(1:18)) for _ in 1:4)
                xv,yv,zv,ev=view(x,inds),view(y,inds),view(z,inds),view(expected,inds)
                for f in (identity,+,*)
                    args=f===identity ? (xv,) : (xv,yv)
                    broadcast!(f,zv,args...)
                    _generic_packed_broadcast!(ev,f,args...)
                    @test isequal(collect(z),collect(expected))
                end
                zv .= zv .+ xv
                _generic_packed_broadcast!(ev,+,ev,xv)
                @test isequal(collect(z),collect(expected))
            end
            # Both overlap directions, reverse inputs, and gathered source indices.
            for (outidx,inidx) in ((2:6,1:5),(1:5,2:6),(2:6,6:-1:2),(1:5,[5,1,5,2,3]))
                for f in (identity,+,*)
                    a,b=PackedBallVector(T,T.(1:7)),PackedBallVector(T,T.(1:7))
                    dest,source=view(a,outidx),view(a,inidx)
                    edest,esource=view(b,outidx),view(b,inidx)
                    if f===identity
                        dest .= source
                        _generic_packed_broadcast!(edest,identity,esource)
                    else
                        broadcast!(f,dest,source,dest)
                        _generic_packed_broadcast!(edest,f,esource,edest)
                    end
                    @test isequal(collect(a),collect(b))
                end
            end
            # Singleton expansion snapshots the original first element before any writes.
            a,b=PackedBallVector(T,T.(1:7)),PackedBallVector(T,T.(1:7))
            a .= view(a,1:1) .+ a
            _generic_packed_broadcast!(b,+,view(b,1:1),b)
            @test isequal(collect(a),collect(b))
            @test all(i -> a[i]==T(i+1),eachindex(a))
            # Two overlapping sources must both be snapshotted before writing.
            a,b=PackedBallVector(T,T.(1:7)),PackedBallVector(T,T.(1:7))
            view(a,2:6) .= view(a,1:5) .* view(a,6:-1:2)
            _generic_packed_broadcast!(view(b,2:6),*,view(b,1:5),view(b,6:-1:2))
            @test isequal(collect(a),collect(b))
            # Repeated destination indices retain the generic Base path and behavior.
            a,b=PackedBallVector(T,T.(1:7)),PackedBallVector(T,T.(1:7))
            view(a,[1,1,3]) .= view(a,[3,2,1]) .+ T(1)
            _generic_packed_broadcast!(view(b,[1,1,3]),+,view(b,[3,2,1]),T(1))
            @test isequal(collect(a),collect(b))
        end
    end

    @testset "generic fallback effects and types" begin
        for family in (ArbBall,AcbBall)
            T=family{128}
            x=PackedBallVector(T,T.(1:5))
            a,b=similar(x),similar(x)
            ca,cb=Ref(0),Ref(0)
            fa=v -> (ca[]+=1; FlintFloats.add!(v,v,T(2)); v)
            fb=v -> (cb[]+=1; FlintFloats.add!(v,v,T(2)); v)
            a .= fa.(x)
            _generic_packed_broadcast!(b,fb,x)
            @test ca[]==cb[]==length(x)
            @test isequal(collect(a),collect(b))
            @test all(i -> x[i]==T(i),eachindex(x))
            # Throw after partial progress: no retry or duplicated callback invocation.
            fill!(a,T(0)); fill!(b,T(0)); ca[]=cb[]=0
            fa=v -> (ca[]+=1; ca[]==3 && error("callback failed"); v)
            fb=v -> (cb[]+=1; cb[]==3 && error("callback failed"); v)
            @test_throws ErrorException a .= fa.(x)
            @test_throws ErrorException _generic_packed_broadcast!(b,fb,x)
            @test ca[]==cb[]==3 && isequal(collect(a),collect(b))
            # Nested expressions stay generic in this first step, including repeated destination leaves.
            a,b=copy(x),copy(x)
            a .= a .* x .+ a
            inner=Base.Broadcast.broadcasted(*,b,x)
            _generic_packed_broadcast!(b,+,inner,b)
            @test isequal(collect(a),collect(b))
            # Ordinary vectors, zero-dimensional scalar fill, and mixed styles remain generic.
            a .= collect(x) .+ x
            _generic_packed_broadcast!(b,+,collect(x),x)
            @test isequal(collect(a),collect(b))
            a .= T(3)
            @test all(v -> v==T(3),a)
            custom=PackedBroadcastCustomVector(T.(2:6))
            a .= x .+ custom
            _generic_packed_broadcast!(b,+,x,custom)
            @test isequal(collect(a),collect(b))
            # Different precision and function result family preserve containing conversion.
            high=PackedBallVector(family{256},[family{256}(1)/family{256}(7) for _ in 1:5])
            a .= high .+ high
            _generic_packed_broadcast!(b,+,high,high)
            @test isequal(collect(a),collect(b))
            realdest=PackedBallVector(ArbBall{128},5)
            realdest .= real.(high)
            @test eltype(realdest)===ArbBall{128}
            @test all(i -> contains(ArbBall{256}(realdest[i]),real(high[i])),eachindex(realdest))
            before=collect(a)
            @test_throws DimensionMismatch a .= PackedBallVector(T,3) .+ T(1)
            @test isequal(collect(a),before)
            bad=PackedBallVector(T,0); finalize(bad)
            @test_throws ArgumentError bad .= bad .+ T(1)
        end
    end

    @testset "independent exact endpoint bounds" begin
        rng=MersenneTwister(942)
        for P in (64,256), family in (ArbBall,AcbBall)
            T=family{P}
            realvalue()=ArbBall{P}(ArbFloat{P}(rand(rng,-16:16)),ArbFloat{P}(rand(rng,0:8)/8))
            value()=family===ArbBall ? realvalue() : T(realvalue(),realvalue())
            x,y=PackedBallVector(T,[value() for _ in 1:17]),PackedBallVector(T,[value() for _ in 1:17])
            z=similar(x)
            for f in (+,*)
                broadcast!(f,z,x,y)
                for i in eachindex(z)
                    if family===ArbBall
                        a,b=_broadcast_endpoints(x[i]),_broadcast_endpoints(y[i])
                        exact=f===(+) ? _broadcast_add(a,b) : _broadcast_mul(a,b)
                        @test _broadcast_contains(_broadcast_endpoints(z[i]),exact)
                    else
                        a,b=_broadcast_endpoints(real(x[i])),_broadcast_endpoints(imag(x[i]))
                        c,d=_broadcast_endpoints(real(y[i])),_broadcast_endpoints(imag(y[i]))
                        er=f===(+) ? _broadcast_add(a,c) : _broadcast_sub(_broadcast_mul(a,c),_broadcast_mul(b,d))
                        ei=f===(+) ? _broadcast_add(b,d) : _broadcast_add(_broadcast_mul(a,d),_broadcast_mul(b,c))
                        @test _broadcast_contains(_broadcast_endpoints(real(z[i])),er)
                        @test _broadcast_contains(_broadcast_endpoints(imag(z[i])),ei)
                    end
                end
            end
            x[3]=T(0)/T(0)
            z .= x .+ y
            @test isindeterminate(z[3])
            z .= x .* y
            @test isindeterminate(z[3])
        end
    end
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
