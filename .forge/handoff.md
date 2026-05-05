# Forge Pipeline Handoff

**Date**: 2026-05-05  
**Stopped at**: Stage 1-requirements COMPLETE (architect not yet started)  
**Reason**: Container images must be built outside TSCC HPC.

## What Was Accomplished

### Stage 0 — Research (COMPLETE)
Full audit of `pipelines/Morales_et_all/` pipeline. Findings:
- 9/9 rules missing `container:` directives
- 4 new Dockerfiles needed: `containers/star/`, `containers/red_ml/`, `containers/fastx/`, `containers/morales_downstream/`
- 5 existing containers reusable: `picard`, `reditools`, `sprint`, `wgs`, `jacusa2`
- All `~/bin/` tool paths must move to container-native commands
- `downstream.smk` uses bare relative paths to empty submodule → needs `config["downstream_scripts_dir"]`

### Stage 1 — Requirements (COMPLETE)
20 functional requirements and 17 acceptance criteria packaged for the architect.
Key context files in `.forge/stages/1-requirements/context/`.

## What Needs to Be Done Off-HPC

### Build These New Docker Images

```bash
# From the repo root, on a machine with Docker + apptainer/singularity:
TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh
```

The Dockerfiles do NOT exist yet — they need to be created before building.

**1. `containers/star/Dockerfile`** — STAR 2.7.x + samtools
```
Tools: STAR (splice-aware RNA aligner), samtools (BAM indexing)
Base: ubuntu:22.04 or conda-forge
Purpose: trim_reads preprocessing + star_mapping in Morales pipeline
```

**2. `containers/red_ml/Dockerfile`** — RED-ML (Perl + R)
```
Tools: Perl, R (with required packages), RED-ML (red_ML.pl)
Source: https://github.com/BGIT-Lab/RED-ML
Purpose: red_ml rule in tools.smk
NOTE: NOT the same as containers/red/ (which is a Java app)
```

**3. `containers/fastx/Dockerfile`** — FASTX-Toolkit
```
Tools: fastx_trimmer (FASTX-Toolkit)
Base: ubuntu:22.04
Purpose: trim_reads rule in preprocessing.smk
```

**4. `containers/morales_downstream/Dockerfile`** — Python 3 for analysis scripts
```
Tools: Python 3, pandas, numpy, matplotlib, scipy, scikit-learn
Purpose: All 5 downstream rules (run_downstream_parsers, update_alu, etc.)
Note: Scripts come from Benchmark-of-RNA-Editing-Detection-Tools submodule
```

## Next Forge Steps (Resume with `/forge go`)

1. Run `/forge architect` to generate the implementation task list
2. Run `/forge build` to implement the changes
3. Run `/forge review` to verify

The architect input is ready in `.forge/stages/1-requirements/architect-prompt.md`.

## Files Changed in This Session

```
.forge/                           # forge pipeline state (new)
  state.json                      # stages 0+1 marked COMPLETE
  codemap.md                      # codebase structural index
  stages/0-research/              # full audit artifacts
  stages/1-requirements/          # architect-ready context package
  history/traces.jsonl            # execution trace
CLAUDE.md                         # updated with pipeline architecture notes
```

## Key Reference Files for Next Session

```
pipelines/Morales_et_all/Snakefile          # target: add container_for() + includes
pipelines/Morales_et_all/preprocessing.smk  # target: trim_reads, star_mapping, mark_dup
pipelines/Morales_et_all/tools.smk          # target: 6 tool rules
pipelines/Morales_et_all/downstream.smk     # target: 5 downstream rules
pipelines/Morales_et_all/config.yaml        # target: add containers: block
pipelines/editing_wgs/Snakefile             # reference: container_for() pattern
containers/*/Dockerfile                     # existing; 4 new ones needed
```
