# Task 02: Update config.yaml — containers block, downstream_scripts_dir, remove tools section

<!-- DEPENDENCIES: 01 -->
<!-- LABELS: phase-3, stage:3-implement, config-edit -->
<!-- VERIFIES: AC-3, AC-11, FR-2, FR-3, FR-14, SEC-1 -->

## Goal

Modify `pipelines/Morales_et_all/config.yaml` to (a) add `singularity_image_dir:` and a `containers:` block matching the 9 SIF assignments, (b) add `downstream_scripts_dir:` with a submodule-init comment, (c) delete the entire `tools:` section that contains user-home and cluster-specific paths.

## Files Modified

- `pipelines/Morales_et_all/config.yaml`

## Exact Diff

### Delete

The entire block currently at config.yaml lines 36-43:

```yaml
# ==========================================
# Tool Executables & Scripts
# ==========================================
tools:
  picard_jar: "~/bin/picard-tools/MarkDuplicates.jar"
  reditools_script: "~/bin/reditools2.0-master/src/cineca/reditools.py"
  sprint_bin: "~/bin/SPRINT/bin/sprint_from_bam"
  jacusa2_jar: "/binf-isilon/rennie/gsn480/scratch/bin/JACUSA_v2.0.2-RC.jar"
  red_ml_script: "~/bin/RED-ML/bin/red_ML.pl"
  samtools_bin: "~/bin/samtools"
```

### Insert

After the `references:` block (immediately before the `# Tool Specific Parameters` comment if present, or before `params:`) insert:

```yaml
# ==========================================
# Container Images (Apptainer/Singularity)
# ==========================================
singularity_image_dir: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity"
containers:
  fastx: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/fastx.sif"
  star: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/star.sif"
  picard: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/picard.sif"
  reditools: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/reditools.sif"
  sprint: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/sprint.sif"
  wgs: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/wgs.sif"
  red_ml: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/red_ml.sif"
  jacusa2: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/jacusa2.sif"
  morales_downstream: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/morales_downstream.sif"

# Path to the Benchmark-of-RNA-Editing-Detection-Tools/Downstream directory.
# IMPORTANT: This is an empty git submodule by default. Run the following before
# executing downstream rules:
#   git submodule update --init Benchmark-of-RNA-Editing-Detection-Tools
downstream_scripts_dir: "Benchmark-of-RNA-Editing-Detection-Tools/Downstream"
```

### Preserve

- `threads:` (top-level)
- `conditions:` and `samples:` lists
- `aligners:` list (do NOT remove; it is unused but reserved per requirements §5.4)
- `references:` block
- `params:` block

## Acceptance Criteria

- [ ] `grep "tools:" pipelines/Morales_et_all/config.yaml` returns no matches at column 0 (the `tools:` top-level key is removed; `tools/` substrings inside paths or comments are acceptable but should not exist)
- [ ] `grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/` returns no matches (exit 1 means PASS)
- [ ] `grep -c "downstream_scripts_dir" pipelines/Morales_et_all/config.yaml` returns `1`
- [ ] `grep -c "singularity_image_dir" pipelines/Morales_et_all/config.yaml` returns `1`
- [ ] `python -c "import yaml; yaml.safe_load(open('pipelines/Morales_et_all/config.yaml'))"` exits 0 (file is valid YAML)
- [ ] `python -c "import yaml; c=yaml.safe_load(open('pipelines/Morales_et_all/config.yaml')); assert set(c['containers'].keys()) == {'fastx','star','picard','reditools','sprint','wgs','red_ml','jacusa2','morales_downstream'}"` exits 0
- [ ] `aligners` and `references` keys are still present in the config
- [ ] No other file is modified

## Verification

```bash
grep "^tools:" pipelines/Morales_et_all/config.yaml || echo "PASS: tools: removed"
grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/ || echo "PASS: no user paths"
grep -c "downstream_scripts_dir\|singularity_image_dir" pipelines/Morales_et_all/config.yaml
python -c "import yaml; c=yaml.safe_load(open('pipelines/Morales_et_all/config.yaml')); print(sorted(c['containers'].keys()))"
```

## Notes

- The `containers:` paths are absolute and TSCC-specific. This matches the editing_wgs pattern. Users on other machines override via `--config` or a separate config file.
- The `downstream_scripts_dir` value is RELATIVE (`Benchmark-of-RNA-Editing-Detection-Tools/Downstream`). It is interpreted relative to the Snakemake working directory, which is the `pipelines/Morales_et_all/` directory unless overridden.
- The submodule comment is mandatory; reviewers should reject the diff if the comment is omitted.
