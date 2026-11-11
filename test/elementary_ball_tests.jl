using FlintFloats, Test
_eb_bounds(x::ArbBall)=let m=Rational{BigInt}(BigFloat(midpoint(x))),r=Rational{BigInt}(BigFloat(radius(x)));(m-r,m+r) end
function _eb_mpfr(f,q,P,rnd)
    setprecision(BigFloat,P+96) do
        setrounding(BigFloat,rnd) do
            f(BigFloat(q))
        end
    end
end
function _eb_series(f,z,P)
    # Independent exact rational power series with a proved l1-norm tail bound, q<=1/2.
    w=f===log ? z-1 : z
    q=abs(real(w))+abs(imag(w));@assert q<=1//2
    N=cld(P,2)+32;s=zero(z)
    if f===exp
        term=one(z);s=term
        for k in 1:N;term=term*z/k;s+=term;end
        tail=2q^(N+1)//factorial(big(N+1))
    elseif f===sin || f===cos
        start=f===sin ? 1 : 0
        for k in 0:N;s+=(-1)^k*z^(2k+start)//factorial(big(2k+start));end
        tail=2q^(2N+start+2)//factorial(big(2N+start+2))
    elseif f===atan
        for k in 0:N;s+=(-1)^k*z^(2k+1)/(2k+1);end
        tail=q^(2N+3)/((2N+3)*(1-q^2))
    else
        for k in 1:N;s+=(-1)^(k+1)*w^k/k;end
        tail=q^(N+1)/((N+1)*(1-q))
    end
    s,tail
end
function _eb_cover_series(out,z,f,P)
    ref,err=_eb_series(f,z,P)
    for (part,value) in ((real,real(ref)),(imag,imag(ref)))
        lo,hi=_eb_bounds(part(out))
        @test lo<=value-err && value+err<=hi
    end
end
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
