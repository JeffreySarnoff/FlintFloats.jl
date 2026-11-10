using Test
using Libdl
using FLINT_jll

@testset "FLINT 3.7 development artifact" begin
    @test FLINT_jll.is_available()
    @test isfile(FLINT_jll.libflint_path)
    @test FLINT_jll.libflint_handle != C_NULL
    # flint_version is an exported char array, not a char ** or function.
    @test unsafe_string(cglobal((:flint_version, libflint), UInt8)) == "3.7.0-dev"
    for symbol in (:dfloat_is_supported, :d2_add, :nfloat_ctx_init, :nfloat_add,
                   :arb_init, :arb_clear, :arb_add, :acb_init, :acb_clear, :acb_add)
        @test dlsym_e(FLINT_jll.libflint_handle, symbol) != C_NULL
    end
    @test isdir(joinpath(FLINT_jll.artifact_dir, "include", "flint"))
    @test isfile(joinpath(FLINT_jll.artifact_dir, "share", "licenses", "FLINT", "COPYING.LESSER"))
end

@testset "dfloat through the exported library product" begin
    @test ccall((:dfloat_is_supported, libflint), Cint, ()) == 1
    x = Ref((0.0, 0.0))
    y = Ref((0.0, 0.0))
    z = Ref((0.0, 0.0))
    ccall((:d2_set_d, libflint), Cvoid, (Ref{NTuple{2,Cdouble}}, Cdouble), x, 2.0)
    ccall((:d2_set_d, libflint), Cvoid, (Ref{NTuple{2,Cdouble}}, Cdouble), y, 3.0)
    ccall((:d2_add, libflint), Cvoid,
          (Ref{NTuple{2,Cdouble}}, Ref{NTuple{2,Cdouble}}, Ref{NTuple{2,Cdouble}}), z, x, y)
    @test sum(z[]) == 5.0
end

@testset "arb and acb ownership and arithmetic" begin
    # Let FLINT allocate correctly aligned elements; no guessed struct layout.
    x = ccall((:_arb_vec_init, libflint), Ptr{Cvoid}, (Int,), 1)
    y = ccall((:_arb_vec_init, libflint), Ptr{Cvoid}, (Int,), 1)
    z = ccall((:_arb_vec_init, libflint), Ptr{Cvoid}, (Int,), 1)
    try
        ccall((:arb_set_si, libflint), Cvoid, (Ptr{Cvoid}, Int), x, 2)
        ccall((:arb_set_si, libflint), Cvoid, (Ptr{Cvoid}, Int), y, 3)
        ccall((:arb_add, libflint), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Int), z, x, y, 128)
        @test ccall((:arb_contains_si, libflint), Cint, (Ptr{Cvoid}, Int), z, 5) == 1
        @test ccall((:arb_contains_si, libflint), Cint, (Ptr{Cvoid}, Int), z, 6) == 0
    finally
        for pointer in (x, y, z)
            ccall((:_arb_vec_clear, libflint), Cvoid, (Ptr{Cvoid}, Int), pointer, 1)
        end
    end

    a = ccall((:_acb_vec_init, libflint), Ptr{Cvoid}, (Int,), 1)
    b = ccall((:_acb_vec_init, libflint), Ptr{Cvoid}, (Int,), 1)
    try
        ccall((:acb_one, libflint), Cvoid, (Ptr{Cvoid},), a)
        ccall((:acb_add, libflint), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Int), b, a, a, 128)
        ccall((:acb_sub, libflint), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Int), b, b, a, 128)
        @test ccall((:acb_is_one, libflint), Cint, (Ptr{Cvoid},), b) == 1
    finally
        for pointer in (a, b)
            ccall((:_acb_vec_clear, libflint), Cvoid, (Ptr{Cvoid}, Int), pointer, 1)
        end
    end
end
