# Loader for gen/inventory.toml shared by audit.jl and generate.jl.
using TOML

const DFLOAT_FAMILIES = ("dfloat", "dfloatball")

"One concrete binding: C name, Julia argument types, Julia return type."
struct Binding
    name::String
    family::String
    ret::String
    args::Vector{String}
end

const CTYPE = Dict(
    "void" => "Cvoid", "int" => "Cint", "double" => "Cdouble",
    "slong" => "Int", "ulong" => "UInt", "arf_rnd_t" => "Cint",
    "double*" => "Ptr{Cdouble}", "void*" => "Ptr{Cvoid}",
)

function ctype(t::AbstractString)
    t = strip(t)
    t = first(split(t))                       # drop a trailing parameter label, e.g. "slong prec"
    haskey(CTYPE, t) && return CTYPE[t]
    (endswith(t, "_ptr") || endswith(t, "_srcptr")) && return "Ptr{Cvoid}"
    error("unsupported C type: $t")
end

function parse_sig(sig::AbstractString)
    m = match(r"^(.+?)\((.*)\)$", sig)
    m === nothing && error("bad signature: $sig")
    ret = ctype(m[1])
    argstr = strip(m[2])
    args = isempty(argstr) ? String[] : [ctype(a) for a in split(argstr, ",")]
    return ret, args
end

"Concrete symbol list for one inventory row (dfloat templates expand d2 to d1..d4)."
function expand(op)
    names = op["kind"] == "export" ? [op["symbol"]] : get(op, "use", String[])
    out = Tuple{String,String}[]               # (symbol, family)
    for n in names
        if op["family"] in DFLOAT_FAMILIES && occursin(r"^d2", n)
            for N in 1:4
                push!(out, (replace(n, r"^d2" => "d$N"), op["family"]))
            end
        else
            push!(out, (n, op["family"]))
        end
    end
    return out
end

function load_inventory(path = joinpath(@__DIR__, "inventory.toml"))
    inv = TOML.parsefile(path)
    bindings = Binding[]
    for op in inv["op"]
        op["kind"] == "export" || continue     # inline rows are not bound; their `use` rows are listed separately
        ret, args = parse_sig(op["sig"])
        for (sym, fam) in expand(op)
            push!(bindings, Binding(sym, fam, ret, args))
        end
    end
    return inv, bindings
end
