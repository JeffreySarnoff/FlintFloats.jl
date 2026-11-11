# Selected elementary functions

`exp`, `log`, `sin`, `cos`, and `atan` are implemented for `ArbBall{P}` and `AcbBall{P}`.
Each returns a fresh owned enclosure at working precision `P`. Qualified destination operations
(`FlintFloats.exp!`, `log!`, `sin!`, `cos!`, `atan!`) reuse matching-format initialized storage,
including exact output/input aliasing. No process-wide precision or rounding setting is changed.

Real balls enclose the range on the input interval. A real logarithm reaching nonpositive values
returns FLINT's indeterminate result; select complex balls explicitly for complex values. Huge or
wide arguments can yield crude but rigorous enclosures. These are enclosures, not correctly rounded
point functions; their midpoint rounding error is included in the radius.

Complex logarithms use the principal branch with the negative real axis as cut; a rectangle crossing
it can enclose both sides. Complex arctangent has cuts along the imaginary rays starting at `±im`.
Singularities and undefined inputs retain FLINT's nonfinite/indeterminate behavior. No midpoint-only
approximation or silent real-to-complex promotion is used.

## Pinned source audit

Authority: FLINT `3.7.0-dev`, revision `82c40b299084b92299c2d8dac464e39d6743fce4`, ABI 25.
The matching `src/arb.h` and `src/acb.h` declare each operation as
`void(prefix_ptr output, prefix_srcptr input, slong precision)`. These are exported symbols with
no status return. `gen/inventory.toml` records all ten declarations; generated bindings are audited.

The pinned `doc/src/arb/elementary.md` gives the range-enclosure, precision, domain, and huge-argument
contracts. `doc/src/acb/index.md` gives rounding with error radii and output/input alias permissions,
principal logarithm, and arctangent cuts. The `src/arb/log.c` and `src/acb/atan.c` implementations
were checked for nonpositive real inputs and branch/singularity handling. All new wrappers preserve
the existing scalar ownership and cleanup rules.

## Evidence

`test/elementary_ball_tests.jl` uses MPFR directed bounds for real interval endpoints and independent
exact rational complex power series with proved tail bounds for point/corner values. It covers
zero identities, uncertain real/complex inputs, destination aliasing, midpoint precision, wide
trigonometric inputs, nonfinites, principal log/cut crossing, and arctangent singularities. Sampled
corner tests do not constitute a universal proof of complex range evaluation; that guarantee comes
from the pinned native kernels.

[Recorded measurements](../benchmark/results/elementary_balls.txt) compare complete allocating calls
with initialized destination reuse at 64, 256, and 1024 bits, reporting Julia allocations and radii.
Julia allocation counters do not include native scratch. First-use timings and other-family expansion
remain separate follow-up work. No additional special functions are advertised at this checkpoint.
