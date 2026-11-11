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

## Strict point functions

The same five functions are implemented for `ArbFloat{P}` and `AcbFloat{P}`, with a trailing optional
rounding mode (default `RoundNearest`). `RoundToZero`, `RoundFromZero`, `RoundDown`, and `RoundUp`
are also supported. Each result (each complex component) is correctly rounded in these strict modes.
Qualified destination and `_inexact!` forms follow the existing scalar API; the latter return an
aggregate Boolean indicating whether any component is inexact. Unsupported rounding modes are
rejected before destination mutation. No relaxed native rounding mode is exposed.

Real negative logarithms throw `DomainError`; zero gives native negative infinity. Select complex
points explicitly for a principal logarithm of a negative real. Point nonfinites retain native
behavior. Very large exponentials/trigonometric arguments can yield native NaN at the pinned source's
polynomial-cost limits, despite the unbounded exponent representation. This is not an MPFR exponent-
range fallback. Complex functions retain principal branches and native singularity behavior.

The matching `arf.h`/`acf.h` declare `int(prefix_ptr, prefix_srcptr, slong, arf_rnd_t)`.
`arf` strict return values indicate inexactness; `acf` uses per-component bits. The pinned
`arf` elementary documentation and `src/acf/elem.c`/`elem_acb.c` describe strict rounding with
certified retries, special cases on axes, aliasing, and range limits. Ten new declarations bring the
audited inventory to 329 symbols.

`test/elementary_point_tests.jl` checks real results bit-for-bit against MPFR in all five modes
at 5, 24, 53, 128, and 512 bits. Complex references use exact rational series with proved tails:
both endpoints must round to the same component before comparison. Rational numerators and
denominators are converted to MPFR exactly before the rounded division; converting them separately
at target precision would compromise the oracle. Complex tests cover 5 through 256 bits, both
signs, aliases, exact/inexact flags, rejected modes, log domains, nonfinites, and near-axis values.
These sampled checks support the native guarantee; they are not a proof over every possible input.
[Point measurements](../benchmark/results/elementary_points.txt) record allocation/reuse costs and
fresh-precision first-use timings.

## Inline families

All five selected functions also accept `DFloat{N}`, `DFloatBall{N}` (N=1:4), and `NFloat{L}`.
They return inline values and do not add destination methods for immutable scalars.

Dfloat points use the native approximate kernels. The matching `dfloat.h` records static
`DFLOAT_EXP_EPS_N`, `DFLOAT_LOG_EPS_N`, `DFLOAT_TRIG_EPS_N`, and `DFLOAT_ATAN_EPS_N` bounds with
argument ranges and slow fallbacks. Exp/log/atan bounds are relative; sine/cosine bounds are
absolute and scale with argument magnitude. These are not correctly rounded functions. Native
nonfinites/overflow propagate; negative real log is checked as DomainError and log(0) is -Inf.
Dfloat balls add the static errors and input-radius propagation to produce rigorous enclosures.
Entirely nonpositive log throws DomainError; zero-crossing log returns the whole real line. Its
native failed output is never read. Void-returning ball functions can produce finite range bounds
even for indeterminate input (for example sine of the whole real line encloses [-1,1]).

Nfloat kernels use the existing immutable shared finite-only contexts. The pinned `rounding.md`
describes elementary accuracy as approximately one ulp in default mode; no correctly-rounded or
universal eight-ulp guarantee is made. Log requires a positive input, including rejection of zero
because this format cannot represent -Inf. Exp underflow flushes to zero; overflow/unsupported
native evaluation throws through the existing status policy before reading the result buffer.
The audited `exp.c`, `log.c`, `sin_cos.c`, `atan.c`, and `elem.c` read context settings and use local
scratch. No function-precision/context setting is mutated, including during concurrent reads.

The inventory adds 40 dfloat declarations (five functions, plain/ball, four N) and five nfloat
declarations, bringing the audit to 374 symbols. The dfloat declarations are `void(ptr, srcptr)`
except ball log, which returns GR status; all nfloat declarations return GR status and take a
context pointer. Headers and `src/dfloat/template.inc` establish the ball-log failure convention.

`test/elementary_inline_tests.jl` checks independent MPFR references with the actual dfloat static
bounds, uncertain-ball endpoint containment, representative nfloat lengths through 66 limbs,
negative domains, nonfinites, overflow/underflow, reuse after errors, and concurrent context reads.
Nfloat accuracy tolerances in the tests are empirical regression limits, not new API guarantees.
[Inline measurements](../benchmark/results/elementary_inline.txt) record complete calls and Julia
allocations for tiny/large inline formats and first-use compilation. Native allocations are excluded.
