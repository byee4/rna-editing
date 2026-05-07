# Deployment Checklist — rna-editing v0.2.0

**Pipeline run:** forge-8a8d6b83  
**Date:** 2026-05-07

---

## Pre-Deployment Checks

### Sign-offs
- [ ] Forge pipeline complete through 8-release (this document)
- [ ] CI last run: conclusion=success on `main` branch
- [ ] QA verdict: GO_WITH_NOTES (38/38 tests pass; 1 minor accepted finding)
- [ ] Review verdict: APPROVED (round 2; 0 critical, 0 major, 1 deferred minor)
- [ ] Docs stage: COMPLETE (7 artifacts, 1 TBD: escalation contact in runbook)
- [ ] 6-security: SKIPPED with justification (internal HPC research pipeline)

### Pre-Merge Quality Gates
- [ ] Run unit tests locally and confirm pass:
  ```bash
  python -m unittest tests/test_morales_pipeline_spec.py
  python -m unittest tests/test_sprint_to_deepred_vcf.py
  ```
- [ ] Confirm working tree is clean: `git status`
- [ ] Tag the release commit:
  ```bash
  git tag -a v0.2.0 -m "Morales_et_all Snakemake 9+ containerization"
  git push origin v0.2.0
  ```

---

## Deploy Steps

> These steps apply to TSCC deployment. Steps 3-4 require human access to TSCC.

### Step 1 — Pull latest on TSCC

```bash
git pull --rebase
git log --oneline -3   # verify expected commits present
```

### Step 2 — Verify submodule (if running downstream rules)

```bash
git submodule status pipelines/Morales_et_all/Benchmark-of-RNA-Editing-Detection-Tools
# If shows '-' prefix (not initialized):
git submodule update --init pipelines/Morales_et_all/Benchmark-of-RNA-Editing-Detection-Tools
```

### Step 3 — Build the four new SIF containers

```bash
module load singularitypro
conda activate snakemake9

# Preview what will be built (dry run — review before executing):
TOOLS="star red_ml fastx morales_downstream" CONTAINER_DATA_ROOT=/path/to/output \
  scripts/validate_containers.sh --dry-run 2>/dev/null || \
  echo "Note: validate_containers.sh may not support --dry-run; review Dockerfiles before building"

# Build and validate:
TOOLS="star red_ml fastx morales_downstream" \
  SIF_OUTPUT_DIR=/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity \
  scripts/validate_containers.sh
```

Expected output per container: `PASS: validate-<tool> exited 0`

### Step 4 — Update config.yaml SIF paths

Edit `pipelines/Morales_et_all/config.yaml` so `singularity_image_dir` points to the directory containing the new SIFs, and verify:

```bash
grep singularity_image_dir pipelines/Morales_et_all/config.yaml
```

### Step 5 — Verify dry-run on TSCC

```bash
module load singularitypro
conda activate snakemake9
cd examples
unset SLURM_JOB_ID
snakemake -ns ../pipelines/Morales_et_all/Snakefile \
  --configfile ../pipelines/Morales_et_all/config.yaml \
  --profile /tscc/nfs/home/bay001/projects/codebase/rna-editing/profiles/tscc2 \
  --use-singularity
```

Expected: exits 0, lists ~67 jobs.

---

## Post-Deployment Checks

- [ ] Dry-run exits 0 with no ERROR lines (Step 5 above)
- [ ] All 4 container SIFs present in `singularity/`:
  ```bash
  ls singularity/star.sif singularity/red_ml.sif singularity/fastx.sif singularity/morales_downstream.sif
  ```
- [ ] `tests/test_morales_pipeline_spec.py` still passes after container builds
- [ ] Complete an end-to-end test run on `pipelines/Morales_et_all/data/` test data
- [ ] Update `deployment-runbook.md` TBD: fill in escalation contact (PI email) on line 120

---

## Rollback Steps

If dry-run fails or end-to-end run produces incorrect results:

```bash
# Revert containerization commits (non-destructive: creates a revert commit)
git revert 820fad0..HEAD --no-edit
git push origin main

# editing_wgs pipeline is unaffected; continue using it as before

# File a bug report:
bd q "Rollback: Morales_et_all containerization — <error summary>" --type bug
```

> Note: `git revert` is used (not `reset --hard`) to preserve audit trail.

---

## Release Artifacts

| Artifact | Path | Status |
|----------|------|--------|
| Release plan | `.forge/stages/8-release/release-plan.md` | GENERATED |
| Deployment checklist | `.forge/stages/8-release/deployment-checklist.md` | GENERATED (this file) |
| Release notes | `.forge/stages/8-release/release-notes.md` | GENERATED |
| SLSA provenance | `.forge/stages/8-release/provenance.json` | GENERATED (unsigned) |
| CHANGELOG.md | `CHANGELOG.md` | UPDATED (stage 7) |
| API reference | `.forge/stages/7-docs/api-reference.md` | GENERATED (stage 7) |
| Deployment runbook | `.forge/stages/7-docs/deployment-runbook.md` | GENERATED (stage 7) |
| User guide | `.forge/stages/7-docs/user-guide.md` | GENERATED (stage 7) |
