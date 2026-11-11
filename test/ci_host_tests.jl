using Test
include("../scripts/check_host.jl")
@testset "portable bundled target gate" begin
    @test check_bundled_host(os=:Linux,arch=:x86_64,cpu="Intel Core i9-14900K",libc="2.43")===nothing
    @test check_bundled_host(os=:Linux,arch=:x86_64,cpu="generic x86-64",libc="2.17")===nothing
    @test_throws ErrorException check_bundled_host(os=:Windows,arch=:x86_64,cpu="generic",libc="2.43")
    @test_throws ErrorException check_bundled_host(os=:Linux,arch=:i686,cpu="generic",libc="2.43")
    @test_throws ErrorException check_bundled_host(os=:Linux,arch=:x86_64,cpu="generic",libc="2.16")
end
