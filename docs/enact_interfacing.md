# FlintFloats development guide

This guide defines the implementation sequence, numerical contracts, architecture, and release criteria for FlintFloats. It develops the recommendations in [the interfacing plan](plan_interfacing.md) into work that can be implemented and reviewed in small, verifiable changes.

The objective is a Julia interface to FLINT's **dfloat (plain and ball), nfloat, arb, and acb** families, with the arb families exposed both as floating-point types (`arf`, `acf`) and as balls (`arb`, `acb`), that combines efficient scalar and bulk arithmetic with clear source and reliable resource management. Julia **1.13** is the minimum supported version. The real families subtype `AbstractFloat`; the complex types `AcbFloat` and `AcbBall` are `<: Number` because `AbstractFloat <: Real`. Point types end in `Float` (`DFloat`, `NFloat`, `ArbFloat`, `AcbFloat`); ball types end in `Ball` (`DFloatBall`, `ArbBall`, `AcbBall`); a point type and its ball share one parameter. **Precision is a type parameter for every type.** The full interface contract is in [float_interfacing.md](float_interfacing.md).

Descriptions of the existing repository are distinguished from requirements for future implementation. Proposed Julia constructors and operations below are interface specifications, not claims that those methods already exist.

**Resume point:** M0–M3, M4a–M4c, reusable scratch, and the packed-interface follow-ups are
implemented: copied indexing, `eachborrow`, bounded assignment broadcast, sum, conjugating dot,
and `sum(abs2, v)`. The five selected M5 elementary functions now support all seven scalar families;
[their contracts and audits](elementary.md) distinguish strict point rounding, approximation, and
rigorous enclosures. Latest focused validation: 712 inline elementary + 2,227 adjacent Base-float
checks, documentation/doctests, 374-symbol audit, and unchanged regeneration. The 13,709 M4c
full-suite result remains historical. [Both](checkpoint.md) [checkpoints](checkpoint_gpt.md) record
completed checks and current limits. Compatible CI configuration and local fresh-project install/docs evidence are implemented;
next finish portable build/audit, target tests, and external CI execution.

## 1. Starting point and development priorities

### 1.1 Existing implementation

| Area | Current state | Consequence for development |
| --- | --- | --- |
| Main Julia package | Seven scalar types, M0–M3, M4a–M4c bulk operations, packed ball owners/borrowing, and reusable nfloat scratch are implemented | Complete compatible CI and portable release gates; extend mappings/matrices only on measured need. |
| Julia compatibility | Main project requires Julia 1.13; precision is in the type | Use `with_precision(f, bits)` as a `Val` function barrier; there is no scoped runtime precision default. |
| Local binary package | [`FlintFloat.jl/FLINT_jll`](../FlintFloat.jl/FLINT_jll/README.md) contains a working loader, native artifact, headers, source archive, and build tools | Use this package for host development rather than waiting for a published dfloat-capable wrapper. |
| Pinned FLINT source | `82c40b299084b92299c2d8dac464e39d6743fce4`, reporting `3.7.0-dev` | Consult this revision's declarations and implementation when writing bindings. |
| Local wrapper version | `301.690.0+0`, shared-library ABI 25 | Do not equate its layout or compatibility with the reference wrapper's ABI 24. |
| Existing validation | Binary/layout/symbol checks and 6,540 Julia tests passed at the M3 checkpoint; scalar benchmarks are recorded | Preserve those contracts; add container and per-kernel evidence for M4. Sampled numerical tests are not universal proofs. |
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

The main `Project.toml` already declares `FLINT_jll`, pins `=301.690.0`, and resolves the nested package through `[sources]`. Instantiate the existing environment and install its bundled artifact:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.build("FLINT_jll")'
```

Review dependency resolution in the manifest. Retain the exact wrapper-version constraint until additional builds have been validated. Keep runtime dependencies limited to the wrapper and required standard libraries. Put BenchmarkTools and generator tools in their own development environments.

The local package uses the official `FLINT_jll` UUID. Developing its path replaces that dependency in the selected environment. Use an isolated environment when examining Nemo or Arblib so their dependency requirements do not accidentally select or constrain the development binary.

The main and documentation projects already declare local `[sources]` paths; the generator and benchmark environments also need the intended wrapper resolution. Instantiate each environment separately. A developer manifest alone is insufficient for reproducible setup. Before distribution, select a reproducible source-resolution mechanism for the intended deployment and replace the host-specific artifact with validated portable artifacts.

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

**Resolved nfloat representation (M1).** `NFloat{L}` uses the **limb count** as its single parameter: `exp::Int`, `sign::UInt`, `d::NTuple{L,UInt}` with `precision(NFloat{L}) = 64L` on the verified 64-bit target. The C probe verifies `NFLOAT_HEADER_LIMBS = 2` and 1–66 supported mantissa limbs. `NFloat{2}` is a concrete isbits type suitable for packed `Vector{NFloat{2}}` storage. `NFloatType(bits)` rounds the requested bit count up to whole limbs (`NFloatType(128) == NFloat{2}`); validate the supported range before native use. `NFloat{128}` denotes 128 limbs and is outside the supported range, not a partially specified 128-bit type. The earlier two-parameter prototype is superseded.

### 3.2 First supported operations

Deliver a small, useful interface across all families before adding large function sets:

- Constructors from integers and machine floats; explicit precision where relevant.
- Copying, `zero`, `one`, `precision`, classification predicates, parsing, and display.
- Addition, subtraction, multiplication, division, negation, absolute value, and square root where their domains are supported.
- Explicit conversions and a narrowly defined set of mixed arithmetic methods.
- For `AcbFloat` and `AcbBall`: `real`, `imag`, `conj`, `abs2`, and `abs`; the modulus returns `realtype(T)` (`ArbFloat` value or `ArbBall` enclosure). `AcbFloat` `abs` and `abs2` are correctly rounded although FLINT exports no `acf_abs` (see `src/acf.jl`).
- For `ArbFloat` and `AcbFloat`: a trailing `RoundingMode` argument on rounding operations, and `_inexact!` destination variants returning FLINT's inexact flag.
- For mutable owned destinations (`ArbFloat`, `AcbFloat`, `ArbBall`, `AcbBall`): destination-first `add!`, `sub!`, `mul!`, and `div!`, returning the destination.

Destination methods and their `_inexact!` variants are qualified as `FlintFloats.add!`, `FlintFloats.mul!`, etc.; they are not exported, avoiding conflicts such as `LinearAlgebra.mul!`.

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

Use the existing organization below, adding container code in M4. The shared `_result`/`_with`/`_status` protocol proposed in the interface contract has not been factored: current family implementations carry these responsibilities. Extract only the helpers needed to make safe container operations possible, with scalar regression checks; a package-wide refactor is not a prerequisite for M4.

| Location | Responsibility |
| --- | --- |
| `src/FlintFloats.jl` | Module declarations, imports, include ordering, and exports. |
| `src/libflint/LibFlint.jl` | Private adapter module and library product import. |
| `src/{dfloat,dfloatball,nfloat,arf,acf,arb,acb}.jl`, `src/storage.jl` | Verified inline/owner layouts and pointer adapters; checked by `test/abi_tests.jl`. |
| `src/libflint/generated/` | Checked-in foreign declarations grouped by family. |
| `src/storage.jl` | Ownership, cleanup, and pointer-conversion helpers. |
| `src/precision.jl` | Validated precision parameters, `DEFAULT_PRECISION`, `with_precision`, and context policy. |
| `src/dfloat.jl`, `dfloatball.jl`, `nfloat.jl`, `arf.jl`, `acf.jl`, `arb.jl`, `acb.jl` | Family values and their arithmetic/semantic rules. |
| `src/typegrid.jl` | `pointtype`, `balltype`, `realtype`, `complextype`, and the guarantee/storage traits. |
| `src/conversions.jl`, `promotion.jl`, `compare.jl`, `basefloat.jl` | Cross-family conversion, narrow promotion, comparisons/hash, and audited Base methods. |
| `src/arrays.jl` | Shared inline vector validation and dfloat dispatch (M4a/M4b). |
| `src/reusable.jl` | Exported `NFloatWorkspace`, growth/exclusive-use guard, shared nfloat kernels and commit-on-success. |
| `src/packed.jl` | Fixed-size `PackedBallVector`, `BorrowedBall`/`borrow`, lifetime/semantic copying, native ball-add and borrowed arithmetic. |
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

Complex owning-scalar `set!` is implemented for both `AcbFloat` (strict explicit modes) and
`AcbBall` (containing copy), including cross precision and exact aliasing. It uses the already
audited native `*_set_round` bindings and allocates no warmed Julia scratch.

The scalar semantic deepcopy path is implemented in `src/storage.jl`: it uses native copy and the
caller's identity dictionary to preserve alias graphs without sharing storage with the source.
`ext/FlintFloatsSerializationExt.jl` activates only with the Serialization stdlib and rejects writing
or typed reconstruction of native owners and borrowed references. Inline values retain ordinary
serialization. Focused checks cover heap-backed mantissas, source cleanup, graph aliases, extension
activation, nested rejection, and inline round trips (81 checks plus 17 existing ownership checks).

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
| Destination arithmetic | Use the destination type's precision; no public precision override is currently implemented. Internal guard precision must still produce a result satisfying the destination invariant. |
| Copy/part extraction | Preserve the source type unless an explicit documented conversion (`ArbBall{Q}(x)`) requests another. |

Mixed arithmetic with integers and machine floats keeps the ball operand's type. Validate the precision parameter once, when the type is first instantiated, as an integer at or above the FLINT minimum and representable by the verified C type; pass it to C as a constant.

`precision(x)` reports the type's precision, not a certificate of correct digits. Increasing working precision cannot recover information lost in an input enclosure. Precision-changing conversions preserve containment.

Provide `with_precision(f, bits)`, which calls `f(Val(bits))`, as the function barrier for dynamic (adaptive) precision: the body is a method on `Val{P}`, compiled once per precision and free of dynamic dispatch. Use a documented 256-bit `DEFAULT_PRECISION`, the compile-time constant currently defined in `src/precision.jl` (no preference mechanism is implemented), so `ArbBall(x)` is type-stable. Keep it independent of `BigFloat` settings. There is no scoped runtime default and no `setprecision`: runtime state would make constructor return types depend on it. Each new `P` compiles the methods it touches. M1 recorded roughly 6–8 ms first-use latency per new precision, followed by microsecond warmed calls; the proposed hybrid `P = 0` fallback was not needed and is not supported. Consider precompiling common precisions only when measurements justify it. `ArbBall{P}` and `AcbBall{P}` have the same 48/96-byte layout at every `P`.

Test that code inside the `with_precision` barrier infers concretely and allocates nothing beyond results, that nested barriers with different precisions are independent, and that concurrent tasks using different precisions do not interact (precision is part of the type, so there is no shared state).

The type determines precision for every family. Changing precision constructs a value of another concrete type, for example `ArbBall{Q}(x)`; no `withprec` helper is implemented. dfloat's nominal precision does not imply uniform relative accuracy, especially around subnormal values and cancellation.

### 7.2 nfloat contexts

Initialize contexts at runtime and keep them alive through every dependent operation. Validate P against the selected artifact's limb width and supported range. The pinned source permits 1–66 mantissa limbs on the current 64-bit target, corresponding to 64–4224 bits in 64-bit steps. Derive limits from verified source constants when adding another target. Key context reuse by precision and **all** behavior flags, including handling of nonfinite values and directed rounding.

Inspect the pinned implementation before sharing contexts across tasks. Until immutability during operations is established, use task-owned contexts and workspaces; child tasks must not inherit a mutable parent's workspace. Hoist acquisition and validation outside bulk loops. Define deterministic cleanup for bounded internal workspaces where practical, with safe fallback ownership.

Support for infinities and NaNs is a context capability, not merely a storage encoding. Select and test flags consistent with the advertised Julia predicates and arithmetic. Distinguish supported special values from errors and unavailable operations.

**M1 decision:** one shared, immutable context per limb count, created in `__init__` (the pinned `src/nfloat` never assigns to a context during arithmetic) with flags `NFLOAT_ALLOW_UNDERFLOW` only. With `ALLOW_INF|ALLOW_NAN` the pinned `nfloat_add(Inf, 1)` returns NaN and `nfloat_mul` returns `GR_UNABLE` for every special operand (including `0*0`), so `NFloat` is finite-only: conversion of `Inf`/`NaN` throws `DomainError`, division by zero throws `DivideError`. `nfloat_div` truncates (error under 1 ulp) and is not correctly rounded.

### 7.3 Status and numerical guarantees

For `dNb` operations returning a status, `GR_DOMAIN` means the input is disjoint from the function's domain (`DomainError`) and `GR_UNABLE` means it is only partly inside or undecidable; FLINT leaves the output **unspecified** in that case, so the scalar wrapper writes the whole real line explicitly. Do not assume vector entry points return scalar-style statuses: the pinned `dfloat.h` declares `_dNb_vec_*` arithmetic with `void` returns. Audit each kernel's failure semantics before binding it. If a selected status-returning bulk kernel OR-combines element statuses, that aggregate cannot identify failed elements; use a verified conservative policy or checked scalar fallback, and never read unspecified outputs. `dNb_cmp` returns `GR_UNABLE` when the order is not certain, including balls that touch at an endpoint.

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

- Points compare by exact value across precisions, families (`DFloat`, `NFloat`, `ArbFloat`, `AcbFloat`) and against Julia numbers (`Bool`, machine integers and floats, `Int128`, `BigInt`, `BigFloat`); precision is never part of equality or the hash. `hash` of a real point uses the `BigFloat` hash of its exact value when its exponent is within MPFR's range, so it equals the hash of equal Julia numbers; outside that range, collision with Inf is allowed; a complex value with zero imaginary part hashes as its real part. A point zero is `+0`: it is `isequal` to `0.0` but not `-0.0`.
- Real-ball `==`, `!=`, `<`, `<=`, `>`, `>=`, and complex-ball `==`, `!=` are proofs (`arb_eq`/`arb_ne`/`arb_lt`/..., `acb_eq`/`acb_ne`) and return `false` when unproved; complex balls have no numerical ordering; `isequal` is representation equivalence; an exact ball is `isequal` to and hashes like its midpoint. Every indeterminate ball (NaN midpoint or infinite radius, and the whole real line of `DFloatBall`) is one value for `isequal` and `hash`, and is never `isequal` to a point or number. `ArbBall(Inf)` is an exact infinite ball; `DFloatBall(Inf)` is the whole real line.
- Balls have no `isless`, `min`, `max`, `sort`; `sortkey` gives a deterministic presentation order. `isapprox` and neighbours (`eps`, `nextfloat`, ...) are rejected for balls.
- Promotion is implemented for the cases in `src/promotion.jl` only; `convert` narrows a point only when exact (`InexactError`) and a ball with containment. Converting a ball to a point never happens implicitly (`ArgumentError`).
- `AbstractFloat` audit (`src/basefloat.jl`): `eps`, `nextfloat`, `prevfloat`, `significand`, `exponent` for `ArbFloat` and `NFloat`; `eps(::Type)` only for `DFloat`; `floatmin`/`floatmax` rejected everywhere; `typemin`/`typemax`, rounding and elementary functions are undefined.

## 9. Add containers and bulk arithmetic

### 9.1 Fixed-format arrays

Use ordinary dense arrays of fully concrete isbits values (`DFloat{N}`, `DFloatBall{N}`, `NFloat{L}`) where their layout matches the native format; `dNb` vector kernels apply to `DFloatBall` arrays. Verify stride and alignment before passing spans to FLINT. Handle empty arrays and array lifetime correctly. Pass only supported contiguous spans to kernels; use a documented scalar fallback or temporary for strided and noncontiguous views.

Use the C vector kernel's exact indexing and length conventions. A Julia array's logical shape does not prove compatibility with a C matrix representation. Introduce matrix-specific storage only after checking row/column layout and native ownership.

### 9.2 Packed ball containers

Use fixed-size packed owners with FLINT's vector allocation/init/clear functions. One owner clears the entire allocation. **Retain copied ordinary indexing and iteration:** `v[i]` returns an independent scalar of `eltype(v)`, and `for x in v` yields independent values. Explicit borrowing retains the container and does not clear elements. Do not change these defaults to introduce implicit numeric proxies; improve the surrounding interface as specified in §9.4.

Implement `eltype`, size/axes, iteration, copying, bounds behavior, assignment, and `similar` consistently before adding optimized broadcast. `setindex!` performs semantic copying into an initialized destination, never copying an owning pointer. Define how element working precision is represented and retained: begin with one container working precision, applied to copied-out values and destination operations.

Prevent resize or reallocation while references can be borrowed; a fixed-size owner is the simplest first implementation. Specify overlapping source and destination behavior for bulk operations. Exact destination/input aliasing and partial-span overlap are separate cases and require separate evidence.

Prioritize vector add/multiply, dot products, and measured matrix workloads. A fused or native dot kernel may have different rounding behavior from a scalar accumulation; publish its own guarantee. Add `@inbounds` or `@simd` only after establishing indexing and independence invariants.

### 9.3 Next implementation: M4 in reviewable parts

**M4a–M4c are complete. Documentation, borrowed iteration, and flat in-place broadcast are implemented; sum and dot products are implemented; `sum(abs2, v)` is implemented (§9.4.4); nfloat square-root evidence is complete; M5 ball elementary functions are implemented; strict arb/acf point functions are also implemented; all seven families now implement the five selected functions; next complete compatible CI and release gates.** Ordinary Julia arrays already store concrete inline types; dot accumulation and measured matrix follow-up retain their separate numerical contracts. M4a is implemented in `src/arrays.jl`: qualified `FlintFloats.add!`/`mul!` accept matching-format `DFloat`/`DFloatBall` vectors, with ordinary/strided destinations, checked scalar fallbacks, and a native contiguous ball-add path at length ≥ 4. Exact aliasing uses `===`; other possible destination/input overlap is rejected. Gather/repeated-index destinations are rejected because they do not guarantee independent slots. M4b extends the same interface to `NFloat{L}`, with native aligned contiguous input paths and checked scalar fallbacks. It uses initialized private scratch and commits only after successful arithmetic, preserving the destination on numerical or input-read failure. M4c adds `PackedBallVector`, copied indexing, explicit `borrow` references, native ball-add, and borrowed scalar multiply. M4d sum and dot products are implemented; mapped reductions and measured matrix work remain. The checkpoints summarize this state.

| Part | Deliverable | Acceptance evidence |
| --- | --- | --- |
| **M4a — array contract and first inline kernel (complete)** | Define destination-first elementwise add/multiply contracts over same-format vectors. Begin with a checked scalar implementation and one audited contiguous vector-add path for `DFloatBall{N}`; use `DFloat{N}` instead if the ball kernel's guarantee cannot yet be established. | Correct empty/singleton/ordinary vectors, concrete element types, length/axes checks, initialized outputs, dfloat capability gate, permitted aliasing, and a benchmark against the corresponding scalar loop. |
| **M4b — nfloat vectors (complete)** | Extend the same interface to `Vector{NFloat{L}}`; bind selected `_nfloat_vec_add`/`_nfloat_vec_mul` kernels after verifying stride, status, flags, and context behavior. Hoist context lookup out of loops. | Multiple supported limb counts, finite-only/domain/underflow/overflow behavior, input preservation, failure policy, overlap and strided fallback tests, and measured copy/context costs. |
| **M4c — packed ball owners and borrowing (complete)** | Add fixed-size `ArbBall{P}` and `AcbBall{P}` vector owners, semantic indexing/assignment/copying, explicit borrowed references, then selected native vector arithmetic. | One matching vector clear per allocation, safe partial-construction cleanup, independent copied elements, parent retention under GC, bounds checks, precision/containment, and destination alias tests. |
| **Packed-interface follow-up (§9.4; complete)** | Optimized flat and bounded nested in-place broadcast expressions without changing scalar or ordinary iteration semantics. | Independent copies, stable parent-retaining references, Base broadcast compatibility/alias handling, bounded scratch and specialization, and focused numerical/allocation evidence. |
| **M4d — reductions, dot products, and measured follow-up (sum/dot complete)** | Borrowed accumulation for `sum` and audited native/borrowed dot kernels are implemented. Selected mapped reductions follow with their own numerical contracts. | Fresh typed empty/singleton results, independent exact/certified references, cancellation, complex conjugation, strides, radius quality, and complete-operation benchmarks. Matrix work follows measured need. |

Before the first native call, settle and document these shared contracts:

- **Shape and precision:** initially require matching axes and identical concrete element types; reject mismatches before mutation. A mutating operation uses the destination precision and preserves enclosure containment. Defer mixed-precision bulk promotion until a separate policy and tests exist.
- **Empty inputs and bounds:** validate dimensions and native length conversion before pointer arithmetic. Return the destination for an empty elementwise operation without dereferencing an element pointer. Define an empty dot as the appropriate typed zero.
- **Aliasing and views:** allow exact destination/input aliasing only where the selected kernel's source supports it. Use a temporary or reject partial overlap before mutation; a forward scalar loop is not generally safe for overlapping views. Noncontiguous views need a documented checked scalar or copy fallback with the same numerical contract. Preserve all owners while raw pointers are live.
- **Failures:** specify whether a destination may be partially updated on failure. Use scratch output when promising unchanged destinations. Do not infer successful elements from aggregate status bits or publish unspecified native outputs (§7.3).
- **Borrowing:** copied indexing returns an independent scalar; borrowed indexing returns an explicit parent-retaining reference, never an independently finalized scalar owner. Fixed-size owners cannot resize. Define permitted mutation through references and reject unsupported operations before exposing them.
- **Dot semantics:** distinguish an unconjugated sum of products from Julia's conjugating complex `dot`. Audit native accumulator, initial-value, subtract, and stride arguments. Fused native accumulation need not equal a rounded scalar loop bit for bit, so validate its own error or containment guarantee.

Candidate native entry points must be checked against the pinned headers **and** exported-symbol audit: `_dNb_vec_add`/`_dNb_vec_mul` (N = 1–4), `_nfloat_vec_add`/`_nfloat_vec_mul`, `_arb_vec_init`/`_arb_vec_clear`, `_acb_vec_init`/`_acb_vec_clear`, `_arb_vec_add`/`_acb_vec_add`, and selected dot functions. The add kernels for dfloat balls and the add/multiply kernels for nfloat are implemented and audited in M4a/M4b; M4c also audits the arb/acb vector init/clear/set/add entries; the remaining entries are candidates requiring their own audits. Allocation interfaces differ: `_nfloat_vec_init` initializes supplied storage, whereas `_arb_vec_init` and `_acb_vec_init` allocate owned storage. Do not generalize one family's ownership contract to another. `Vector{ArbBall{P}}` and `Vector{AcbBall{P}}` contain Julia owner references and cannot be passed as packed native structs.

For each part, keep `gen/inventory.toml`, generated declarations, implementation, focused container/numerical tests, and `docs/capability_table.md` synchronized. For new bindings, audit symbols and regenerate twice without drift. After a change, run the focused tests covering the affected contracts and any directly affected shared callers; do not automatically rerun the entire suite. Record relevant bulk measurements in the benchmark environment. Cover short and long vectors at representative formats/precisions, with and without allocation/copying included. Retain a scalar path when a specialization has no demonstrated benefit. Do not block M4 on a wholesale internal-protocol refactor, elementary functions, complex dfloat/nfloat types, or speculative matrix storage.

M4a verification on Julia 1.13.3: **8,591 tests pass**; all **297** inventoried symbols resolve; binding regeneration twice produces no drift. On the recorded host and input distribution, checked contiguous ball addition at lengths 4–4096 is about 1.5–7× faster than the scalar loop, with zero warmed Julia allocations.

M4a evidence: `test/array_tests.jl` covers all four component counts, SIMD boundaries/tails, exact rational endpoint containment, empty/strided/reversed spans, exact aliasing, rejected overlap and repeated-index destinations, precision/type mismatches, exceptional lanes, and GC between aliased calls. The pinned `template.inc` vector-add path loads each SIMD block before storing, returns to scalar handling before storing exceptional blocks, and uses scalar tails; upstream `t-vec.c` and `t-vec_aliasing.c` provide additional source evidence. All four `_dNb_vec_add` exports resolve. `benchmark/m4a_vectors.jl` and [recorded results](../benchmark/results/m4a_vectors.txt) compare warmed scalar loops and checked native calls with equivalent enclosure guarantees, including a separately allocating path. Measurements are specific to the recorded host/artifact and input distribution; no native-memory-allocation claim follows from Julia allocation counts.

M4b verification on Julia 1.13.3 with four Julia threads: **11,906 tests pass**, all **299** inventoried symbols resolve, and two binding regenerations produce no drift. The matching-header ABI probe was rebuilt to record the nfloat minimum/maximum exponents.

M4b source audit: the pinned `nfloat.c` vector-add dispatch uses specialized loops for L = 1–4 and scalar kernels at larger L; vector multiply specializes L = 1–2 and otherwise uses scalar multiplication or squaring for identical input pointers. Strides are `L + NFLOAT_HEADER_LIMBS` words. These paths only read the shared context. Statuses are OR-combined: overflow with the finite-only flags writes a zero placeholder and returns `GR_UNABLE`; the wrapper rejects the entire scratch result rather than publishing that placeholder. Underflow is accepted and flushes to zero. Partial-overlap native calls are never made, and exact destination/input aliasing is implemented by committing from independent scratch. Scalar strided/gather-input fallbacks acquire the context once and use the same commit-on-success policy. Three-argument calls allocate initialized scratch. Four-argument calls accept a reusable `NFloatWorkspace{L}`; within reserved capacity the warmed contiguous native path allocates no Julia heap memory. Both forms share the kernel and commit-on-success code in `src/reusable.jl`.

M4b numerical evidence is in `test/nfloat_array_tests.jl`: independently decoded exact dyadics test the pinned default-mode error bounds at L = 1, 2, 3, 4, 5, 16, 66; sampled scalar equivalence is additional regression evidence, not a proof. Tests also cover zero/cancellation, boundary exponents from the rebuilt C probe, native and strided overflow preservation (including aliases), empty/invalid formats, rejected overlap, and context snapshots under concurrent tasks. The pinned `doc/src/nfloat/rounding.md` specifies < 2 ulp for addition and truncation with a possible extra ulp toward zero for approximate high products from three limbs onward. No new rounding mode or special-value support is introduced. [M4b benchmark results](../benchmark/results/m4b_vectors.txt) record complete checked calls against scalar calls with the same numerical-failure policy, plus raw native, copy, and inferred-context costs. Benefits vary by format and workload; at 66 limbs multiplication shows little material improvement. Reusable caller-provided scratch is implemented as described below; the three-argument API remains available.

**Reusable nfloat scratch.** `NFloatWorkspace(NFloat{L}, capacity)` owns initialized scratch of one concrete format. Pass it as the fourth argument to `FlintFloats.add!`/`mul!`; use `sizehint!(work, capacity)` before a hot loop to reserve storage. Operations grow automatically when necessary, initialize only newly added slots, and process/copy only `length(dest)` elements even if more capacity is reserved. They retain capacity after smaller calls or failures. Workspace storage must not overlap any operand. An atomic exclusive-use guard rejects concurrent/reentrant operations and growth; it is released on every exit. Use independent workspaces concurrently. Context pointers are acquired at operation time rather than stored across serialization or precompilation. The successful-result copy remains necessary to preserve the supplied destination's identity.

`test/reusable_tests.jl` verifies repeated add/multiply, growth and smaller active prefixes, exact aliases, rejected overlap and format mismatch, numerical/input exceptions followed by successful reuse, exclusive access under four threads, and zero warmed native allocations at L = 1, 2, 4, 16, 66. `benchmark/reusable.jl` and [recorded results](../benchmark/results/reusable.txt) compare allocating calls, reused workspaces, raw kernels, initial construction/growth, and strided fallbacks, including validation, atomic-guard, and commit costs in reused calls. Short-vector and large-format workloads can be dominated by those costs or native arithmetic; workspace reuse is not a universal speedup. M4c is implemented; the planned surrounding-interface work and M4d are sequenced in §9.4.

**Packed ball owners and borrowing (M4c).** `PackedBallVector(ArbBall{P}, n)` and the `AcbBall{P}`
form allocate initialized fixed-size storage through FLINT; `PackedBallVector(T, values)` copies in
values. One finalizer clears the entire allocation exactly once; failed population clears all already
initialized slots immediately. Ordinary indexing returns an independent scalar. Assignment and
`set!` round to the destination precision with containment. `copy`/`deepcopy` duplicate values into
independent owners, never pointer bytes. `similar`, iteration, fill, and ordinary Base broadcast work.
M4c established those semantics; §9.4.3 now adds flat destination broadcast optimization. Packed vectors
cannot resize or reallocate.

`borrow(v, i)` (also on packed views) creates a checked `BorrowedBall` retaining the parent and fixed
slot index. It is not a number and does not clear storage. `r[]`/`copy(r)` read independently;
`r[] = value`/`FlintFloats.set!` and qualified same-format scalar `add!`/`sub!`/`mul!`/`div!` mutate
slots. Source or destination references retain their owners through C argument conversion. Explicit
finalization is idempotent and surviving references detect closed parents before a C call; do not
explicitly finalize a parent concurrently with use. Concurrent mutation requires independent slots.

Packed vector `FlintFloats.add!`/`mul!` require identical element formats and axes. Native `_arb_vec_add`
and `_acb_vec_add` are forward loops of rigorous scalar addition; exact aliases are supported. Views
and multiplication use borrowed scalar calls. Other possible destination/input overlap is rejected;
destination views require independent strided slots. Empty calls skip native arithmetic. Validation
errors preserve the destination; custom input-read exceptions may leave it valid and partially updated.
This family preserves FLINT's indeterminate enclosures rather than applying nfloat's status policy.

Evidence is in `test/packed_tests.jl`: exact rational real/complex endpoint oracles, precision/containment,
heap-backed copy independence, parent GC retention, bounds, construction failure, idempotent cleanup,
strided/reversed views, exact/rejected alias cases, and independent concurrent owners/slots. The pinned
`arb`/`acb` `vec_init.c`, `vec_clear.c`, and `vec.c` supply allocation, ownership, and scalar-loop evidence.
`benchmark/m4c_packed.jl` and [results](../benchmark/results/m4c_packed.txt) record scalar-owner versus
borrowed/native arithmetic, warmed allocations, independent copy-out, construction/cleanup, and semantic
copying. Arithmetic throughput is comparable on the recorded workloads; construction and packed layout
are the clearest benefits. Zero warmed Julia allocations do not imply zero native allocations.

### 9.4 Improve the packed interface while retaining copied indexing

**Status: documentation, explicit borrowed iteration, and flat in-place broadcast (§9.4.1–3) are implemented.**
`PackedBallVector`, `borrow`, copied indexing/iteration, qualified destination arithmetic, and exported
`eachborrow` exist. Flat same-format identity/add/multiply broadcast has a destination fast path.
Bounded nested arithmetic is implemented; borrowed sum is implemented; M4d dot products are also implemented; selected mapped reductions remain the next optional extension.
These additions keep the interface small: value reads stay ordinary Julia reads; explicit references
serve custom mutation; ordinary broadcast/reduction expressions gain internal storage reuse.

#### 9.4.1 Make value and mutation semantics prominent (implemented)

Implemented in `docs/src/index.md`, `docs/float_interfacing.md` collection/destination sections, and the
`PackedBallVector`/`BorrowedBall`/`borrow` docstrings in `src/packed.jl`. Keep the following distinction
next to the first packed-vector example, not only in performance notes:

| Intent | Interface and effect |
| --- | --- |
| Independent value | `x = v[i]`, `copy(borrow(v, i))`, or ordinary iteration; later mutation of `x` does not change `v`. |
| Replace a slot | `v[i] = x`; semantic containing copy at the element working precision, never pointer assignment. |
| Convenient scalar update | `v[i] += step`; read, arithmetic, and write-back work, but can allocate temporary owners. |
| Reuse whole-vector storage | `FlintFloats.add!(dest, x, y)` / `mul!`; prefer these when the operation already fits. |
| Custom slot mutation | `r = borrow(v, i)` and `FlintFloats.add!(r, r, step)`; changes `v[i]` without copying out. |

Explicitly show that `FlintFloats.add!(v[i], v[i], step)` mutates a temporary, not the packed slot.
Views retain their parent, but reading `view(v, inds)[j]` still copies; assignment through the view
changes its mapped slot. `r[]` also copies. Keeping one reference keeps the entire packed owner alive;
a copied scalar can survive independently after that owner is released. Document fixed size,
precision/containment, explicit-finalization checks, and independent writable slots for concurrency.
Keep `BorrowedBall` nonnumeric and the scalar owning representation unchanged.

**Acceptance:** small doctests demonstrate independent read, explicit write-back, `+=`, view writes,
and borrowed mutation. Extend only the existing packed ownership tests needed to check those public
contracts. Benchmark copy-out and borrowed mutation with equivalent work and retained outputs; report
Julia and native allocation distinctions. Do not promise that every ordinary array expression is
already optimized. Documentation changes need documentation/doctest checks, not a full numeric run.

#### 9.4.2 Add one explicit borrowed-element iterator (implemented)

Exported **`eachborrow(v)`** is implemented in `src/packed.jl` for the same packed owners/views accepted by
`borrow(v, i)`. Its concrete `_BorrowedElements` iterator type is private. Implement `iterate`, `length`, type-level `eltype`, and the Base iterator traits returning
`HasLength()` and `HasEltype()`. For a span with element type `T`, the iterator
eltype is concretely `BorrowedBall{T}`, with an inferred `(reference, next_state)` iteration result. The iterator retains its span and therefore the parent. Traverse
logical view order, including reversed ranges and existing gather-view reads, by reusing the checked
`borrow` mapping. Do not cache raw pointers. View index maps must remain valid under Base's view rules.

Yield a separate immutable reference value for each position; never reuse a mutable cursor whose
index changes references already saved by the caller. Stored references stay attached to their
original slots after iteration ends. Check finalized parents when constructing/resuming iteration,
including empty spans. References remain bounds/lifetime checked when entering C, even if the iterator
later gains a proved internal bounds fast path. Ordinary `iterate(v)` and `eltype(v)` remain unchanged.
The iterator is not an `AbstractVector` of numbers and does not implicitly read or mutate slots.

Usage:

```julia
for r in eachborrow(v)
    FlintFloats.mul!(r, r, scale)  # scale has the same concrete scalar type
end
```

Do not teach unchecked `zip` as a substitute for validating multi-vector axes: it truncates at the
shortest input. Existing bulk methods remain the preferred interface for operations they cover.

**Acceptance:** focused `test/packed_iteration_tests.jl` cases cover concrete inference, empty/full/
strided/reversed/gathered spans, stable saved references, partial iterator consumption, copied versus
borrowed iteration, GC after dropping the original owner name, finalized parents, and independent
concurrent destinations. Compare the iterator against manual `borrow` loops and current bulk methods
at several lengths and precisions. Require no per-element Julia allocation in a warmed typed loop;
`collect(eachborrow(v))` intentionally allocates a collection of references and retains the parent.
If iteration adds overhead, improve its private implementation rather than making ordinary indexing
return references or exposing unchecked pointer access.

Implementation evidence: `test/packed_iteration_tests.jl` covers the documented read/write semantics
and iterator contracts, with focused existing ownership coverage in `test/packed_tests.jl`. Iterator
construction/iteration inline into typed loops without changing checked borrowing. The existing
concurrent-owner test was isolated into a function to avoid shared captured x/y/z locals. The focused
run passes 950 packed ownership checks, 775 iterator/value-semantics checks, and 10 repeated
concurrency regression checks with four Julia threads; module method-ambiguity detection is empty.
The full suite is not rerun for this follow-up. Numerical bounds and
foreign declarations are unchanged. `benchmark/packed_iteration.jl` and
[recorded results](../benchmark/results/packed_iteration.txt) compare retained copied results, manual
borrowing, the iterator, and bulk operations across full/strided/reversed/gather spans. Gathered
iteration permits repeated slots; bulk gathered destinations remain unsupported. Zero per-element
Julia allocation is scoped to warmed typed loops; collecting references still allocates.

#### 9.4.3 Optimize in-place broadcast in two bounded steps

Flat broadcast is implemented in `src/packed_broadcast.jl`, included after `packed.jl`; the bounded nested step is also implemented.
Begin with destination specialization at `Base.copyto!(dest, bc::Broadcasted{Nothing})` for packed
owners and supported strided packed views; keep normal broadcast style and allocating-result container
selection unchanged. Do not introduce a new `BroadcastStyle` or override `broadcasted` globally just
to optimize assignment. Verify method ambiguities against Julia 1.13 and each supported version.
Keep version-sensitive Base broadcast handling in this file. The first release targets `dest .= ...`;
an allocating expression such as `x .+ y` retains its current result-container behavior. If that result
is an ordinary vector of scalar owners, per-element ownership allocation is inherent. Teach
`dest = similar(x); dest .= x .+ y` for packed output reuse. A later custom broadcast style for
allocating packed results needs its own result-type, mixed-style, and compatibility review; it is
not a prerequisite for these in-place optimizations.

**First step: flat expressions (implemented).** Recognize only `identity`, binary `+`, and binary `*` with supported
packed leaves and same-concrete-type owned scalar/`Ref` leaves. Optimize `dest .= src`, `dest .= x .+ y`,
and `dest .= x .* y`; use current vector kernels where the prepared spans and axes qualify. Scalar
expansion and singleton dimensions must follow Base's instantiated axes/index mapping. Mixed precision,
other element/result types, custom functions, and unsupported array inputs use the existing generic
Base path. In particular, comparison broadcasts must still produce Boolean results, and real-valued
functions of complex balls must retain their scalar result types. Add functions only with explicit
destination semantics and independent evidence.

Validate before writing and use Base-compatible alias preprocessing. Julia 1.13's installed
`base/broadcast.jl` documents the destination specialization and uses `instantiate`/`preprocess`,
with `broadcast_unalias` exempting `dest === src`. Audit these helpers per supported version; treat
the nonpublic helpers as private implementation dependencies, not user interface. Snapshot overlapping
views or leaves whose broadcast mapping reads a destination slot at a different logical index;
preserve safe exact self-aliasing. Singleton expansion is an alias case, not just a shape case.
For example, `dest .= view(dest, 1:1) .+ x` must retain the original singleton value for every output,
and shifted-view assignments must not depend on loop direction. Allocate snapshots before mutation.
Repeated-index destination views use generic Base behavior, not the packed arithmetic fast path.
Explicit `FlintFloats.add!`/`mul!` keep their existing overlap-rejection contract; dotted assignment
must not inherit that restriction accidentally.

Choose optimization or generic fallback **before mutation**. Never catch an exception after a partial
optimized evaluation and retry through Base: arbitrary functions or inputs could then run twice.
Keep a direct invocation of the unspecialized Base destination method as the fallback, avoiding
recursive dispatch into the new method. Preserve generic scalar-call counts and exceptions on the
fallback. Recognized fast paths retain the current valid-but-partially-updated policy for evaluation
errors; allocation/shape/alias-preparation failures happen before writing.

Flat-step evidence: `test/packed_broadcast_tests.jl` passes 781 focused checks on Julia 1.13.3 with
four threads, including method-ambiguity detection, generic Base comparisons, exact endpoint oracles,
empty/strided/reversed/gather-source cases, shifted/singleton aliases, callback counts/exceptions,
result-type/precision changes, and conflicting broadcast styles. Directly affected packed-owner tests
are run separately; the whole numeric suite is not rerun. `benchmark/packed_broadcast.jl` and
[results](../benchmark/results/packed_broadcast.txt) compare the full checked operation to an explicit
invocation of Base's generic destination method, with snapshot costs reported separately.

The optimized scalar Ref leaf is `Ref(value)` (`Base.RefValue{T}`); other Ref implementations remain
generic. Known packed leaves use Base's `broadcast_unalias`, retaining concrete source/view types;
possibly overlapping views therefore snapshot their parent using Base's existing unalias-copy rules.
Only logical integer slot indices enter borrowing, including gathered source views. Whole packed
same-axis identity/add cases reuse native set/add kernels; scalar/singleton expansion, multiply, and
other recognized spans use checked borrowed destinations. No new foreign declarations are added.
Shape/lifetime checks and all alias snapshots precede mutation; closed packed parents are rejected.
The fast path does not change the explicit bulk methods' stricter overlap-rejection policy. Large
alias snapshots can still allocate and cost native memory; ordinary nonaliasing typed arithmetic
avoids per-element Julia owners. Unsupported or oversized nested trees select generic fallback before evaluation.

**Second step: bounded nested arithmetic (implemented).** Extend the supported set to same-format pure trees of
`identity`, unary negation, and binary `+ - * /`. A private evaluator walks the concrete broadcast
tree and reuses one initialized owned scalar per arithmetic-node occurrence, allocated once per
call. Evaluate each element fully into scratch, then copy its root result into the packed destination.
This is essential for `dest .= dest .* y .+ dest`: an intermediate must not overwrite a destination
leaf needed later in the same element. Distinct live subexpressions need distinct scratch; do not
reuse a left-result slot while evaluating its right sibling.

Preserve tree structure and the scalar working precision at every node. Do not reassociate,
common-subexpression eliminate, introduce `fma`/`addmul!`, or evaluate at higher precision and round
only once: those changes can alter enclosure widths and the scalar-expression contract. Initially
limit specialization to eight arithmetic-node occurrences; larger or unsupported trees fall back to
Base. Benchmark that budget for first-use latency/code size as well as runtime, and revise it only
with evidence. Do not allocate full intermediate vectors or an owner per element. Keep scratch
private to one invocation; add no global cache or new public broadcast workspace without measured need.

**Acceptance:** focused `test/packed_broadcast_tests.jl` covers owners and views, scalar/singleton
expansion, empty axes, exact aliases, shifted/reversed/gathered sources, repeated destination indices
on the generic path, and repeated destination leaves in nested trees. Check normal generic behavior
for Boolean outputs, precision/type changes, arbitrary callbacks, exceptions, and conflicting broadcast
styles. Supported arithmetic should match independently evaluated scalar trees in representation
where deterministic, and must contain independent exact references. Check midpoint precision and
indeterminate values. Benchmark `dest .= x .+ y`, `dest .= x .* y .+ w`, self-updates, tiny/long spans,
and larger mantissas against generic copied-scalar broadcast, manual borrowed loops, and explicit bulk
methods. Report alias-snapshot cost separately. Scratch allocations may scale with expression size
but not vector length on nonoverlapping warmed fast paths; claims exclude native capacity growth.

Nested implementation evidence: 781 flat-broadcast checks and 215 focused nested checks pass with
four Julia threads, including repeated destination leaves, live sibling scratch, exact uncertain
real/complex bounds, scalar-tree representation agreement, view snapshots, 8/9-node limits, callback
fallback, and allocation bytes independent of vector length. Each recognized node (including identity)
owns a private temporary; all sources are prepared before mutation, and only the fully evaluated root
is copied to the destination. In addition to eight arithmetic nodes, depth is capped at 16 to bound
identity-only nesting. `benchmark/packed_nested_broadcast.jl` and
[results](../benchmark/results/packed_nested_broadcast.txt) record 2/8-node runtime/allocation and fresh-
precision compilation: the recorded eight-node first use is about 105 ms at P=997/998, not warmed
arithmetic time. Scratch Julia allocations scale with tree size, not vector length. No new C bindings.

#### 9.4.4 Optimize reductions with their own numerical contract (M4d)

Reduction implementation is in `src/packed_reduce.jl`. **`sum(v)` and dot products are implemented**. The sum path supports matching
packed real/complex ball owners and supported views. Use one fresh owned accumulator at element
precision and borrowed inputs; do not call ordinary copied indexing per term. An empty sum is a fresh
typed zero; a singleton result must also be independent of its input. Return an owned scalar, never
a borrowed slot. Initial accumulation is deterministic in logical iteration order and encloses the
exact set sum. State that its representation/radius need not equal Base's possibly reassociated
reduction. Keep generic handling of `init`, `dims`, mapped functions, and unsupported combinations
unless their semantics are explicitly implemented; do not intercept and silently discard keywords
or change result types. A private destination helper can support internal reuse without adding a
public `sum!` name before there is a caller need.

The pinned `arb.h`/`acb.h` inspected for this plan expose dot kernels but no general vector-sum entry.
Do not invent a `_arb_vec_sum` binding or allocate a vector of ones as the default sum algorithm.
Audit any later native substitute independently and retain borrowed accumulation unless measurements
support replacing it. Accumulator allocation is expected; the performance goal is no per-term Julia
owner allocation and bounded private scratch.

Sum evidence: 205 focused reduction checks pass with four Julia threads. Empty/singleton results
are fresh, logical-order accumulation encloses exact uncertain sums and large cancellation, and
`init`/`dims`/unknown keywords and mapped callbacks delegate to Base without changing scalar value
semantics. `benchmark/packed_sum.jl` and [results](../benchmark/results/packed_sum.txt) report complete
operations, radius quality, and constant one-result-owner Julia allocation as vector length grows.
No new C bindings or public `sum!` are introduced. The previous full-suite result remains historical;
this change uses focused reduction tests and documentation checks only.

Implemented audited **`LinearAlgebra.dot(x, y)`** specializations for same-concrete-format packed spans.
Declare the standard-library dependency and import only `dot`, keeping the package's qualified
`mul!` convention intact. Other combinations retain the generic interface until separately supported.
Real dot encloses the ordinary sum of products; complex dot conjugates the **first** operand.
FLINT `acb_dot` must not be treated as a drop-in conjugating dot. First implement a correct borrowed
reference path with reusable product/conjugation temporaries. Audit a native alternative using real/
imaginary strided `arb_dot` calls, or a conjugated copy plus `acb_dot`, and benchmark complete costs
before choosing. Prefer avoiding a full conjugated input copy when verified part-stride calls are
competitive; keep part offsets/stride conversion inside the checked packed implementation.

Record source guarantees, exports, signed element-stride and native-length conventions, initial/
subtract arguments, output/input alias permissions, precision, and indeterminate behavior before
binding. For reversed/strided spans, derive the first element and step in native **struct units**,
not bytes, and check arithmetic overflow; fall back to borrowed loops where source support is unproved.
Preserve all parents during native calls. Empty dot returns a fresh typed zero without pointer
arithmetic; nonempty output storage is independent of inputs. Native accumulation may produce different
radii from a rounded scalar loop; require rigorous containment and record radius quality rather than
requiring bitwise equality across different algorithms. Avoid `approx` kernels.

Dot implementation/evidence: `src/packed_reduce.jl` imports only `LinearAlgebra.dot` (stdlib dependency
and manifest updated). Both native declarations are symbol-audited: `arb_dot` and unconjugated
`acb_dot` take signed struct strides, nullable initial terms, and subtract=0/1; output may alias its
initial term but never input entries. This follows the pinned arb/acb index documentation and dot
implementations. Public output is always a fresh scalar, and empty calls skip pointer arithmetic.

Real strided spans use `arb_dot`. Finite complex spans of at least four elements use four real-part
`arb_dot` calls with checked doubled part strides, implementing `re = dot(xr,yr)+dot(xi,yi)` and
`im = dot(xr,yi)-dot(xi,yr)`. Two private real accumulators plus the complex result bound Julia scratch
independently of length. Small/gathered/unsupported-stride or nonfinite complex spans use borrowed
conjugate/product/accumulator temporaries. Mixed element formats delegate to the generic LinearAlgebra
array interface. Input parents remain preserved across native calls. No approximate kernel is used.

`test/packed_dot_tests.jl` covers nonreal singleton conjugation, signed/gathered spans, exact uncertain
rational endpoint oracles, mixed precision, cancellation, nonfinite inputs, independent results,
heap-backed result lifetime after parent cleanup, concurrent readers, and method ambiguities. The sum
suite is checked alongside it because both share the reduction module. `benchmark/packed_dot.jl` and
[results](../benchmark/results/packed_dot.txt) compare generic/public calls, borrowed accumulation,
part-stride native accumulation, and a conjugated-copy `acb_dot` alternative including allocation and
cleanup. Candidate wrappers derive precision types from inputs to avoid dynamic Type dispatch in
measurements. The chosen native part path avoids an O(n) conjugation copy and was faster on recorded
workloads. Radius quality differs by algorithm: tables include ordinary uncertain inputs and severe
cross-component cancellation; none claims correctly rounded point results or identical enclosures.
The binding inventory now audits 309 symbols and regenerates twice without drift.

**Selected mapping implemented:** `sum(abs2, v)` reuses mapped-value scratch and a fresh real
accumulator for both packed families. Complex parts are extracted into two reusable real scalars;
squares/addition preserve the existing scalar mapping. Keywords delegate to Base, and arbitrary
callbacks keep copied arguments. Focused tests cover exact rational interval bounds, zero crossing,
view order, independence, finalized parents, inference, and allocation independent of length.
The [mapped reduction benchmark](../benchmark/results/packed_mapped_reduce.txt) records complete
operation time, Julia allocations, and radius quality. No new native bindings.

For any additional mapping, Specify mapping result
family/precision (complex `abs2` is real), reuse destination-capable scalar primitives, and prove the
mapped bounds. Arbitrary `sum(f, v)`/`mapreduce` callbacks must continue to receive independent scalar
values and retain their generic effects/exception behavior; never pass them implicit mutable borrows.
Do not rewrite unconjugated `sum(x .* y)` into conjugating complex `dot`. Leave general reductions,
`norm`, numerical extrema, threading, and matrix work outside the first change.

**Acceptance:** focused `test/packed_reduce_tests.jl` covers exact dyadic/rational set references,
large cancellation/exponent gaps, empty/singleton independence, real/complex conjugation, uncertain
inputs, indeterminates, precision invariants, strided/reversed/gather fallback, keyword/generic
compatibility, and parent lifetime. Test a nonreal singleton dot so omission of conjugation is visible.
Benchmark generic copied-scalar reductions, borrowed accumulation, and native candidates over length
and precision; report result/scratch allocation, first-use cost, native memory, radius quality, and
any conjugated-input copy. Optimize additional inline families only in separate verified changes.

#### 9.4.5 Enactment order and review gates

| Change | Files and implementation | Gate before the following change |
| --- | --- | --- |
| Documentation (complete) | Packed docstrings, `docs/src/index.md`, interface/capability documents; examples distinguish values, writes, and references. | Focused doctests and packed copy/mutation cases; no change to indexing/iteration return types. |
| Borrowed iteration (complete) | Private iterator and exported `eachborrow` in `src/packed.jl`; iteration tests and a benchmark driver. | Stable saved references, parent lifetime, inference, and allocation/throughput parity with manual borrowing. |
| Flat broadcast (complete) | `src/packed_broadcast.jl`, module include, focused broadcast tests/benchmarks; reuse checked kernels after compatible alias preparation. | Ordinary Base result/axes/style behavior and overlap semantics, with measured benefit or a retained generic path. |
| Nested broadcast (complete) | Bounded typed evaluator and private per-node scratch in that same file. | Tree/precision preservation, repeated destination-leaf safety, bounded specialization and no per-element owners. |
| Sum, then dot (M4d; complete) | `src/packed_reduce.jl`, module include, focused reduction tests/benchmarks; add `LinearAlgebra` and inventory/generation changes only when dot bindings are ready. | Independent containment/conjugation evidence and complete-operation/radius measurements. |
| Selected mapped reductions (`abs2` complete) | `sum(abs2, v)` is implemented; add any other mapping only with individual evidence. | Correct mapped result type, generic-callback compatibility, and measured allocation/accuracy benefit. |

Review the implementation against these rejected shortcuts before accepting a fast path:

| Shortcut considered | Decision and reason |
| --- | --- |
| Return a borrowed proxy from ordinary indexing | Keep independent `T` values; proxy results would change the declared element-type/ownership contract. |
| Yield one mutable reference cursor repeatedly | Yield stable reference values; callers can safely retain different yielded references. |
| Add one broad broadcast rewrite or change allocating result containers immediately | Start with destination-only, recognized trees; retain Base compatibility and generic function effects. |
| Evaluate a nested tree directly into the destination or use fused scalar arithmetic | Keep live per-node scratch and preserve the tree, so repeated destination leaves and enclosure rounding remain correct. |
| Borrow arguments implicitly for arbitrary reduction callbacks or use complex `acb_dot` unchanged | Keep copied callback values and explicit conjugation; mutation effects and the mathematical dot definition must remain correct. |

The review decisions above preserve `AbstractVector{T}` value reads, keep iterator references stable,
separate broadcast alias preparation from explicit bulk rejection, and distinguish expression-tree
rounding from reduction accumulation. All temporary ownership, pointer lifetimes, dispatch/fallback,
and numerical handling remain behind the packed module's small interface. On a source change, run
only the tests covering that change and directly affected shared contracts; document the selected
scope. Update the capability table when implementation lands, not merely because this plan names a
method. A planned benchmark or test is not current evidence.

### 9.5 Carry forward checkpoint limits

Keep the following limits visible while extending the package: `NFloat` square root now has an independent exact integer-root oracle across all 1:66 limb counts, MPFR truncation comparisons, native exponent limits, and concurrent-read checks (`test/nfloat_sqrt_tests.jl`); `Rational` and `Complex{Float64}` interop remain future work; shared helper factoring remains incomplete; and portable artifacts/CI remain unverified. New bulk methods inherit none of the scalar numerical guarantees automatically: record the selected kernel's guarantee and failure policy explicitly. Elementary-function expansion (`exp`, `log`, `sin`, `cos`, `atan` as possible first candidates) remains M5, with a source audit and domain/rounding evidence per function.

### 9.6 M5 selected elementary functions (in progress)

`src/elementary.jl` implements `exp`, `log`, `sin`, `cos`, and `atan` for real/complex balls,
with qualified same-format destination methods. [Elementary contracts and source audit](elementary.md)
record domains, branches, precision, aliasing, and ownership. Ten new symbols bring the inventory
from 309 to 319. The 291 focused checks use independent MPFR directed bounds and exact rational
complex series/tail bounds; measurements compare allocating calls and destination reuse.
Strict point functions for `ArbFloat` and `AcbFloat` are also implemented in all five rounding
modes, with aggregate inexact flags and native alias/branch/range behavior. The 3,166 focused point
checks use MPFR and certified rational-series endpoint rounding; ball checks pass after extracting
the shared reference helper. Ten more audited declarations bring the inventory to 329.
Inline dfloat/ball and nfloat functions are implemented with separately documented approximation,
enclosure, domain, and status contracts. The 712 focused inline checks cover static bounds,
uncertain inputs, formats through 66 nfloat limbs, failure recovery, and concurrent reads. The
adjacent Base-float test now expects explicit exp support. The inventory audits 374 symbols.
[Measurements](../benchmark/results/elementary_inline.txt) report complete inline-call costs.
Next complete compatible CI and portable artifact/release gates. Selected functions are sufficient for this milestone; further special
functions require individually justified scope. Portable artifacts and verified target CI remain
release gates after numerical implementation.

## 10. Verification and performance evidence

### 10.1 Required verification layers

| Layer | Evidence required |
| --- | --- |
| Binary and ABI | Source/artifact identity, symbols, sizes, offsets, alignment, integer widths, and compatible runtime target. |
| Ownership | Independent copies, failure cleanup, allowed aliasing, parent retention, GC during borrowed operations, and no double clear. |
| Point arithmetic | Exact examples, exceptional inputs, and error checks matching each operation's actual guarantee. For correctly rounded `ArbFloat` operations: bit-for-bit MPFR agreement at equal precision in each supported mode. For `AcbFloat`: independently certified component references (rounding a finite-precision complex approximation is insufficient). Check inexact flags and mantissa-length invariants where applicable. |
| Enclosures | Exact rational cases, independently certified bounds, uncertain domains, cancellation, zero-crossing divisors, and complex branch cuts. |
| Julia contracts | Inference, concrete promotion, equality/hash laws, unsupported fallback behavior, parsing/display, and array semantics. |
| Precision and concurrency | Concrete inference through `with_precision`, nested barriers and tasks using distinct type precisions, immutable context reuse for audited operations, and independent writable destinations. No runtime default needs restoration. |
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
| **M3 — Julia numeric contracts** | Type-precision function barrier; explicit comparison/inequality behavior; `isequal`/hash; narrow promotion; audited Base fallbacks and complex behavior. | Contract tests pass, including uncertainty examples, mixed hashing, task isolation, and concrete promoted types. Documentation identifies unsupported generic algorithms. |
| **M4 — bulk arithmetic** | Concrete fixed-format arrays; packed ball vectors; explicit borrowing and `eachborrow`; selected broadcast/reduction/dot paths under §9.4. | Copied indexing retained; container/lifetime, Base compatibility, aliasing, empty/strided inputs, expression precision, reduction containment/conjugation, and measured performance are verified per path. |
| **M5 — function expansion and release** | Selected elementary/special functions; portable artifacts; clean CI/docs setup; capability and benchmark reports. | Every advertised function and target passes its required evidence; users can install without a compiler or development-host assumptions. |

**Status:** M0–M3 and scoped M4 bulk/packed work are implemented, including `sum(abs2, v)`.
Nfloat square-root evidence is complete. M5's five selected elementary functions are implemented
for all seven families. Compatible CI, portable artifacts, and clean-target release validation remain
unfinished. Native matrices and further mappings require measured need; optional interoperability
and shared-helper refactoring do not block the scoped numerical milestones.

All seven types participate in M1 and M2. A family-specific issue may delay its completion without forcing unrelated work to stop, but the first complete release includes all seven. Do not expand the function inventory faster than it can be verified.

For each implementation change, describe the caller-visible behavior, affected guarantees, ownership/aliasing implications, verification, and relevant measurements. Keep generated declarations separate enough for a reviewer to inspect semantic changes. Update the inventory and user-facing capability table in the same change as each new operation.

## 12. CI, documentation, and release readiness

The workflow now runs host-independent source/archive checks and deterministic binding generation
on hosted Julia 1.13. It does not load FLINT there. An explicitly dispatched compatible-runner job
validates the host before native imports, then runs contracts, symbol/ABI checks, and docs.
[CI/release instructions](ci_release.md) document labels, headers, deployment opt-in, and remaining
external runner/portable-target evidence. The old unverified hosted native matrix has been removed.

Establish one of two explicit CI paths during development: a compatible controlled runner using the local artifact, or a build job producing an appropriate artifact for the test runner. For release, use portable, audited artifacts and test each supported target. Remove or exclude unprovided targets rather than letting incompatible native code run. Include Windows, 32-bit, or other architectures only after their Julia builds, native dependencies, layouts, and numerical behavior have been verified.

Documentation has its own environment. Ensure it resolves the intended wrapper and run it from a clean setup; do not rely on a developer's main-project manifest. Keep expensive memory diagnostics and noisy speed comparisons in separate jobs or controlled runners. Ordinary CI should run deterministic numerical, ownership, ABI, and contract checks.

The [release evidence report](release_evidence.md) records fresh-project resolution, actual bundled
installation, archive docs checks, portable-recipe fixes, and independently verified replacement
toolchain downloads/tree hashes. These do not satisfy portable-target
certification. Before release, require all of the following:

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
4. Julia's installed foreign-call, numeric-interface, and type-specialization documentation for the supported Julia version.
5. Nemo and Arblib as implementation precedents for owners, borrowed references, and ball semantics; validate adaptations against this guide's contracts.

Resolve these decisions at their designated milestone rather than leaving them implicit in implementation:

| Decision | Deadline | Required evidence |
| --- | --- | --- |
| Concrete nfloat representation and array construction interface | M1 — **resolved**: `NFloat{L}` = `exp::Int`, `sign::UInt`, `d::NTuple{L,UInt}` (`test/abi_tests.jl`; 0 allocations, `benchmark/results/m1_scalar.txt`). Array construction deferred to M4. | Valid layout, concrete inferred types, allocation/copying measurements. |
| Context sharing versus task-owned reuse | M1 — **resolved**: shared immutable contexts for `+ - * /` (source audit; 8-task test). Re-audit before adding functions that may use workspaces. | Matching-source audit and concurrent tests; conservative ownership until verified. |
| Exact supported function/rounding/flag set | Before each operation is added | Inventory entry, source guarantee, and numerical test cases. |
| Hash normalization and mixed-type identity | M3 — **resolved** in `src/compare.jl` and `test/compare_tests.jl`; includes canonical indeterminate balls and allowed huge-exponent hash collisions | Preserve equality/hash laws across supported mixed types and seeds. |
| First native bulk kernels | M4a — **resolved**: contiguous `_dNb_vec_add`, N = 1–4; M4b adds `_nfloat_vec_add`/`_nfloat_vec_mul`; M4c adds arb/acb init/clear/set/add; dot kernels remain M4d | Exact endpoint containment, scalar equivalence, alias/layout checks, and recorded benchmarks. |
| Portable artifact delivery and supported platforms | Before public release | Built/audited binaries and clean-machine installation/test results. |

This sequence keeps the managed numeric interface deep: callers obtain useful arithmetic and containment behavior from a small interface, while implementation details and verification remain local to the code that owns them.
