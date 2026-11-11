using FlintFloats, Test
# This file follows packed_broadcast_tests.jl, reusing its independent Base destination reference.
_nested_bc(f,args...)=Base.Broadcast.broadcasted(f,args...)
function _apply_nested!(z,bc)
    Base.Broadcast.materialize!(z,bc)
end
function _nested_bytes(z,bc)
    _apply_nested!(z,bc)
    _apply_nested!(z,bc)
    @allocated _apply_nested!(z,bc)
end

@testset "bounded nested packed broadcast" begin
    for family in (ArbBall,AcbBall), P in (64,256)
        T=family{P}
        for n in (0,1,17)
            x=PackedBallVector(T,[T(i)/T(7) for i in 1:n])
            y=PackedBallVector(T,[T(i+1)/T(9) for i in 1:n])
            z,e=similar(x),similar(x)
            trees=(
                _nested_bc(+,_nested_bc(*,x,y),x),
                _nested_bc(-,_nested_bc(/,x,T(3))),
                _nested_bc(-,_nested_bc(*,x,y),_nested_bc(/,y,T(3))),
                _nested_bc(identity,_nested_bc(+,_nested_bc(-,x),y)),
                _nested_bc(/,_nested_bc(+,x,y),_nested_bc(-,x,y)),
            )
            for tree in trees
                @test _apply_nested!(z,tree)===z
                _generic_packed_broadcast!(e,tree.f,tree.args...)
                @test isequal(collect(z),collect(e))
            end
            a,b=copy(x),copy(x)
            a .= a .* y .+ a
            _generic_packed_broadcast!(b,+,_nested_bc(*,b,y),b)
            @test isequal(collect(a),collect(b))
            a,b=copy(x),copy(x)
            a .= (a .+ y) .* (a .- y)
            _generic_packed_broadcast!(b,*,_nested_bc(+,b,y),_nested_bc(-,b,y))
            @test isequal(collect(a),collect(b))
        end
        # Preserve scalar-tree rounding at every node, not a fused multiply-add.
        x=PackedBallVector(T,[T(1)/T(7),T(2)/T(9)])
        y=copy(x); z=similar(x)
        z .= x .* y .+ x
        @test all(i -> isequal(z[i],(x[i]*y[i])+x[i]),eachindex(z))
        # A repeated Broadcasted object still needs separate live scratch per occurrence.
        term=_nested_bc(+,x,y)
        tree=_nested_bc(*,term,_nested_bc(+,term,x))
        _apply_nested!(z,tree)
        @test all(i -> isequal(z[i],(x[i]+y[i])*((x[i]+y[i])+x[i])),eachindex(z))
        # Alias snapshots before tree evaluation, including singleton and shifted/reversed views.
        for (destidx,srcidx) in ((1:5,1:1),(2:6,1:5),(1:5,5:-1:1),(1:5,[5,1,3,2,5]))
            a,b=PackedBallVector(T,T.(1:7)),PackedBallVector(T,T.(1:7))
            d,s=view(a,destidx),view(a,srcidx)
            de,se=view(b,destidx),view(b,srcidx)
            d .= s .* T(2) .+ d
            _generic_packed_broadcast!(de,+,_nested_bc(*,se,T(2)),de)
            @test isequal(collect(a),collect(b))
        end
        # Full/view scratch allocation stays bounded in length (no per-element owners).
        function bytes_at_length(T,n)
            x=PackedBallVector(T,fill(T(1)/T(7),n)); y=copy(x); z=similar(x)
            _nested_bytes(z,_nested_bc(+,_nested_bc(*,x,y),x))
        end
        @test bytes_at_length(T,512)==bytes_at_length(T,1)
        # Eight arithmetic nodes optimize; nine and excessive identity depth retain Base fallback.
        for count in (8,9)
            tree=x
            for _ in 1:count
                tree=_nested_bc(+,tree,T(1))
            end
            @test FlintFloats._packed_tree_cost(T,tree)==count
            _apply_nested!(z,tree)
            e=similar(x); _generic_packed_broadcast!(e,tree.f,tree.args...)
            @test isequal(collect(z),collect(e))
        end
        tree=x
        for _ in 1:17
            tree=_nested_bc(identity,tree)
        end
        @test FlintFloats._packed_tree_cost(T,tree)>8
        _apply_nested!(z,tree)
        @test isequal(collect(z),collect(x))
        # Independent exact interval oracle for a nested polynomial with cancellation.
        a=PackedBallVector(T,[T(i) for i in -8:8]); b=similar(a)
        b .= (a .+ T(1)) .* (a .- T(1)) .- a .* a
        @test all(v -> v==T(-1),b)
        # Indeterminates and precision invariant survive nested operations.
        a[3]=T(0)/T(0)
        b .= -(a .* a) .+ a
        @test isindeterminate(b[3])
        @test all(i -> isequal(b[i],-(a[i]*a[i])+a[i]),eachindex(b))
    end
    @testset "independent uncertain interval bounds" begin
        for P in (64,256), family in (ArbBall,AcbBall)
            R=ArbBall{P}; T=family{P}
            r(m,d)=R(ArbFloat{P}(m),ArbFloat{P}(d))
            xv=family===ArbBall ? r(1.5,0.125) : T(r(1.5,0.125),r(-0.5,0.25))
            yv=family===ArbBall ? r(-1.25,0.0625) : T(r(-1.25,0.0625),r(0.75,0.125))
            x=PackedBallVector(T,[xv,xv]); y=PackedBallVector(T,[yv,yv])
            if family===ArbBall
                a,b=_broadcast_endpoints(xv),_broadcast_endpoints(yv)
                expected=_broadcast_add(_broadcast_mul(a,b),a)
                x .= x .* y .+ x
                @test all(v -> _broadcast_contains(_broadcast_endpoints(v),expected),x)
            else
                a,b=_broadcast_endpoints(real(xv)),_broadcast_endpoints(imag(xv))
                c,d=_broadcast_endpoints(real(yv)),_broadcast_endpoints(imag(yv))
                er=_broadcast_add(_broadcast_sub(_broadcast_mul(a,c),_broadcast_mul(b,d)),a)
                ei=_broadcast_add(_broadcast_add(_broadcast_mul(a,d),_broadcast_mul(b,c)),b)
                x .= x .* y .+ x
                @test all(v -> _broadcast_contains(_broadcast_endpoints(real(v)),er) &&
                               _broadcast_contains(_broadcast_endpoints(imag(v)),ei),x)
            end
        end
    end
    # A nested arbitrary callback executes exactly once per element; never borrowed implicitly.
    T=ArbBall{128}; x=PackedBallVector(T,[1,2,3]); z=similar(x); calls=Ref(0)
    f=v -> (calls[]+=1; FlintFloats.add!(v,v,T(1)); v)
    z .= f.(x) .+ x
    @test calls[]==3 && all(i -> z[i]==T(2i+1),eachindex(z))
    @test all(i -> x[i]==T(i),eachindex(x))
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
