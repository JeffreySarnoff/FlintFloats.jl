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
