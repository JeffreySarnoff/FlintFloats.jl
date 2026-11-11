using FlintFloats, Test
isdefined(@__MODULE__, :_eb_series) || include("elementary_reference.jl")
@testset "selected elementary ball enclosures" begin
    for P in (64,128,256),f in (exp,log,sin,cos,atan)
        R=ArbBall{P};C=AcbBall{P};bang=getfield(FlintFloats,Symbol(nameof(f),:!))
        center=f===log ? 1.25 : 0.25
        x=R(ArbFloat{P}(center),ArbFloat{P}(1/32));a,b=_eb_bounds(x)
        out=@inferred f(x)
        reflo=f===cos ? _eb_mpfr(f,b,P,RoundDown) : _eb_mpfr(f,a,P,RoundDown)
        refhi=f===cos ? _eb_mpfr(f,a,P,RoundUp) : _eb_mpfr(f,b,P,RoundUp)
        lo,hi=_eb_bounds(out)
        @test lo<=reflo && refhi<=hi
        @test precision(midpoint(out))==P
        z=copy(x);@test bang(z,z)===z && isequal(z,out)
        @test bang(R(),x) isa R
        # Complex point series, then all corners of an uncertain input rectangle.
        xr=R(ArbFloat{P}(f===log ? 1.125 : 0.125),ArbFloat{P}(1/128))
        xi=R(ArbFloat{P}(0.0625),ArbFloat{P}(1/256))
        input=C(xr,xi);result=@inferred f(input)
        for re in _eb_bounds(xr),im in _eb_bounds(xi)
            _eb_cover_series(result,complex(re,im),f,P)
        end
        point=C(f===log ? 1.125 : 0.125,0.0625)
        _eb_cover_series(f(point),complex(big(f===log ? 9 : 1)//8,big(1)//16),f,P)
        z=copy(input);@test bang(z,z)===z && isequal(z,result)
        @test precision(midpoint(real(result)))==P && precision(midpoint(imag(result)))==P
        @test isindeterminate(f(R(0)/R(0)))
        @test isindeterminate(f(C(0)/C(0)))
    end
    for P in (64,256)
        R=ArbBall{P};C=AcbBall{P}
        @test iszero(log(R(1))) && iszero(sin(R(0))) && iszero(atan(R(0)))
        @test exp(R(0))==R(1) && cos(R(0))==R(1)
        @test isindeterminate(log(R(-1)))
        @test isindeterminate(log(R(ArbFloat{P}(0),ArbFloat{P}(1))))
        # Principal log at negative reals; a cut-crossing rectangle must cover both +/-pi.
        pi_lo=_eb_mpfr(x->4atan(x),big(1)//1,P,RoundDown)
        pi_hi=_eb_mpfr(x->4atan(x),big(1)//1,P,RoundUp)
        l=log(C(-1,0));a,b=_eb_bounds(imag(l));@test a<=pi_lo && pi_hi<=b
        cut=log(C(R(-1),R(ArbFloat{P}(0),ArbFloat{P}(1/16))))
        a,b=_eb_bounds(imag(cut));@test a<=-pi_hi && pi_hi<=b
        @test isindeterminate(log(C(0)))
        @test !isfinite(atan(C(0,1))) && !isfinite(atan(C(0,-1)))
        @test contains(sin(R(ArbFloat{P}(0),ArbFloat{P}(8))),R(-1))
        @test contains(cos(R(ArbFloat{P}(0),ArbFloat{P}(8))),R(1))
    end
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
