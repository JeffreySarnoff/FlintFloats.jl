using FlintFloats, Test, Random
isdefined(@__MODULE__, :_eb_series) || include("elementary_reference.jl")
# Rational-to-MPFR must preserve the numerator and denominator exactly before division. The
# generic BigFloat(Rational,mode) constructor can round them separately at P and double-round.
function _ep_round(q::Rational,P,mode)
    n,d=numerator(q),denominator(q)
    a=BigFloat(n;precision=max(2,ndigits(abs(n);base=2)))
    b=BigFloat(d;precision=max(2,ndigits(d;base=2)))
    setprecision(BigFloat,P) do
        setrounding(BigFloat,mode) do;a/b;end
    end
end
@testset "strict point elementary rounding" begin
    modes=(RoundNearest,RoundToZero,RoundFromZero,RoundDown,RoundUp)
    rng=MersenneTwister(0xefa5)
    for P in (5,24,53,128,512),f in (exp,log,sin,cos,atan),mode in modes
        T=ArbFloat{P};bang=getfield(FlintFloats,Symbol(nameof(f),:!))
        for input in (0.125,0.75,1.0,2.0,8.0,rand(rng)*16)
            x=T(input)
            expected=setprecision(BigFloat,P) do
                setrounding(BigFloat,mode) do
                    f(BigFloat(x))
                end
            end
            got=@inferred f(x,mode)
            @test isequal(BigFloat(got),expected)
            z=copy(x);@test bang(z,z,mode)===z && isequal(z,got)
        end
        for input in (-0.125,-2.0)
            x=T(input)
            if f===log
                @test_throws DomainError f(x,mode)
                z=T(3);@test_throws DomainError bang(z,x,mode);@test z==T(3)
            else
                expected=setprecision(BigFloat,P) do
                    setrounding(BigFloat,mode) do;f(BigFloat(x));end
                end
                @test isequal(BigFloat(f(x,mode)),expected)
            end
        end
    end
    for P in (5,24,53,128,256),f in (exp,log,sin,cos,atan),mode in modes
        T=AcbFloat{P};R=ArbFloat{P};bang=getfield(FlintFloats,Symbol(nameof(f),:!))
        for (a,b) in ((f===log ? 9//8 : 1//8,1//16), (f===log ? 9//8 : -1//8,-1//32))
            x=T(R(BigFloat(a;precision=P)),R(BigFloat(b;precision=P)))
            reference,error=_eb_series(f,complex(big(a),big(b)),P)
            got=@inferred f(x,mode)
            for part in (real,imag)
                lo=_ep_round(part(reference)-error,P,mode)
                hi=_ep_round(part(reference)+error,P,mode)
                @test lo==hi # Certificate that the entire rigorous interval rounds identically.
                @test BigFloat(part(got))==lo
            end
            z=copy(x);@test bang(z,z,mode)===z && isequal(z,got)
        end
    end
    for T in (ArbFloat{64},AcbFloat{64}),f in (exp,log,sin,cos,atan)
        zeroarg=f===log ? T(1) : T(0)
        out,flag=getfield(FlintFloats,Symbol(nameof(f),:_inexact!))(T(),zeroarg)
        @test !flag && (f===exp || f===cos ? out==T(1) : iszero(out))
        out,flag=getfield(FlintFloats,Symbol(nameof(f),:_inexact!))(T(),T(0.25))
        @test flag
        saved=T(7);@test_throws ArgumentError f(T(1),RoundNearestTiesAway)
        @test_throws ArgumentError getfield(FlintFloats,Symbol(nameof(f),:!))(saved,T(1),RoundNearestTiesAway)
        @test saved==T(7)
    end
    R=ArbFloat{128};C=AcbFloat{128}
    @test isinf(log(R(0))) && signbit(log(R(0)))
    @test iszero(exp(R(-Inf))) && isinf(exp(R(Inf)))
    @test isnan(sin(R(Inf))) && isnan(cos(R(Inf)))
    @test isnan(exp(R(NaN))) && isnan(log(R(NaN)))
    @test iszero(real(log(C(-1,0)))) && imag(log(C(-1,0)))>R(3)
    # Component precision and near-axis relative accuracy (tiny imaginary part survives).
    for f in (exp,log,sin,cos,atan)
        x=C(R(0.25),R(BigFloat(2)^(-200)))
        y=f(x);@test !iszero(imag(y))
        @test precision(real(y))==128 && precision(imag(y))==128
    end
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
