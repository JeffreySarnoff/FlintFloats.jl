"""
    FlintFloats

Julia interface to FLINT's floating-point types: `DFloat`, `DFloatBall`, `NFloat`, `ArbFloat`,
`ArbBall`, `AcbFloat`, `AcbBall`. Precision is a type parameter on every type. See `docs/`.
"""
module FlintFloats

include("libflint/LibFlint.jl")
using .LibFlint

include("types.jl")
include("precision.jl")
include("dfloat.jl")
include("dfloatball.jl")
include("arf.jl")
include("nfloat.jl")        # after arf.jl: Float64(::NFloat) uses ArbFloat
include("acf.jl")
include("arb.jl")
include("acb.jl")
include("storage.jl")

export FlintReal, DFloat, DFloatBall, NFloat, NFloatType,
       ArbFloat, ArbBall, AcbFloat, AcbBall,
       midpoint, radius, isindeterminate, overlaps

const DFLOAT_SUPPORTED = Ref(false)

"`true` when the loaded FLINT supports dfloat arithmetic on this machine (see `dfloat_is_supported`)."
dfloat_supported() = DFLOAT_SUPPORTED[]

function __init__()
    DFLOAT_SUPPORTED[] = LibFlint.dfloat_is_supported() != 0
    _init_nfloat_contexts!()
    return nothing
end

end # module
