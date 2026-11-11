using FlintFloats, Test, Random

# Independent decoding of the pinned little-endian mantissa layout into an exact dyadic rational.
function _nfloat_dyadic(x::NFloat{L}) where {L}
    iszero(x) && return big(0)//big(1)
    m = sum(BigInt(x.d[j]) << (64*(j-1)) for j in 1:L)
    signbit(x) && (m = -m)
    e = x.exp - 64L
    return e >= 0 ? (m << e)//big(1) : m//(big(1) << -e)
end
_pow2q(e) = e >= 0 ? (big(1) << e)//big(1) : big(1)//(big(1) << -e)

@testset "M4b nfloat vectors" begin
    rng = MersenneTwister(405)
    for L in (1, 2, 3, 4, 5, 16, 66)
        T = NFloat{L}
        # Full mantissas exercise high-product paths as well as cancellation and exponent alignment.
        makevalue() = T(rand(rng, -200:200), UInt(rand(rng, Bool)),
                        ntuple(j -> rand(rng, UInt) | (j == L ? UInt(1)<<63 : UInt(0)), L))
        for len in (0, 1, 3, 4, 17, 65)
            x, y = [makevalue() for _ in 1:len], [makevalue() for _ in 1:len]
            len > 0 && (x[1] = zero(T))
            len > 1 && (y[2] = -x[2])
            xbefore, ybefore = copy(x), copy(y)
            for (f!, op) in ((FF.add!, +), (FF.mul!, *))
                z = similar(x)
                @test @inferred(f!(z, x, y)) === z
                # Scalar equivalence is regression evidence; independent error checks follow.
                @test isequal(z, op.(x, y))
                @test isequal(x, xbefore) && isequal(y, ybefore)
                a, b = copy(x), copy(y)
                f!(a, a, y)
                @test isequal(a, z)
                f!(b, x, b)
                @test isequal(b, z)
                a = copy(x)
                f!(a, a, a)
                # Squaring and multiplication may use different approximate high products.
                for (u, v, w) in zip(x, y, z)
                    exact = op(_nfloat_dyadic(u), _nfloat_dyadic(v))
                    if iszero(exact)
                        @test iszero(w)
                    else
                        e = ndigits(abs(numerator(exact)); base=2) - ndigits(denominator(exact); base=2) + 1
                        @test abs(_nfloat_dyadic(w) - exact) < 2 * _pow2q(e - 64L)
                    end
                end
                for (u, w) in zip(x, a)
                    exact = op(_nfloat_dyadic(u), _nfloat_dyadic(u))
                    if iszero(exact)
                        @test iszero(w)
                    else
                        e = ndigits(abs(numerator(exact)); base=2) - ndigits(denominator(exact); base=2) + 1
                        @test abs(_nfloat_dyadic(w) - exact) < 2 * _pow2q(e - 64L)
                    end
                end
            end
        end
        for step in (1, 2, -1)
            ix = step == -1 ? (20:-1:4) : (3:step:20)
            x, y, z = T.(1:24), T.(25:48), fill(T(-1), 24)
            for (f!, op) in ((FF.add!, +), (FF.mul!, *))
                xv, yv, zv = view(x, ix), view(y, ix), view(z, ix)
                f!(zv, xv, yv)
                @test isequal(zv, op.(xv, yv))
                @test z[1] == T(-1) && z[end] == T(-1)
                a = copy(x)
                av = view(a, ix)
                f!(av, av, yv)
                @test isequal(av, op.(xv, yv))
            end
        end
        # Gathered inputs use scalar calls with one context acquisition, but gathered outputs are rejected.
        x = T.(1:12)
        for (f!, op) in ((FF.add!, +), (FF.mul!, *))
            z = fill(T(-1), 4)
            f!(z, view(x, [2, 2, 4, 1]), fill(T(2), 4))
            @test isequal(z, op.(T.([2, 2, 4, 1]), T(2)))
            @test_throws DimensionMismatch f!(z, x, x)
            @test_throws ArgumentError f!(z, NFloat{L == 1 ? 2 : 1}.(1:4), z)
            @test_throws ArgumentError f!(view(x, [1, 1, 2, 3]), z, z)
            before = copy(x)
            @test_throws ArgumentError f!(view(x, 2:9), view(x, 1:8), fill(T(1), 8))
            @test isequal(x, before)
        end

        # Boundary exponents come from the matching-header C probe, not guessed machine limits.
        limits = read_layout()
        emin, emax = parse(Int, limits["NFLOAT_MIN_EXP"]), parse(Int, limits["NFLOAT_MAX_EXP"])
        mantissa = ntuple(j -> j == L ? UInt(1)<<63 : UInt(0), L)
        tiny, huge = T(emin, UInt(0), mantissa), T(emax, UInt(0), mantissa)
        z = fill(T(-7), 3)
        FF.mul!(z, [tiny, one(T), zero(T)], fill(T(0.25), 3))
        @test iszero(z[1]) && z[2] == T(0.25) && iszero(z[3])
        for (f!, bad) in ((FF.add!, T(emax, UInt(0), ntuple(_ -> typemax(UInt), L))),
                         (FF.mul!, huge))
            x = [one(T), bad, one(T)]
            y = f! === FF.add! ? copy(x) : fill(T(4), 3)
            for dest in (fill(T(-7), 3), x, y)
                before = copy(dest)
                @test_throws ErrorException f!(dest, x, y)
                @test isequal(dest, before)
            end
            # The strided fallback must have the same failure guarantee.
            xp, yp = repeat(x; inner=2), repeat(y; inner=2)
            dest = fill(T(-7), 3)
            @test_throws ErrorException f!(dest, view(xp, 1:2:6), view(yp, 1:2:6))
            @test all(isequal(T(-7)), dest)
            xv, yv = view(xp, 1:2:6), view(yp, 1:2:6)
            before = copy(xp)
            @test_throws ErrorException f!(xv, xv, yv)
            @test isequal(xp, before)
        end
        @test_throws DomainError T(Inf)
        @test_throws DomainError T(NaN)
    end
    @test_throws ArgumentError FF.add!(NFloat{0}[], NFloat{0}[], NFloat{0}[])
    @test_throws ArgumentError FF.mul!(NFloat{67}[], NFloat{67}[], NFloat{67}[])

    @testset "context reuse and dfloat independence" begin
        before = copy(FF._NFLOAT_CTX)
        saved = FF.DFLOAT_SUPPORTED[]
        try
            FF.DFLOAT_SUPPORTED[] = false
            tasks = [Threads.@spawn begin
                T = NFloat{L}
                x, y = fill(T(1.5), 65), fill(T(2), 65)
                z = similar(x)
                GC.gc()
                FF.add!(z, x, y)
                ok = all(isequal(T(3.5)), z)
                FF.mul!(x, x, y)
                ok && all(isequal(T(3)), x)
            end for L in (1, 2, 3, 4, 5, 16, 66, 2)]
            @test all(fetch, tasks)
            @test FF._NFLOAT_CTX == before
        finally
            FF.DFLOAT_SUPPORTED[] = saved
        end
    end
end
