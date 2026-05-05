## Pre-Execution Plan: 0-research

1. **Three most likely failure modes**:
   - Snakemake 9+ syntax changes are subtle (e.g., `expand()` behavior, `ancient()`, `multiext()`, rule inheritance, `storage:` directive) — risk of missing a non-obvious deprecation. Watch for: any `rule all:` input using old glob patterns, any `params:` using lambda with positional args instead of keyword.
   - Container/tool mapping may be incomplete — the pipeline uses multiple tools (STAR, samtools, SPRINT, REDItools, REDInet, etc.) and containers may only exist for some. Watch for: tools with no existing Dockerfile AND no public Docker image reference.
   - Script discoverability: wrapper scripts and Python scripts may be referenced with relative paths that break when the working directory changes. Watch for: `script:` directives using `../scripts/` or bare filenames without `workflow.source_path()`.

2. **First verification steps**:
   - Read `pipelines/editing_wgs/rna_editing.smk` fully
   - Inventory all `rule` blocks and their `container:` / `conda:` fields
   - Check `containers/` and `singularity/` directories for existing container definitions
   - List all `script:` and `shell:` references to identify script paths

3. **Context dependencies**:
   - pipelines/editing_wgs/rna_editing.smk (primary target)
   - containers/ directory (existing Dockerfiles)
   - singularity/data/ directory (existing .sif or definition files)
   - scripts/ directory (helper scripts)
   - profiles/tscc2/ (execution profiles, container binding config)
   - CLAUDE.md (architecture notes)
   - AGENTS.md (if exists, for additional context)
