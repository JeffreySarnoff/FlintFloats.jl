using FlintFloats
using Test

@testset "FlintFloats.jl" begin
    include("abi_tests.jl")
    include("construction_tests.jl")
    include("conversion_tests.jl")
    include("unary_tests.jl")
    include("compare_tests.jl")
    include("promotion_tests.jl")
    include("basefloat_tests.jl")
    include("arithmetic_tests.jl")
    include("ownership_tests.jl")
    include("array_tests.jl")
end
