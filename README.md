# FlintFloats.jl

[![CI](https://github.com/JeffreySarnoff/FlintFloats.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JeffreySarnoff/FlintFloats.jl/actions/workflows/CI.yml)

Julia 1.13+ interfaces to FLINT's seven floating-point formats: `DFloat`, `DFloatBall`, `NFloat`,
`ArbFloat`, `AcbFloat`, `ArbBall`, and `AcbBall`. Precision is part of each concrete type.
Scalar arithmetic and five selected elementary functions (`exp`, `log`, `sin`, `cos`, `atan`),
checked vector arithmetic, reusable nfloat scratch, and explicitly borrowed packed ball storage are
implemented. The [capability table](docs/capability_table.md) specifies guarantees by family;
point approximations, correctly rounded point operations, and rigorous balls have different contracts.

## Development installation

The repository pins a local FLINT 3.7.0-dev wrapper, version 301.690.0+0, ABI 25. Its bundled binary
is tuned for x86_64 Linux, i9-14900K, glibc 2.43 or later. A portable release is still being prepared.
Run the host check before loading that artifact. See the [wrapper guide](FlintFloat.jl/FLINT_jll/README.md)
for source/binary provenance and rebuilding on another target.

From a checkout on the verified development host:

```sh
julia --startup-file=no scripts/check_host.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(;allow_autoprecomp=false); Pkg.build("FLINT_jll"); Pkg.precompile()'
```

The installer verifies and unpacks the bundled binary; ordinary loading does not compile FLINT.
Project source paths resolve the nested wrapper. It is not the currently published ABI-24 wrapper
and must not be substituted into another package without checking its binary contract.

```julia
using FlintFloats, LinearAlgebra

x = ArbBall{128}(1)
y = exp(x)                               # rigorous enclosure
v = PackedBallVector(ArbBall{128}, [1, 2, 3])
snapshot = v[1]                           # independent owned copy
sum(abs2, v)                              # real ball enclosing 14
dot(v, v)                                # fresh owned result
r = borrow(v, 1)                          # explicit parent-retaining reference
FlintFloats.add!(r, r, ArbBall{128}(1))     # updates v[1], not snapshot
```

## Documentation and verification

- [Development guide](docs/enact_interfacing.md) and [current checkpoint](docs/checkpoint.md)
- [Numerical interface](docs/float_interfacing.md), [elementary contracts](docs/elementary.md), and [capabilities](docs/capability_table.md)
- [CI/release gates](docs/ci_release.md) and [installation/build evidence](docs/release_evidence.md)
- [Benchmark drivers and recorded results](benchmark/)

Use the focused commands in the checkpoints after changing code. Generator, benchmark, and docs
projects have separate environments. Build docs with `julia --project=docs docs/make.jl` after
instantiating that project; deployment requires explicit opt-in. Hosted CI performs source checks;
native checks require the documented compatible runner. Other platforms remain unclaimed until
portable builds, ABI/numerical checks, and clean installation pass.

Nemo.jl and Arblib.jl inform the interface design; neither is a runtime dependency.
