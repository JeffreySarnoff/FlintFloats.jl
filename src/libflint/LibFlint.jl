# Private adapter: one ccall method per bound FLINT symbol, generated from gen/inventory.toml.
# Pointer arguments are Ptr{Cvoid}; callers pass Refs or owner objects (see storage.jl).
# Nothing here interprets status codes or manages ownership.
module LibFlint

using FLINT_jll: libflint

include("generated/shared.jl")
include("generated/dfloat.jl")
include("generated/dfloatball.jl")
include("generated/nfloat.jl")
include("generated/arbfloat.jl")
include("generated/acbfloat.jl")
include("generated/arbball.jl")
include("generated/acbball.jl")

end # module
