export libflint

using GMP_jll
using MPFR_jll
using OpenBLAS32_jll

JLLWrappers.@generate_wrapper_header("FLINT")
JLLWrappers.@declare_library_product(libflint, "libflint.so.25")

function __init__()
    JLLWrappers.@generate_init_header(GMP_jll, MPFR_jll, OpenBLAS32_jll)
    JLLWrappers.@init_library_product(
        libflint,
        "lib/libflint.so",
        RTLD_LAZY | RTLD_DEEPBIND,
    )
    JLLWrappers.@generate_init_footer()
end
