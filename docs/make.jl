using FlintFloats
using Documenter

DocMeta.setdocmeta!(FlintFloats, :DocTestSetup, :(using FlintFloats); recursive=true)

makedocs(;
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

deploydocs(;
    repo="github.com/JeffreySarnoff/FlintFloats.jl",
    devbranch="main",
)
