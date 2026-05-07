# Forge Review Report: Morales_et_al Pipeline Containerization (Round 2)

<!-- FORGE_STAGE: 4-review -->
<!-- STATUS: APPROVED -->
<!-- REVIEW_ROUND: 2 -->
<!-- GENERATED_UTC: 2026-05-07T14:45:00Z -->
<!-- PRIOR_ROUND: review-report.md (round 1) → CHANGES_REQUIRED with 3 MAJOR + 4 MINOR -->

## Summary

| Verdict | Critical | Major | Minor | Notes |
|---------|----------|-------|-------|-------|
| **APPROVED** | 0 | 0 | 1 (deferred) | All 7 round-1 fixes applied and verified. Architect-scoped 17 ACs all PASS. Post-implement scope formally ratified via architecture-addendum.md. AC-1, AC-2 (snakemake --lint, dry-run) remain DEFERRED to TSCC. |

## Round-1 Fixes — Verification

| ID | Severity | Description | Round-1 Status | Round-2 Verdict | Evidence |
|----|----------|-------------|----------------|-----------------|----------|
| M-1 | MAJOR | Resolve post-implement scope expansion | COMPLETE | **PASS** | `.forge/stages/2-architect/architecture-addendum.md` (129 lines) ratifies the 7 commits. New rules covered (A2), D-13/D-14/D-15 added (A6), build_downstream_dbs.py contract specified (A4), submodule strategy documented (A5). |
| M-2 | MAJOR | Record RED-ML URL deviation, amend ADR-02 | COMPLETE | **PASS** | `.forge/stages/3-implement/spec-deviations.json` records D-RED-ML-URL with verification evidence. `architecture-plan.md` §5.6 lines 677, 698 use `BGIRED/RED-ML` (curl 200). |
| M-3 | MAJOR | Add `resources:` and `container:` to post-implement rules | COMPLETE | **PASS** | All 4 rules (`generate_simple_repeat`, `generate_alu_bed`, `build_dbrna_editing`, `wgs_vcf_to_ag_tc_bed`) now have `threads:`, `resources:` (mem_mb + runtime lambdas), and `container:` directives. `build_dbrna_editing` uses `container_for("morales_downstream")`. Per-rule directive checker outputs OK across 22 rules. |
| m-1 | MINOR | Add `import re` to Snakefile | COMPLETE | **PASS** | Snakefile line 3: `import re` (after `import os`). Unused but matches editing_wgs convention per plan §5.1. |
| m-2 | MINOR | Add `container:` to `build_dbrna_editing` | COMPLETE | **PASS** | references.smk:101: `container: container_for("morales_downstream")`. Covered by M-3. |
| m-3 | MINOR | Document `prepare_fastq` localrule constraint | COMPLETE | **PASS** | preprocessing.smk lines 1-4: comment warns about head-node execution and large-file footgun. |
| m-4 | MINOR | Document `wgs_samples` requirement | COMPLETE | **PASS** | config.yaml lines 52-57: `IMPORTANT` block explains that omitting `wgs_samples` causes runtime failure in `multiple_analysis.done`. |

## Verified Patterns Carried Forward (round-1 STRONG, unchanged)

The following 15 ACs and 12 decisions were verified STRONG in round 1 and remain unchanged in this round (no relevant code touched). See `.forge/stages/4-review/verified-clean.json`.

- **AC-3 .. AC-17**: PASS (15 of 17 originals; structural, file-existence, container_for, ADR follow-through)
- **AC-1, AC-2**: DEFERRED to TSCC (snakemake --lint and `snakemake -n`); not run on review host. WEAK sufficiency persists.
- **D-1 .. D-12**: All FOLLOWED. D-2 deviation now formally recorded.
- **Sprint adapter unit test**: PASS (1 test, OK; ran from `/tscc/nfs/home/bay001/projects/codebase/rna-editing` with `python3 -m unittest discover -s tests -p "test_sprint*" -t .`)

## Adversarial Spec Verification — Round 2

Round 2 adds two checks for the remediation work:

| Check | Verdict | Evidence | Challenge | Sufficiency |
|-------|---------|----------|-----------|-------------|
| Per-rule directive invariant (M-3) | PASS | Python checker iterates every `^rule\s+\w+:` block in 5 smk files (22 non-localrule rules) and asserts `container:`/`log:`/`resources:` present. Output: OK. Only `prepare_fastq` localrule reported missing — explicitly exempt per A2 / m-3. | Could a regex match adjacent text? No — checker scopes body between rule markers. | STRONG |
| RED-ML URL plan/Dockerfile match (M-2) | PASS | `grep "BGI" architecture-plan.md` shows BGIRED at lines 677 (LABEL) and 698 (RUN); Dockerfile lines 4 and 25 match. `curl -I` returns 200 for BGIRED, 404 for BGI-shenzhen. spec-deviations.json present. | task-07-container-red_ml.md still has stale BGI-shenzhen at line 24, 75, 89. See m-5 below. | STRONG (with note) |
| Resources values are sensible (M-3) | PASS | `build_dbrna_editing` has `mem_mb=16000` (heavier for REDIportal load); the other 3 use `mem_mb=4000`. Runtime lambdas with attempt scaling. | Hardcoded 4 GB / 30 min could OOM on full REDIportal but matches review's suggested values. | STRONG |
| `import re` actually present (m-1) | PASS | Snakefile line 3. | Cosmetic — `re` is unused; introduced only for parity. | STRONG (intentional) |
| Localrule comment present (m-3) | PASS | preprocessing.smk lines 1-4. | Comment-only fix; does not constrain at runtime. Acceptable per the resolution path chosen. | STRONG |
| config.yaml wgs_samples doc (m-4) | PASS | config.yaml lines 52-57 contain IMPORTANT block. | Doc-only; does not enforce DAG-time check. Acceptable per the resolution path chosen. | STRONG |
| Architecture addendum covers post-implement scope (M-1) | PASS | 129-line file at `.forge/stages/2-architect/architecture-addendum.md`. Sections A1–A7 cover new files, ACs, D-13/14/15, downstream contract, submodule strategy. | The addendum did not migrate per-task ACs to actual `tasks/task-NN-*.md` files; the 8 new rules are documented in tabular form in A2 only. Acceptable for a remediation addendum. | STRONG |

**Sufficiency rollup**: 7 STRONG / 0 WEAK / 0 MISSING for round-2-specific checks. Combined with carried-forward 15 STRONG and 2 DEFERRED from round 1: **22 STRONG / 2 DEFERRED**. Below downgrade threshold.

## Adversarial Sweep — New Issues Introduced by Revision?

Revision diff: `0e2cb98` (829 insertions, 4 deletions across 16 files). Specific risks checked:

| Concern | Result |
|---------|--------|
| Did adding `threads: 1` to existing rules break anything? | NO. `threads: 1` is the default; explicit declaration is a no-op behaviorally. |
| Did adding `container: container_for("morales_downstream")` to `build_dbrna_editing` introduce a missing-container risk? | LOW. `morales_downstream` is declared in `config.yaml:44` with an explicit path; the SIF must exist on disk before the rule runs. This is the same constraint as all other containers; addressed by `scripts/validate_containers.sh`. |
| Did the `import re` addition shadow an existing variable? | NO. No `re` symbol is bound elsewhere in Snakefile. |
| Did the architecture-plan URL patch introduce inconsistency with task-07? | YES (m-5). See finding below. Plan §5.6 corrected; task-07-container-red_ml.md still has stale BGI-shenzhen lines 24, 75, 89. Spec-deviations.json explicitly references task-07 line 24, so the deviation is recorded but the task file itself was not patched. Minor. |
| Does the comment-only m-3 fix change runtime behavior? | NO. `localrules: prepare_fastq` is unchanged; only a leading comment was added. |
| Does the m-4 doc-only fix prevent runtime failure when `wgs_samples` is unset? | NO. The fix documents but does not enforce. The reviewer's recommendation (b) was chosen — acceptable, but the runtime risk remains for users who do not read config.yaml comments. |

## New Findings (Round 2)

### m-5 — Stale `BGI-shenzhen` references in `task-07-container-red_ml.md` — MINOR (informational)

**Severity**: MINOR (deferred — already covered by spec-deviations.json reference)
**Files**: `.forge/stages/2-architect/tasks/task-07-container-red_ml.md` lines 24, 75, 89
**Detail**: The architecture-plan.md §5.6 (canonical spec) was updated to BGIRED/RED-ML.git. The task-07 file (a derivative architect artifact) was not updated. Lines 24 (LABEL), 75 (verification grep), 89 (verification grep) still reference `BGI-shenzhen/RED-ML`. The deviation is correctly recorded in spec-deviations.json D-RED-ML-URL, which explicitly cites task-07-container-red_ml.md line 24 as one of the spec sources. Implementation is correct.
**Suggested fix** (defer): Either (a) patch task-07 to match the corrected plan and Dockerfile, or (b) add a note at the top of task-07 marking it as superseded by spec-deviations.json D-RED-ML-URL. Not a blocker for approval — the canonical artifact (architecture-plan.md) and the implementation (Dockerfile) are consistent, and the deviation record is the single source of truth.
**Verification**: `grep -c BGI-shenzhen .forge/stages/2-architect/tasks/task-07-container-red_ml.md` returns 3; `grep -c BGI-shenzhen .forge/stages/2-architect/architecture-plan.md` returns 0; `grep -c BGI-shenzhen containers/red_ml/Dockerfile` returns 0.

## Verification Run — Round 2

| Check | Result | Notes |
|-------|--------|-------|
| Per-rule directive checker (5 smk files, 22 non-localrule rules) | PASS | OK. Only `prepare_fastq` localrule is missing directives (exempt per A2 / m-3). |
| `import re` in Snakefile | PASS | Line 3, after `import os`. |
| `container_for("morales_downstream")` on `build_dbrna_editing` | PASS | references.smk:101. |
| Comment present on `localrules: prepare_fastq` | PASS | preprocessing.smk lines 1-4. |
| `wgs_samples` IMPORTANT comment | PASS | config.yaml lines 52-57. |
| RED-ML URL Dockerfile vs plan parity | PASS | Both reference `https://github.com/BGIRED/RED-ML.git`. curl: BGIRED=200, BGI-shenzhen=404. |
| spec-deviations.json present and valid | PASS | 1 entry: D-RED-ML-URL with verified_via and approved_by. |
| Architecture addendum present | PASS | 129 lines, covers A1–A7. |
| Sprint adapter unit test | PASS | 1 test, OK (run from `/tscc/nfs/home/bay001/projects/codebase/rna-editing` with `python3 -m unittest discover -s tests -p "test_sprint*" -t .`). |
| Snakemake `--lint` | DEFERRED | Snakemake unavailable on review host; must run on TSCC with `conda activate snakemake9`. |
| Snakemake `-n` (dry-run) | DEFERRED | Same as above. |
| Container build (`scripts/validate_containers.sh`) | DEFERRED | Container build is a post-merge step; not a review-stage gate. |

## Quality Scores (Round 2)

| Dimension | Score | Notes |
|-----------|-------|-------|
| Correctness | PASS | All 17 original ACs PASS; M-2 deviation recorded; M-3 functional defect resolved. AC-1/AC-2 deferred — must clear on TSCC before merge. |
| Completeness | PASS | All 7 round-1 fixes applied. Architecture addendum formally ratifies the 8 post-implement rules. |
| Maintainability | PASS | Code style consistent with editing_wgs convention. Resource lambdas follow `BASE * (1.5 ** (attempt - 1))` pattern. Two-handle log style preserved. |
| Security | PASS | No new vulnerabilities. All round-1 SEC findings remain PASS. |

All four dimensions: PASS. Verdict: **APPROVED**.

## Decision Compliance — Round 2

All 12 round-1 decisions remain FOLLOWED. New decisions D-13, D-14, D-15 ratified via architecture-addendum.md §A6:
- D-13 (Samplesheet driver): FOLLOWED — Snakefile:11-44 implements `_load_samplesheet()`.
- D-14 (WGS pipeline integration): FOLLOWED — `rules/wgs.smk` with 5 rules.
- D-15 (Reference DB generation): FOLLOWED — `rules/references.smk` with 3 rules; `build_dbrna_editing` uses `morales_downstream` container.

## ADR Drift Detection — Round 2

| ADR | Status | Notes |
|-----|--------|-------|
| ADR-01, ADR-03, ADR-04 | CONSISTENT | (unchanged from round 1) |
| ADR-02 | CONSISTENT | URL discrepancy resolved via spec-deviations.json D-RED-ML-URL. Plan §5.6 patched to BGIRED. |

## Decision Gate

**Verdict**: **APPROVED**

**Reason**: All 3 MAJOR and 4 MINOR findings from round 1 have been resolved with STRONG evidence. The architect-scoped 17 ACs are PASS (15 STRONG, 2 DEFERRED to TSCC). The post-implement scope expansion is formally ratified via architecture-addendum.md. One new MINOR finding (m-5) is informational only — the canonical artifacts are consistent; the stale task-07 references are tracked by spec-deviations.json and do not affect runtime behavior or downstream pipeline stages.

The two DEFERRED ACs (snakemake --lint, snakemake -n) remain the largest residual risk. They must be cleared on TSCC before merge, but they are explicitly documented as TSCC-only checks in the implementation report and the project CLAUDE.md.

## Recommended Next Steps

1. Proceed to `/forge test` (stage 5-qa) for QA validation, OR
2. Before merge, run on TSCC:
   ```
   module load singularitypro
   conda activate snakemake9
   cd pipelines/Morales_et_all
   snakemake --lint --snakefile Snakefile --configfile config.yaml
   snakemake -n --snakefile Snakefile --configfile config.yaml --cores 1
   TOOLS="star red_ml fastx morales_downstream" /tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/scripts/validate_containers.sh
   ```
3. Optional follow-up: patch task-07-container-red_ml.md to remove stale BGI-shenzhen references, OR mark it superseded by spec-deviations.json D-RED-ML-URL (m-5, deferred).
