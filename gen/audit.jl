# Symbol audit: every "export" row in inventory.toml must resolve in libflint.
# Run: julia --project=. gen/audit.jl      (exit status 1 on any missing symbol)
using Libdl, FLINT_jll
include(joinpath(@__DIR__, "inventory.jl"))

inv, _ = load_inventory()
handle = Libdl.dlopen(FLINT_jll.libflint_path)
missing_syms = String[]
nexp = 0
for op in inv["op"]
    for (s, _) in expand(op)
        global nexp += 1
        Libdl.dlsym_e(handle, s) == C_NULL && push!(missing_syms, s)
    end
end
println("checked $nexp symbols against ", FLINT_jll.libflint_path)
if isempty(missing_syms)
    println("all present")
else
    println("MISSING: ", join(unique(missing_syms), ", "))
    exit(1)
end
