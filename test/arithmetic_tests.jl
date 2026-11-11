using FlintFloats, Test
using Random

const MODES = (RoundNearest, RoundToZero, RoundFromZero, RoundDown, RoundUp)

@testset "arithmetic" begin
    @testset "dfloat" begin
        for N in 1:4
            x, y = DFloat{N}(1.5), DFloat{N}(2.25)
            @test Float64(x + y) == 3.75 && Float64(y - x) == 0.75
            @test Float64(x * y) == 3.375 && Float64(y / x) == 1.5
        end
        # a two-double expansion carries more than 53 bits: (1 + 2^-60) - 1 is exact
        e = DFloat{2}((1.0, 2.0^-60)) - DFloat{2}(1.0)
        @test Float64(e) == 2.0^-60
        @test Float64(DFloat{2}(1.0) / DFloat{2}(0.0)) == Inf
        @test isnan(Float64(DFloat{2}(0.0) / DFloat{2}(0.0)))
    end

    @testset "dfloat ball" begin
        a, b = DFloatBall{2}(1.0), DFloatBall{2}(3.0)
        @test Float64(a + b) == 4.0 && (a + b).rad == 0.0           # exact stays exact
        q = a / b
        @test q.rad > 0 && q.rad < 1e-30                            # inexact gains a radius
        @test !isindeterminate(q)
        # status mapping: divisor exactly zero is a domain error
        @test_throws DomainError a / DFloatBall{2}(0.0)
        # divisor containing zero: FLINT leaves the output unspecified; wrapper writes the whole line
        straddle = DFloatBall{2}((0.0, 0.0), 1.0)
        w = a / straddle
        @test isindeterminate(w) && w.d == (0.0, 0.0)
        # enclosure property on random exact inputs
        rng = MersenneTwister(1)
        for _ in 1:200
            u, v = randn(rng), randn(rng) + 3
            r = DFloatBall{2}(u) / DFloatBall{2}(v)
            exact = big(u) / big(v)
            @test abs(sum(big, r.d) - exact) <= big(r.rad)   # full expansion, not just the head
        end
    end

    @testset "nfloat" begin
        for L in (1, 2, 4, 16, 66)
            x, y = NFloat{L}(1.5), NFloat{L}(2.25)
            @test Float64(x + y) == 3.75 && Float64(y - x) == 0.75
            @test Float64(x * y) == 3.375 && Float64(y / x) == 1.5
        end
        z = NFloat{2}(0.0)
        @test Float64(z * z) == 0.0 && Float64(z / NFloat{2}(1.0)) == 0.0
        @test_throws DivideError NFloat{2}(1.0) / z
        @test_throws DivideError z / z
        # nfloat division is truncated (error < 1 ulp), not correctly rounded; at 128 bits the
        # quotient still rounds to the nearest double
        @test Float64(NFloat{2}(1.0) / NFloat{2}(3.0)) == 1 / 3
    end

    @testset "arf: exact cases and flag" begin
        x, y = ArbFloat{64}(1.5), ArbFloat{64}(2.25)
        @test Float64(x + y) == 3.75 && Float64(y - x) == 0.75
        @test Float64(x * y) == 3.375 && Float64(y / x) == 1.5
        z, inexact = FlintFloats.add_inexact!(ArbFloat{64}(0.0), x, y)
        @test !inexact && Float64(z) == 3.75
        _, inexact = FlintFloats.div_inexact!(ArbFloat{10}(0.0), ArbFloat{10}(1), ArbFloat{10}(3))
        @test inexact
        @test isnan(Float64(ArbFloat{64}(1.0) / ArbFloat{64}(0.0)))   # FLINT: x/0 is NaN
        @test_throws ArgumentError FlintFloats.add!(ArbFloat{64}(0.0), x, y, RoundNearestTiesAway)
    end

    @testset "arf: bit-for-bit with MPFR, every mode" begin
        rng = MersenneTwister(42)
        checked = bad = 0
        for P in (5, 24, 53), mode in MODES
            for _ in 1:300
                u, v = rand(rng) * 2.0^rand(rng, -8:8) * rand(rng, (-1, 1)), rand(rng) * 2.0^rand(rng, -8:8) * rand(rng, (-1, 1))
                v == 0 && continue
                a, b = ArbFloat{P}(u), ArbFloat{P}(v)
                ma = BigFloat(Float64(a); precision = P); mb = BigFloat(Float64(b); precision = P)
                for (name, op) in ((:add!, +), (:sub!, -), (:mul!, *), (:div!, /))
                    got = Float64(getfield(FlintFloats, name)(ArbFloat{P}(0.0), a, b, mode))
                    want = setprecision(BigFloat, P) do
                        setrounding(BigFloat, mode) do
                            Float64(op(ma, mb))
                        end
                    end
                    checked += 1
                    got == want || (bad += 1)
                end
            end
        end
        @test checked > 10_000
        @test bad == 0
    end

    @testset "acf" begin
        a, b = AcbFloat{64}(1.0, 2.0), AcbFloat{64}(3.0, -1.0)
        c = a * b
        @test (Float64(real(c)), Float64(imag(c))) == (5.0, 5.0)
        s = a + b
        @test (Float64(real(s)), Float64(imag(s))) == (4.0, 1.0)
        d = a - b
        @test (Float64(real(d)), Float64(imag(d))) == (-2.0, 3.0)
        q = c / b
        @test (Float64(real(q)), Float64(imag(q))) == (1.0, 2.0)
    end

    @testset "acf: each part correctly rounded (differential, every mode)" begin
        # exact complex results at 4000 bits, then one rounding to P bits in the mode under test
        rng = MersenneTwister(7)
        rnd(P, x, mode) = Float64(BigFloat(x, mode; precision = P))
        randf() = rand(rng) * 2.0^rand(rng, -6:6) * rand(rng, (-1, 1))
        checked = 0; failures = Tuple[]
        for P in (5, 24, 53), mode in MODES
            for _ in 1:150
                ar, ai, br, bi = randf(), randf(), randf(), randf()
                a, b = AcbFloat{P}(ar, ai), AcbFloat{P}(br, bi)
                # inputs are rounded to P bits first; use the stored values as the exact operands
                xr, xi, yr, yi = (big(Float64(real(a))), big(Float64(imag(a))), big(Float64(real(b))), big(Float64(imag(b))))
                setprecision(BigFloat, 4000) do
                    exact = Dict(
                        :add! => (xr + yr, xi + yi),
                        :sub! => (xr - yr, xi - yi),
                        :mul! => (xr * yr - xi * yi, xr * yi + xi * yr),
                        :div! => ((xr * yr + xi * yi) / (yr^2 + yi^2), (xi * yr - xr * yi) / (yr^2 + yi^2)))
                    for name in (:add!, :sub!, :mul!, :div!)
                        z = getfield(FlintFloats, name)(AcbFloat{P}(0.0, 0.0), a, b, mode)
                        want = (rnd(P, exact[name][1], mode), rnd(P, exact[name][2], mode))
                        got = (Float64(real(z)), Float64(imag(z)))
                        checked += 1
                        got == want || push!(failures, (name, P, mode, got, want))
                    end
                end
            end
        end
        @test checked == 9000
        @test isempty(failures) || (println(first(failures, 3)); false)
    end

    @testset "arb ball" begin
        a, b = ArbBall{64}(1), ArbBall{64}(3)
        @test Float64(midpoint(a + b)) == 4.0 && Float64(radius(a + b)) == 0.0
        q = a / b
        @test Float64(radius(q)) > 0
        @test contains(q * b, a)                                    # enclosure of the exact 1
        @test !contains(q, ArbBall{64}(0.5))
        @test overlaps(q, q) && !overlaps(q, a)
        # rounded input gains a radius that covers the loss
        r = ArbBall{10}(Float64(pi))
        @test Float64(radius(r)) >= abs(Float64(midpoint(r)) - Float64(pi)) > 0
        # zero-crossing divisor yields a non-finite enclosure, not an error
        w = ArbBall{64}(1) / ArbBall{64}(0)
        @test !isfinite(Float64(radius(w))) || isnan(Float64(midpoint(w)))
    end

    @testset "acb ball" begin
        a, b = AcbBall{64}(1.0, 2.0), AcbBall{64}(3.0, -1.0)
        c = a * b
        @test (Float64(real(c)), Float64(imag(c))) == (5.0, 5.0)
        @test Float64(real(a + b)) == 4.0 && Float64(imag(a - b)) == 3.0
        q = c / b
        @test contains(real(q), ArbBall{64}(1.0)) && contains(imag(q), ArbBall{64}(2.0))
    end
end
