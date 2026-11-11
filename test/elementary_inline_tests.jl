using FlintFloats, Test, Random
# Exact expansion sum. No Float64 collapse in reference inputs or computed outputs.
_ei_value(x::Union{DFloat,DFloatBall})=sum(Rational{BigInt}.(x.d))
_ei_value(x::NFloat{L}) where {L}=Rational{BigInt}(BigFloat(ArbFloat{64L}(x)))
function _ei_reference(f,q,P,mode)
    setprecision(BigFloat,P) do
        setrounding(BigFloat,mode) do;f(BigFloat(q));end
    end
end
function _ei_reader(::Val{L},f) where {L}
    x=NFloat{L}(0.25)
    f,x,f(x)
end
@testset "inline elementary functions" begin
    exp_eps=(0x1.04p-51,0x1.c6p-101,0x1.f6p-152,0x1.48p-202)
    log_eps=(0x1.a4p-50,0x1.9cp-100,0x1.c8p-151,0x1.28p-201)
    trig_eps=(0x1.86p-51,0x1.66p-99,0x1.62p-149,0x1.eep-201)
    atan_eps=(0x1.22p-50,0x1.5p-100,0x1.68p-151,0x1.92p-202)
    if FlintFloats.dfloat_supported()
        for N in 1:4,f in (exp,log,sin,cos,atan)
            T=DFloat{N};B=DFloatBall{N};P=53N+160
            for arg in (0.125,0.5,1.0,2.0,16.0)
                x=T(arg);q=_ei_value(x);got=@inferred f(x)
                a=_ei_reference(f,q,P,RoundDown);b=_ei_reference(f,q,P,RoundUp)
                e=f===exp ? exp_eps[N] : f===log ? log_eps[N] : f===atan ? atan_eps[N] : trig_eps[N]
                scale=f===sin ? abs(q)+min(abs(q),1) : f===cos ? abs(q)+1 : max(abs(a),abs(b))
                tolerance=e*scale
                y=_ei_value(got)
                @test a-tolerance<=y<=b+tolerance
                ball=B(x.d,1/64);out=@inferred f(ball)
                lo=q-1//64;hi=q+1//64
                lower=f===cos && arg<2 ? _ei_reference(f,hi,P,RoundDown) : _ei_reference(f,lo,P,RoundDown)
                upper=f===cos && arg<2 ? _ei_reference(f,lo,P,RoundUp) : _ei_reference(f,hi,P,RoundUp)
                # For nonmonotonic large trig intervals, check endpoint containment separately.
                center=_ei_value(out);rad=Rational{BigInt}(out.rad)
                @test center-rad<=min(lower,upper) && max(lower,upper)<=center+rad
            end
            @test f(T(0.125)) isa T && f(B(0.125)) isa B
        end
        for N in 1:4
            T=DFloat{N};B=DFloatBall{N}
            @test exp(T(0))==T(1) && cos(T(0))==T(1)
            @test iszero(sin(T(0))) && iszero(atan(T(0))) && iszero(log(T(1)))
            @test_throws DomainError log(T(-1))
            @test_throws DomainError log(B(-1))
            @test_throws DomainError log(B(0))
            @test isindeterminate(log(B(ntuple(_->0.0,N),1.0)))
            @test isindeterminate(exp(B(Inf)))
            s=sin(B(Inf));@test _ei_value(s)-s.rad<=-1 && 1<=_ei_value(s)+s.rad
            @test isnan(sin(T(Inf))) && isnan(cos(T(Inf)))
            @test isinf(exp(T(Inf))) && iszero(exp(T(-Inf)))
            @test isinf(log(T(0))) && signbit(log(T(0)))
        end
    end
    for L in (1,2,3,4,16,32,66),f in (exp,log,sin,cos,atan)
        T=NFloat{L};P=64L
        for arg in (0.125,0.5,1.0,2.0,16.0)
            x=T(arg);q=_ei_value(x);got=@inferred f(x);a=_ei_reference(f,q,P+128,RoundDown);b=_ei_reference(f,q,P+128,RoundUp)
            y=_ei_value(got)
            # Empirical accuracy check, not a universal correctly-rounded or 8-ulp guarantee.
            tolerance=8*max(abs(a),abs(b))*BigFloat(2)^(-P+1)
            @test a-tolerance<=y<=b+tolerance
            @test precision(got)==P && isfinite(got)
        end
        f!==log && @test f(T(-0.125)) isa T
    end
    for L in (1,2,3,4,16,32,66)
        T=NFloat{L}
        @test exp(T(0))==T(1) && cos(T(0))==T(1)
        @test iszero(sin(T(0))) && iszero(atan(T(0))) && iszero(log(T(1)))
        @test_throws DomainError log(T(0))
        @test_throws DomainError log(T(-1))
        huge=T(BigFloat(2)^64)
        @test_throws ErrorException exp(huge)
        @test iszero(exp(-huge))
        @test exp(T(1)) isa T # Failure does not poison context/output for subsequent calls.
    end
    jobs=[Threads.@spawn _ei_reader(Val(L),f) for L in (1,2,16,66),f in (exp,log,sin,cos,atan)]
    for task in jobs
        f,x,y=fetch(task);@test isequal(y,f(x))
    end
    @test isempty(detect_ambiguities(FlintFloats;recursive=true))
end
