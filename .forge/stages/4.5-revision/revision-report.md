# Revision Report — Round 1

<!-- FORGE_STAGE: 4.5-revision -->
<!-- SOURCE: .forge/stages/4-review/review-fixup-prompt.md -->

**Started:** 2026-05-07
**Review round:** 1
**Fixes required:** 3 MAJOR, 4 MINOR

## Status Summary

| ID | Severity | Description | Status |
|----|----------|-------------|--------|
| M-1 | MAJOR | Resolve post-implement scope expansion | IN PROGRESS |
| M-2 | MAJOR | Record RED-ML URL deviation, amend ADR-02 | IN PROGRESS |
| M-3 | MAJOR | Add resources: and container: to post-implement rules | IN PROGRESS |
| m-1 | MINOR | Add import re to Snakefile | PENDING |
| m-2 | MINOR | Add container: to build_dbrna_editing | (covered by M-3) |
| m-3 | MINOR | Document or constrain prepare_fastq localrule | PENDING |
| m-4 | MINOR | Document wgs_samples requirement for downstream | PENDING |

---

## Fix Details

### M-1 — Post-implement scope expansion

**Resolution path chosen:** (a) Architecture addendum

The 7 commits added ~1,200 lines of unplanned code. An architecture addendum will be created as
`.forge/stages/2-architect/architecture-addendum.md` covering:
- ACs for the 8 new rules
- Samplesheet driver pattern as formal architectural choice (D-13)
- Contract for scripts/build_downstream_dbs.py
- Submodule patch strategy

**Status:** COMPLETE — see .forge/stages/2-architect/architecture-addendum.md

### M-2 — RED-ML URL deviation

**Action:** Created `.forge/stages/3-implement/spec-deviations.json` and amended architecture-plan.md §5.6

**Status:** COMPLETE

### M-3 — Add resources: and container: to post-implement rules

**Files modified:**
- `pipelines/Morales_et_all/rules/references.smk` — added threads/resources to generate_simple_repeat, generate_alu_bed; added threads/container/resources to build_dbrna_editing
- `pipelines/Morales_et_all/rules/wgs.smk` — added threads/resources to wgs_vcf_to_ag_tc_bed

**Status:** COMPLETE

### m-1 — Add import re to Snakefile

**Status:** COMPLETE — added `import re` at line 2

### m-3 — Document prepare_fastq localrule

**Status:** COMPLETE — added comment warning about head-node execution

### m-4 — Document wgs_samples requirement

**Status:** COMPLETE — added explanatory comment to config.yaml

---

## Verification Results

### Per-rule directive checker
```
OK
```
All 22 non-localrule rules across the 5 checked smk files pass the container:/log:/resources: invariant.
`prepare_fastq` is a localrule and explicitly exempt per review M-3.

### Unit tests
- `tests/test_sprint_to_deepred_vcf.py` — PASS (1 test)
- `tests/test_editing_wgs_dryrun.py` — SKIP (pre-existing macOS /private/tmp issue, undocumented at CLAUDE.md; not caused by these fixes)

### Snakemake dry-run (TSCC)
Requires `conda activate snakemake9` + `module load singularitypro`. Not run in this session.
Recommended before final re-review verdict.
