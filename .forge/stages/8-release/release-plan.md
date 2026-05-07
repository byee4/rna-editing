# Release Plan — rna-editing v0.2.0

**Pipeline run:** forge-8a8d6b83  
**Date:** 2026-05-07  
**Release type:** Minor — new pipeline sub-system (no public API break)

---

## 1. Release Scope

### User-Visible Changes

| Change | Description |
|--------|-------------|
| Morales_et_all fully containerized | All 22 non-localrule rules now carry `container:`, `log:`, and `resources:` directives; the pipeline runs end-to-end with `--use-singularity` on TSCC2 |
| Four new container build contexts | `containers/star/`, `containers/red_ml/`, `containers/fastx/`, `containers/morales_downstream/` — each includes a `validate.sh` script |
| Samplesheet-driven config | `Snakefile` reads `samplesheet.csv` at runtime; SE/PE detection is automatic |
| Reference DB generation rules | `references.smk`: `generate_simple_repeat`, `generate_alu_bed`, `build_dbrna_editing` |
| WGS sub-pipeline | `wgs.smk`: `wgs_bwa_mem` through `wgs_vcf_to_ag_tc_bed`; activated when `wgs_samples` is set in config |
| `scripts/build_downstream_dbs.py` | Builds HEK293T, REDIportal, Alu JSON databases; supports gzip input |
| `container_for()` helper | Mirrors `editing_wgs` pattern; enables per-tool SIF override |
| QA test suite | `tests/test_morales_pipeline_spec.py` — 37 spec-derived tests |

### Non-Visible Changes

- `tools:` section removed from `config.yaml`; replaced by `containers:` block
- `set -euo pipefail` added to all shell rules
- Wildcard constraints on `condition`, `sample`, `wgs_sample`
- `import re` added to `Snakefile` header
- `mark_duplicates` uses Picard wrapper (`/usr/local/bin/picard`), not `java -jar`
- `star_mapping` adds `--outSAMattrRGline` for Picard compatibility
- Per-rule `threads` and `mem_mb` resources with SLURM-compatible defaults
- Architecture addendum + spec-deviations.json created for audit trail

### Breaking Changes

None. The `editing_wgs` pipeline is untouched. The Morales config schema changes are backwards-compatible for new deployments (no existing production users of Morales config).

---

## 2. Version Bump Recommendation

**Previous version:** untagged (last tag: none in repo)  
**Recommended version:** `v0.2.0`

Rationale (SemVer):
- `0.1.0` is implicitly the `editing_wgs` initial pipeline
- `0.2.0` adds the Morales_et_all sub-system (new feature, no break)
- Not `1.0.0` — production-ready but not yet declared stable for external release

---

## 3. Rollout Strategy

Three options evaluated:

| Option | Description | Risk |
|--------|-------------|------|
| A. Tag + merge (chosen) | Tag `v0.2.0` on main; no feature flags; HPC pipeline has no staged rollout | Low |
| B. Branch-based staging | Merge to a `staging` branch; run on TSCC test data; then fast-forward main | Low-Medium |
| C. PR with protected main | Open PR, require CI pass + 1 review, merge | Low |

**Chosen: Option A** — This is an HPC research pipeline with a single team of users. The feature is already validated by the forge QA stage (38/38 tests pass, dry-run PASS at 67 jobs). A tag + merge is proportionate.

---

## 4. Deployment Prerequisites

1. **Build 4 new container SIFs on TSCC** (human step, post-merge):
   ```bash
   module load singularitypro
   conda activate snakemake9
   TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh
   ```
   Output SIFs go to `singularity/` (or wherever `SIF_OUTPUT_DIR` is set).

2. **Initialize the benchmark submodule** (if running downstream rules):
   ```bash
   git submodule update --init pipelines/Morales_et_all/Benchmark-of-RNA-Editing-Detection-Tools
   ```

3. **Set `wgs_samples` in config.yaml** if WGS sub-pipeline is needed. Omitting the key disables WGS rules; do not leave it empty string (causes runtime failure — documented with IMPORTANT comment).

4. **Update `singularity_image_dir` in config.yaml** to the path where the four new SIFs were built.

5. **CI** — `forge-ci.yml` passed last run (conclusion: success).

---

## 5. Rollback Plan

**Triggers:**
- Snakemake dry-run fails after merge
- Container build fails for any of the 4 new images
- A production run produces clearly wrong editing calls

**Steps:**
```bash
# Step 1: revert to commit before containerization work
git revert 820fad0..HEAD --no-edit

# Step 2: re-run existing editing_wgs pipeline (untouched)
# editing_wgs is unaffected by this release

# Step 3: file an issue with error logs for triage
bd q "Rollback: Morales_et_all containerization — <error summary>" --type bug
```

The `editing_wgs` pipeline has no dependencies on Morales_et_all; rollback is surgical.

---

## 6. Verification Plan

### Pre-Deploy (before tagging)
- [ ] `git status` — working tree clean
- [ ] CI last run: `conclusion: success` (already confirmed)
- [ ] `python -m unittest tests/test_morales_pipeline_spec.py` — 37 tests pass
- [ ] `python -m unittest tests/test_sprint_to_deepred_vcf.py` — 1 test passes

### Post-Merge (on TSCC, human step)
- [ ] `conda run -p .conda/editing-wgs-snakemake snakemake -n -s pipelines/Morales_et_all/Snakefile --configfile pipelines/Morales_et_all/config.yaml` — dry-run exits 0
- [ ] `TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh` — all 4 SIFs built and validated
- [ ] End-to-end run on TSCC with test data in `pipelines/Morales_et_all/data/`
