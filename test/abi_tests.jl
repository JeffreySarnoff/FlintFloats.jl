# Julia layouts and constants versus the recorded C probe (test/abi/layout.txt).
using FlintFloats, Test

const FF = FlintFloats

function read_layout()
    d = Dict{String,String}()
    for line in eachline(joinpath(@__DIR__, "abi", "layout.txt"))
        k, v = split(line, ' '; limit = 2)
        d[k] = v
    end
    return d
end

@testset "ABI layout" begin
    L = read_layout()
    num(k) = parse(Int, L[k])
    @test L["flint_version"] == "3.7.0-dev"
    @test num("flint_bits") == 64 && num("sizeof.slong") == sizeof(Int)

    @testset "fixed formats" begin
        for N in 1:4
            @test sizeof(DFloat{N}) == num("sizeof.d$N")
            @test sizeof(DFloatBall{N}) == num("sizeof.d$(N)b")
            @test fieldoffset(DFloatBall{N}, 2) == 8N          # rad follows the N midpoint doubles
        end
        @test fieldoffset(DFloatBall{2}, 2) == num("offsetof.d2b.rad")
        @test fieldoffset(DFloatBall{4}, 2) == num("offsetof.d4b.rad")
        for l in (1, 2, 3, 66)
            @test sizeof(NFloat{l}) == 8 * (num("NFLOAT_HEADER_LIMBS") + l)
            @test fieldoffset(NFloat{l}, 1) == 0 && fieldoffset(NFloat{l}, 2) == 8
            @test fieldoffset(NFloat{l}, 3) == 8 * num("NFLOAT_HEADER_LIMBS")
        end
        @test FF.NFLOAT_MAX_LIMBS == num("NFLOAT_MAX_LIMBS")
        @test FF.NFLOAT_FLAGS == num("NFLOAT_ALLOW_UNDERFLOW")      # no ALLOW_INF / ALLOW_NAN
        @test FF.NFLOAT_EXP_ZERO == parse(Int, L["NFLOAT_EXP_ZERO"])
        @test sizeof(eltype(FF._NFLOAT_CTX)) == num("sizeof.gr_ctx")
    end

    @testset "owners" begin
        for (T, key) in ((ArbFloat, "arf"), (AcbFloat, "acf"), (ArbBall, "arb"), (AcbBall, "acb"))
            @test sizeof(fieldtype(T{64}, :w)) == num("sizeof.$key")
        end
        # midpoint and radius of arb, and the parts of acb/acf, rely on these offsets
        @test num("offsetof.arb.mid") == 0 && num("offsetof.arb.rad") == 32
        @test num("offsetof.acb.real") == 0 && num("offsetof.acb.imag") == 48
        @test num("offsetof.acf.real") == 0 && num("offsetof.acf.imag") == 32
    end

    @testset "constants" begin
        @test FF.GR_SUCCESS == num("GR_SUCCESS") && FF.GR_DOMAIN == num("GR_DOMAIN") && FF.GR_UNABLE == num("GR_UNABLE")
        @test FF.ARF_RND_DOWN == num("ARF_RND_DOWN") && FF.ARF_RND_UP == num("ARF_RND_UP")
        @test FF.ARF_RND_FLOOR == num("ARF_RND_FLOOR") && FF.ARF_RND_CEIL == num("ARF_RND_CEIL")
        @test FF.ARF_RND_NEAR == num("ARF_RND_NEAR")
    end
end
