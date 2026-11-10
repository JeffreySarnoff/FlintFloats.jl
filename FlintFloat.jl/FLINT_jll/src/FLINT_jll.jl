# Based on JuliaBinaryWrappers/FLINT_jll.jl; see LICENSE.
baremodule FLINT_jll
using Base
using Base: UUID
import JLLWrappers

JLLWrappers.@generate_main_file_header("FLINT")
JLLWrappers.@generate_main_file("FLINT", UUID("e134572f-a0d5-539d-bddf-3cad8db41a82"))
end # baremodule FLINT_jll
