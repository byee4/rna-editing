# Task 01: Add container_for helper to Morales Snakefile

<!-- DEPENDENCIES: -->
<!-- LABELS: phase-3, stage:3-implement, smk-edit -->
<!-- VERIFIES: AC-16, FR-1, NFR-6 -->

## Goal

Add the `SIF_DIR`, `CONTAINERS`, and `container_for()` helper to `pipelines/Morales_et_all/Snakefile` mirroring the canonical pattern from `pipelines/editing_wgs/Snakefile` lines 14-25. This unblocks all subsequent rule modifications that call `container: container_for("<tool>")`.

## Files Modified

- `pipelines/Morales_et_all/Snakefile`

## Exact Change

Open `pipelines/Morales_et_all/Snakefile`. The current file is:

```python
import os

# Load the configuration file
configfile: "config.yaml"

# Include modular workflows
include: "preprocessing.smk"
include: "tools.smk"
include: "downstream.smk"

# Define the target outputs for the entire workflow
rule all:
    input:
        # ... unchanged ...
```

After the `configfile: "config.yaml"` line and BEFORE the `include:` lines, insert:

```python

# ==========================================
# Container Resolution
# ==========================================
SIF_DIR = config.get(
    "singularity_image_dir",
    "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity",
)
CONTAINERS = config.get("containers", {})


def container_for(tool):
    """Return the configured Singularity image path for a workflow tool."""
    return CONTAINERS.get(tool, f"{SIF_DIR}/{tool}.sif")

```

The `import os` and `rule all:` and `include:` lines remain unchanged.

## Acceptance Criteria

- [ ] `grep -c "^def container_for" pipelines/Morales_et_all/Snakefile` returns `1`
- [ ] `grep "SIF_DIR" pipelines/Morales_et_all/Snakefile` returns at least 2 matches (assignment and use)
- [ ] `grep "CONTAINERS" pipelines/Morales_et_all/Snakefile` returns at least 2 matches (assignment and use)
- [ ] `python -c "import ast; ast.parse(open('pipelines/Morales_et_all/Snakefile').read())"` exits 0 (file is syntactically valid Python)
- [ ] The `import os`, `configfile:`, `include:`, and `rule all:` blocks are unchanged in content (only inserted lines added)
- [ ] No other file is modified by this task

## Verification

```bash
grep -c "^def container_for" pipelines/Morales_et_all/Snakefile
grep "SIF_DIR\|CONTAINERS\|container_for" pipelines/Morales_et_all/Snakefile
python -c "import ast; ast.parse(open('pipelines/Morales_et_all/Snakefile').read())"
```

## Notes

- The default `SIF_DIR` value matches editing_wgs's TSCC convention. Users can override via `config.yaml` `singularity_image_dir:` (added in Task 02).
- Do NOT add `import re` — Morales Snakefile does not need it (unlike editing_wgs).
- Do NOT modify `rule all:` — adding container directives belongs to tasks 03/04/05.
