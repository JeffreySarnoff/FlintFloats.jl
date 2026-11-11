using FlintFloats
using Test

@testset "FlintFloats.jl" begin
    include("abi_tests.jl")
    include("construction_tests.jl")
    include("conversion_tests.jl")
    include("unary_tests.jl")
    include("nfloat_sqrt_tests.jl")
    include("elementary_ball_tests.jl")
    include("elementary_point_tests.jl")
    include("elementary_inline_tests.jl")
    include("compare_tests.jl")
    include("promotion_tests.jl")
    include("basefloat_tests.jl")
    include("arithmetic_tests.jl")
    include("ownership_tests.jl")
    include("storage_copy_tests.jl")
    include("array_tests.jl")
    include("nfloat_array_tests.jl")
    include("reusable_tests.jl")
    include("packed_tests.jl")
    include("packed_iteration_tests.jl")
    include("packed_broadcast_tests.jl")
    include("packed_nested_broadcast_tests.jl")
    include("packed_reduce_tests.jl")
    include("packed_dot_tests.jl")
    include("packed_mapped_reduce_tests.jl")
end
