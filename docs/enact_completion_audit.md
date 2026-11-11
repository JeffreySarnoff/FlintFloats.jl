# Enactment completion audit

This audit follows [enact_interfacing.md](enact_interfacing.md) and the current source, rather than
inferring completion from a green test count. Base implementation: `f1a9c2e`; subsequent corrections
in this change concern documentation/inventory metadata and clean-install evidence only.

Scope: seven precision-typed scalar families; the specified vector/packed interfaces and selected
five elementary functions; one supplied target, x86_64 glibc Linux with Julia 1.13/glibc 2.17 minimum.
Optional matrices, other platforms, further functions, and interoperability are not advertised.

## Section-by-section findings

| Guide requirement | Authoritative evidence inspected | Finding |
| --- | --- | --- |
| §1 priorities, baseline, pinned library | Main/wrapper Project.toml, Source.toml, Artifacts.toml, bundled checksums, capability table | Source/ABI pinned; portable wrapper 301.690.0+1 selected; stale unexecuted-build table entry corrected. |
| §2 reproducible installation and independent environments | Tracked source paths/manifests; archived-project and empty-depot install logs; separately resolved docs project | Bundle installs without compiling FLINT. Empty-depot dependencies are downloaded independently. Docs resolve without either developer manifest. Commands suppress precompile until the artifact is installed. |
| §3 seven scalar foundations and precision | src/{types,precision,dfloat,dfloatball,nfloat,arf,acf,arb,acb,conversions}.jl; construction/conversion/arithmetic/unary tests | All seven paths are present and covered by accepted numerical run; supported functions/guarantees are identified per family. |
| §4 architecture | Module include/dependency order, family sources, storage/precision helpers, packed modules, optional extension | Native lifetime/status/context details stay behind the numeric interface. The guide explicitly does not require a wholesale shared-protocol refactor. |
| §5 declarations, layouts, generation | gen/inventory.toml; 374-symbol audit; artifact-header C probe vs test/abi/layout.txt; regenerated-file hashes | Every inventoried export resolves; layout probe matches; generation unchanged. nfloat neg/abs metadata corrected to GR status after reading their pinned implementations. |
| §6 ownership and borrowing | Scalar constructors/copy/deepcopy, storage.jl, packed.jl, Serialization extension; ownership/storage/packed tests | Semantic independent copies, parent-retaining references, initialized writable C outputs, cleanup/GC, and rejection of raw persistence are implemented and tested. |
| §7 precision, contexts, status policies | precision.jl, nfloat.jl, reusable.jl; inventory source notes; all-limb root, scalar/vector/workspace tests | Type precision and strict modes are explicit; contexts are initialized at runtime and audited read-only; failures are checked before result reads; scratch commits only after success. |
| §8 Julia semantics | compare/promotion/basefloat/show/conversions sources; compare/promotion/Base/conversion tests and docs | Ball proof relations and isequal/hash are separate; unsupported ordering/conversion is explicit; selected numeric interoperability is documented without claiming future interfaces. |
| §9 arrays and packed follow-ups | arrays/reusable/packed/packed_broadcast/packed_reduce sources; focused tests; recorded benchmarks | Shape/alias/lifetime and copied-read contracts are retained. Iterator, bounded trees, fresh sum/dot/abs2 results, conjugation, callback fallback, and constant scratch have independent numerical/ownership evidence. |
| §10 numerical/performance evidence | Exact dyadic/rational references, directed MPFR and certified complex-series bounds; accepted full run; benchmark drivers/results | 34,151 checks cover the changed binary. Accuracy claims distinguish correct rounding, approximation, and enclosures. Current portable measurements identify the new tree; older reports retain historical identities. |
| §11 milestones | Capabilities, source map, selected M5 elementary implementation, accepted artifact | Scoped M0–M4 and selected M5 numerical deliverables are implemented; release publication is not marked complete. |
| §12 CI/docs/release | Hosted workflow; verified header helper and ABI script; acceptance/installation reports; licenses in artifact | Local commands and distribution inputs are verified. Actual hosted workflow passes at ce2831e, including isolated package tests; public publication remains outstanding. |
| §13 upgrades/maintenance | Version +1, Source.toml compiler/source/artifact provenance, binary/layout/symbol/numerical evidence, protected native packager | The portable replacement was accepted before selection. Old identities remain in history/provenance. Procedure remains the rule for future updates, not a request to invent another upstream revision now. |
| §14 decisions/references | Representation/context/promotion decisions, curated inventory, pinned source/header references, portable target metadata | Initial numerical decisions are resolved and supported by source/tests. Other-platform/public-release decisions remain explicitly gated. |

## Release checklist details (§12)

- Seven-family scalar/elementary contracts: source, per-family capability rows and tests are present.
- Foreign declarations/layout: 374 symbols resolve and the compiled matching-header probe agrees.
- Ownership: copy/deepcopy alias graphs, native cleanup/GC, parent retention and explicit persistence
  rejection are covered by ownership/storage/packed tests.
- Numeric semantics: independent comparison/hash, conversion/promotion, domains, precision, and
  unsupported Base behavior are covered by their corresponding test files and interface docs.
- Installation: actual bundled SHA/tree validation and public API/extension smoke pass with a new
  project and empty depot; package dependencies are fetched through Pkg's integrity-checked paths.
- Delivery/provenance/licenses: the archive and hashes exist in the repository; wrapper version and
  source/binary metadata agree; license files are installed. No fabricated remote asset URL is used.
- Target: the supplied baseline Linux artifact has build logs, ELF inspection, ABI/symbol/numerical
  acceptance and clean installation. No other target is claimed.
- Generation/docs: generated files are unchanged after regeneration. Checkout and archive docs build
  and pass doctests, including a separately resolved docs environment without developer manifests.
- Performance: recorded numbers name their workload, numerical contract, Julia/native allocation
  limits and artifact identity. They are not universal performance promises.

Draft PR #5 is open. The initial workflow expression failure was corrected and a SHA-pinned
linter now validates Actions contexts. [Hosted run 42962433938](https://github.com/JeffreySarnoff/FlintFloats.jl/actions/runs/42962433938)
passes both jobs at ce2831e, including actual package-isolated tests (34,151), ABI/symbols,
generation, and docs/doctests. [Selected logs](evidence/hosted_ci_acceptance.txt) identify the head.
The follow-up changes only evidence/checkpoints, leaving all tested code and workflow inputs
identical; numerical CI is not rerun for those documentation changes. Public merge/release
publication remains unperformed and requires authorization. The overall goal is not marked achieved.
