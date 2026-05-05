# Codebase Audit: Morales_et_al Pipeline

## Pipeline Structure

```
pipelines/Morales_et_all/
├── Snakefile           # top-level: configfile, includes, rule all
├── preprocessing.smk   # trim_reads, star_mapping, mark_duplicates
├── tools.smk           # reditools, sprint, bcftools, red_ml, add_md_tag, jacusa2
├── downstream.smk      # run_downstream_parsers, update_alu, individual_analysis,
│                       #   reanalysis_multiple, multiple_analysis
└── config.yaml         # references, tool paths, params
```

## Snakemake 9+ Syntax Issues

### BREAKING — Must Fix

| Issue | Location | Details |
|-------|----------|---------|
| No `container:` directives | ALL rules | Every rule is missing a `container:` field. Snakemake 9 runs without containers by default but this prevents reproducible execution. |
| Hardcoded `~/bin/` paths in config | `config.yaml` tools section | `picard_jar`, `reditools_script`, `sprint_bin`, `red_ml_script`, `samtools_bin` all reference `~/bin/` paths. These are user-specific paths that break in containers and on other machines. |
| No `singularity_image_dir` / `containers:` block in config | `config.yaml` | Editing_wgs uses a `containers:` block + `container_for()` helper. Morales has neither. |
| Missing `container_for()` function | `Snakefile` | No helper defined. Must be added (or copy from editing_wgs pattern). |
| Bare relative script paths in downstream | `downstream.smk` shell blocks | `python Downstream/REDItools2.py` etc. depend on CWD being `pipelines/Morales_et_all/`. The `Benchmark-of-RNA-Editing-Detection-Tools` submodule is empty in this checkout. |

### RECOMMENDED — Should Fix

| Issue | Location | Details |
|-------|----------|---------|
| No `log:` directives | ALL rules | None of the rules declare log files. Required for debugging on HPC. |
| No `resources:` directives | ALL rules | No memory/runtime declarations for SLURM scheduling. |
| Shell pipe without `set -euo pipefail` | `bcftools` rule | `bcftools mpileup | bcftools call` — pipe failure won't be caught. |
| `threads: config["threads"]` | `star_mapping` rule | Config value is YAML integer (8), so this works, but worth verifying. |
| `java -jar {params.picard}` | `mark_duplicates` | Should call `picard MarkDuplicates` after containerization (the picard container provides a `picard` wrapper). |
| `python {params.script}` for reditools | `reditools` rule | Should call `reditools.py` from PATH once containerized. |
| `{params.sprint_bin}` for sprint | `sprint` rule | Should call `sprint_from_bam` from PATH once containerized. |
| `perl {params.script}` for red_ml | `red_ml` rule | RED-ML script path hardcoded; should be in container PATH. |

### SNAKEMAKE 9 SPECIFIC

| Issue | Details |
|-------|---------|
| `--use-singularity` deprecated | Snakemake 9 replaces this with `--software-deployment-method apptainer`. The TSCC profile (`profiles/tscc2/config.yaml`) must be checked. |
| `workflow.basedir` → `workflow.source_path()` | Snakemake 9 deprecates `workflow.basedir`; use `workflow.source_path(".")` instead. Used in editing_wgs `REPO_ROOT` definition — check if Morales needs similar script resolution. |

## Container Gap Analysis

| Rule | Tool | Existing Dockerfile | Action Needed |
|------|------|---------------------|---------------|
| `trim_reads` | fastx_trimmer | ❌ NONE | **CREATE** `containers/fastx/` |
| `star_mapping` | STAR + samtools | ❌ NONE (editing_wgs reuses lodei.sif) | **CREATE** `containers/star/` |
| `mark_duplicates` | Picard | ✅ `containers/picard/` | Use existing |
| `reditools` | REDItools2 | ✅ `containers/reditools/` | Use existing; update shell command |
| `sprint` | SPRINT | ✅ `containers/sprint/` | Use existing; update shell command |
| `add_md_tag` | samtools calmd | ✅ `containers/wgs/` (has samtools) | Use `wgs` or `jacusa2` container |
| `bcftools` | BCFtools + samtools | ✅ `containers/wgs/` (has bcftools) | Use `wgs` container |
| `red_ml` | RED-ML (Perl/R) | ❌ NONE (`containers/red/` is for RED Java) | **CREATE** `containers/red_ml/` |
| `jacusa2` | JACUSA2 | ✅ `containers/jacusa2/` | Use existing; update to use JAR from /opt |
| Downstream rules | Python 3 + pandas | ❌ NONE | **CREATE** `containers/morales_downstream/` |

### Note on `red` vs `red_ml`

`containers/red/` contains RED — a Java GUI application for RNA editing detection.
`red_ml` in the Morales pipeline calls `red_ML.pl` — a completely different tool (RED-ML, Perl+R based ML approach). These are NOT the same. A new `containers/red_ml/` Dockerfile is required.

### Note on STAR container

The editing_wgs pipeline maps `container_for("star")` → `lodei.sif`. LoDEI's biocontainer from `quay.io/biocontainers/lodei:1.0.0--pyh7e72e81_0` includes STAR as a dependency. This is an indirect reuse and should be made explicit. For the Morales pipeline, create a dedicated `containers/star/` with STAR + samtools.

## Script Discoverability Issues

### Downstream Scripts

All five downstream rules in `downstream.smk` call:
```
python Downstream/REDItools2.py
python Downstream/SPRINT.py
python Downstream/REDML.py
python Downstream/BCFtools.py
python Downstream/JACUSA2.py
python Downstream/Alu.py
python Downstream/Individual-Analysis.py
python Downstream/Re-Analysis-Multiple.py
python Downstream/Multiple-Analysis.py
```

These paths are relative and assume CWD = `pipelines/Morales_et_all/`. The `Benchmark-of-RNA-Editing-Detection-Tools/` directory is an empty git submodule stub.

**Recommended fix**: Add `downstream_scripts_dir` to `config.yaml` and use `{params.downstream_dir}/REDItools2.py` etc. Use `workflow.source_path()` to resolve the path relative to the Snakefile. The scripts live in the Benchmark submodule repo under `Downstream/`.

### Tool Binary Paths (in `config.yaml`)

```yaml
tools:
  picard_jar: "~/bin/picard-tools/MarkDuplicates.jar"      # replace with container cmd
  reditools_script: "~/bin/reditools2.0-master/src/cineca/reditools.py"  # on PATH in container
  sprint_bin: "~/bin/SPRINT/bin/sprint_from_bam"           # on PATH in container
  jacusa2_jar: "/binf-isilon/rennie/gsn480/scratch/bin/JACUSA_v2.0.2-RC.jar"  # replace with /opt/jacusa2/jacusa2.jar
  red_ml_script: "~/bin/RED-ML/bin/red_ML.pl"             # on PATH in container
  samtools_bin: "~/bin/samtools"                           # on PATH in container
```

After containerization, all tool binaries are resolved from the container image. The `tools:` section in config should be replaced with container image paths or removed.

## Reference to Existing Pattern

The `pipelines/editing_wgs/Snakefile` provides the canonical pattern:
- `SIF_DIR = config.get("singularity_image_dir", "...")`
- `CONTAINERS = config.get("containers", {})`
- `container_for(tool)` helper function
- Each rule: `container: container_for("toolname")`

The `containers:` block in `config.yaml` maps tool names to SIF paths. This same pattern should be applied to the Morales pipeline.
