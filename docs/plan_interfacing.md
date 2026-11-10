# FlintFloats interfacing plan

## Decisions and scope

Build a Julia interface to FLINT's floating-point families using `FLINT_jll`, as described in `README.md`. Optimize for inexpensive scalar calls, contiguous bulk arithmetic, and source that makes ownership and numerical guarantees easy to inspect. This is an implementation plan: `src/FlintFloats.jl` is still a skeleton, and no FLINT dependency or bindings have been implemented.

The Julia floor is **1.13**. Use the standard library's scoped values for dynamic precision defaults; remove the proposed fallback for earlier Julia versions. `Project.toml` and CI are updated with this plan.

Required families are **dfloat, nfloat, arb, and acb** (`asb` was clarified to mean `acb`). Balls are part of the initial design, not optional scope. Use the following proposed Julia names consistently:

| FLINT family | Julia interface | Representation strategy | Numerical contract |
| --- | --- | --- | --- |
| Real `dN`, N = 1–4 | `DFloat{N} <: AbstractFloat` | Immutable, inline double expansion | Approximate real value; operation-specific error bounds |
| Real `nfloat` | `NFloat{P} <: AbstractFloat`, P in bits | Immutable, inline words for a validated precision | Approximate real value; guarantees depend on operation and context |
| `arb_t` | `Arb <: AbstractFloat` | Managed owning storage and working precision | Rigorous real enclosure |
| `acb_t` | `Acb <: Number` | Managed owning storage and working precision | Rigorous rectangular complex enclosure |
| `arf_t`, `mag_t` | Private storage/bindings initially | Reused by ball storage, conversion and inspection | Midpoint arithmetic and magnitude bounds |

**Hierarchy recommendation:** subtype `AbstractFloat` for the real families, as requested. `AbstractFloat <: Real`, so making `Acb` its subtype would falsely declare complex balls to be real. Use `Number` for `Acb`, with `real`, `imag`, `conj`, and complex arithmetic; make this exception explicit in the public documentation. Arblib uses the same `Arb`/`Acb` split ([type definitions](https://github.com/kalmarek/Arblib.jl/blob/master/src/types.jl)).

FLINT also offers ball and complex dfloat formats. Design the internal binding inventory to accommodate them, but do not multiply public types in the first release unless those formats are needed. Exposing `Arf` or `Mag` publicly is a later scope decision, not a prerequisite to wrapping balls. A magnitude upper bound should not automatically inherit the ordinary floating-point contract.

## 1. Establish the binary contract first

The latest online documentation is for **FLINT 3.7.0-dev**. The inspected `FLINT_jll` main-branch metadata reports **301.600.0+0**. This is evidence of a potential feature gap, not proof of which symbols an installed artifact provides. Do not infer dfloat availability from an unqualified requirement for “FLINT 3.x.” ([dfloat reference](https://flintlib.org/doc/dfloat/index.html), [wrapper metadata](https://raw.githubusercontent.com/JuliaBinaryWrappers/FLINT_jll.jl/main/Project.toml))

Before implementing wrappers:

1. Resolve the latest released wrapper and record its package version, upstream FLINT version, artifact identity, supported targets, and library product name. Inspect that artifact's headers and exported symbols.
2. Inventory the exact functions needed for constructors, arithmetic, conversion, predicates and vectors in all four required families. Record argument types, return/status semantics, aliasing rules, and whether each function is exported, inline, or a macro.
3. Verify `sizeof`, alignment, field offsets, limb width, and C integer widths with a small **development/test C probe compiled against matching headers**. Cover nested `arf`/`mag` storage and contexts as well as whole structs. Do not assume that FLINT exposes runtime size-query functions.
4. If dfloat is absent, identify the first wrapper release that includes it. Treat its publication as a release prerequisite for the complete interface; document the gap and continue other families independently. Do not silently substitute a different arithmetic family or build FLINT during ordinary package installation.
5. Add the verified `FLINT_jll` dependency and a compatibility range limited to versions whose interface has been checked. A later wrapper upgrade repeats the layout and symbol checks. “Latest” means tracking supported releases through maintenance, not accepting every future ABI without review.

Use `Libdl.dlsym_e` or an equivalent symbol audit in development/CI; `nm` is a useful local diagnostic but is not a portable runtime requirement. A header declaration alone is insufficient evidence that a symbol can be called.

## 2. Put the seam around storage and arithmetic

Use one private C adapter and family-specific Julia implementations. The public interface should hide object lifetimes, pointer conversion, contexts and C status codes. Avoid a runtime backend registry or a common mutable storage model imposed on every family.

```text
src/
  FlintFloats.jl          includes and exports
  libflint/
    LibFlint.jl           private module and library import
    layouts.jl            verified C representations
    generated/            concrete, reviewable foreign calls by family
  precision.jl            scoped defaults and validated options
  storage.jl              owned and borrowed storage, lifetime helpers
  dfloat.jl               fixed expansion values and arithmetic
  nfloat.jl               fixed word values, contexts and arithmetic
  arb.jl                 real balls and their arithmetic
  acb.jl                 complex balls and their arithmetic
  conversions.jl         explicit conversions and promotion rules
  arrays.jl              contiguous owners, views and bulk kernels
  show.jl                formatting and parsing policy
gen/                     binding inventory and regeneration tools
test/                    interface, ABI, numerical and ownership checks
benchmark/               separate BenchmarkTools environment
```

These are cohesive files, not a requirement for a hierarchy of tiny modules. Keep operations with their family when their semantics differ; share code only when ownership, precision and errors actually agree. The deep module is the managed numeric interface: callers learn ordinary constructors, arithmetic and a small reusable-destination interface while the implementation handles C complexity in one place.

### Foreign calls and generation

Use literal `@ccall`/`ccall` library symbols and concrete argument types. Prefer direct dfloat/nfloat functions for scalar arithmetic when exported; use the generic ring interface for algorithms that require it. Benchmark direct and generic calls before adding indirection to the hot path.

Generate a **curated** binding set from a small declarative inventory. Check generated Julia into version control and retain upstream names for cross-reference. The inventory includes status handling and aliasing metadata, not just argument types. A generator must reject unsupported signatures and missing symbols. Clang can assist header inspection; it is not a runtime dependency or a reason to wrap every FLINT function.

Keep type layouts hand-reviewed and ABI-tested. Implement an inline helper in Julia only after verifying its exact semantics; otherwise use an exported equivalent. Introduce a compiled shim only for a demonstrated missing operation, with explicit artifact/distribution work. Do not hide a local compiler requirement in package loading.

Generate repetitive foreign declarations and truly identical wrappers. Write conversions, ball predicates, context management and exceptional operations explicitly. Avoid broad `@eval` loops whose brevity hides different guarantees.

## 3. Storage and lifetime

### Fixed-size values

Prototype `DFloat{N}` with `NTuple{N,Float64}` payloads. FLINT describes dfloat's direct formats as stack-allocatable and requiring no init/clear. Check `dfloat_is_supported` once during runtime initialization before permitting calls, and report unsupported targets clearly. Do not enable `@fastmath` around algorithms that rely on controlled rounding. ([direct interface and target support](https://flintlib.org/doc/dfloat/using.html), [format definitions](https://flintlib.org/doc/dfloat/index.html))

For `NFloat{P}`, validate that P is a supported multiple of the artifact's limb width. Public precision is in bits; the private layout has an exponent, sign word, and a fixed-length mantissa. Use separate fields for the header and `NTuple{L,Limb}` payload, deriving L through validated construction. Do not put arithmetic on a type variable directly into a field type such as `NTuple{P+2,UInt}`. Verify any extra internal storage parameter and keep it out of ordinary constructors. FLINT documents packed, allocation-free element storage; it does not guarantee that Julia temporaries or foreign-call adapters allocate nothing. ([nfloat representation](https://flintlib.org/doc/nfloat/index.html))

Immutable inputs may be passed through input references. **Never let C write into an immutable Julia value.** Produce results in valid writable storage, then construct a value from it. Measure whether temporary `Ref` storage is eliminated by the compiler; an isbits definition alone does not prove stack allocation or zero allocations. If scalar copying is expensive at large P, use explicit buffers and packed arrays for sustained work rather than changing all scalar values into finalizable boxes.

Limit type-level specialization to representation-changing parameters: dfloat component count and nfloat fixed precision. Do not add precision parameters to variable-precision balls or specialize on arbitrary runtime options.

### Owning balls

Use a concrete mutable C-layout owner for each heap-owning FLINT struct, wrapped by the public numeric value and its working-precision metadata. Keep metadata outside the C payload. Each initialized owner has exactly one matching clear action; register cleanup immediately after successful initialization and make partial construction exception-safe.

Pass the owner using a tested `cconvert`/`unsafe_convert` path and concrete `Ref{Owner}` types where appropriate. Validate the Julia payload layout against C. Do not assume `Ref(x, :field)` is a supported field reference, or that `pointer_from_objref` identifies an arbitrary nested field. Derived raw pointers require a narrow `GC.@preserve` scope retaining the actual owner. Julia's [foreign-call documentation](https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/) is the reference for conversion and preservation rules.

`copy(x)` creates independent FLINT storage; ordinary Julia assignment shares the value/owner. Document that explicit mutation can affect aliases, as with other managed mutable numbers. Never bit-copy a live pointer-owning `arf`, `arb` or `acb` into a second independently cleared owner. Avoid making raw isbits mirrors containing owning pointers generally copyable.

Finalizers are a fallback for owned resources, not a performance strategy or a reason to invoke global FLINT cleanup. Free returned strings using the allocator required by FLINT. Do not call process-wide cleanup functions from ordinary operations or finalizers; other packages may use the same library.

### Arrays and borrowed views

Start with ordinary dense arrays for inline `DFloat`/`NFloat` values, verifying that element stride matches the C format. For balls, prototype an owning packed vector using FLINT's appropriate vector allocation/init/clear functions. Reuse the ownership design for matrices only when matrix work is introduced.

Give packed containers concrete `eltype`, indexing, iteration, copying and broadcast behavior. Ordinary indexing returns an independent value; explicit borrowed element references retain their parent and never clear storage themselves. Keep parent storage stable while a view exists: forbid resizing/reallocation, or use a fixed-size owner. Preserve owners while passing element pointers or bulk spans to C.

Borrowed midpoint, radius, real-part and imaginary-part views obey the same lifetime rule. Begin with copying accessors; add borrowed mutation only where measurements justify its extra interface.

## 4. Precision, contexts and arithmetic

Provide ordinary value operations (`+`, `*`, `sqrt`, and so on) for all supported families. Add destination-first `add!`, `mul!`, and a small set of reusable-destination operations for mutable ball destinations. For immutable fixed types, use ordinary arithmetic and bulk `map!`/dedicated vector kernels; introduce an explicit writable buffer only if it improves measured workloads. Do not promise scalar `add!(z, ...)` can replace an immutable `z`.

For balls, define these rules before coding:

- `Arb`/`Acb` carry working precision as a value, separate from accuracy or radius. `precision(x)` reports the working precision, not the number of certified correct bits.
- Constructors use explicit `precision=` or the scoped family default. Allocating binary operations use the maximum working precision of their operands; unary operations retain input precision. This makes existing values independent of later changes to defaults.
- Destination operations use destination precision, unless an explicit operation precision is supplied. An explicit override changes the operation's rounding work, not the destination's stored precision metadata. Precision must be a validated positive integer representable by the C argument type.
- Provide scoped `setprecision(Arb, p) do ... end` and the corresponding `Acb` form. Read defaults at construction or once at a deliberate operation seam, never inside repeated foreign calls. Pass precision explicitly through kernels.
- Higher working precision does not recover information already lost in an input enclosure. Conversions and changes in working precision preserve containment.

For fixed formats, `precision(DFloat{N})` describes nominal format precision and `precision(NFloat{P}) == P`; operation accuracy remains separately documented. Precision changes require conversion to another concrete type. Avoid an unbounded nfloat specialization workload; benchmark common precisions first and keep compilation cost visible.

Manage nfloat contexts privately. Initialize at runtime, clear exactly once, and key reuse by precision **and all behavior flags**. Establish from matching source whether a context is immutable during operations; until verified, use task-owned contexts/workspaces rather than a shared mutable global cache. Hoist context acquisition and validation outside vector loops. Scoped defaults must restore after exceptions and behave predictably in child tasks.

Do not promise one universal rounding mode. Ball operations compute enclosures; dfloat arithmetic is approximate; nfloat guarantees vary by operation and flags. Maintain an operation/rounding capability table from the selected artifact. Unsupported requested modes produce explicit errors, never a silent ignored option. A future public `Arf` could offer a separate correctly rounded interface.

Translate C status bits at the checked interface, after the call. Keep domain failures distinct from unavailable algorithms. For operations following established enclosure semantics, retain FLINT's documented indeterminate/unbounded result; for an unsupported operation, throw a descriptive error. Publish this policy per operation before release. Do not discard status codes or automatically fall back through `BigFloat` and lose the family’s guarantees.

Document allowed aliasing for each destination operation. Test destination=input and overlapping spans separately; use a temporary when FLINT disallows an overlap. Do not mark bulk loops `@simd` or `@inbounds` until independence and indexing invariants are established.

## 5. Make `AbstractFloat` integration deliberate

Subtyping gives dispatch compatibility, not proof that every generic real-number algorithm is valid for enclosures. Audit Base fallbacks and implement the supported interface explicitly.

1. Implement constructors, `zero`, `one`, `float`, `precision`, finite/zero/NaN predicates, arithmetic, `abs`, `real`, `imag`, conversion, parsing and display. For `Acb`, add `conj`, `abs2` and complex operations; `abs(::Acb)` returns a real enclosure.
2. Define `==` for balls as proven singleton equality and `<`/`<=` as proven relations; overlapping uncertainty can make both a predicate and its apparent complement false. Offer named `contains`, `overlaps`, and certainty predicates. Never compare midpoints as a substitute for comparing enclosures. FLINT provides distinct predicates for these purposes ([arb reference](https://flintlib.org/doc/arb/index.html)).
3. Keep `isequal` an equivalence relation distinct from proven numerical equality. Use normalized represented-value/enclosure equality, with explicit handling of special values, and ensure `isequal(x,y)` implies identical hashes across supported mixed types. For noncanonical double expansions, normalize a copy for comparison/hashing or otherwise compare represented values; raw tuple equality is insufficient. Numeric hashes must not include working-precision metadata when it does not change equality. Mutable values must not be mutated while used as dictionary keys.
4. Define `isless` for point formats consistently with Julia's special-value ordering. Do not inherit a misleading total numeric order for nonsingleton balls: reject unsupported sorting comparisons explicitly. If deterministic enclosure sorting is needed, provide a separately named key. Define `eps`, `nextfloat`, `prevfloat`, `significand`, `exponent`, `floatmin` and `floatmax` only where the representation has a coherent documented interpretation. Nonsingleton balls have no unique next real floating-point value; reject that case rather than silently selecting the midpoint.
5. Conversions to point values are explicit about information loss. A nonsingleton ball cannot silently become a midpoint during `convert(Float64, x)`; require an explicit midpoint or bound extraction. Provide endpoint/enclosure conversion paths and raise `InexactError` when a requested exact conversion is impossible.
6. Start promotion with integers and machine floats within each family. Between `DFloat{N}` values use the larger supported component count; between `NFloat{P}` values use the larger supported precision. Prefer exact scalar mixed-operation bindings when available, avoiding temporary balls. Promote point values to balls through enclosure-preserving conversion, and real balls to `Acb` when mixed with complex balls. Leave dfloat/nfloat cross-family promotion explicit until its precision and range policy is settled. Never use a blanket `Real` promotion rule that catches unrelated packages.

Print balls with their uncertainty and fixed values with enough information for the stated round-trip policy. Parsing decimal text must not pass through `Float64`. Separately document nominal precision, achieved accuracy, exponent range and support for signed zeros/nonfinite values for each family. Do not promise IEEE behavior that the underlying format does not preserve.

## 6. Performance work with measurable gates

Prioritize eliminating temporary owners, repeated contexts and per-element foreign calls. Contiguous storage and FLINT vector/dot/matrix kernels are likely to matter more than saving a Julia wrapper instruction; verify this with measurements. Add specialized bulk operations only for demonstrated workloads and inspect their semantics, including whether a dot product uses a different rounding scheme from repeated scalar accumulation.

Maintain a benchmark environment comparing:

| Workload | Comparisons | Measurements |
| --- | --- | --- |
| Scalar add/multiply/divide/sqrt | Checked wrapper versus equivalent direct C call | Time, Julia allocations, dispatch/inference |
| Elementary functions | Wrapper, BigFloat and Arblib where comparable | Time versus precision and numerical guarantee |
| Reused destinations | Ball `!` operations versus allocating operations | Time, Julia allocations, C allocation behavior |
| Vectors, dot products, then matrices | Scalar loops versus FLINT bulk kernels | Throughput, memory footprint, context overhead |
| Fixed formats | dfloat N=1–4; nfloat at 64/128/256/1024/4096 supported bits | Runtime, copying, compilation cost |

Warm up specializations, interpolate benchmark operands, and separate construction, context creation and arithmetic. Prevent constant folding. Include tiny operations that expose call overhead and larger operations that expose arithmetic cost. Record artifact, Julia, architecture, CPU and thread count.

Target zero Julia heap allocations for warmed fixed-format arithmetic and reuse of suitably sized ball destinations **where the prototype demonstrates it**. FLINT may still allocate or grow mantissas/exponents internally. `@allocated` does not measure those C allocations. Measure them separately when investigating memory costs. Track absolute overhead in nanoseconds; a universal “less than 10%” threshold is inappropriate for extremely short kernels. Compare algorithms at equivalent accuracy/containment, not merely similar nominal precision.

Use Julia threads over independent destinations only. Verify context and library threading assumptions against the selected artifact, and avoid nested oversubscription with FLINT's own threads. Keep numeric defaults scoped and make shared mutation an explicit caller responsibility.

## 7. Validation and release gates

- **ABI:** probe sizes, offsets and alignment on each supported target; verify every bound symbol. Include 32-bit and Windows checks before claiming those platforms. Probe availability of dfloat separately from its runtime hardware-support check.
- **Numerical correctness:** compare point operations using the operation's documented rounding/error guarantee. Use independently computed high-precision references and proved error bounds for approximate formats. Exact bit equality with MPFR is appropriate only for operations actually specified as correctly rounded.
- **Enclosures:** check containment against exact rational cases and independently certified references; include uncertain domains, branch cuts, nonfinite values, zero-crossing divisors and cancellation. A high-precision approximation alone is not a rigorous containment oracle. Exercise both real and complex balls ([acb reference](https://flintlib.org/doc/acb/index.html)).
- **Ownership:** test independent copies, parent retention by views, construction failure, aliasing, and repeated GC while borrowed references remain live. Use bounded stress tests; RSS alone cannot establish that clear is correct. Run longer native memory diagnostics separately when available.
- **Julia contracts:** test inference, conversion/promotion termination, equality/hash laws, ordinary array behavior, uncertainty predicates, precision restoration after exceptions, and concurrent tasks with different defaults.
- **Allocations/performance:** use warmed, function-scoped checks for representative stable workloads. Keep noisy runtime comparisons on a controlled benchmark runner rather than making every shared CI job a speed test.

CI tests Julia 1.13, the current stable release, and prerelease Julia. Documentation builds use 1.13. Retain a target only when Julia and the selected FLINT artifact support it; record unsupported configurations rather than assuming all layouts are portable.

## 8. Review of the earlier approach

The existing `docs/planinterfacing.md` draft contains useful instincts: literal foreign calls, a private adapter, destination reuse, symbol auditing and bulk storage. This plan revises its scope and several assumptions:

| Earlier proposal | Improvement and reason |
| --- | --- |
| Start with public `mag`/`arf`; balls optional and nfloat late | All four requested families shape the design now; use `arf`/`mag` as private support initially. Prototype the performance-critical fixed formats early. |
| One finalizable scalar representation | Separate inline fixed values from owning ball storage; finalizers are unnecessary for dfloat/nfloat payloads. |
| Raw immutable mirrors for owning pointers | Keep ownership unique and borrowing explicit; raw copies can double-free. |
| `pointer_from_objref` or a presumed field `Ref` | Use verified owner conversions, ABI checks and explicit preservation for derived pointers. |
| All operations table-generated | Generate declarations and identical cases; keep semantic differences readable. |
| One rounding policy and bitwise BigFloat oracle | Specify guarantees by family and operation, with containment tests for balls. |
| Every `!` call allocates zero | Separate Julia allocations, native allocations, capacity growth and immutable result handling. |
| Context flags/precision from ambient state | Fixed representation parameters plus explicit kernel options; scoped defaults only at deliberate seams. |
| Nominal 64-bit sizes and presumed size-query functions | Matching-header C probes, including offsets, integer widths and target-specific layouts. |
| Full generic float behavior follows from subtyping | Audit equality, order, hashing, neighbors and information-losing conversion explicitly. |
| Global/thread cleanup guidance inside the package | Clear only owned resources; shared-library cleanup needs process-level coordination. |

Study [Nemo's owners and init/clear pattern](https://github.com/Nemocas/Nemo.jl/blob/master/src/arb/ArbTypes.jl) and Arblib's numeric wrappers and borrowed references. Reuse established lifetime ideas without inheriting a ring-parent interface or adding either package as a mandatory runtime dependency. Add interoperability extensions only when a real use case needs them and never share unverified owning pointers across packages.

## 9. Implementation sequence

1. **Binary inventory:** resolve the wrapper, inspect headers and symbols, run the ABI probe, and record dfloat availability. Exit: a reproducible supported-artifact contract for each family, with any missing release prerequisite explicit.
2. **Representation prototypes:** implement one dfloat add, one nfloat add/context, and one owning Arb/Acb add with cleanup. Compare inline results, destination reuse and direct calls. Exit: verified layouts/lifetimes, inferred concrete returns and measured allocation/copying behavior. Adjust representation here, before broad generation.
3. **Vertical slice across the four families:** constructors, conversion, display, basic arithmetic and predicates; ball precision rules and complex behavior included. Exit: numerical and ownership checks pass through the public interface. A missing dfloat artifact blocks that family's completion, not the others.
4. **Julia integration:** complete the documented Base subset, equality/hashing and mixed-operation rules; implement scoped defaults. Exit: uncertainty semantics and unsupported generic operations are documented and tested.
5. **Bulk arithmetic:** packed ball vectors, borrowed views and verified FLINT vector/dot kernels, followed by matrices where justified. Exit: validated aliasing/lifetimes and measured throughput improvements over scalar loops.
6. **Release hardening:** expand elementary functions and required special functions, run platform and memory checks, publish the guarantee/capability tables and benchmark results. Exit: all four requested families work against released supported artifacts, with no unsupported performance or rounding claims.

Do not gate the entire design on a claim of being faster than existing packages. The deliverable is a clear, safe interface to the selected FLINT formats; each optimization earns its complexity with measurements. Keep remaining decisions concrete: verified wrapper versions, supported targets, exported function inventory, context sharing guarantees and the measured choice of fixed-format result storage.
