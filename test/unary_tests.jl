using FlintFloats, Test, Random

const FF = FlintFloats
const MODES = (RoundNearest, RoundToZero, RoundFromZero, RoundDown, RoundUp)

@testset "classification and unary operations" begin
    @testset "typegrid" begin
        @test pointtype(DFloatBall{3}) == DFloat{3} && balltype(DFloat{3}) == DFloatBall{3}
        @test pointtype(NFloat{2}) == NFloat{2}
        @test pointtype(ArbBall{70}) == ArbFloat{70} && balltype(ArbFloat{70}) == ArbBall{70}
        @test pointtype(AcbBall{70}) == AcbFloat{70} && balltype(AcbFloat{70}) == AcbBall{70}
        @test realtype(AcbFloat{9}) == ArbFloat{9} && realtype(AcbBall{9}) == ArbBall{9}
        @test realtype(DFloat{2}) == DFloat{2} && realtype(NFloat{2}) == NFloat{2}
        @test complextype(ArbFloat{9}) == AcbFloat{9} && complextype(ArbBall{9}) == AcbBall{9}
        @test complextype(AcbBall{9}) == AcbBall{9}
        @test pointtype(ArbBall{70}(1)) == ArbFloat{70}                      # value forms
        @test_throws MethodError balltype(NFloat{2})                          # missing cells
        @test_throws MethodError complextype(DFloat{2})
        @test_throws MethodError complextype(NFloat{2})
        @test_throws MethodError realtype(Int)
        @test FF.guarantee(DFloat{2}) isa FF.Point && FF.guarantee(ArbBall{64}) isa FF.Enclosure
        @test FF.guarantee(AcbFloat{64}) isa FF.Point && FF.guarantee(DFloatBall{1}) isa FF.Enclosure
        @test FF.storage(NFloat{2}) isa FF.Inline && FF.storage(DFloatBall{2}) isa FF.Inline
        @test all(T -> FF.storage(T) isa FF.Owned, (ArbFloat{64}, AcbFloat{64}, ArbBall{64}, AcbBall{64}))
        for T in (DFloat{2}, DFloatBall{2}, NFloat{2}, ArbFloat{64}, ArbBall{64}, AcbFloat{64}, AcbBall{64})
            @test T <: FlintNumber
            @test pointtype(pointtype(T)) == pointtype(T)                     # idempotent
        end
    end

    @testset "zero, one" begin
        for T in (DFloat{2}, DFloatBall{2}, NFloat{2}, ArbFloat{64}, ArbBall{64}, AcbFloat{64}, AcbBall{64})
            @test iszero(zero(T)) && !iszero(one(T)) && zero(one(T)) isa T && one(zero(T)) isa T
            @test zero(T) + one(T) isa T
        end
        @test zero(ArbBall) isa ArbBall{FlintFloats.DEFAULT_PRECISION}
        @test one(AcbFloat) isa AcbFloat{FlintFloats.DEFAULT_PRECISION}
        @test Float64(real(one(AcbBall{64}))) == 1 && Float64(imag(one(AcbBall{64}))) == 0
    end

    @testset "predicates" begin
        nan, inf = ArbFloat{64}(NaN), ArbFloat{64}(BigFloat(Inf))
        @test isnan(nan) && !isfinite(nan) && !isinf(nan)
        @test isinf(inf) && !isfinite(inf) && !isnan(inf) && !signbit(inf) && signbit(-inf)
        @test iszero(ArbFloat{64}(0)) && !signbit(ArbFloat{64}(0)) && !signbit(-ArbFloat{64}(0))   # no negative zero
        @test isinteger(ArbFloat{64}(3)) && !isinteger(ArbFloat{64}(0.5))
        @test sign(ArbFloat{64}(-3)) == ArbFloat{64}(-1) || Float64(sign(ArbFloat{64}(-3))) == -1
        @test isnan(sign(nan))
        # DFloat behaves like Float64 here
        @test isnan(DFloat{2}(NaN)) && isinf(DFloat{2}(Inf)) && !isfinite(DFloat{2}(Inf)) && signbit(DFloat{2}(-1.0))
        @test isfinite(NFloat{2}(1)) && !isnan(NFloat{2}(1)) && !isinf(NFloat{2}(1))
        @test signbit(NFloat{2}(-1)) && !signbit(NFloat{2}(1)) && !signbit(NFloat{2}(0))
        w = FF._indeterminate(DFloatBall{2})
        @test isindeterminate(w) && !isfinite(w) && !isnan(w) && !isexact(w) && containszero(w)
        @test isexact(DFloatBall{2}(1)) && !containszero(DFloatBall{2}(1)) && iszero(DFloatBall{2}(0))
        q = ArbBall{64}(1) / ArbBall{64}(3)
        @test isfinite(q) && !isexact(q) && !isnan(q) && !isindeterminate(q)
        bad = ArbBall{64}(1) / ArbBall{64}(0)
        @test !isfinite(bad) && isnan(bad) && isindeterminate(bad)
        @test isexact(ArbBall{64}(2)) && isinteger(ArbBall{64}(2)) && iszero(ArbBall{64}(0))
        z = AcbBall{64}(1, 0)
        @test isfinite(z) && isexact(z) && !iszero(z) && iszero(AcbBall{64}(0, 0)) && !isinf(z)
        @test isnan(AcbBall{64}(ArbBall{64}(NaN), ArbBall{64}(1)))
        c = AcbFloat{64}(nan, ArbFloat{64}(1))
        @test isnan(c) && !isfinite(c) && !iszero(c) && iszero(AcbFloat{64}(0, 0))
        @test isinf(AcbFloat{64}(inf, ArbFloat{64}(1))) && isfinite(AcbFloat{64}(1, 2))
    end

    @testset "neg and abs" begin
        for (T, mk) in ((DFloat{2}, x -> DFloat{2}(x)), (DFloatBall{2}, x -> DFloatBall{2}(x)),
                        (NFloat{2}, x -> NFloat{2}(x)), (ArbFloat{64}, x -> ArbFloat{64}(x)),
                        (ArbBall{64}, x -> ArbBall{64}(x)))
            @test Float64(-mk(2.5)) == -2.5 && Float64(abs(mk(-2.5))) == 2.5 && Float64(abs(mk(2.5))) == 2.5
            @test (-mk(1.0)) isa T && abs(mk(-1.0)) isa T
            @test iszero(-mk(0.0))
        end
        z = AcbFloat{64}(1.5, -2.5)
        @test (Float64(real(-z)), Float64(imag(-z))) == (-1.5, 2.5)
        @test (Float64(real(conj(z))), Float64(imag(conj(z)))) == (1.5, 2.5)
        @test Float64(abs2(AcbFloat{64}(3, 4))) == 25
        w = AcbBall{64}(3, 4)
        @test contains(abs(w), ArbBall{64}(5)) && abs(w) isa ArbBall{64}
        @test contains(abs2(w), ArbBall{64}(25)) && abs2(w) isa ArbBall{64}
        @test (Float64(real(conj(w))), Float64(imag(conj(w)))) == (3, -4)
        @test (Float64(real(-w)), Float64(imag(-w))) == (-3, -4)
    end

    @testset "sqrt" begin
        @test Float64(sqrt(DFloat{2}(2.25))) == 1.5 && Float64(sqrt(NFloat{2}(2.25))) == 1.5
        @test Float64(sqrt(ArbFloat{64}(2.25))) == 1.5 && Float64(sqrt(DFloatBall{2}(2.25))) == 1.5
        @test sqrt(DFloat{2}(0.0)) == DFloat{2}(0.0) && iszero(sqrt(NFloat{2}(0))) && iszero(sqrt(ArbFloat{64}(0)))
        @test_throws DomainError sqrt(DFloat{2}(-1.0))
        @test_throws DomainError sqrt(NFloat{2}(-1))
        @test_throws DomainError sqrt(ArbFloat{64}(-1))
        @test_throws DomainError sqrt(DFloatBall{2}(-1.0))
        @test isindeterminate(sqrt(DFloatBall{2}((0.0, 0.0), 1.0)))              # straddles zero: GR_UNABLE
        @test isnan(sqrt(ArbFloat{64}(NaN)))
        # ball sqrt of a negative enclosure is FLINT's indeterminate result, not an error
        @test !isfinite(sqrt(ArbBall{64}(-1))) || isnan(sqrt(ArbBall{64}(-1)))
        r = sqrt(ArbBall{64}(2))
        @test contains(r * r, ArbBall{64}(2)) && sqrt(ArbBall{64}(2)) isa ArbBall{64}
        s = sqrt(AcbBall{64}(-4, 0))
        @test contains(real(s), ArbBall{64}(0)) && contains(imag(s), ArbBall{64}(2))
    end

    @testset "arf sqrt: bit-for-bit with MPFR, every mode" begin
        rng = MersenneTwister(11)
        checked = bad = 0
        for P in (5, 24, 53), mode in MODES, _ in 1:200
            x = ArbFloat{P}(rand(rng) * 2.0^rand(rng, -8:8))
            got = Float64(FF.sqrt!(ArbFloat{P}(0.0), x, mode))
            want = setprecision(BigFloat, P) do
                setrounding(BigFloat, mode) do
                    Float64(sqrt(BigFloat(Float64(x); precision = P)))
                end
            end
            checked += 1
            got == want || (bad += 1)
        end
        @test checked == 3000 && bad == 0
        _, inexact = FF.sqrt_inexact!(ArbFloat{64}(0.0), ArbFloat{64}(2), RoundNearest)
        @test inexact
        _, inexact = FF.sqrt_inexact!(ArbFloat{64}(0.0), ArbFloat{64}(4), RoundNearest)
        @test !inexact
    end

    @testset "acf sqrt: each part correctly rounded, every mode" begin
        rng = MersenneTwister(13)
        checked = 0; failures = Tuple[]
        rnd(P, x, mode) = Float64(BigFloat(x, mode; precision = P))
        for P in (5, 24, 53), mode in MODES, _ in 1:150
            a = AcbFloat{P}(rand(rng) * 2.0^rand(rng, -5:5) * rand(rng, (-1, 1)),
                            rand(rng) * 2.0^rand(rng, -5:5) * rand(rng, (-1, 1)))
            x, y = big(Float64(real(a))), big(Float64(imag(a)))
            want = setprecision(BigFloat, 4000) do
                m = sqrt(x^2 + y^2)
                (rnd(P, sqrt((m + x) / 2), mode), rnd(P, copysign(sqrt((m - x) / 2), y), mode))
            end
            z = FF.sqrt!(AcbFloat{P}(0.0, 0.0), a, mode)
            got = (Float64(real(z)), Float64(imag(z)))
            checked += 1
            got == want || push!(failures, (P, mode, got, want))
        end
        @test checked == 2250
        @test isempty(failures) || (println(first(failures, 3)); false)
    end

    @testset "destination forms" begin
        x = ArbFloat{64}(-2.25)
        @test FF.abs!(x, x) === x && Float64(x) == 2.25                        # aliasing allowed
        @test FF.sqrt!(x, x) === x && Float64(x) == 1.5
        @test FF.neg!(x, x) === x && Float64(x) == -1.5
        @test FF.set!(ArbFloat{10}(0), ArbFloat{64}(Float64(pi))) isa ArbFloat{10}
        b = ArbBall{64}(-4)
        @test FF.neg!(b, b) === b && Float64(b) == 4
        @test FF.sqrt!(b, b) === b && Float64(b) == 2
        @test FF.set!(ArbBall{10}(0), ArbBall{64}(Float64(pi))) isa ArbBall{10}
        w = AcbBall{64}(3, 4)
        @test FF.neg!(w, w) === w && Float64(real(w)) == -3
        @test FF.sqrt!(AcbBall{64}(), AcbBall{64}(-4, 0)) isa AcbBall{64}
        c = AcbFloat{64}(3, 4)
        @test FF.neg!(c, c) === c && Float64(imag(c)) == -4
    end

    @testset "with_precision" begin
        third(::Val{P}) where {P} = ArbBall{P}(1) / ArbBall{P}(3)
        for bits in (64, 100, 300)
            r = with_precision(third, bits)
            @test r isa ArbBall{bits} && precision(r) == bits
        end
        # nested barriers are independent
        inner(::Val{Q}) where {Q} = Q
        outerf(::Val{P}) where {P} = (P, with_precision(inner, 2P))
        @test with_precision(outerf, 64) == (64, 128)
        # radius shrinks as precision grows
        r64 = with_precision(third, 64); r256 = with_precision(third, 256)
        @test Float64(radius(r256)) < Float64(radius(r64))
        tasks = [Threads.@spawn(precision(with_precision(third, 64 + 10i))) for i in 1:8]
        @test fetch.(tasks) == [64 + 10i for i in 1:8]
    end

    @testset "dfloat gate" begin
        FF.DFLOAT_SUPPORTED[] = false
        try
            @test_throws ErrorException DFloat{2}(1.0)
            @test_throws ErrorException DFloatBall{2}(1.0)
            @test_throws ErrorException DFloat{2}((1.0, 0.0))
            @test_throws ErrorException parse(DFloat{2}, "1")
            @test ArbBall{64}(1) isa ArbBall{64} && NFloat{2}(1) isa NFloat{2}      # other families unaffected
        finally
            FF.DFLOAT_SUPPORTED[] = true
        end
        @test DFloat{2}(1.0) isa DFloat{2}
    end
end

@testset "AcbFloat modulus is correctly rounded" begin
    rnd(P, x, mode) = Float64(BigFloat(x, mode; precision = P))
    @testset "exact cases" begin
        z = AcbFloat{64}(3, 4)
        r, inexact = FlintFloats.abs_inexact!(ArbFloat{64}(), z)
        @test Float64(r) == 5 && !inexact
        r2, inexact2 = FlintFloats.abs2_inexact!(ArbFloat{64}(), z)
        @test Float64(r2) == 25 && !inexact2
        @test Float64(abs(AcbFloat{64}(0, 0))) == 0 && Float64(abs2(AcbFloat{64}(-2, 0))) == 4
        @test Float64(abs(AcbFloat{64}(-3, -4))) == 5
        @test abs(z) isa ArbFloat{64} && abs2(z) isa ArbFloat{64}
        @test FlintFloats.abs!(ArbFloat{64}(), z) isa ArbFloat{64}
    end
    @testset "special values" begin
        nan, inf = ArbFloat{64}(NaN), ArbFloat{64}(BigFloat(Inf))
        one_ = ArbFloat{64}(1)
        @test isinf(abs(AcbFloat{64}(inf, one_))) && isinf(abs(AcbFloat{64}(one_, -inf)))
        @test isinf(abs(AcbFloat{64}(nan, inf)))                      # infinity wins over NaN, as hypot
        @test isnan(abs(AcbFloat{64}(nan, one_))) && isnan(abs2(AcbFloat{64}(one_, nan)))
        @test isinf(abs2(AcbFloat{64}(inf, one_)))
    end
    @testset "rounding boundaries (exact square plus a tiny part)" begin
        # re = 1 is a P-bit boundary of sqrt; a tiny imaginary part makes the sum inexact but only just
        P = 24
        z = AcbFloat{P}(ArbFloat{P}(1), ArbFloat{P}(BigFloat(2)^-300))
        up = Float64(abs(z, RoundUp)); dn = Float64(abs(z, RoundDown)); ne = Float64(abs(z))
        @test dn == 1.0 && ne == 1.0 && up == nextfloat(1.0f0) |> Float64
        # same with a huge exponent gap: cost does not depend on it
        z2 = AcbFloat{P}(ArbFloat{P}(1), ArbFloat{P}(BigFloat(2)^-100000))
        @test Float64(abs(z2, RoundUp)) == up && Float64(abs(z2, RoundDown)) == 1.0
        # re = 1 + 2^-23 (24 bits): its square is NOT a boundary; check sign of the effect in both modes
        zb = AcbFloat{P}(ArbFloat{P}(1 + 2.0^-23), ArbFloat{P}(BigFloat(2)^-300))
        @test Float64(abs(zb, RoundDown)) == 1 + 2.0^-23
        @test Float64(abs(zb, RoundUp)) == 1 + 2.0^-22
        # nearest-mode tie boundary b = 1 + 2^-24 (25 bits): sqrt(s) just above or below it
        P = 24
        b2 = BigFloat(1 + 2.0^-24)^2                         # exact square of a 25-bit number
        # re = 1, im = sqrt(b2 - 1) rounded to 24 bits: the sum lands near the tie; compare with the exact value
        x = ArbFloat{P}(1)
        y = ArbFloat{P}(BigFloat(sqrt(b2 - 1); precision = P))
        w = AcbFloat{P}(x, y)
        ref = setprecision(BigFloat, 4000) do
            s = BigFloat(1)^2 + BigFloat(y)^2
            (rnd(P, sqrt(s), RoundNearest), rnd(P, sqrt(s), RoundDown), rnd(P, sqrt(s), RoundUp))
        end
        @test (Float64(abs(w)), Float64(abs(w, RoundDown)), Float64(abs(w, RoundUp))) == ref
    end
    @testset "differential against exact references, every mode" begin
        rng = MersenneTwister(21)
        MODES = (RoundNearest, RoundToZero, RoundFromZero, RoundDown, RoundUp)
        checked = 0; fails = Tuple[]
        for P in (5, 11, 24, 53), mode in MODES, _ in 1:200
            gap = rand(rng, (0, 0, 0, 5, 40, 200))                  # include wildly different magnitudes
            a = AcbFloat{P}(rand(rng) * 2.0^rand(rng, -4:4) * rand(rng, (-1, 1)),
                            rand(rng) * 2.0^(rand(rng, -4:4) - gap) * rand(rng, (-1, 1)))
            x, y = big(Float64(real(a))), big(Float64(imag(a)))
            want = setprecision(BigFloat, 6000) do
                s = x^2 + y^2
                (rnd(P, s, mode), rnd(P, sqrt(s), mode))
            end
            got = (Float64(abs2(a, mode)), Float64(abs(a, mode)))
            checked += 1
            got == want || push!(fails, (P, mode, gap, got, want))
        end
        @test checked == 4000
        @test isempty(fails) || (println(first(fails, 3)); false)
    end
end
