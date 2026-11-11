using FlintFloats
using Documenter

DocMeta.setdocmeta!(FlintFloats, :DocTestSetup, :(using FlintFloats); recursive=true)

makedocs(;
    root=@__DIR__,
    # Source archives have no Git metadata; disable automatic source links in that case.
    remotes=ispath(joinpath(@__DIR__, "..", ".git")) ? Dict() : nothing,
    modules=[FlintFloats],
    authors="Jeffrey Sarnoff <jeffrey.sarnoff@gmail.com> and contributors",
    sitename="FlintFloats.jl",
    format=Documenter.HTML(;
        canonical="https://JeffreySarnoff.github.io/FlintFloats.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

if get(ENV,"FLINTFLOATS_DOCS_DEPLOY","false")=="true"
    deploydocs(;
        repo="github.com/JeffreySarnoff/FlintFloats.jl",
        devbranch="main",
    )
end
