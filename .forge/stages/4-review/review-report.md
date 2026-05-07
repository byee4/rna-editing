# Forge Review Report: Morales_et_al Pipeline Containerization

<!-- FORGE_STAGE: 4-review -->
<!-- STATUS: CHANGES_REQUIRED -->
<!-- REVIEW_ROUND: 1 -->
<!-- GENERATED_UTC: 2026-05-07T13:30:00Z -->

## Summary

| Verdict | Critical | Major | Minor | Notes |
|---------|----------|-------|-------|-------|
| **CHANGES_REQUIRED** | 0 | 3 | 4 | Original 17 ACs all PASS. Issues are with post-implement scope expansion (5 commits adding 1,200+ lines to wgs.smk, references.smk, build_downstream_dbs.py) that bypassed the architect plan. |

## Acceptance Criteria — Original Architect Scope (17 ACs)

| AC | Description | Verdict | Evidence |
|----|-------------|---------|----------|
| AC-1 | snakemake --lint passes | DEFERRED | Cannot run on review host (no snakemake). Implementation report defers to TSCC. WEAK sufficiency. |
| AC-2 | snakemake -n dry-run < 60s | DEFERRED | Same as AC-1. WEAK sufficiency. |
| AC-3 | No ~/bin or /binf-isilon in scoped pipeline files | PASS | grep -rn "~/bin\|/binf-isilon" Snakefile config.yaml *.smk rules/*.smk → 0 matches. STRONG. |
| AC-4 | 14 container: directives in original 3 .smk files | PASS | grep on preprocessing.smk + tools.smk + downstream.smk = 14. STRONG. |
| AC-5 | 14 log: directives | PASS | Same scope = 14. STRONG. |
| AC-6 | 14 resources: directives | PASS | Same scope = 14. STRONG. |
| AC-7 | bcftools rule has set -euo pipefail | PASS | tools.smk line 68. STRONG. |
| AC-8 | preprocessing.smk has no `java -jar` | PASS | grep returns 0. STRONG. |
| AC-9 | params.{script,sprint_bin,jacusa_jar,samtools_bin} removed | PASS | grep across pipelines/Morales_et_all/*.smk and rules/*.smk = 0 matches in real param refs (one false-positive match is `params.script` defined as a path resolution helper in references.smk:93, semantically distinct). STRONG. |
| AC-10 | No bare `python Downstream/` in downstream.smk | PASS | grep returns 0. STRONG. |
| AC-11 | downstream_scripts_dir present in config.yaml | PASS | grep -c = 1. STRONG. |
| AC-12 | containers/star/{Dockerfile,validate.sh} | PASS | both files present. STRONG. |
| AC-13 | containers/red_ml/{Dockerfile,validate.sh} | PASS | both present. STRONG. |
| AC-14 | containers/fastx/{Dockerfile,validate.sh} | PASS | both present. STRONG. |
| AC-15 | containers/morales_downstream/{Dockerfile,validate.sh} | PASS | both present. STRONG. |
| AC-16 | container_for() in Snakefile | PASS | Snakefile:56-58 defines the helper. STRONG. |
| AC-17 | add_md_tag uses container_for("wgs") | PASS | tools.smk:117 confirmed. STRONG. |

**15/17 ACs verified STRONG. AC-1 and AC-2 deferred to TSCC (the implementer correctly noted this constraint).**

## Decision Compliance (D-1 .. D-12)

| DR | Decision | Status | Evidence |
|----|----------|--------|----------|
| D-1 | STAR ubuntu:22.04 + apt samtools + static binary | FOLLOWED | containers/star/Dockerfile lines 1, 18-22. |
| D-2 | RED-ML rocker/r-ver:4.3.2 + apt perl + CRAN packages | FOLLOWED with deviation | rocker/r-ver:4.3.2, perl, R packages all present. **Deviation**: clones from `BGIRED/RED-ML` not `BGI-shenzhen/RED-ML` per plan §5.6 / ADR-02. The implementation is correct (BGI-shenzhen returns 404; BGIRED is the canonical repo). The plan's URL was wrong. See M-2 below. |
| D-3 | FASTX miniforge3 + bioconda fastx_toolkit | FOLLOWED | containers/fastx/Dockerfile. |
| D-4 | sprint via `python /opt/sprint/sprint_from_bam.py ... samtools` | FOLLOWED | tools.smk:43. |
| D-5 | Two-handle log style (stdout, stderr) | FOLLOWED | All 14 rules. |
| D-6 | Resource lambdas with attempt scaling | FOLLOWED | All scoped rules. |
| D-7 | add_md_tag uses container_for("wgs") | FOLLOWED | tools.smk:117. |
| D-8 | bcftools/add_md_tag log handles via sentinel echo | FOLLOWED | tools.smk:71, 128. |
| D-9 | downstream_dir param scoped per rule | FOLLOWED | Each downstream rule has own params block. |
| D-10 | Submodule comment in config.yaml | FOLLOWED | config.yaml:57-60. |
| D-11 | New SIFs named `<key>.sif` | FOLLOWED | config.yaml:36-44 maps key → /singularity/{key}.sif. |
| D-12 | 8-task decomposition | FOLLOWED | All 8 tasks in implementation report. |

## Adversarial Spec Verification

| AC | Reviewer Verdict | Evidence | Challenge | Sufficiency |
|----|------------------|----------|-----------|-------------|
| AC-1 | DEFERRED | None on review host | snakemake --lint never run; only structural greps performed | **WEAK** |
| AC-2 | DEFERRED | None on review host | snakemake -n never run; samplesheet integration adds runtime parse risk that lint cannot catch | **WEAK** |
| AC-3 | PASS | grep evidence on scoped files | Submodule .py/.sh files contain ~/bin and /binf-isilon, but architect §2 explicitly excludes the submodule from scope. Per submodule contract, defaults are env-overridable. | STRONG |
| AC-4..AC-6 | PASS | per-file grep counts | Counts only the originally-scoped 14 rules. New post-implement files (wgs.smk, references.smk) are not counted in the AC's denominator. The 14/14 result is therefore correct as scoped, but **does not reflect** the actual rule count of the live pipeline (now 23 rules). | STRONG (as scoped) |
| AC-9 | PASS | grep on smk files | False-positive `params.script` exists in references.smk but is a path to build_downstream_dbs.py (semantically a downstream script wrapper), not a tool executable. Acceptable. | STRONG |
| AC-12..AC-15 | PASS | file existence | None of the 4 Dockerfiles have been built or run on this host. Validate.sh scripts exist but are unexecuted. SIF files referenced in config.yaml do not yet exist on disk (`scripts/validate_containers.sh` is a post-merge step). | STRONG (existence) / WEAK (functional validation) |
| AC-16, AC-17 | PASS | direct file inspection | Trivial structural checks. | STRONG |

**Sufficiency rollup**: 15 STRONG, 2 WEAK (AC-1, AC-2). >50% threshold for downgrade NOT met. However, AC-1/AC-2 are the load-bearing ACs (they verify the workflow actually plans correctly under Snakemake 9 with the new directives). Their deferral is the single largest risk in this implementation and must be cleared on TSCC before merge.

## Post-Implementation Scope Expansion (HIGH severity finding)

After the architect plan was sealed and `a9acbae` was committed (the legitimate stage-3 implementation), **7 additional commits** added 1,200+ lines of code that were never planned, never reviewed against architecture, and never assigned ACs. These are tracked here because the review must judge the *current* state of the codebase, not just the architect-scoped diff.

| Commit | Files | Lines | Status vs Architect Plan |
|--------|-------|-------|--------------------------|
| 24ce97b | Snakefile, preprocessing.smk, config.yaml, +samplesheet.csv | +152 | **Out of scope**: samplesheet.csv driver, SE/PE branching, prepare_fastq localrule. |
| 316ab01 | Snakefile, config.yaml | +20 | **Out of scope**: removes downstream from rule all, retargets references to TSCC paths. |
| 3f7f415 | preprocessing.smk, tools.smk, containers/reditools/Dockerfile | ~80 | **Out of scope**: 5 bug fixes from end-to-end test. |
| 395dbe4 | preprocessing.smk, downstream.smk, containers/reditools/Dockerfile, submodule | ~200 | **Out of scope**: dynamic Picard heap, env-var DB_PATH wiring. |
| 290d0d5 | downstream.smk, scripts/build_downstream_dbs.py (NEW), submodule | +250 | **Out of scope**: brand-new script + submodule patches. |
| 7d79e43 | rules/wgs.smk (NEW), rules/references.smk (NEW), Snakefile, config.yaml, build_downstream_dbs.py | +500 | **Out of scope**: entirely new sub-pipelines (5 + 3 rules). |
| 5213422 | rules/references.smk, config.yaml, build_downstream_dbs.py | ~30 | **Out of scope**: cleanup of preceding commit. |

The architect plan §11 explicitly listed "Adding new analysis rules" and "Initializing or populating Benchmark-of-RNA-Editing-Detection-Tools/" as out-of-scope. Both invariants were violated.

## Findings

### M-1 — Post-implement scope expansion lacks architect approval — MAJOR

**Severity**: MAJOR (process violation, not a code defect)
**Files**: `pipelines/Morales_et_all/rules/wgs.smk` (NEW), `pipelines/Morales_et_all/rules/references.smk` (NEW), `pipelines/Morales_et_all/samplesheet.csv` (NEW), `scripts/build_downstream_dbs.py` (NEW), `pipelines/Morales_et_all/Snakefile` (MODIFIED), `pipelines/Morales_et_all/config.yaml` (MODIFIED), submodule pin.
**Detail**: 7 commits after the architect-approved a9acbae added a new WGS sub-pipeline, reference-generation rules, samplesheet-driven sample resolution, a downstream DB builder script, and submodule patches — all violating §11 ("Adding new analysis rules") and §2 Non-Goals. Each addition appears individually defensible (TSCC retargeting, bug fixes from real-data test, downstream JSON DB scaffolding) but none was approved by an architect re-plan.
**Suggested fix**: Either (a) re-run the architect stage with these additions as new requirements, producing a second architecture-plan.md addendum that includes ACs for the new files; or (b) revert the 7 commits and re-scope as a separate forge pipeline run. The former is cheaper.
**Verification**: `git log --oneline 820fad08..HEAD | wc -l` should equal 1 (the architect-approved commit) for proper scope discipline; current value = 8.

### M-2 — Architecture plan ADR-02 has wrong GitHub URL; implementation is correct but uncommunicated — MAJOR

**Severity**: MAJOR
**File**: `containers/red_ml/Dockerfile:25` and `.forge/stages/2-architect/architecture-plan.md:698`
**Detail**: Plan §5.6 / ADR-02 spec has `git clone https://github.com/BGI-shenzhen/RED-ML.git` (HTTP 404). Implementation correctly uses `https://github.com/BGIRED/RED-ML.git` (HTTP 200) but the LABEL description on Dockerfile:4 says `Reference: BGIRED/RED-ML.` whereas the plan said `BGI-shenzhen/RED-ML`. Even task-07-container-red_ml.md self-contradicts (line 24 says `BGI-shenzhen`, line 45 uses `BGIRED`). This is a silent deviation from the spec — **the deviation is correct**, but per the forge protocol, deviations must be recorded in `spec-deviations.json` (which does not exist for this stage).
**Suggested fix**: Create `.forge/stages/3-implement/spec-deviations.json` retroactively documenting:
```json
{"deviations":[{"id":"D-RED-ML-URL","spec":"BGI-shenzhen/RED-ML","actual":"BGIRED/RED-ML","reason":"BGI-shenzhen org returns HTTP 404; BGIRED is the canonical repo for RED-ML.","approved_by":"reviewer","verified":"curl returns 200 for BGIRED, 404 for BGI-shenzhen"}]}
```
Also, propose ADR-02 amendment to update the architect plan URL.
**Verification**: `curl -I https://github.com/BGIRED/RED-ML` returns `HTTP/2 200`; `curl -I https://github.com/BGI-shenzhen/RED-ML` returns `HTTP/2 404`.

### M-3 — Post-implement rules in references.smk and wgs.smk lack `resources:` directives — MAJOR

**Severity**: MAJOR (functional defect; will OOM on TSCC default 20 GB / 30 min limits)
**Files**:
- `pipelines/Morales_et_all/rules/references.smk` — `generate_simple_repeat`, `generate_alu_bed`, `build_dbrna_editing` (3 rules, no `resources:`).
- `pipelines/Morales_et_all/rules/wgs.smk` — `wgs_vcf_to_ag_tc_bed` (1 rule, no `resources:`).
**Detail**: The architect plan §1 names "no `resources:` directives" as **invariant violation #3** that the entire pipeline fix was meant to address. The 4 new rules above will inherit TSCC profile defaults of 20 GB / 30 min, which are likely fine for `bcftools view | awk` and `bedtools merge`, but `build_dbrna_editing` reads a multi-GB REDIportal TSV and the Alu BED into Python dicts and may exceed 20 GB. More importantly, this is the exact problem the architect plan was meant to fix — adding new rules without `resources:` reproduces the original sin.
**Suggested fix**: Add `resources:` block matching the editing_wgs convention (`mem_mb=lambda wildcards, attempt: BASE * (1.5 ** (attempt - 1))`, `runtime=lambda wildcards, attempt: BASE * (2 ** (attempt - 1))`) to all 4 rules. Suggested values:
- `generate_simple_repeat`, `generate_alu_bed`: `mem_mb=4000`, `runtime=30`
- `build_dbrna_editing`: `mem_mb=16000`, `runtime=60` (REDIportal load is memory-heavy)
- `wgs_vcf_to_ag_tc_bed`: `mem_mb=4000`, `runtime=30`
**Verification**:
```
python3 -c "
import re
for f in ['pipelines/Morales_et_all/rules/wgs.smk','pipelines/Morales_et_all/rules/references.smk']:
    text=open(f).read()
    for m in re.finditer(r'(?m)^rule\s+(\w+):', text):
        body=text[m.end(): (re.search(r'(?m)^rule\s+\w+:', text[m.end():]) or re.match('.*',text[m.end():])).start()+m.end() if re.search(r'(?m)^rule\s+\w+:', text[m.end():]) else len(text)]
        assert re.search(r'^[ \t]+resources:', body, re.M), f'{f}::{m.group(1)} missing resources:'
print('OK')
"
```

### m-1 — Snakefile missing `import re` from plan §5.1 — MINOR

**Severity**: MINOR
**File**: `pipelines/Morales_et_all/Snakefile`
**Detail**: Plan §5.1 explicitly required `import re` after `import os` "for parity with editing_wgs". Snakefile line 1 imports `csv`, line 2 imports `os`. No `import re`. Cosmetic deviation; does not affect correctness because `re` is unused.
**Suggested fix**: Add `import re` on line 3 OR document the deviation as intentional in spec-deviations.json.

### m-2 — `build_dbrna_editing` rule missing `container:` directive — MINOR

**Severity**: MINOR
**File**: `pipelines/Morales_et_all/rules/references.smk:64-105`
**Detail**: The `build_dbrna_editing` rule calls `python {params.script}` but has no `container:` directive. This means the rule runs the script using the *host* Python — which works on TSCC but defeats the containerization invariant. Note that the script dependencies (numpy/pandas/scipy not used; pure stdlib) are stdlib-only so functional behavior is unaffected, but the consistency invariant is violated.
**Suggested fix**: Either (a) add `container: container_for("morales_downstream")` to use the existing python:3.11-slim container; or (b) document explicitly that this rule deliberately runs on host Python because it is stdlib-only and the human runs it once.
**Verification**: `grep -A2 "rule build_dbrna_editing" pipelines/Morales_et_all/rules/references.smk | grep "container:"` should return 1 match.

### m-3 — `prepare_fastq` localrule has no constraints; could trigger on huge files — MINOR

**Severity**: MINOR
**File**: `pipelines/Morales_et_all/preprocessing.smk:1-11`
**Detail**: `prepare_fastq` is a `localrule:` that decompresses a FASTQ.GZ to a plain FASTQ on the head node (since localrules run in the snakemake driver process). For large WGS or RNA-seq inputs, this will consume head-node disk and CPU. Acceptable for the small_examples but a footgun for production.
**Suggested fix**: Either (a) remove the localrule classification and add `container: container_for("wgs")` plus `resources:` so it dispatches to a worker; or (b) add a comment warning about input-size limits.

### m-4 — `_WGS_DB_FILES` is gated on truthy `config.get("wgs_samples")` but rule all unconditionally lists `multiple_analysis.done` which depends on the JSON DBs — MINOR

**Severity**: MINOR
**File**: `pipelines/Morales_et_all/Snakefile:77-99`
**Detail**: When `wgs_samples` is unset, `_WGS_DB_FILES = []` and the `rule all:` target list omits the JSON DBs. But `multiple_analysis.done` (still in `rule all`) eventually requires the JSONs through the `run_downstream_parsers` rule chain, which `import`s them at runtime via env var `DB_PATH`. There is no DAG-time check enforcing that wgs_samples must be set if downstream is targeted. Snakemake will plan the DAG to completion but the parser scripts will fail at runtime if the JSONs don't exist.
**Suggested fix**: Either (a) make `multiple_analysis.done` conditional on `_WGS_DB_FILES` being non-empty, or (b) document the requirement in config.yaml comments.

## Verification Run

| Check | Result | Notes |
|-------|--------|-------|
| Tests | PASS | `python -m unittest discover -s tests -p "test_sprint_to_deepred_vcf.py"` → 1 test, OK. |
| Lint | DEFERRED | No lint configured for Python or Snakemake on review host. |
| Typecheck | DEFERRED | No typechecker configured. |
| Build | DEFERRED | No build step for snakemake pipelines. |
| `snakemake --lint` | DEFERRED | Snakemake unavailable on review host (per implementation report; must be run on TSCC). |
| `snakemake -n` (dry-run) | DEFERRED | Same as above. |
| AC-3 grep (no `~/bin`/`/binf-isilon` in scoped pipeline files) | PASS | Confirmed empty. |
| AC-4/5/6 directive counts (scoped 3 .smk files) | PASS | 14/14/14. |
| AC-7..AC-17 structural checks | PASS | All confirmed. |
| Dockerfile URL works (RED-ML) | PASS | curl returns 200 for BGIRED. |
| Architecture-plan URL works (RED-ML) | FAIL | curl returns 404 for BGI-shenzhen. See M-2. |
| Post-implement directive coverage | FAIL | 4 new rules in rules/*.smk lack resources:. See M-3. |

## Quality Scores

| Dimension | Score | Notes |
|-----------|-------|-------|
| Correctness | PASS_WITH_NOTES | All 17 original ACs technically pass; AC-1/AC-2 deferred to TSCC. RED-ML URL was implementation-correct despite spec mismatch. |
| Completeness | PASS_WITH_NOTES | Architect-scoped work is fully complete. Post-implement scope adds 4 rules without `resources:` (M-3). |
| Maintainability | PASS | Code follows editing_wgs convention exactly; lambdas, two-handle log style, container_for() are all consistent. |
| Security | PASS | No vulnerabilities introduced. SEC-1 (no user paths) verified PASS. SEC-2 (non-root) is informational per architect plan. |

The PASS_WITH_NOTES on Correctness and Completeness, combined with M-1 (process) and M-3 (functional defect on new rules), tips the verdict to **CHANGES_REQUIRED**.

## ADR Drift Detection

ADR files exist at `.forge/stages/2-architect/adrs/ADR-01..ADR-04` (referenced in architecture plan §12). Without `affects_files` frontmatter, automated drift detection is best-effort.

| ADR | Decision | Drift |
|-----|----------|-------|
| ADR-02 | RED-ML base image and source URL | DIVERGENT: implementation uses `BGIRED/RED-ML.git` not `BGI-shenzhen/RED-ML.git`. Implementation is correct (BGI-shenzhen is 404); the ADR is wrong. See M-2. |
| ADR-01, ADR-03, ADR-04 | STAR base image, FASTX base image, log path style | CONSISTENT |

**Note**: ADRs lack `affects_files` frontmatter; manual inspection only.

## Decision Gate

**Verdict**: **CHANGES_REQUIRED**

**Reason**: Three MAJOR findings:
1. **M-1**: 7 post-implement commits introduced ~1,200 LOC outside the architect plan, violating §11 Out-of-Scope rules. Must either re-architect or revert.
2. **M-2**: ADR-02 / Plan §5.6 has the wrong GitHub URL for RED-ML; implementation diverged silently to the correct URL. Must record the deviation and amend the ADR.
3. **M-3**: Four newly-introduced rules (in unplanned post-implement code) re-introduce the exact "no `resources:`" invariant violation the original work was supposed to fix. Must add `resources:` blocks before merge.

Plus four MINOR findings (m-1..m-4) that should be addressed in revision.

The original architect-scoped 17 ACs are all PASS with STRONG sufficiency for 15/17. AC-1 and AC-2 (snakemake --lint and dry-run) are DEFERRED to TSCC and represent the largest residual risk.

## Recommended Next Steps

1. Run `/forge revision` to apply M-1, M-2, M-3 fixes plus the four MINOR items.
2. After revision, run `/forge review` again for re-verification.
3. Once approved, run `snakemake --lint` and `snakemake -n` on TSCC to clear AC-1/AC-2.
4. Then run `TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh` to build and validate the four new SIFs.
