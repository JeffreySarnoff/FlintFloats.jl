using FlintFloats, Test, Random

# Exact dyadic endpoints, independent of FLINT arithmetic and radius rounding.
_dyadic(x::Float64) = Rational{BigInt}(x)
_ball_endpoints(x::DFloatBall) = (sum(_dyadic, x.d) - _dyadic(x.rad),
                                sum(_dyadic, x.d) + _dyadic(x.rad))

@testset "M4a inline vector arithmetic" begin
    rng = MersenneTwister(304)
    for N in 1:4, family in (DFloat, DFloatBall)
        T = family{N}
        @test isbitstype(T)
        for len in (0, 1, 3, 4, 5, 7, 8, 17, 129)
            x = T.(randn(rng, len))
            y = T.(randn(rng, len))
            before_x, before_y = copy(x), copy(y)
            z = Vector{T}(undef, len)
            if len > 0
                GC.@preserve x begin
                    @test UInt(pointer(x)) % 8 == 0
                    len > 1 && @test UInt(pointer(x, 2)) - UInt(pointer(x)) == sizeof(T)
                end
            end
            for (f!, op) in ((FF.add!, +), (FF.mul!, *))
                reference = op.(x, y)
                @test @inferred(f!(z, x, y)) === z
                @test isequal(z, reference)
                @test isequal(x, before_x) && isequal(y, before_y)
                a = copy(x)
                @test f!(a, a, y) === a
                @test isequal(a, reference)
                b = copy(y)
                f!(b, x, b)
                @test isequal(b, reference)
                a = copy(x)
                f!(a, a, a)
                @test isequal(a, op.(x, x))
            end
        end
        for step in (1, 2, -1)
            parent_x = T.(1:24)
            parent_y = T.(25:48)
            parent_z = fill(T(-1), 24)
            inds = step == -1 ? (20:-1:5) : (3:step:20)
            x, y, z = view(parent_x, inds), view(parent_y, inds), view(parent_z, inds)
            for (f!, op) in ((FF.add!, +), (FF.mul!, *))
                f!(z, x, y)
                @test isequal(z, op.(x, y))
                @test parent_z[1] == T(-1) && parent_z[end] == T(-1)
                a = copy(parent_x)
                av = view(a, inds)
                f!(av, av, y)
                @test isequal(av, op.(x, y))
            end
        end
        # Reject both directions of partial overlap before mutation.
        for (f!, _) in ((FF.add!, +), (FF.mul!, *))
            a = T.(1:12)
            before = copy(a)
            for (iz, ix) in ((2:9, 1:8), (1:8, 2:9))
                @test_throws ArgumentError f!(view(a, iz), view(a, ix), fill(T(1), 8))
                @test isequal(a, before)
            end
            z = fill(T(-1), 5)
            @test_throws DimensionMismatch f!(z, fill(T(1), 4), fill(T(2), 5))
            @test all(isequal(T(-1)), z)
            a = T.(1:8)
            before = copy(a)
            @test_throws ArgumentError f!(view(a, [1, 1, 2]), fill(T(1), 3), fill(T(2), 3))
            @test isequal(a, before)
            other = family{N == 4 ? 3 : N + 1}
            @test_throws ArgumentError f!(z, fill(other(1), 5), fill(T(2), 5))
            @test all(isequal(T(-1)), z)
            @test_throws ArgumentError f!(T[], other[], T[])
        end
    end

    @testset "certified ball sums and products" begin
        for N in 1:4
            T = DFloatBall{N}
            # Includes SIMD tails, wide radii, cancellation, subnormal values, and overflow.
            x = [T(ntuple(j -> j == 1 ? ldexp(randn(rng), rand(rng, -900:900)) : 0.0, N),
                   ldexp(rand(rng), rand(rng, -1000:900))) for _ in 1:65]
            y = [T(ntuple(j -> j == 1 ? -x[i].d[1] : 0.0, N),
                   ldexp(rand(rng), rand(rng, -1000:900))) for i in eachindex(x)]
            push!(x, T(ntuple(j -> ldexp(1.0, -60*(j-1)), N), 2.0^-200))
            push!(y, T(ntuple(j -> -ldexp(1.0, -60*(j-1)), N), 2.0^-180))
            append!(x, T.([0.0, nextfloat(0.0), floatmax(Float64), Inf]))
            append!(y, T.([0.0, nextfloat(0.0), floatmax(Float64), 1.0]))
            for (f!, op) in ((FF.add!, +), (FF.mul!, *))
                z = similar(x)
                f!(z, x, y)
                @test isequal(z, op.(x, y))
                for i in eachindex(x)
                    if isindeterminate(x[i]) || isindeterminate(y[i])
                        @test isindeterminate(z[i])
                        continue
                    end
                    a, b = _ball_endpoints(x[i])
                    c, d = _ball_endpoints(y[i])
                    lo, hi = op === (+) ? (a + c, b + d) : extrema((a*c, a*d, b*c, b*d))
                    if !isindeterminate(z[i])
                        zl, zh = _ball_endpoints(z[i])
                        @test zl <= lo && hi <= zh
                    else
                        @test z[i].rad == Inf
                    end
                end
                # Repeated native calls with GC and exact aliases, including exceptional SIMD lanes.
                for _ in 1:3
                    a = copy(x)
                    GC.gc()
                    f!(a, a, y)
                    @test isequal(a, z)
                end
            end
        end
    end

    @testset "runtime dfloat gate" begin
        T = DFloatBall{2}
        x, z = fill(T(1), 8), fill(T(-1), 8)
        before = copy(z)
        saved = FF.DFLOAT_SUPPORTED[]
        try
            FF.DFLOAT_SUPPORTED[] = false
            @test_throws ErrorException FF.add!(z, x, x)
            @test_throws ErrorException FF.mul!(z, x, x)
            @test isequal(reinterpret(Float64, z), reinterpret(Float64, before))
        finally
            FF.DFLOAT_SUPPORTED[] = saved
        end
    end
end
