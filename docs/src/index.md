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

## Packed ball vectors and borrowed slots

Packed vectors own fixed-size initialized FLINT storage. Indexing returns an independent value;
`borrow` explicitly retains and refers to a parent slot. References support qualified scalar
destination arithmetic and never clear elements independently. Vector operations reject other
possible destination/input overlap; concurrent writes require independent slots. Dot products and
matrix kernels remain future work.

```jldoctest
julia> using FlintFloats

julia> T = ArbBall{128}; v = PackedBallVector(T, [1, 2, 3]); r = borrow(v, 2);

julia> snapshot = v[2]; FlintFloats.add!(r, r, T(1));

julia> v[2] == T(3) && snapshot == T(2)
true

julia> w = similar(v); FlintFloats.add!(w, v, v) === w
true

julia> all(i -> w[i] == v[i] + v[i], eachindex(v))
true
```

```@index
```

```@autodocs
Modules = [FlintFloats]
```
