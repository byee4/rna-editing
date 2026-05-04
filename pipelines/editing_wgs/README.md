# Matched RNA/WGS Editing Workflow

This Snakemake workflow aligns RNA-seq inputs with either matched WGS data or a
precomputed variant file, marks duplicates, adds MD tags, and runs both DNA/RNA
comparison callers and RNA-only editing callers. The DNA/RNA branch runs
JACUSA2 only for samples with WGS, while the RNA-only branch provides SPRINT,
DeepRED, editPredict, and REDInet outputs from the deduplicated RNA BAM.

The workflow is split into small Snakemake modules so assay processing and
editing callers can be maintained independently:

- `Snakefile`: shared configuration, helper functions, final targets, and module
  includes.
- `preprocessing.smk`: shared BAM cleanup steps that prepare aligned RNA and WGS
  BAMs for downstream analysis.
- `rna_processing.smk`: RNA-seq alignment and RNA-specific processing rules.
- `wgs_processing.smk`: WGS alignment, coverage, and germline variant rules.
- `rna_editing.smk`: DNA/RNA comparison callers plus RNA-only editing and
  classification rules.

Run with Singularity/Apptainer enabled:

```bash
snakemake --snakefile pipelines/editing_wgs/Snakefile --directory pipelines/editing_wgs --use-singularity --cores 24
```

For Snakemake validation and dry-run tests, create the project-local test
environment from the tracked definition and invoke Snakemake through that env:

```bash
conda env create -p .conda/editing-wgs-snakemake -f pipelines/editing_wgs/environment.yaml
conda run -p .conda/editing-wgs-snakemake snakemake --snakefile pipelines/editing_wgs/Snakefile --directory pipelines/editing_wgs --runtime-source-cache-path /private/tmp/editing_wgs_snakemake_source_cache --dry-run --cores 1
```

The `tests/` directory beside this Snakefile contains generated dry-run
fixtures for every supported sample instance type: single-end RNA plus WGS,
paired-end RNA plus paired-end WGS, paired-end RNA plus an external `.vcf.gz`,
and single-end RNA plus an external `.bed.gz`. Run the unittest harness from
the repository root to verify all of those instances still build a Snakemake
DAG:

```bash
conda run -p .conda/editing-wgs-snakemake python -m unittest tests/test_editing_wgs_dryrun.py
```

The config maps each sample to RNA FASTQs plus either WGS FASTQs or an external
variant file. Each `rna` or `wgs` entry can be either a single FASTQ path for
single-end data or a two-item list for paired R1/R2 data. External variant files
must be `.vcf.gz` or `.bed.gz`; `.vcf.gz` files are passed to compatible callers
such as EditPredict, while `.bed.gz` files are accepted as configured variant
data for rules that can consume BED-style inputs.

```yaml
samples:
  sample_with_wgs:
    rna: "raw/sample_rna.fastq.gz"
    wgs: "raw/sample_wgs.fastq.gz"
  sample_with_variants:
    rna:
      - "raw/sample_rna_R1.fastq.gz"
      - "raw/sample_rna_R2.fastq.gz"
    variants: "refs/sample_variants.vcf.gz"
```

The workflow passes those one- or two-file FASTQ lists directly to STAR and
BWA-MEM. Before any RNA alignment runs, STAR builds a shared genome index at
`{reference}_idx` from the configured reference FASTA, so `reference` should
point to the FASTA file rather than a prebuilt STAR index directory. The
workflow also creates the required FASTA, BWA, and BAM index sidecars before
tools that consume them. Samples with WGS require germline VCF creation at
`results/germline/{sample}_germline.vcf.gz`, and that generated VCF is used by
variant-aware editing rules. Samples with external variants skip WGS-only rules
and do not schedule workflow-generated VCF outputs. Downstream caller rules
consume BAMs, so SPRINT, DeepRED, editPredict, and REDInet work the same way for
single-end and paired-end samples after alignment.

SPRINT receives a dedicated `results/sprint_mapq/{sample}.bam` input whose MAPQ
values are rewritten to 30 with SPRINT's `changesammapq.py` utility. That keeps
STAR's MAPQ=255 alignments inside SPRINT's accepted 20-200 MAPQ window without
modifying the shared deduplicated RNA BAM.

REDInet now follows the upstream REDInet recipe: REDItools v1 first extracts a
low-stringency RNA-only candidate table, the workflow bgzips and tabix-indexes
that `outTable_*` as `results/redinet/{sample}/outTable.gz`, and REDInet light
inference consumes that indexed table to produce the classified output.

Primary outputs include:

- `results/jacusa2_dnarna/{sample}.out`: JACUSA2 RNA-DNA difference calls for samples with WGS.
- `results/sprint/{sample}/regular.res`: SPRINT RNA-only editing candidates.
- `results/redinet/{sample}/outTable.gz`: bgzip-compressed and tabix-indexed REDItools v1 candidate table for REDInet.
- `results/deepred/{sample}_predictions.txt`: DeepRED scores for SPRINT calls after converting SPRINT's regular RES table to DeepRed's documented `#CHROM`, `POS`, `REF`, `ALT` candidate SNV input and running the upstream preprocess/predict Perl workflow.
- `results/editpredict/{sample}_scores.txt`: editPredict scores for SPRINT calls after converting SPRINT's BED-like coordinates to EditPredict positions, with `--vcf` when a `.vcf.gz` variant source is available.
- `results/redinet/{sample}_classified.txt`: REDInet classes for indexed REDItools v1 candidate calls.
- `results/wgs_coverage/{sample}.cov`: WGS-only coverage from `{sample}.wgs.md.bam` for samples with WGS.
- `results/germline/{sample}_germline.vcf.gz`: WGS-only germline SNVs from `{sample}.wgs.md.bam` for samples with WGS.

Container paths and caller thresholds are defined in `config.yaml`; existing
local SIFs cover STAR indexing and alignment through `lodei.sif`, REDItools, JACUSA2, SPRINT, DeepRED,
editPredict, and REDI-NET. The WGS and Picard images need to be built from
`containers/wgs` and `containers/picard` before a full production run:

```bash
TOOLS="wgs picard sprint deepred editpredict redinet" scripts/validate_containers.sh
```

Use the `redinet` block to tune the REDItools candidate-extraction thread count
plus REDInet minimum coverage, A-to-G frequency, and minimum A-to-G substitution
count. Use `deepred.matlab_bin_dir` when MATLAB is mounted into the DeepRed
container but its `matlab` executable is not already on `PATH`. DNA coverage
and germline variant rules are restricted to the MD-tagged WGS BAM path,
`results/mapped/{sample}.wgs.md.bam`, so they are not scheduled for RNA BAMs.
Real runs require the configured FASTQs and reference FASTA; the workflow
generates the STAR genome index at `refs/genome.fa_idx`.
