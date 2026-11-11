```@meta
CurrentModule = FlintFloats
```

# FlintFloats

Documentation for [FlintFloats](https://github.com/JeffreySarnoff/FlintFloats.jl).

## Reuse nfloat vector scratch

Reserve a workspace once and pass it to repeated vector operations. Each successful operation
copies its result into the destination; numerical or input-read failure leaves that destination
unchanged. Capacity grows automatically, or can be reserved with `sizehint!`. Use separate
workspaces for concurrent operations; sharing an active workspace throws an error.

```jldoctest
julia> using FlintFloats

julia> T = NFloat{2}; work = NFloatWorkspace(T, 100);

julia> x = fill(T(1), 100); y = fill(T(2), 100); dest = similar(x);

julia> FlintFloats.add!(dest, x, y, work) === dest
true

julia> all(v -> v == T(3), dest)
true

julia> FlintFloats.mul!(dest, dest, y, work) === dest
true

julia> all(v -> v == T(6), dest)
true
```

```@index
```

```@autodocs
Modules = [FlintFloats]
```
