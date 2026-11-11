# FlintFloats.jl — Interfacing Plan

> **Superseded.** This first draft is kept for history only. Current documents: [plan_interfacing.md](plan_interfacing.md) (decisions), [enact_interfacing.md](enact_interfacing.md) (procedure) and [float_interfacing.md](float_interfacing.md) (interface contract). Names here are partly updated (`DFloatBall`), but its design choices (runtime ball precision, scoped `setprecision`, `NFloat{L}` vs bits, private `arf`, `ArfFloat`/`MagFloat` names) are replaced by those documents.

Goal: Julia interface to FLINT floating-point types via `FLINT_jll`, maximally fast, source clean and clear.
Prior art studied: Nemo.jl (ring-oriented, GC-managed wrappers), Arblib.jl (thin generated `ccall` layer + ergonomic layer).

Historical starting-point status (superseded): repo was an empty PkgTemplates skeleton. `FLINT_jll` not yet a dependency. Everything below is design, not yet code.

## 1. Scope

Types in scope (FLINT 3.x):

| FLINT type | Meaning | C struct size (64-bit) | Phase |
|---|---|---|---|
| `mag_t` | unsigned magnitude upper bound, 30-bit mantissa, fmpz exponent | 16 B | 1 |
| `arf_t` | arbitrary-precision float, exact value, explicit rounding per op | 32 B | 1 |
| `nfloat` | fixed-precision (multiple of 64 bits), no allocation, via `gr` | precision-dependent | 3 |
| `dfloat` `dN`/`dNb`/`dNc`/`dNcb`, N=1..4 | unevaluated sum of N doubles (~53N bits); `b` = ball (adds a double radius), `c` = complex. `struct { double d[N]; }`; ball adds `double rad` | 8N B; ball 8(N+1) B | 2.5 (before nfloat) |
| `arb_t` | real ball = `arf` mid + `mag` rad | 48 B | 2 |
| `acb_t` | complex ball = 2 × `arb` | 96 B | 2 |

Owner decision (confirmed): scope includes `dfloat`, `nfloat`, `arb`, `acb` (plus `mag`/`arf` as the foundation). `dfloat` confirmed by FLINT docs (https://flintlib.org/doc/dfloat/index.html, labelled 3.7.0-dev; page says parts are LLM-generated, and the sizes/init-free claim here are inferred from its struct listing, so check against the headers). See §3a. Struct sizes above must be verified (see §7).
Julia floor: **1.13** (confirmed).

## 2. Layering

Three layers, one-way dependencies. Each layer replaceable without touching the one above.

```
src/
  FlintFloats.jl      # module, includes, exports only
  LibFlint.jl         # L0: raw ccall bindings (generated + checked in)
  structs.jl          # L1: isbits mirror structs (mag_struct, arf_struct, ...)
  precision.jl        # global/task-local precision + rounding state
  mag.jl  arf.jl      # L2: Julia types, memory mgmt, constructors
  arithmetic.jl       # L2: Base operator methods
  conversions.jl      # L2: Float64/BigFloat/Int/String conversion + promotion
  show.jl             # printing
  ball.jl             # arb/acb (phase 2)
  nfloat.jl dfloat.jl # phase 3 (fixed-precision, gr-based)
```

- **L0 `LibFlint`**: one Julia function per C function, name identical to C (`arf_add`, `arf_set_d`). No logic. Arguments typed `Ref{arf_struct}`/`Ptr{arf_struct}`. Easy to diff against FLINT docs.
- **L1 structs**: plain `mutable`-free `struct`s mirroring C layout, so `Ref` and `Vector{arf_struct}` give correct memory layout.
- **L2 Julia API**: idiomatic types, `Base` methods, no raw pointers visible to users.

## 3. Performance decisions

1. **`ccall` with literal `(:fn, libflint)` tuples.** `libflint` is a `const` from `FLINT_jll`. Static symbol resolution, no dlsym per call. Never use runtime-computed symbol names. Macro `@flint` may wrap this to cut noise but must expand to a plain `ccall`.
2. **Mutable ("in-place") API is primary; allocating API is sugar.** FLINT is destination-first (`arf_add(z, x, y, prec, rnd)`). Expose `add!(z, x, y)` etc. as the fast path. `z = x + y` allocates result then calls `add!`. Enables allocation-free loops and matches Nemo/Arblib convention.
3. **Wrapper representation.** FLINT structs contain fmpz exponents and (for arf) limb pointers → the struct must live at a stable address and be `clear`ed. Choose:
   - `mutable struct ArfFloat; d::arf_struct; end` with `finalizer` → `arf_clear`. Pass `pointer_from_objref` / `Ref(x, :d)` for the call. One GC object per number. Simple, safe.
   - Arrays: `Vector{ArfFloat}` holds pointers to boxes (slow, cache-unfriendly). Provide `ArfVector` backed by contiguous `Vector{arf_struct}` with one finalizer per vector (Arblib's `ArbVector` idea). Much better for linear algebra and bulk ops.
4. **Avoid finalizer cost where possible.** Finalizers are the main per-object overhead. Mitigations: `mag` with small exponent and `arf` with small mantissa hold no heap memory but still need `clear` for the fmpz exponent in general → cannot skip safely. Keep finalizers; use vectors and in-place ops to reduce object count. Do not use `GC.@preserve` tricks to skip clear.
5. **GC safety.** Every `ccall` taking a pointer to a mutable wrapper must keep it alive: use `Ref`-to-field forms or `GC.@preserve`. Centralize this in a small number of internal helpers, not at call sites.
6. **Precision & rounding as arguments, not globals, at L0/L1.** At L2 default comes from task-local state via `Base.ScopedValue` (floor is Julia 1.13, so no fallback path). Read once per operation, not per limb. Provide `setprecision(ArfFloat, n) do ... end`. Precision stored as `Int` (`slong`), rounding as `Cint` constants mapping `ARF_RND_*`.
7. **Type stability.** `ArfFloat` has no precision type parameter by default (avoids dispatch explosion, matches `BigFloat`). Rounding mode and precision are values, not types. Return types of all methods concrete.
8. **`nfloat` (phase 3) is a speed play; `dfloat` (§3a) is the earliest one.** Fixed precision, no heap, stack-allocatable. Model as `NFloat{P}` where `P` = limb count type parameter so size is static and `isbits`-able storage (`NTuple{P+2,UInt}`-style) is possible, called through `gr`/`nfloat_*` functions with a context object. Must prototype before committing: verify layout, context lifetime, and whether `isbits` passing by `Ref` works without allocation. Highest upside, highest risk.
9. **Threading.** FLINT is thread-safe for distinct objects. Document that wrappers are not safe for concurrent mutation of one object. Call `flint_cleanup_master`/thread cleanup guidance in docs (verify exact function names).
10. **Benchmarks gate every performance claim.** `benchmark/` with BenchmarkTools: wrapper vs raw `ccall` vs `BigFloat` for add/mul/div/sqrt/exp, scalar and vector, at 64/256/1024/4096 bits. Target: wrapper overhead < ~10% over raw `ccall` for in-place ops.

## 3a. dfloat specifics

Source: FLINT dfloat docs. Fits the plan well because it needs no memory management.

- **Layout → pure Julia isbits.** `dN_struct` is `double d[N]`; ball adds `double rad`. Map to `struct DFloat{N} <: AbstractFloat; d::NTuple{N,Float64}; end` and `struct DFloatBall{N}; mid::NTuple{N,Float64}; rad::Float64; end`; complex = pair of these. No finalizer, no `clear`, no `GC.@preserve`, arrays of them (`Vector{DFloat{2}}`) are contiguous for free. Faster and simpler than `ArfFloat`; skip a separate vector type.
- **Pass by `Ref`/`Ptr`, aliasing allowed** (docs: input/output aliasing is permitted everywhere), so in-place `add!(z,x,y)` with `z===x` is safe.
- **Two implementation routes, benchmark-decided:**
  1. `ccall` to FLINT (`d2_add`, `d2b_mul`, `d4_exp`, ...), if those are real exported symbols.
  2. Native Julia reimplementation of the core arithmetic (error-free transforms `two_sum`/`two_prod` using `Base.fma`, renormalisation). Inlines into user loops, no call overhead, SIMD-friendly. Likely wins for add/mul at N=2..3; `ccall` wins where FLINT has tuned kernels (exp, log, trig, vector ops).
  Recommend: `ccall` first (correctness oracle, full function set), native Julia fast paths only where benchmarks show a win, with the FLINT binding as the test oracle.
- **Symbol audit is critical here.** Docs list names like `DFLOAT_FAST_TWO_SUM`, `DFLOAT_TWO_PROD`, `DFLOAT_CTX` (macros — not callable). Many arithmetic functions are probably `static inline` in headers; check with `nm -D`. Inline ones must be reimplemented in Julia (route 2) anyway.
- **Runtime requirement.** `dfloat_is_supported()` must return 1 before any dfloat function is used (needs correctly rounded `fma`, no FP contraction, `FLT_EVAL_METHOD` 0/1/16, i.e. no x87). Call it once in `__init__`; if unsupported, disable dfloat types with a clear error rather than returning wrong results. For Julia-native route: use explicit `fma`, never `muladd`/`@fastmath` in these kernels (contraction or reassociation breaks error-free transforms).
- **Accuracy semantics.** Plain `dN`: not correctly rounded, a few ulps at 53N bits; document this (no bit-for-bit BigFloat oracle as for `arf`; test with error bound instead, e.g. `|x - exact| <= k*2^(-53N)*|exact|`, k from the documented `DFLOAT_*_EPS_N`). Trig error is absolute, not relative, near zeros. `dNb` balls are rigorous enclosures; test enclosure containment against `arb`.
- **Ball status codes.** `dNb_div/inv/sqrt/log/...` return GR status (`GR_SUCCESS`, `GR_DOMAIN`, `GR_UNABLE`). Wrap: throw `DomainError` for `GR_DOMAIN`; `GR_UNABLE` (ball contains zero, etc.) → return indefinite ball `[0±Inf]` or throw per option; decide and document once.
- **Generic path.** `gr_ctx_init_dfloat(ctx, n, flags)` with flags `BALL=1, STRONG=2, FAST=4, COMPLEX=8` gives `gr_poly`/`gr_mat` over dfloat. Only needed if wrapping those; direct `dNxxx` calls are lighter. Defer gr route to the shared nfloat layer (M3).
- **Vector ops** (`_dN_vec_add`, `_dN_vec_dot`, `_dN_vec_exp`, ...) use AVX2/FMA or NEON in FLINT. Expose via `LinearAlgebra`-style hooks (`dot`, broadcast fusion fallback) once audited.
- **Max N is 4** (`DFLOAT_MAX_N`); N as type parameter keeps dispatch static. Conversions between N are exact when growing, rounding when shrinking.
- **Edge:** `dN_equal` compares values, not components; implement `==` and `hash` on canonicalised value (`dN_canonicalise`), otherwise equal numbers hash differently.

## 4. Clean-code decisions

- **Generate L0, do not hand-write it.** Option A: Clang.jl generator over FLINT headers (like Arblib's approach), output checked in with the generator script in `gen/`. Option B: small hand-curated table `(:arf_add, Cvoid, (Ref{arf}, Ref{arf}, Ref{arf}, Int, Cint))` expanded by macro. Recommend **B for phase 1** (only ~80 functions needed; headers are macro-heavy and Clang.jl output for FLINT needs cleanup), revisit A if scope grows.
- **Table-driven L2.** Binary ops (`add sub mul div`), unary (`neg abs sqrt exp log sin cos ...`), predicates (`isnan isinf iszero ...`) defined from a list via `@eval` loops, each one-liner. Keeps hand-written code to the genuinely different cases.
- **Naming.** Types: `Mag`, `Arf`... decide once; plan proposes `ArfFloat`, `MagFloat`, `NFloat`. Mutating funcs: Julia `!` convention with destination first (`add!(z,x,y)`).
- **`<: AbstractFloat` (confirmed).** `ArfFloat`, `MagFloat`, `NFloat`, `DFloat{N}`, `ArbFloat` subtype `AbstractFloat`. Complex ball: `Complex{ArbFloat}` vs dedicated `AcbFloat <: Number` — decide in M2b by benchmark. Implement the minimal set: `precision`, `eps`, `significand`, `exponent`, `nextfloat`/`prevfloat` (where defined), `isfinite`, `isnan`, `isinf`, `signbit`; `floatmin`/`floatmax` documented as precision-dependent or erroring for arbitrary-precision types. Fixed-size types (`NFloat`, `DFloat`) can give real `eps`/`floatmax`. Ball `==` means exact midpoint/radius equality, not enclosure equality; provide `contains`/`overlaps`.
- **Follow Base semantics.** Implement `Base.:+`, `Base.sqrt`, `Base.isnan`, `Base.convert`, `Base.promote_rule`, `Base.hash`, `Base.:(==)`, `Base.isless`, `Base.Rounding`/`rounding` where meaningful. `<: AbstractFloat`. Avoid private parallel vocabulary.
- **No raw pointers in public API.** Internal `unsafe_*` helpers are prefixed and documented.
- **File size / cohesion.** One concept per file, under ~300 lines. `FlintFloats.jl` is includes + exports only.
- **Docs.** Docstrings mirror FLINT function names ("wraps `arf_add`") so users can cross-reference the C docs. Documenter site already scaffolded in `docs/`.

## 5. Dependencies

- Add `FLINT_jll` to `[deps]` with a `[compat]` bound. README says "latest" jll; pin lower bound to the first version providing FLINT 3.x (needed for `nfloat`; `arf`/`mag`/`arb` live in FLINT ≥ 3.0 since Arb merged into FLINT — verify the exact jll version and library names before locking).
- Keep runtime deps minimal: `FLINT_jll` only. Optional (weak deps/extensions): `Nemo`/`Arblib` interop, `MultiFloats`, `IntervalArithmetic` conversion — via Julia 1.9+ package extensions, never hard deps.
- Julia compat: set `julia = "1.13"` in Project.toml (currently `1.10.10`). Update CI matrix (drop 1.10; test 1.13 + nightly). Allows `ScopedValue` and package extensions without shims.
- Dev-only: `BenchmarkTools`, `Clang` in `gen/` and `benchmark/` Project.tomls, not the main one.

## 6. Testing

- **Differential vs BigFloat/Float64:** random inputs, same precision, correctly-rounded ops must match bit-for-bit (`arf` rounding is exact-by-spec, so this is a strong oracle).
- **Edge cases:** ±0, ±Inf, NaN, subnormal-range Float64 conversion, huge exponents (beyond `Int64` → fmpz path), precision 1 and 2^20.
- **Memory:** loop creating 10^7 temporaries; assert RSS bounded (finalizer correctness). Run with `--check-bounds=yes` and GC stress (`GC.gc()` between ops) to catch missing `GC.@preserve`.
- **Allocation tests:** `@allocated add!(z,x,y) == 0` for every in-place op.
- **Layout tests:** `sizeof(arf_struct) == 32` etc. checked against the library at test time (via a tiny C-free check using FLINT's own `flint_*` size queries if available, otherwise against documented sizes).
- CI already exists (`.github/workflows/CI.yml`); use Julia 1.13 + nightly matrix, plus a benchmark-regression job.

## 7. Risks / things to verify before coding

1. Exact struct layouts and sizes (arf's mantissa union, 32-bit vs 64-bit). Verify by `ccall` into FLINT or read installed headers inside `FLINT_jll` artifact.
2. Which functions are real exported symbols vs `static inline` in headers (inline functions have **no** symbol to `ccall`; must be reimplemented in Julia or skipped). This matters: many `mag_*`/`arf_*` helpers are inline. Audit with `nm -D libflint.so`.
3. `FLINT_jll` version and library product name for the current release.
4. `nfloat`/`gr` API stability — newest part of FLINT, expect changes.
5. `dfloat`: exists per docs (3.7.0-dev). Still unverified: minimum FLINT version / whether the current `FLINT_jll` ships it, which functions are exported symbols vs inline/macros, and the real struct sizes. `dfloat_is_supported()` may be false on some platforms.

## 8. Review of this plan — improvements found

Review pass looked for gaps, over-engineering, and risk. Changes folded in above are marked ✔; open ones need owner input.

1. ✔ **Original impulse: wrap everything.** Too broad. Cut to `mag`+`arf` first; balls and `nfloat` deferred. Ship a working, benchmarked core before widening.
2. ✔ **Inline-symbol trap** (§7.2) was the biggest hidden risk: a binding generator will happily emit `ccall`s to symbols that do not exist. Add an `nm`-based check that every L0 binding resolves at load/test time.
3. ✔ **Per-object finalizer overhead** drove the `ArfVector` contiguous design (§3.3). Without it, matrix-scale use would be dominated by GC.
4. ✔ **Precision as global was a performance and correctness hazard** (task-safety, repeated lookup). Moved to explicit args at L0/L1 and scoped state at L2.
5. ✔ **Generator choice**: Clang.jl is heavier than needed for ~80 functions; table+macro is clearer to read and review. Revisit if scope grows.
6. ✔ **Benchmarks as a gate** rather than an afterthought; define the <10% overhead target up front.
7. ✔ **Resolved — Julia floor 1.13.** No `ScopedValue` fallback code.
8. ✔ **Resolved — subtype `AbstractFloat`.** Cost: variable-precision semantics for `eps`/`nextfloat`/`floatmax` must be defined and documented (§4).
9. ✔ **Resolved — balls and `dfloat` in scope.** Naming settled as `*Float` suffix. `dfloat` now confirmed (§3a); isbits, so it is the cheapest type to bring up. Risk: it may need a newer `FLINT_jll` than the rest (§7.5). `nfloat` stays phase 3; share the `gr`-context layer with dfloat's optional generic path.
10. **Open — overlap with Arblib.jl/Nemo.jl.** Both already wrap `arf`/`arb`. Differentiator should be stated: the `nfloat` fixed-precision path and in-place/vector-first design. If phase 3 prototype shows no speed win, reconsider scope.
11. **Not recommended:** SIMD/threaded reimplementation of arithmetic in Julia, custom allocator for wrappers, BigFloat-backed storage. All add complexity for gains FLINT already provides.

## 9. Milestones

1. **M0** — set Julia 1.13 floor, add `FLINT_jll`, verify symbols and struct sizes (`nm`, layout test), confirm `FLINT_jll` ships `dfloat` and which `dfloat` symbols export, CI green.
2. **M1** — L0/L1 for `mag`, `arf`; `ArfFloat` scalar type with finalizer; in-place ops; `Float64`/`BigFloat`/`Int` conversion; `show`. Differential + allocation tests.
3. **M2** — operator layer, precision scoping, `ArfVector`, benchmarks vs `BigFloat` and Arblib.
4. **M2b** — `arb`/`acb` (`ArbFloat`, complex type decision by benchmark).
5. **M2c** — `dfloat` (`DFloat{N}`, `DFloatBall{N}`, complex): isbits types, `ccall` binding, `dfloat_is_supported` gate, benchmark native-Julia fast paths vs FLINT.
6. **M3** — `nfloat` on a `gr` layer; performance go/no-go.
7. **M4** — package extensions, docs, registration.
