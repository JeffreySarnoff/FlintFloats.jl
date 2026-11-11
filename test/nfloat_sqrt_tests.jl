using FlintFloats, Test, Random

# Exact integer oracle: x=M*2^(e-P), sqrt(x) truncates to Q*2^(ceil(e/2)-P),
# Q=isqrt(M*2^(P-isodd(e))). This does not depend on FLINT or approximate roots.
function _nfloat_root_check(x::NFloat{L}) where {L}
    P=64L
    M=sum(BigInt(x.d[i])<<(64(i-1)) for i in 1:L)
    Q=isqrt(M << (P-Int(isodd(x.exp))))
    y=@inferred sqrt(x)
    got=sum(BigInt(y.d[i])<<(64(i-1)) for i in 1:L)
    @test got==Q
    @test y.exp==cld(x.exp,2)
    @test iszero(y.sign)
    @test precision(y)==P
    # Neighbor criterion is exact even at exponents outside MPFR's range.
    target=M << (P-Int(isodd(x.exp)))
    @test Q^2<=target<(Q+1)^2
    y
end
function _sqrt_reader(::Val{L},seed) where {L}
    rng=MersenneTwister(seed)
    limbs=ntuple(i->i==L ? rand(rng,UInt)|(UInt(1)<<63) : rand(rng,UInt),L)
    x=NFloat{L}(rand(rng,-4096:4096),UInt(0),limbs)
    x,sqrt(x)
end
@testset "nfloat truncated square root" begin
    rng=MersenneTwister(0x51a7)
    emin=typemin(Int)÷4;emax=typemax(Int)÷4
    for L in 1:66
        T=NFloat{L};P=64L
        patterns=(ntuple(i->i==L ? UInt(1)<<63 : UInt(0),L),ntuple(i->typemax(UInt),L))
        for e in (emin,emin+1,-4097,-4096,-3,-2,-1,0,1,2,3,4096,4097,emax-1,emax), d in patterns
            _nfloat_root_check(T(e,UInt(0),d))
        end
        for _ in 1:8
            d=ntuple(i->i==L ? rand(rng,UInt)|(UInt(1)<<63) : rand(rng,UInt),L)
            x=T(rand(rng,-4096:4096),UInt(0),d)
            y=_nfloat_root_check(x)
            reference=setprecision(BigFloat,P) do
                setrounding(BigFloat,RoundToZero) do
                    sqrt(BigFloat(ArbFloat{P}(x)))
                end
            end
            @test BigFloat(ArbFloat{P}(y))==reference
        end
        @test iszero(sqrt(zero(T)))
        @test_throws DomainError sqrt(T(-1))
        @test_throws DomainError sqrt(-T(2))
    end
    # Shared context reads with task-local operands; no global rounding/context mutation.
    jobs=[Threads.@spawn _sqrt_reader(Val(L),1000+L) for L in (1,2,3,4,16,32,65,66)]
    for task in jobs
        x,y=fetch(task)
        @test isequal(y,sqrt(x))
        _nfloat_root_check(x)
    end
end
