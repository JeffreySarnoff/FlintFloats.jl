# FlintFloats development guide

This guide defines the implementation sequence, numerical contracts, architecture, and release criteria for FlintFloats. It develops the recommendations in [the interfacing plan](plan_interfacing.md) into work that can be implemented and reviewed in small, verifiable changes.

The objective is a Julia interface to FLINT's **dfloat (plain and ball), nfloat, arb, and acb** families, with the arb families exposed both as floating-point types (`arf`, `acf`) and as balls (`arb`, `acb`), that combines efficient scalar and bulk arithmetic with clear source and reliable resource management. Julia **1.13** is the minimum supported version. The real families subtype `AbstractFloat`; the complex types `AcbFloat` and `AcbBall` are `<: Number` because `AbstractFloat <: Real`. Point types end in `Float` (`DFloat`, `NFloat`, `ArbFloat`, `AcbFloat`); ball types end in `Ball` (`DFloatBall`, `ArbBall`, `AcbBall`); a point type and its ball share one parameter. **Precision is a type parameter for every type.** The full interface contract is in [float_interfacing.md](float_interfacing.md).

Descriptions of the existing repository are distinguished from requirements for future implementation. Proposed Julia constructors and operations below are interface specifications, not claims that those methods already exist.

## 1. Starting point and development priorities

### 1.1 Existing implementation

| Area | Current state | Consequence for development |
| --- | --- | --- |
| Main Julia package | `src/FlintFloats.jl` and its tests are skeletons | Implement the numeric interface from the storage and arithmetic foundations upward. |
| Julia compatibility | Main project requires Julia 1.13 | Use `Base.ScopedValues`; maintain one supported precision-scoping implementation. |
| Local binary package | [`../FlintFloat.jl/FLINT_jll`](../FlintFloat.jl/FLINT_jll/README.md) contains a working loader, native artifact, headers, source archive, and build tools | Use this package for host development rather than waiting for a published dfloat-capable wrapper. |
| Pinned FLINT source | `82c40b299084b92299c2d8dac464e39d6743fce4`, reporting `3.7.0-dev` | Consult this revision's declarations and implementation when writing bindings. |
| Local wrapper version | `301.690.0+0`, shared-library ABI 25 | Do not equate its layout or compatibility with the reference wrapper's ABI 24. |
| Existing validation | Wrapper tests, C arithmetic/size smoke test, and upstream dfloat/nfloat tests have passed | These establish a working binary; they do not establish the correctness of future Julia numeric wrappers. |
| Portable distribution | BinaryBuilder recipe is present but has not been executed | Portable artifacts and platform coverage remain release work. |

The native artifact is tuned for the development host: x86_64 Linux, glibc 2.43, and an Intel i9-14900K. Its platform entry does not encode all CPU and libc restrictions. Do not install it on a generic CI runner or interpret `FLINT_jll.is_available()` as a CPU compatibility test.

Read the active artifact identity from [`Artifacts.toml`](../FlintFloat.jl/FLINT_jll/Artifacts.toml) and its archive checksum from [`bundles/Checksums.toml`](../FlintFloat.jl/FLINT_jll/bundles/Checksums.toml). These change after rebuilding. Source identity and build dependencies are recorded in [`Source.toml`](../FlintFloat.jl/FLINT_jll/Source.toml).

### 1.2 Order of priorities

1. Establish correct foreign declarations, layouts, ownership, and numerical behavior.
2. Demonstrate a complete construction/arithmetic/conversion path for all seven types (`DFloat`, `DFloatBall`, `NFloat`, `ArbFloat`, `ArbBall`, `AcbFloat`, `AcbBall`).
3. Make the supported Julia numeric interface explicit and testable.
4. Remove unnecessary allocations and exploit contiguous storage and FLINT bulk kernels.
5. Expand functionality and supported targets using reproducible builds and evidence.

Optimize an established operation, with its contract preserved. A measured improvement in one family does not justify forcing other families into the same storage or precision model.

## 2. Set up a reproducible working environment

Run commands in this section from the repository root unless stated otherwise.

### 2.1 Verify the local binary package

On the compatible development host:

```sh
julia --project=FlintFloat.jl/FLINT_jll -e 'using Pkg; Pkg.instantiate(); Pkg.build("FLINT_jll"); Pkg.test()'
julia --project=FlintFloat.jl/FLINT_jll -e 'using FLINT_jll; println(FLINT_jll.libflint_path)'
```

`Pkg.build` installs the bundled artifact after checksum verification. It does not compile upstream FLINT. To rebuild FLINT from the pinned source, use the native rebuild and packaging instructions in the [wrapper README](../FlintFloat.jl/FLINT_jll/README.md). A native rebuild and a portable BinaryBuilder build are separate workflows.

### 2.2 Connect the numeric package to the local wrapper

The main package does not yet depend on `FLINT_jll`. As the first implementation change, develop the nested package into the main environment:

```sh
julia --project=. -e 'using Pkg; Pkg.develop(path="FlintFloat.jl/FLINT_jll"); Pkg.build("FLINT_jll")'
```

Review the resulting `Project.toml` and manifest. Declare only the wrapper versions whose ABI has been verified; begin with an exact local-version constraint and broaden it after validating additional builds. Keep runtime dependencies limited to the wrapper and required standard libraries. Put BenchmarkTools and generator tools in their own development environments.

The local package uses the official `FLINT_jll` UUID. Developing its path replaces that dependency in the selected environment. Use an isolated environment when examining Nemo or Arblib so their dependency requirements do not accidentally select or constrain the development binary.

A local path in a developer manifest is insufficient for a clean checkout or documentation environment. Provide explicit setup for every environment that needs it. Before distribution, select a reproducible source-resolution mechanism for the intended deployment and replace the host-specific artifact with validated portable artifacts.

### 2.3 Record the baseline

Capture Julia version, wrapper version, source revision, artifact tree hash, CPU, libc, compiler, dependency versions, thread settings, and benchmark configuration with each baseline. Keep measurements associated with that identity. Never compare a newly rebuilt library against stale benchmark labels.

## 3. Define the supported numeric interface

### 3.1 Families and representation commitments

| Family | Public interface direction | Storage commitment | Precision/accuracy meaning |
| --- | --- | --- | --- |
| dfloat | `DFloat{N} <: AbstractFloat`, N = 1–4 | Immutable inline expansion of N doubles | Nominal expansion precision (`53N`); accuracy depends on operation. |
| dfloat ball (`dNb`) | `DFloatBall{N} <: AbstractFloat`, N = 1–4 | Immutable inline: `NTuple{N,Float64}` midpoint plus `Float64` radius; no finalizer | Rigorous real enclosure; indeterminate value is the whole real line `[0±∞]`; no NaN. |
| nfloat | `NFloat{L}`, L = limb count (`precision = 64L` bits); `NFloatType(bits)` helper | Immutable inline: exponent word, sign word, `NTuple{L,UInt}` | Fixed format precision; context and operation determine rounding guarantees. |
| arf | `ArbFloat{P} <: AbstractFloat`, P = precision in bits | One private mutable heap object laid out as the four-word C `arf_struct`; no heap memory up to 128 mantissa bits | Correctly rounded floating point in FLINT's strict modes; unbounded exponent; no negative zero; not an enclosure. |
| acf | `AcbFloat{P} <: Number`, P = precision in bits | One private mutable heap object laid out as `acf_struct` (two `arf`) | Complex floating point, each part correctly rounded; not an enclosure. |
| arb | `ArbBall{P} <: AbstractFloat`, P = precision in bits | One private mutable heap object laid out as the C `arb_struct` | Real enclosure with separate working precision (`P`) and achieved accuracy. |
| acb | `AcbBall{P} <: Number`, P = precision in bits | Private mutable heap object laid out as `acb_struct` | Complex rectangular enclosure with real-ball parts. |

`arf` and `acf` are public as `ArbFloat` and `AcbFloat`; `mag` stays private (it supports ball radii and bounds, and exposing it would add another numeric contract). Complex dfloat (`dNc`), complex dfloat balls (`dNcb`, a pair of `dNb`) and complex nfloat are later interface additions, not prerequisites for the seven required types.

**Precision invariant for the arb types.** FLINT's `arf` has no precision of its own and exact setters keep every bit. Every `ArbFloat{P}`, each part of an `AcbFloat{P}`, and the midpoint of every `ArbBall{P}`/`AcbBall{P}` must have at most `P` mantissa bits: round in every constructor, conversion and `set!` (`arf_set_round`, `arb_set_round`) and pass `P` to every operation. `midpoint(::ArbBall{P})` is then exactly an `ArbFloat{P}`.

**Type grid.** Provide `pointtype(T)`, `balltype(T)`, `realtype(T)` and `complextype(T)`; define the return types of `midpoint`, `radius`, `abs`, `real` and `imag` through them. A missing cell is a `MethodError`.

**Resolve the nfloat representation before broad implementation.** Julia cannot use arithmetic on a type variable in a field declaration such as `NTuple{P+2,UInt}`. The preferred design takes the **limb count** as the single parameter: `NFloat{L}` with fields `exp::Int`, `sign::Int`, `d::NTuple{L,UInt}` and `precision(NFloat{L}) = 64L`. There is no derived second parameter and no inconsistent-combination check, every `NFloat{L}` is concrete (so `Vector{NFloat{2}}` is packed), and `NFloatType(bits)` returns `NFloat{bits÷64}` for users who think in bits. The earlier `NFloat{P,L}` prototype is superseded. Validate the layout with the C probe (header of `NFLOAT_HEADER_LIMBS = 2` words plus `L` limbs; 1–66 limbs on the pinned 64-bit build) in milestone M1 before dependent methods are added.

With that design, `NFloat{128}` alone is a partially specified type, not a concrete array element type. Constructors, promotion, `zero`, and array factories must return the fully specified type; use `typeof(NFloat{128}(0))` when a concrete element type is needed. Do not advertise `Vector{NFloat{128}}` as packed storage. If this interface is too costly or confusing, resolve the representation in milestone M1 and revise the interface before adding dependent methods.

### 3.2 First supported operations

Deliver a small, useful interface across all families before adding large function sets:

- Constructors from integers and machine floats; explicit precision where relevant.
- Copying, `zero`, `one`, `precision`, classification predicates, parsing, and display.
- Addition, subtraction, multiplication, division, negation, absolute value, and square root where their domains are supported.
- Explicit conversions and a narrowly defined set of mixed arithmetic methods.
- For `AcbFloat` and `AcbBall`: `real`, `imag`, `conj`, `abs2`, and `abs`; the modulus returns `realtype(T)` (`ArbFloat` value or `ArbBall` enclosure). `AcbFloat` `abs` and `abs2` are correctly rounded although FLINT exports no `acf_abs` (see `src/acf.jl`).
- For `ArbFloat` and `AcbFloat`: a trailing `RoundingMode` argument on rounding operations, and `_inexact` variants returning FLINT's inexact flag.
- For mutable owned destinations (`ArbFloat`, `AcbFloat`, `ArbBall`, `AcbBall`): destination-first `add!`, `sub!`, `mul!`, and `div!`, returning the destination.

Use ordinary scalar arithmetic for immutable fixed formats. An exclamation-mark method cannot replace an immutable destination supplied by the caller. Introduce a separate writable buffer only when a benchmark demonstrates a benefit. Bulk `map!` and native vector kernels are independent opportunities.

Construct identity values through FLINT or a proved format representation. `zero(x)` and `one(x)` retain x's concrete type, hence its precision; for an unparameterised ball type, `zero(ArbBall)` is `ArbBall{DEFAULT_PRECISION}`.

## 4. Architecture and source organization

The public numeric module is the main seam. It should hide initialization, clearing, context selection, pointer conversion, and C status interpretation. The private C adapter supplies literal foreign calls; family implementations define numeric behavior. Keep the dependency direction simple:

```text
Julia callers and numeric tests
            |
            v
Public values, arithmetic, conversions, and containers
            |
            v
Private storage/precision/context implementation
            |
            v
LibFlint: verified layouts and concrete foreign declarations
            |
            v
FLINT_jll.libflint
```

Use this initial file organization:

| Location | Responsibility |
| --- | --- |
| `src/FlintFloats.jl` | Module declarations, imports, include ordering, and exports. |
| `src/libflint/LibFlint.jl` | Private adapter module and library product import. |
| `src/libflint/layouts.jl` | Hand-reviewed C layouts and ABI aliases. |
| `src/libflint/generated/` | Checked-in foreign declarations grouped by family. |
| `src/storage.jl` | Ownership, cleanup, and pointer-conversion helpers. |
| `src/precision.jl` | Validated precision parameters, `DEFAULT_PRECISION`, `with_precision`, and context policy. |
| `src/dfloat.jl`, `nfloat.jl`, `arf.jl`, `acf.jl`, `arb.jl`, `acb.jl` | Family values and their arithmetic/semantic rules. |
| `src/typegrid.jl` | `pointtype`, `balltype`, `realtype`, `complextype`, and the guarantee/storage traits. |
| `src/conversions.jl` | Cross-family conversion and promotion. |
| `src/arrays.jl` | Packed owners, borrowed references, and bulk kernels. |
| `src/show.jl` | Formatting, parsing, and round-trip policy. |
| `gen/` | Binding inventory, generation environment, and regeneration command. |
| `test/abi/` | Development C probes and recorded target-specific layout evidence. |
| `test/` | Numeric, lifetime, precision, container, and Julia-contract tests. |
| `benchmark/` | Independent environment, benchmark driver, and recorded results. |

Split files when responsibilities become difficult to inspect, not at an arbitrary line count. Share implementation only where storage, precision, aliasing, and error behavior agree. Avoid a runtime backend registry or a hierarchy of modules that merely forward arguments.

## 5. Establish the C contract before generating bindings

### 5.1 Build an explicit function inventory

For each requested operation, record the following in a machine-readable inventory maintained under `gen/`:

| Field | Required information |
| --- | --- |
| Declaration | C symbol, matching source header, argument types, and return type. |
| Availability | Exported symbol, inline function, or macro; supported artifact revisions. |
| Storage | Input/output roles, ownership transfer, required initialization, and context lifetime. |
| Numerical behavior | Precision arguments, flags, rounding/error guarantee, and special values. |
| Failure behavior | Status bits, truth values, domain behavior, and state of outputs on failure. |
| Aliasing | Permitted destination/input equality and partial-span overlap. |
| Verification | Numerical cases, symbol check, and relevant layout probe. |

Use the pinned headers and implementation as the declaration authority. Online documentation is explanatory and can advance beyond the selected revision. Preserve FLINT names in private bindings and identify wrapped functions in public docstrings.

### 5.2 Verify layouts and exported symbols

Extend the existing C smoke test into a development ABI probe that reports:

1. `sizeof`, `_Alignof`, and `offsetof` for every mirrored struct and relevant nested field.
2. Width and signedness of `slong`, `ulong`, limbs, context fields, flags, and status arguments.
3. Fixed-format element sizes and array strides.
4. Relevant compile-time flags affecting layouts or algorithms.

The observed native sizes are d2 = 16, arf = 32, mag = 16, arb = 48, acb = 96, and generic context = 80 bytes. These are baseline observations for the existing host, not portable layout definitions. Size equality alone cannot detect incorrect field order or alignment.

Match Julia layouts against a probe compiled with the artifact's headers and compatible dependency headers. Pay attention to include order: some FLINT declarations are conditional on other headers having already been included. Map C integers from the verified ABI; `Int`, `Clong`, and limb-sized types are not universally interchangeable, particularly on Windows.

Check every bound symbol using `Libdl.dlsym_e` in development or CI. A declaration in a header does not establish that a callable export exists. Prefer an exported equivalent for an inline helper; translate a helper only after verifying its complete semantics. A compiled shim requires explicit artifact and packaging work and must not appear as a hidden load-time compiler requirement.

### 5.3 Generate a curated adapter

Generate concrete `@ccall` or `ccall` declarations with literal library symbols and concrete argument types. Reject missing symbols and unsupported signatures. Check generated Julia into source control and make regeneration deterministic. Run generation twice and require no second diff.

Generate identical mechanical declarations; write ownership, conversions, ball predicates, context handling, and exceptional operations explicitly. Keep Clang and any generator dependencies out of the runtime project. Prefer direct scalar kernels where available; reserve generic-ring dispatch for work that needs it or demonstrates comparable performance.

## 6. Implement storage and lifetime invariants

### 6.1 Fixed-size values

Prototype dfloat payloads as `NTuple{N,Float64}` and `DFloatBall{N}` as that midpoint tuple plus a `Float64` radius (FLINT's `dNb_struct`: `double d[N]; double rad`). A dfloat ball is an enclosure stored inline, so it needs no finalizer; ownership rules in §6.2 apply to `ArbBall`/`AcbBall` only. A returned `dNb` has a finite midpoint and finite nonnegative radius, or is the whole real line `[0±∞]`; inputs with any nonfinite part are accepted as the whole real line, and no NaN is ever a ball value. Prototype nfloat with separately declared exponent/sign fields and a concrete tuple of mantissa limbs. Verify actual field order, alignment, normalization, and special-value encodings before treating either representation as C-compatible.

C may read immutable input storage through a suitable input reference. C must write results only into genuinely writable storage, such as a correctly typed `Ref` payload or an array slot. Read the completed result into a new immutable value. Passing an immutable scalar's address as an output pointer is invalid even when a particular compiler run appears to tolerate it.

Benchmark temporary references and result copying. An isbits type permits efficient storage; it does not prove stack allocation, reference elimination, or zero wrapper overhead. Limit specialization to representation-changing parameters. Large nfloat values may need explicit buffers or bulk arithmetic to avoid repeated copies.

Call `dfloat_is_supported` during runtime capability initialization before any dfloat arithmetic. Keep unsupported dfloat behavior local to the dfloat families (`DFloat` and `DFloatBall`, which share the gate) so arb/acb ball arithmetic and nfloat can still load. Do not apply `@fastmath` to code whose error bounds depend on controlled rounding.

### 6.2 Owning arb values: floats and balls

This section applies to all four heap-owning types: `ArbFloat` (`arf_init`/`arf_clear`), `AcbFloat` (`acf_init`/`acf_clear`), `ArbBall` and `AcbBall`.

Use a private mutable owner whose payload matches the C struct. Keep Julia references and working-precision metadata outside the bytes passed as that C struct. Flatten the owner fields when needed to avoid letting C mutate a nested immutable Julia object.

The ownership invariant is: **every successfully initialized C value has exactly one owner and one matching clear action**.

Construct owners in this order:

1. Allocate correctly laid-out owner storage without exposing an invalid public value.
2. Call the matching FLINT initializer.
3. Register the owner's noncapturing cleanup function immediately after successful initialization.
4. Populate the numeric value using checked conversion.
5. Publish the public wrapper only after construction succeeds.

For multi-resource construction, retain already initialized owners so failures clean them correctly. Never clear uninitialized storage. Finalizers must not throw, depend on unrelated finalization order, or call process-wide cleanup. They are a fallback for owned resources; sustained arithmetic should reuse destinations and containers.

`copy(x)` creates independently initialized storage and uses a FLINT value-copy operation. Ordinary Julia assignment retains the same owner. Explicit mutation therefore affects aliases, and must be documented. Raw memory copying, serialization, and `deepcopy` must not duplicate live owning pointers. Implement a semantic `deepcopy` path before claiming it is supported; reject unsupported persistence instead of serializing pointer bytes.

Free returned FLINT strings with `flint_free`. Keep each allocation paired with the allocator required by the function's ownership contract. Do not change shared FLINT allocators or global thread/cleanup settings from ordinary numeric operations.

### 6.3 Pointer conversion and borrowing

Centralize `cconvert`/`unsafe_convert` in a small set of private helpers. Conversion objects must retain every required owner through the call. Prefer concrete `Ref{Owner}` declarations where suitable. For a derived raw pointer, use a narrow `GC.@preserve` region retaining the actual owner and any enclosing container.

Do not assume that `Ref(x, :field)` constructs a field reference or that `pointer_from_objref(x)` points at a chosen nested field. Validate offsets and use supported conversion mechanisms. Never retain a temporary input conversion beyond its valid lifetime.

Start with copying midpoint, radius, real-part, and imaginary-part accessors. Explicit borrowed references may be added later; they must retain their parent, must not independently clear the storage, and must not outlive any operation that can move or free it. Borrowed references must not be constructible from arbitrary public raw pointers.

## 7. Implement precision, contexts, and operation control

### 7.1 Working precision

For balls, adopt these rules consistently:

| Operation | Working precision rule |
| --- | --- |
| Construction | The type's precision parameter (`ArbBall{128}(x)`); `ArbBall(x)` uses the compile-time `DEFAULT_PRECISION`. No `precision=` keyword. |
| Unary allocating arithmetic | Preserve the input's type, hence its precision. |
| Binary allocating arithmetic | Promote to the maximum precision (`ArbBall{max(P,Q)}`). |
| Destination arithmetic | Use the destination type's precision unless an operation-specific override is supplied. |
| Explicit operation override | Change arithmetic work for that call, not the destination's type. |
| Copy/part extraction | Preserve the source type unless an explicit documented conversion (`ArbBall{Q}(x)`, `withprec`) requests another. |

Mixed arithmetic with integers and machine floats keeps the ball operand's type. Validate the precision parameter once, when the type is first instantiated, as an integer at or above the FLINT minimum and representable by the verified C type; pass it to C as a constant.

`precision(x)` reports the type's precision, not a certificate of correct digits. Increasing working precision cannot recover information lost in an input enclosure. Precision-changing conversions preserve containment.

Provide `with_precision(f, bits)`, which calls `f(Val(bits))`, as the function barrier for dynamic (adaptive) precision: the body is a method on `Val{P}`, compiled once per precision and free of dynamic dispatch. Use a documented 256-bit `DEFAULT_PRECISION`, a compile-time constant read from a package preference, so `ArbBall(x)` is type-stable. Keep it independent of `BigFloat` settings. There is no scoped runtime default and no `setprecision`: runtime state would make constructor return types depend on it. Each new `P` recompiles the methods it touches; precompile common values (64, 128, 256, 512, 1024), recommend multiples of 64, and measure first-call latency in M1. If latency is unacceptable, the fallback is a hybrid design with `P = 0` meaning precision stored in the value (see [float_interfacing.md §8](float_interfacing.md)). `ArbBall{P}` and `AcbBall{P}` have the same 48/96-byte layout at every `P`.

Test that code inside the `with_precision` barrier infers concretely and allocates nothing beyond results, that nested barriers with different precisions are independent, and that concurrent tasks using different precisions do not interact (precision is part of the type, so there is no shared state).

The type determines precision for every family. Changing precision constructs another concrete type (`withprec(x, bits)`). dfloat's nominal precision does not imply uniform relative accuracy, especially around subnormal values and cancellation.

### 7.2 nfloat contexts

Initialize contexts at runtime and keep them alive through every dependent operation. Validate P against the selected artifact's limb width and supported range. The pinned source permits 1–66 mantissa limbs on the current 64-bit target, corresponding to 64–4224 bits in 64-bit steps. Derive limits from verified source constants when adding another target. Key context reuse by precision and **all** behavior flags, including handling of nonfinite values and directed rounding.

Inspect the pinned implementation before sharing contexts across tasks. Until immutability during operations is established, use task-owned contexts and workspaces; child tasks must not inherit a mutable parent's workspace. Hoist acquisition and validation outside bulk loops. Define deterministic cleanup for bounded internal workspaces where practical, with safe fallback ownership.

Support for infinities and NaNs is a context capability, not merely a storage encoding. Select and test flags consistent with the advertised Julia predicates and arithmetic. Distinguish supported special values from errors and unavailable operations.

**M1 decision:** one shared, immutable context per limb count, created in `__init__` (the pinned `src/nfloat` never assigns to a context during arithmetic) with flags `NFLOAT_ALLOW_UNDERFLOW` only. With `ALLOW_INF|ALLOW_NAN` the pinned `nfloat_add(Inf, 1)` returns NaN and `nfloat_mul` returns `GR_UNABLE` for every special operand (including `0*0`), so `NFloat` is finite-only: conversion of `Inf`/`NaN` throws `DomainError`, division by zero throws `DivideError`. `nfloat_div` truncates (error under 1 ulp) and is not correctly rounded.

### 7.3 Status and numerical guarantees

For `dNb` operations returning a status, `GR_DOMAIN` means the input is disjoint from the function's domain (`DomainError`) and `GR_UNABLE` means it is only partly inside or undecidable; FLINT leaves the output **unspecified** in that case, so the wrapper writes the whole real line explicitly, element by element for vector kernels (whose statuses are OR-combined). `dNb_cmp` returns `GR_UNABLE` when the order is not certain, including balls that touch at an endpoint.

Maintain an operation capability table that identifies the C entry point, supported options, error bound or enclosure guarantee, special values, and failure behavior.

| Result from C | Checked Julia behavior |
| --- | --- |
| Successful arithmetic | Return the value or destination. |
| Domain failure from a status-returning operation | Apply the operation's published domain policy; throw `DomainError` where the input is outside a point operation's domain. |
| Unsupported algorithm or requested option | Throw a descriptive error identifying the operation and family. |
| Documented indeterminate/unbounded ball result | Preserve that enclosure result and expose predicates to inspect it. |
| Unknown truth value | Preserve uncertainty through the named predicate's contract; never coerce it to proven true. |

C status values may be bit sets. Handle combined and unexpected bits explicitly, using symbolic constants verified against the source. A truth enumeration is not interchangeable with a success status or a C boolean. Record whether failed destination operations leave a valid result; use scratch output when the public contract requires preserving the original destination on failure.

Do not advertise a universal rounding mode: dfloat is approximate, nfloat guarantees depend on operations and flags, ball operations enclose results, and `ArbFloat`/`AcbFloat` are correctly rounded in FLINT's strict modes. Map `RoundNearest`, `RoundToZero`, `RoundFromZero`, `RoundDown`, `RoundUp` to `ARF_RND_NEAR`, `ARF_RND_DOWN`, `ARF_RND_UP`, `ARF_RND_FLOOR`, `ARF_RND_CEIL`; pass the mode as an argument, never through global state; do not use the relaxed modes (`ARF_RND_FAST`, `ARF_RND_ACCURATE`) or `approx` kernels in the first release. Before publishing "correctly rounded" for an operation, confirm it in the pinned documentation and with a differential test (the pinned `acf` introduction and its `acf_div`/`acf_sqrt` entries disagree). Reject unsupported requested modes. Avoid automatic fallbacks through `BigFloat` that silently change guarantees, exponent range, or performance.

**M2 decisions.** Conversions never use a generic `Real` fallback: each source type has an explicit method and rounds once, to nearest, at the target precision. `show` prints a constructor expression; point types rebuild the identical value, ball types a containing ball. Mixed arithmetic with machine numbers keeps the FLINT operand's type (explicit methods; `Bool` is left to Base to avoid ambiguity). The operation capability table is [capability_table.md](capability_table.md).

## 8. Specify Julia semantics before adding broad fallbacks

### 8.1 Equality, uncertainty, and ordering

For point formats, compare represented values rather than raw components. For `ArbFloat`, test `arf_is_nan` before calling `arf_cmp`/`arf_equal`: FLINT's comparisons return 0 when an argument is NaN and `arf_equal` treats NaN as equal to itself, which is not Julia's `==`. Dfloat expansions may have multiple representations of one value. Establish normalization and special-value rules before implementing equality, ordering, and hashing.

For balls (`DFloatBall`, `ArbBall`, `AcbBall`), use explicit certainty semantics. For `DFloatBall`, `==` maps to `dNb_equal` (true only for exact equal balls), `!=` to disjointness (`!dNb_overlaps`), `contains`/`overlaps` to `dNb_contains`/`dNb_overlaps`, and `<`, `<=`, `>`, `>=` to exact endpoint comparison (`dNb_cmp` reports `GR_UNABLE` for touching balls, so it only cross-checks); every form of the whole real line canonicalises to `[0±∞]` for `isequal` and `hash`:

- `==` means the operands are proved to be the same singleton value.
- `!=` means the operands are proved unequal, using disjointness where appropriate. Implement this explicitly; it must not accidentally inherit `!(x == y)`.
- `<`, `<=`, `>`, and `>=` mean the respective relation is proved for the represented sets. Implement both directions and non-strict relations directly; do not derive them by negating another uncertain predicate.
- `contains` and `overlaps` describe enclosure relations. Document their argument order and treatment of indeterminate values.

Overlapping uncertain inputs can make both equality and inequality false. A nonsingleton ball can fail `x == x`. These are deliberate departures from scalar assumptions and must appear prominently in the user documentation and tests. Generic algorithms that require reflexive scalar equality or a total numerical order are not automatically valid for balls.

Use `isequal` for a documented equivalence relation on normalized represented enclosures, including special values. It must be reflexive, symmetric, and transitive, and mixed singleton/point comparisons must agree with the chosen numeric identity. Make hashing obey `isequal(x, y) => hash(x, h) == hash(y, h)` for every seed h across every supported mixed type. Do not include precision metadata when it does not affect equality, or hash an unnormalized component tuple.

Implement numeric hashing without expanding enormous exponents into impractically large integers. Validate it against Julia integers, rationals, and floating-point values where mixed equality is supported. Mutable owners cannot be changed while serving as dictionary keys.

Provide a Julia-compatible `isless` for point formats, including special values. Reject numerical sorting of uncertain balls rather than inheriting midpoint order. A separately named enclosure sort key may provide deterministic presentation order without claiming numerical order.

### 8.2 Conversion, promotion, and constants

| Conversion or operation | Required policy |
| --- | --- |
| Integer to fixed point | Document rounding and overflow behavior; use exact native conversion paths when available. |
| Point to ball | Produce an enclosure containing the input's represented value. |
| Ball to ball or real ball to complex ball | Preserve containment, including any precision reduction. |
| Nonsingleton ball to point | Reject implicit information loss; require explicit midpoint or endpoint extraction. |
| Exact conversion requested but impossible | Raise `InexactError`. |
| Decimal parsing | Parse directly at the destination precision/format; never route through `Float64`. |
| Mathematical constant to ball | Use a rigorous FLINT enclosure at the requested precision. |

A point format need not represent every integer or decimal exactly. Define the intended rounding for ordinary point conversion separately from an exact-conversion request; do not promise universal bitwise agreement with MPFR.

Begin promotion narrowly: machine floats and integers within a family; larger component count for mixed dfloat formats; larger supported precision for mixed nfloat formats. Promotion must produce fully concrete nfloat types. Promote point inputs to balls only through containing conversion. Promote real balls to `AcbBall` when mixed with complex balls. For the arb types: equal kinds promote to the larger `P`; `DFloat` and `NFloat` convert exactly into `ArbFloat` at the larger precision; a point with a ball gives the ball type; real with complex gives the complex type.

Keep dfloat/nfloat cross-family promotion explicit until precision and exponent-range policy is settled. Avoid blanket promotion rules over `Real` or `Number` that capture unrelated packages. Test promotion symmetry, termination, concrete return types, and behavior when one operand has a very large exponent.

### 8.3 Base methods, domains, and display

Audit inherited `AbstractFloat` fallbacks. Implement `eps`, `nextfloat`, `prevfloat`, `significand`, `exponent`, `floatmin`, and `floatmax` only with a coherent format-specific meaning. Nonsingleton balls have no unique neighboring scalar value. A noncanonical expansion also needs a precise representable-value definition before a neighbor operation is meaningful. Explicitly reject unsupported cases.

Document signed-zero behavior, exponent range, infinities, NaNs, indeterminate enclosures, and exceptions separately for each family. `ArbFloat` has no negative zero, returns NaN for a nonzero value divided by zero, and has an unbounded exponent (no `floatmax`/`floatmin`; `eps`, `nextfloat` and `prevfloat` are defined at `P` bits). For real-domain failures, do not silently promote to complex arithmetic; users select `AcbBall` explicitly. Complex functions must preserve FLINT's enclosure and branch-cut conventions.

Show balls with uncertainty. Distinguish a display intended for readability from a representation intended for reconstruction. Define round-trip guarantees separately for fixed values, midpoint text, and entire enclosures. Free C formatting buffers reliably even when Julia string construction throws.

**M3 decisions.**

- Points compare by exact value across precisions, families (`DFloat`, `NFloat`, `ArbFloat`, `AcbFloat`) and against Julia numbers (`Bool`, machine integers and floats, `Int128`, `BigInt`, `BigFloat`); precision is never part of equality or the hash. `hash` of a real point is the `BigFloat` hash of its exact value, so it equals the hash of the equal `Int`, `Float64` or `BigFloat`; a complex value with zero imaginary part hashes as its real part. A point zero is `+0`: it is `isequal` to `0.0` but not `-0.0`.
- Ball `==`, `!=`, `<`, `<=`, `>`, `>=` are proofs (`arb_eq`/`arb_ne`/`arb_lt`/..., `acb_eq`/`acb_ne`) and return `false` when unproved; `isequal` is representation equivalence; an exact ball is `isequal` and hashes like its midpoint. Every indeterminate ball (NaN midpoint or infinite radius, and the whole real line of `DFloatBall`) is one value for `isequal` and `hash`, and is never `isequal` to a point or number. `ArbBall(Inf)` is an exact infinite ball; `DFloatBall(Inf)` is the whole real line.
- Balls have no `isless`, `min`, `max`, `sort`; `sortkey` gives a deterministic presentation order. `isapprox` and neighbours (`eps`, `nextfloat`, ...) are rejected for balls.
- Promotion is implemented for the cases in `src/promotion.jl` only; `convert` narrows a point only when exact (`InexactError`) and a ball with containment. Converting a ball to a point never happens implicitly (`ArgumentError`).
- `AbstractFloat` audit (`src/basefloat.jl`): `eps`, `nextfloat`, `prevfloat`, `significand`, `exponent` for `ArbFloat` and `NFloat`; `eps(::Type)` only for `DFloat`; `floatmin`/`floatmax` rejected everywhere; `typemin`/`typemax`, rounding and elementary functions are undefined.

## 9. Add containers and bulk arithmetic

### 9.1 Fixed-format arrays

Use ordinary dense arrays of fully concrete isbits values (`DFloat{N}`, `DFloatBall{N}`, `NFloat{L}`) where their layout matches the native format; `dNb` vector kernels apply to `DFloatBall` arrays. Verify stride and alignment before passing spans to FLINT. Handle empty arrays and array lifetime correctly. Pass only supported contiguous spans to kernels; use a documented scalar fallback or temporary for strided and noncontiguous views.

Use the C vector kernel's exact indexing and length conventions. A Julia array's logical shape does not prove compatibility with a C matrix representation. Introduce matrix-specific storage only after checking row/column layout and native ownership.

### 9.2 Packed ball containers

Prototype fixed-size packed owners using FLINT's vector allocation/init/clear functions. One owner clears the entire allocation. Julia scalar indexing returns an independent value; explicit borrowed indexing retains the container and does not clear elements.

Implement `eltype`, size/axes, iteration, copying, bounds behavior, assignment, and `similar` consistently before adding optimized broadcast. `setindex!` performs semantic copying into an initialized destination, never copying an owning pointer. Define how element working precision is represented and retained: begin with one container working precision, applied to copied-out values and destination operations.

Prevent resize or reallocation while references can be borrowed; a fixed-size owner is the simplest first implementation. Specify overlapping source and destination behavior for bulk operations. Exact destination/input aliasing and partial-span overlap are separate cases and require separate evidence.

Prioritize vector add/multiply, dot products, and measured matrix workloads. A fused or native dot kernel may have different rounding behavior from a scalar accumulation; publish its own guarantee. Add `@inbounds` or `@simd` only after establishing indexing and independence invariants.

## 10. Verification and performance evidence

### 10.1 Required verification layers

| Layer | Evidence required |
| --- | --- |
| Binary and ABI | Source/artifact identity, symbols, sizes, offsets, alignment, integer widths, and compatible runtime target. |
| Ownership | Independent copies, failure cleanup, allowed aliasing, parent retention, GC during borrowed operations, and no double clear. |
| Point arithmetic | Exact examples, exceptional inputs, and error checks matching each operation's actual guarantee. For `ArbFloat`/`AcbFloat`: bit-for-bit agreement with MPFR at equal precision in each rounding mode, the inexact flag, and the mantissa-length invariant. |
| Enclosures | Exact rational cases, independently certified bounds, uncertain domains, cancellation, zero-crossing divisors, and complex branch cuts. |
| Julia contracts | Inference, concrete promotion, equality/hash laws, unsupported fallback behavior, parsing/display, and array semantics. |
| Precision and concurrency | Scoped restoration, nested scopes, child-task behavior, distinct concurrent defaults, and independent destinations. |
| Performance | Warmed runtime, Julia allocation counts, native memory behavior where relevant, copying, and compilation cost. |

Use the public interface as the main test surface. Internal ABI and ownership seams need focused tests because errors there can invalidate all public results. Generate tests from contracts and independent examples, not by repeating the implementation's formulas.

A high-precision approximate value is useful differential evidence, but it is not by itself a rigorous containment oracle. Use proved bounds or exact references for certified claims. Require bitwise MPFR equality only for operations specified as correctly rounded in the same mode.

Test zero, cancellation, signs, representable boundaries, underflow/overflow, nonfinite encodings, huge exponents, minimum/maximum supported precision, and invalid precision. Use bounded GC stress and native diagnostics where available. Stable RSS does not establish correct clearing, and `@allocated` does not measure allocations made inside C.

### 10.2 Benchmark method

Maintain a separate BenchmarkTools environment and compare:

| Workload | Comparisons and measurements |
| --- | --- |
| Scalar add/multiply/divide/sqrt | Checked Julia operation versus an equivalent direct call; absolute call overhead and allocations. |
| Construction and contexts | Initialization, cleanup, conversion, context creation, and context reuse measured separately. |
| Mutable destinations | Allocating arithmetic versus reused initialized storage, including capacity-growth behavior. |
| Elementary functions | Runtime versus precision and guarantee, with BigFloat/Arblib comparisons where semantics match. |
| Bulk work | Scalar loops versus vector/dot/matrix kernels; throughput, copies, and memory footprint. |
| Specialization | First-use and warmed behavior for dfloat N=1–4 and representative nfloat precisions. |

Warm up functions, interpolate inputs, avoid constant folding, and record thread counts and artifact identity. Evaluate nfloat at supported precisions such as 64, 128, 256, 1024, and 4096 bits; validate these against the target's limb constraints.

Aim for zero warmed Julia heap allocations on fixed-format arithmetic and suitably sized reusable ball destinations when the representation supports it. Report C allocations separately. Do not impose an arbitrary percentage-overhead target on tiny kernels. A performance claim needs a reproducible workload, comparable numerical guarantees, and recorded results.

Use Julia threads only over independent writable destinations. Verify context behavior against the selected source and avoid nested oversubscription with FLINT or BLAS threads. Do not modify process-global thread settings in scalar methods.

## 11. Execute the work in reviewable milestones

| Milestone | Implementation deliverables | Acceptance criteria |
| --- | --- | --- |
| **M0 — environment and binary contract** | Main-package dependency setup; binding inventory for the first operations; ABI probe; symbol audit; documented local setup. | A clean compatible-host environment loads the pinned wrapper; every required first-operation declaration and layout has evidence. Portable-build work is tracked separately. |
| **M1 — representation prototypes** | One dfloat add, one dfloat-ball add (with the `GR_UNABLE` → whole real line rule), one nfloat add/context, and one add with complete ownership for each of ArbFloat, AcbFloat, ArbBall and AcbBall; resolved concrete nfloat layout. | All seven paths construct, calculate, copy as applicable, and clean up correctly; inference and allocation/copying measurements establish the representation choice. |
| **M2 — scalar foundation** | Constructors, core arithmetic, precision rules, classification, basic conversion, parsing, display, and ball destination methods. | Each family has a usable tested path; domain/status handling and special values match the operation table. No guessed layouts or unresolved ownership remain. |
| **M3 — Julia numeric contracts** | Scoped precision; explicit comparison/inequality behavior; `isequal`/hash; narrow promotion; audited Base fallbacks and complex behavior. | Contract tests pass, including uncertainty examples, mixed hashing, task isolation, and concrete promoted types. Documentation identifies unsupported generic algorithms. |
| **M4 — bulk arithmetic** | Concrete fixed-format arrays; packed ball vectors; explicit borrowing; selected native kernels. | Container semantics, aliasing, lifetime, empty/strided inputs, and precision behavior are tested; benchmark evidence supports every specialized path. |
| **M5 — function expansion and release** | Selected elementary/special functions; portable artifacts; clean CI/docs setup; capability and benchmark reports. | Every advertised function and target passes its required evidence; users can install without a compiler or development-host assumptions. |

All seven types participate in M1 and M2. A family-specific issue may delay its completion without forcing unrelated work to stop, but the first complete release includes all seven. Do not expand the function inventory faster than it can be verified.

For each implementation change, describe the caller-visible behavior, affected guarantees, ownership/aliasing implications, verification, and relevant measurements. Keep generated declarations separate enough for a reviewer to inspect semantic changes. Update the inventory and user-facing capability table in the same change as each new operation.

## 12. CI, documentation, and release readiness

The current workflow lists Julia 1.13, stable, and prerelease versions on x64/x86 Linux. This is scaffolding, not a verified support matrix. The host-tuned artifact cannot support that matrix as supplied.

Establish one of two explicit CI paths during development: a compatible controlled runner using the local artifact, or a build job producing an appropriate artifact for the test runner. For release, use portable, audited artifacts and test each supported target. Remove or exclude unprovided targets rather than letting incompatible native code run. Include Windows, 32-bit, or other architectures only after their Julia builds, native dependencies, layouts, and numerical behavior have been verified.

Documentation has its own environment. Ensure it resolves the intended wrapper and run it from a clean setup; do not rely on a developer's main-project manifest. Keep expensive memory diagnostics and noisy speed comparisons in separate jobs or controlled runners. Ordinary CI should run deterministic numerical, ownership, ABI, and contract checks.

Before release, require all of the following:

- All seven types implement the documented scalar foundation and numerical guarantees.
- Every foreign declaration resolves against supported artifacts and every mirrored layout has matching probe evidence.
- Owners and borrowed references satisfy cleanup, copying, aliasing, and lifetime tests.
- Conversion, promotion, uncertainty comparisons, hashing, precision, and unsupported Base behavior are explicit and tested.
- Documented installation works on a clean supported machine without compiling FLINT during ordinary loading.
- Wrapper version constraints, source resolution, real artifact checksums/download locations, and licenses are complete.
- Claimed platforms have compatible portable builds and passing tests.
- Generated files regenerate without drift; documentation and examples build against the intended dependency.
- Published performance statements identify workload, accuracy, environment, and artifact.

Keep optional interoperability in Julia extensions when a concrete need arises. Do not make Nemo or Arblib mandatory runtime dependencies, share their owning pointers without an established lifetime contract, or introduce an allocator abstraction in anticipation of hypothetical backends.

## 13. Upgrade and maintenance procedure

Treat an upstream or wrapper update as a binary-contract change until verified:

1. Select and pin the new source revision; record its upstream version and source checksum.
2. Review changed headers, inline helpers, status meanings, context options, and numerical guarantees used by the inventory.
3. Build artifacts with appropriate toolchains; verify library dependencies, SONAME, and target restrictions.
4. Re-run layout and symbol probes before any unsafe Julia call using a changed representation.
5. Regenerate declarations, inspect the diff, and run numerical, lifetime, Julia-contract, and container tests.
6. Compare controlled performance baselines and investigate material regressions or changed guarantees.
7. Update wrapper constraints, capability tables, source/build provenance, artifact metadata, and support documentation together.

Never select a moving `main` branch at package load time. Keep the old supported artifact usable until its replacement passes the required checks. Changes to precision defaults, ball comparison behavior, conversion loss, or public representation parameters require an explicit compatibility review even when the C ABI remains unchanged.

## 14. Reference material and remaining decisions

Use these references in order:

1. The pinned source archive and matching installed headers recorded in [Source.toml](../FlintFloat.jl/FLINT_jll/Source.toml).
2. The local wrapper's [installation/build guide](../FlintFloat.jl/FLINT_jll/README.md), [Julia tests](../FlintFloat.jl/FLINT_jll/test/runtests.jl), and [C smoke test](../FlintFloat.jl/FLINT_jll/test/smoke.c).
3. [FLINT documentation](https://flintlib.org/doc/index.html) and the [upstream source repository](https://github.com/flintlib/flint), interpreted against the selected revision.
4. Julia's installed foreign-call, numeric-interface, and `Base.ScopedValues` documentation for the supported Julia version.
5. Nemo and Arblib as implementation precedents for owners, borrowed references, and ball semantics; validate adaptations against this guide's contracts.

Resolve these decisions at their designated milestone rather than leaving them implicit in implementation:

| Decision | Deadline | Required evidence |
| --- | --- | --- |
| Concrete nfloat representation and array construction interface | M1 — **resolved**: `NFloat{L}` = `exp::Int`, `sign::UInt`, `d::NTuple{L,UInt}` (`test/abi_tests.jl`; 0 allocations, `benchmark/results/m1_scalar.txt`). Array construction deferred to M4. | Valid layout, concrete inferred types, allocation/copying measurements. |
| Context sharing versus task-owned reuse | M1 — **resolved**: shared immutable contexts for `+ - * /` (source audit; 8-task test). Re-audit before adding functions that may use workspaces. | Matching-source audit and concurrent tests; conservative ownership until verified. |
| Exact supported function/rounding/flag set | Before each operation is added | Inventory entry, source guarantee, and numerical test cases. |
| Hash normalization and mixed-type identity | M3 | Equality/hash laws, including huge exponents and special values. |
| First native bulk kernels | M4 | Real workloads, aliasing/layout evidence, and measurable improvements. |
| Portable artifact delivery and supported platforms | Before public release | Built/audited binaries and clean-machine installation/test results. |

This sequence keeps the managed numeric interface deep: callers obtain useful arithmetic and containment behavior from a small interface, while implementation details and verification remain local to the code that owns them.
