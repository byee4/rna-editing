# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->

## Non-Interactive Shell Commands

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode. Always use force flags to avoid hanging:

```bash
cp -f source dest
mv -f source dest
rm -f file
rm -rf directory
```

## Running the Pipeline

The primary workflow is `pipelines/editing_wgs/Snakefile`. Run it from the `examples/` directory with Singularity enabled on TSCC:

```bash
module load singularitypro
conda activate snakemake9
cd examples
unset SLURM_JOB_ID   # required on interactive nodes
snakemake -kps ../pipelines/editing_wgs/Snakefile \
  --configfile ../pipelines/editing_wgs/config.data.gene.yaml \
  --profile /tscc/nfs/home/bay001/projects/codebase/rna-editing/profiles/tscc2 \
  --use-singularity
```

The TSCC profile (`profiles/tscc2/config.yaml`) submits jobs via SLURM to the `condo` partition with `csd792` account. It uses `software-deployment-method: apptainer` (Snakemake 8+ syntax).

**Available example configs:**
- `config.data.gene.yaml` — small example inputs from `data/small_examples/gene_APP_GAPDH`
- `config.data.rand.yaml` — small example inputs from `data/small_examples/random`
- `config.yaml` — full `data/` inputs (production)

## Tests

First create the test conda environment (one-time setup):

```bash
conda env create -p .conda/editing-wgs-snakemake -f pipelines/editing_wgs/environment.yaml
```

Run all dry-run DAG tests (validates workflow planning without executing containers):

```bash
conda run -p .conda/editing-wgs-snakemake python -m unittest tests/test_editing_wgs_dryrun.py
```

**Note:** `test_editing_wgs_dryrun.py` creates a `tempfile.TemporaryDirectory` under `/private/tmp`, which is a macOS path. On Linux/TSCC, this test will fail unless `/private/tmp` exists or the test is patched to use `/tmp`.

Run the unit test for the SPRINT adapter script (no conda env needed):

```bash
python -m unittest tests/test_sprint_to_deepred_vcf.py
```

Run a single dry-run manually:

```bash
conda run -p .conda/editing-wgs-snakemake snakemake \
  --snakefile pipelines/editing_wgs/Snakefile \
  --directory pipelines/editing_wgs \
  --configfile pipelines/editing_wgs/tests/config.yaml \
  --replace-workflow-config \
  --dry-run --cores 1
```

## Container Build and Validation

Containers are built as Docker images and converted to Singularity/Apptainer SIFs. The final SIFs live in `singularity/`. Build and validate containers using:

```bash
scripts/validate_containers.sh                          # all tools
TOOLS="reditools jacusa2" scripts/validate_containers.sh  # specific tools
TOOLS="wgs picard sprint deepred editpredict redinet picard" scripts/validate_containers.sh
```

The default output root is `/Volumes/X9Pro/container_data` (macOS external drive). Override with `CONTAINER_DATA_ROOT` and `SIF_OUTPUT_DIR` environment variables. TSCC runs `amd64`; build with `DOCKER_PLATFORM=linux/amd64` when building on Apple Silicon.

Each container in `containers/<tool>/` has a `Dockerfile` and a `validate.sh` script. The validation command inside each image is `validate-<tool>`.

## Architecture

### Two Pipelines

**`pipelines/editing_wgs/`** (primary, actively developed): Matched RNA/WGS workflow. Accepts per-sample RNA FASTQs plus either paired WGS FASTQs or a pre-computed `.vcf.gz`/`.bed.gz` variant file. Produces both DNA/RNA comparison outputs (JACUSA2, WGS-only samples only) and RNA-only outputs (SPRINT, REDInet, with DeepRED and editPredict currently deactivated in `rule all`).

**`pipelines/editing/`** (older, BAM-based): Takes pre-aligned BAMs. Runs SPRINT, JACUSA2 (with explicit `jacusa2_pairs` config), REDItools2, DeepRED, editPredict, and REDInet. Differs structurally: samples map to BAM paths, not FASTQs; pairs for JACUSA2 are configured explicitly rather than derived from WGS sample detection.

### editing_wgs Module Structure

The `editing_wgs` Snakefile is split into modules included at the bottom:

| Module | Responsibility |
|---|---|
| `Snakefile` | Global config, helper functions, `rule all`, module includes |
| `preprocessing.smk` | `mark_duplicates` (Picard), `samtools_calmd` — shared RNA and WGS BAM cleanup |
| `rna_processing.smk` | `star_genome_generate`, `star_align_rna` |
| `wgs_processing.smk` | `bwa_mem_wgs`, `generate_dna_coverage`, `call_germline_variants` (BCFtools) |
| `indexing.smk` | `samtools_faidx`, `bwa_index`, `samtools_index` — shared indexing rules |
| `rna_editing.smk` | All editing callers: `jacusa2_dnarna`, `sprint_*`, `reditools_for_redinet`, `deepred_predict`, `editpredict_filter`, `redinet_classify` |

### Data Flow

```
FASTQ (RNA)  →  STAR align  →  mapped/{sample}.rna.bam
                             →  mark_duplicates  →  dedup/{sample}.rna.bam
                             →  samtools_calmd   →  mapped/{sample}.rna.md.bam
                             →  sprint_mapq_bam  →  sprint_mapq/{sample}.bam  →  SPRINT
                             →  reditools_for_redinet  →  REDInet
                             →  [deactivated: DeepRED, editPredict]

FASTQ (WGS)  →  BWA-MEM  →  mapped/{sample}.wgs.bam
                          →  mark_duplicates  →  dedup/{sample}.wgs.bam
                          →  samtools_calmd   →  mapped/{sample}.wgs.md.bam
                          →  JACUSA2 (RNA vs DNA)
                          →  BCFtools germline VCF  →  germline/{sample}_germline.vcf.gz

External variants (.vcf.gz/.bed.gz)  →  JACUSA2 / editPredict (when WGS absent)
```

### Key Design Points

- **WGS vs. no-WGS branching**: `has_wgs(sample)` controls which rules are scheduled. WGS samples get JACUSA2 and germline VCFs; non-WGS samples can supply an external `.vcf.gz` or `.bed.gz`.
- **STAR index**: `star_index` in config is the output *directory path* for `star_genome_generate`. The workflow builds the index if it doesn't exist. It is not a path to an existing prebuilt index; the workflow creates it from the reference FASTA.
- **SPRINT MAPQ rewrite**: STAR emits MAPQ=255 for unique alignments. SPRINT rejects this, so `sprint_mapq_bam` rewrites MAPQ to 30 via SPRINT's own `changesammapq.py` without modifying the shared deduplicated BAM.
- **REDInet two-step**: REDItools v1 runs first with low-stringency filters to generate `outTable_*`, which is bgzip+tabix-indexed as `outTable.gz`; REDInet then classifies from that indexed table.
- **DeepRED/editPredict deactivated**: These are commented out in `rule all` in `Snakefile` as of the most recent commits due to unresolved container issues. The rules still exist in `rna_editing.smk`.
- **Container resolution**: `container_for(tool)` checks `config["containers"][tool]` first, then falls back to `{SIF_DIR}/{tool}.sif`.
- **WGS wildcard restriction**: `WGS_SAMPLE_PATTERN` is a regex alternation of WGS sample names. Rules that produce WGS-only outputs use this as a `wildcard_constraints` to prevent Snakemake from scheduling them for RNA-only samples.

### Adapter Scripts

`scripts/sprint_to_deepred_vcf.py` and `scripts/sprint_to_editpredict_positions.py` convert SPRINT's BED-like RES format to the VCF-like input DeepRED expects and the chromosome/locus TSV editPredict expects, respectively. Both are called from within their corresponding Snakemake rules via `REPO_ROOT`-relative paths.

### Singularity Images

All SIFs are in `singularity/`. The `wgs.sif` includes BWA, SAMtools, and BCFtools; `lodei.sif` is also used for STAR; `jacusa2.sif` doubles as the samtools image. DeepRED and editPredict SIFs exist but their pipeline rules are currently deactivated.

## Reference Data

- GRCh38 reference FASTA: `/tscc/projects/ps-yeolab3/bay001/annotations/GRCh38/GRCh38_no_alt_analysis_set_GCA_000001405.15.fasta`
- STAR index: `GRCh38_no_alt_analysis_set_GCA_000001405.idx` (relative to the working directory `examples/`)
- Download scripts: `scripts/download_refs.sh` (reference FASTA), `scripts/download_variant_data.sh` (HEK293 DepMap/SRA/GEO variant data)
