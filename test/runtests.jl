using FlintFloats
using Test

@testset "FlintFloats.jl" begin
    include("abi_tests.jl")
    include("construction_tests.jl")
    include("arithmetic_tests.jl")
    include("ownership_tests.jl")
end
